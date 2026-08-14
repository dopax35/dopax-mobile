package com.pdcollect.app.ui

import android.Manifest
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.ViewFlipper
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.pdcollect.app.R
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.service.HealthConnectManager
import com.pdcollect.app.service.StravaManager
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.PermissionUtils
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Onboarding v2 (Figma) enrolment wizard — the Android counterpart of iOS's
 * ProfileSetupView, step for step.
 *
 * Every answer is written to [UserProfile] as it is given rather than in one
 * batch at the end, so a participant who is interrupted mid-enrolment resumes
 * where they left off instead of starting over. The participant code is shown
 * but never editable: renumbering one would orphan their historical files.
 */
class ProfileSetupActivity : AppCompatActivity() {

    private companion object {
        const val STEP_ABOUT = 0
        const val STEP_MEDICATIONS = 1
        const val STEP_TIMES = 2
        const val STEP_HEALTH = 3
        const val STEP_KEYBOARD = 4
        const val STEP_REMINDERS = 5
        const val STEP_READY = 6
        const val STEP_COUNT = 7

        /** Consent owns dot 0, so the wizard's steps start at the second dot. */
        const val PROGRESS_DOTS = 7
        const val STATE_STEP = "onboarding_step"

        const val STATUS_CONNECTED = "connected"
        const val STATUS_DENIED = "denied"
        const val STATUS_SKIPPED = "skipped"
        const val STATUS_UNAVAILABLE = "unavailable"

        const val TAG = "ProfileSetup"

        val MEDICATION_UNITS = arrayOf("pill(s)", "mg", "ml", "patch", "drop(s)")
    }

    private lateinit var profile: UserProfile
    private lateinit var flipper: ViewFlipper
    private lateinit var progressRow: LinearLayout
    private lateinit var medicationContainer: LinearLayout

    private val medicationRows = mutableListOf<MedicationRow>()
    private var step = STEP_ABOUT

    private data class MedicationRow(
        val view: View,
        val name: EditText,
        val unit: TextView,
        val count: EditText,
        /**
         * A pre-split free-text dose ("100mg twice daily") that could not be
         * parsed into count + unit. Held so it can be written back verbatim,
         * and cleared the moment the participant edits either field.
         */
        var legacyDose: String? = null,
    )

    private val notificationPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { granted ->
        profile.notificationsOptIn = granted
        goTo(STEP_READY)
    }

    private val healthConnectPermissionLauncher = registerForActivityResult(
        androidx.health.connect.client.PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        profile.healthConnectStatus =
            if (granted.containsAll(HealthConnectManager.PERMISSIONS)) STATUS_CONNECTED else STATUS_DENIED
        renderHealthStep()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_profile_setup)

        profile = UserProfile(this)
        flipper = findViewById(R.id.stepFlipper)
        progressRow = findViewById(R.id.onboardingProgress)
        medicationContainer = findViewById(R.id.medicationContainer)

        bindAboutStep()
        bindMedicationsStep()
        bindTimesStep()
        bindHealthStep()
        bindKeyboardStep()
        bindRemindersStep()
        bindReadyStep()

        // Legacy participants already answered the demographics; drop them at
        // the session windows, which is the one thing v1 never asked for.
        val initialStep = savedInstanceState?.getInt(STATE_STEP)
            ?: if (profile.profileComplete && profile.needsOnboardingV2) STEP_TIMES else STEP_ABOUT
        goTo(initialStep)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (step > STEP_ABOUT) {
                    goTo(step - 1)
                } else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(STATE_STEP, step)
    }

    override fun onResume() {
        super.onResume()
        // The health, interaction and reminder steps all send the participant
        // into a system settings screen, so re-read the real state on return
        // instead of trusting what we showed before leaving.
        renderHealthStep()
        renderKeyboardStep()
        renderRemindersStep()
    }

    override fun onPause() {
        super.onPause()
        // Medication rows only live in the view hierarchy until they are
        // committed, so flush them before the process can be killed.
        commitMedications()
    }

    override fun onDestroy() {
        super.onDestroy()
        pairingScanner?.stopScanning()
        pairingScanner = null
        pairingDialog?.dismiss()
        pairingDialog = null
    }

    // MARK: - Navigation

    private fun goTo(target: Int) {
        // Leaving the medications step in any direction — Continue, Back, or
        // the system back gesture — has to persist what was typed, or an
        // answer given is an answer lost.
        if (step == STEP_MEDICATIONS && target != STEP_MEDICATIONS) commitMedications()

        step = target.coerceIn(STEP_ABOUT, STEP_COUNT - 1)
        flipper.displayedChild = step
        renderProgress()
        when (step) {
            STEP_ABOUT -> renderAboutStep()
            STEP_TIMES -> renderTimesStep()
            STEP_HEALTH -> renderHealthStep()
            STEP_KEYBOARD -> renderKeyboardStep()
            STEP_REMINDERS -> renderRemindersStep()
            STEP_READY -> renderReadyStep()
        }
        hideKeyboard()
    }

    private fun renderProgress() {
        progressRow.removeAllViews()
        val current = minOf(step + 1, PROGRESS_DOTS - 1)
        for (index in 0 until PROGRESS_DOTS) {
            val dot = View(this).apply {
                setBackgroundResource(
                    when {
                        index == current -> R.drawable.onboarding_progress_active
                        index < current -> R.drawable.onboarding_progress_past
                        else -> R.drawable.onboarding_progress_idle
                    }
                )
                layoutParams = LinearLayout.LayoutParams(
                    dp(if (index == current) 22 else 7),
                    LinearLayout.LayoutParams.MATCH_PARENT
                ).apply { if (index > 0) marginStart = dp(6) }
            }
            progressRow.addView(dot)
        }
    }

    private fun hideKeyboard() {
        val focused = currentFocus ?: return
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
        imm.hideSoftInputFromWindow(focused.windowToken, 0)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    // MARK: - Step 1: about you

    private fun bindAboutStep() {
        val nameEdit = findViewById<EditText>(R.id.editDisplayName)
        val yearEdit = findViewById<EditText>(R.id.editYearOfBirth)

        nameEdit.setText(profile.displayName)
        nameEdit.doAfterTextChanged { profile.displayName = it?.toString()?.trim().orEmpty() }

        yearEdit.setText(profile.yearOfBirth)
        yearEdit.doAfterTextChanged { text ->
            val value = text?.toString()?.trim().orEmpty()
            profile.yearOfBirth = value
            // Only derive an age from a plausible complete year — otherwise a
            // half-typed "19" would write an age of 2007.
            val year = value.toIntOrNull()
            if (value.length == 4 && year != null && year in 1900..currentYear()) {
                profile.age = currentYear() - year
            }
            renderAboutStep()
        }

        findViewById<TextView>(R.id.fieldGender).setOnClickListener { showGenderPicker() }

        findViewById<TextView>(R.id.segDominantLeft).setOnClickListener {
            profile.dominantHand = Constants.PARTICIPANT_HAND_LEFT
            renderAboutStep()
        }
        findViewById<TextView>(R.id.segDominantRight).setOnClickListener {
            profile.dominantHand = Constants.PARTICIPANT_HAND_RIGHT
            renderAboutStep()
        }
        findViewById<TextView>(R.id.linkDominantUnknown).setOnClickListener {
            profile.dominantHand = Constants.PARTICIPANT_HAND_UNKNOWN
            renderAboutStep()
        }

        findViewById<TextView>(R.id.segAffectedLeft).setOnClickListener {
            profile.affectedSide = Constants.PARTICIPANT_SIDE_LEFT
            renderAboutStep()
        }
        findViewById<TextView>(R.id.segAffectedRight).setOnClickListener {
            profile.affectedSide = Constants.PARTICIPANT_SIDE_RIGHT
            renderAboutStep()
        }
        findViewById<TextView>(R.id.segAffectedBoth).setOnClickListener {
            profile.affectedSide = Constants.PARTICIPANT_SIDE_BOTH
            renderAboutStep()
        }
        findViewById<TextView>(R.id.segAffectedNeither).setOnClickListener {
            profile.affectedSide = Constants.PARTICIPANT_SIDE_NONE
            renderAboutStep()
        }
        findViewById<TextView>(R.id.linkAffectedOther).setOnClickListener { showAffectedSideOptions() }

        findViewById<MaterialButton>(R.id.btnAboutContinue).setOnClickListener { goTo(STEP_MEDICATIONS) }
    }

    private fun renderAboutStep() {
        val genderField = findViewById<TextView>(R.id.fieldGender)
        val chosenGender = profile.gender
        genderField.text = chosenGender.ifBlank { "Select" }
        genderField.setTextColor(
            androidx.core.content.ContextCompat.getColor(
                this,
                if (chosenGender.isBlank()) R.color.gray_50 else R.color.black_90
            )
        )

        findViewById<TextView>(R.id.segDominantLeft).isSelected =
            profile.dominantHand == Constants.PARTICIPANT_HAND_LEFT
        findViewById<TextView>(R.id.segDominantRight).isSelected =
            profile.dominantHand == Constants.PARTICIPANT_HAND_RIGHT
        renderChoiceLink(
            findViewById(R.id.linkDominantUnknown),
            label = "Prefer not to say",
            active = profile.dominantHand == Constants.PARTICIPANT_HAND_UNKNOWN
        )

        findViewById<TextView>(R.id.segAffectedLeft).isSelected =
            profile.affectedSide == Constants.PARTICIPANT_SIDE_LEFT
        findViewById<TextView>(R.id.segAffectedRight).isSelected =
            profile.affectedSide == Constants.PARTICIPANT_SIDE_RIGHT
        findViewById<TextView>(R.id.segAffectedBoth).isSelected =
            profile.affectedSide == Constants.PARTICIPANT_SIDE_BOTH
        findViewById<TextView>(R.id.segAffectedNeither).isSelected =
            profile.affectedSide == Constants.PARTICIPANT_SIDE_NONE
        renderChoiceLink(
            findViewById(R.id.linkAffectedOther),
            label = "Prefer not to say",
            active = profile.affectedSide == Constants.PARTICIPANT_SIDE_UNKNOWN
        )

        findViewById<TextView>(R.id.tvParticipantCode).text =
            "Participant ID: ${profile.userId} — assigned by the study, so it never changes."

        findViewById<MaterialButton>(R.id.btnAboutContinue).isEnabled = isAboutComplete()
    }

    /**
     * The "prefer not to say" style answers sit outside the segmented row, so
     * they need their own selected state — otherwise declining looks identical
     * to not having answered at all.
     */
    private fun renderChoiceLink(link: TextView, label: String, active: Boolean) {
        link.text = if (active) "✓ $label" else label
        link.setTextColor(
            androidx.core.content.ContextCompat.getColor(
                this,
                if (active) R.color.onboarding_accent else R.color.onboarding_text_tertiary
            )
        )
    }

    private fun showGenderPicker() {
        val options = resources.getStringArray(R.array.gender_options)
        val checked = options.indexOf(profile.gender)
        AlertDialog.Builder(this)
            .setTitle("Gender")
            .setSingleChoiceItems(options, checked) { dialog, which ->
                profile.gender = options[which]
                renderAboutStep()
                dialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showAffectedSideOptions() {
        AlertDialog.Builder(this)
            .setTitle("Which hand is affected?")
            .setSingleChoiceItems(arrayOf("Prefer not to say"), 0) { dialog, _ ->
                profile.affectedSide = Constants.PARTICIPANT_SIDE_UNKNOWN
                renderAboutStep()
                dialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun isAboutComplete(): Boolean {
        val year = profile.yearOfBirth.toIntOrNull()
        val hasBirthInfo = profile.age > 0 || (year != null && year in 1900..currentYear())
        return hasBirthInfo && profile.gender.isNotBlank()
    }

    private fun currentYear() = Calendar.getInstance().get(Calendar.YEAR)

    // MARK: - Step 2: medications

    private fun bindMedicationsStep() {
        loadMedications()

        findViewById<TextView>(R.id.btnAddMedication).setOnClickListener { addMedicationRow() }

        // Shelly BLE is temporarily disabled (Constants.SHELLY_BLE_ENABLED) —
        // hide the pairing entry point entirely rather than leaving a button
        // that taps through to a scanner that silently ignores the request.
        findViewById<MaterialButton>(R.id.btnPairShelly).apply {
            if (Constants.SHELLY_BLE_ENABLED) {
                visibility = View.VISIBLE
                setOnClickListener { startShellyPairing() }
            } else {
                visibility = View.GONE
            }
        }

        findViewById<MaterialButton>(R.id.btnMedicationsContinue).setOnClickListener { goTo(STEP_TIMES) }
        findViewById<TextView>(R.id.btnMedicationsBack).setOnClickListener { goTo(STEP_ABOUT) }
    }

    private fun loadMedications() {
        val stored = runCatching { JSONArray(profile.medications) }.getOrNull()
        if (stored == null || stored.length() == 0) {
            addMedicationRow()
            return
        }
        for (i in 0 until stored.length()) {
            val entry = stored.optJSONObject(i) ?: continue
            val name = entry.optString("name")
            val storedUnit = entry.optString("unit")
            val storedCount = entry.optString("count")

            if (storedUnit.isNotBlank() || storedCount.isNotBlank()) {
                addMedicationRow(
                    name = name,
                    unit = storedUnit.ifBlank { "pill(s)" },
                    count = storedCount.ifBlank { "1" },
                )
                continue
            }

            // Written before this screen split dose into count + unit.
            val legacy = entry.optString("dose").trim()
            val parsed = parseLegacyDose(legacy)
            if (parsed != null) {
                addMedicationRow(name = name, unit = parsed.second, count = parsed.first)
            } else {
                addMedicationRow(name = name, legacyDose = legacy.ifBlank { null })
            }
        }
        if (medicationRows.isEmpty()) addMedicationRow()
    }

    /**
     * Splits a free-text dose such as "100mg" or "2 pill(s)" into count + unit.
     * Returns null for anything that does not start with a number ("one tablet
     * after food"), which the caller then preserves verbatim rather than
     * overwriting with a guess.
     */
    private fun parseLegacyDose(dose: String): Pair<String, String>? {
        val match = Regex("""^(\d+(?:[.,]\d+)?)\s*(.*)$""").matchEntire(dose.trim()) ?: return null
        return match.groupValues[1] to match.groupValues[2].trim().ifBlank { "pill(s)" }
    }

    private fun addMedicationRow(
        name: String = "",
        unit: String = "pill(s)",
        count: String = "1",
        legacyDose: String? = null,
    ) {
        val view = LayoutInflater.from(this)
            .inflate(R.layout.onboarding_medication_row, medicationContainer, false)
        (view.layoutParams as? ViewGroup.MarginLayoutParams)?.bottomMargin = dp(12)

        val nameEdit = view.findViewById<EditText>(R.id.editMedicationName).apply { setText(name) }
        val unitField = view.findViewById<TextView>(R.id.fieldMedicationUnit).apply { text = unit }
        val countEdit = view.findViewById<EditText>(R.id.editMedicationCount).apply { setText(count) }
        val row = MedicationRow(view, nameEdit, unitField, countEdit, legacyDose)

        unitField.setOnClickListener {
            val checked = MEDICATION_UNITS.indexOf(unitField.text.toString()).coerceAtLeast(0)
            AlertDialog.Builder(this)
                .setTitle("Unit")
                .setSingleChoiceItems(MEDICATION_UNITS, checked) { dialog, which ->
                    unitField.text = MEDICATION_UNITS[which]
                    row.legacyDose = null
                    dialog.dismiss()
                }
                .setNegativeButton("Cancel", null)
                .show()
        }
        countEdit.doAfterTextChanged { row.legacyDose = null }

        view.findViewById<ImageView>(R.id.btnRemoveMedication).setOnClickListener {
            medicationContainer.removeView(view)
            medicationRows.removeAll { it.view === view }
            if (medicationRows.isEmpty()) addMedicationRow()
            commitMedications()
        }

        medicationContainer.addView(view)
        medicationRows.add(row)
    }

    private fun composeMedicationDose(count: String, unit: String): String {
        val trimmedCount = count.trim().ifBlank { "1" }
        val trimmedUnit = unit.trim().ifBlank { "pill(s)" }
        return "$trimmedCount $trimmedUnit"
    }

    private fun commitMedications() {
        val array = JSONArray()
        for (row in medicationRows) {
            val name = row.name.text.toString().trim()
            if (name.isEmpty()) continue
            val unit = row.unit.text.toString().trim().ifBlank { "pill(s)" }
            val count = row.count.text.toString().trim().ifBlank { "1" }
            array.put(
                JSONObject()
                    .put("name", name)
                    .put("unit", unit)
                    .put("count", count)
                    // An unparsed legacy dose survives untouched until the
                    // participant edits the fields themselves. Recomposing it
                    // would turn "100mg twice daily" into "1 pill(s)".
                    .put("dose", row.legacyDose ?: composeMedicationDose(count, unit))
            )
        }
        profile.medications = array.toString()
    }

    // MARK: - Step 3: session windows

    private fun bindTimesStep() {
        findViewById<View>(R.id.rowCustomWindow).setOnClickListener {
            pickCustomWindowTime()
        }

        findViewById<MaterialButton>(R.id.btnTimesContinue).setOnClickListener { goTo(STEP_HEALTH) }
        findViewById<TextView>(R.id.btnTimesBack).setOnClickListener { goTo(STEP_MEDICATIONS) }
    }

    private fun renderTimesStep() {
        findViewById<TextView>(R.id.tvMorningWindow).text = profile.testTimeMorning
        findViewById<TextView>(R.id.tvEveningWindow).text = profile.testTimeEvening
        findViewById<TextView>(R.id.tvCustomWindow).text = customWindowLabel()
        findViewById<MaterialButton>(R.id.btnTimesContinue).isEnabled = isTimesComplete()
    }

    private fun customWindowLabel(): String {
        val custom = profile.testTimeCustom.trim()
        return custom.ifBlank { "12:00-16:00" }
    }

    private fun isTimesComplete() = profile.testTimeCustom.isNotBlank()

    private fun pickCustomWindowTime() {
        val current = profile.testTimeCustom.ifBlank { "14:00" }
        val parts = current.split(":", "-")
        val hour = parts.getOrNull(0)?.toIntOrNull() ?: 14
        val minute = parts.getOrNull(1)?.toIntOrNull() ?: 0
        TimePickerDialog(this, { _, pickedHour, pickedMinute ->
            val clampedHour = when {
                pickedHour < 12 -> 12
                pickedHour > 16 || (pickedHour == 16 && pickedMinute > 0) -> 16
                else -> pickedHour
            }
            val clampedMinute = if (clampedHour == 16) 0 else pickedMinute
            profile.testTimeCustom = String.format(java.util.Locale.US, "%02d:%02d", clampedHour, clampedMinute)
            renderTimesStep()
        }, hour.coerceIn(12, 16), minute, true).show()
    }

    // MARK: - Step 4: health apps

    private fun bindHealthStep() {
        findViewById<TextView>(R.id.btnConnectHealthConnect).setOnClickListener { connectHealthConnect() }

        findViewById<TextView>(R.id.btnConnectStrava).setOnClickListener {
            if (StravaManager.isConnected(this)) {
                profile.healthStravaStatus = STATUS_CONNECTED
                renderHealthStep()
            } else {
                // Toasts and returns on its own if this build has no Strava
                // credentials, so the row stays honest about not being linked.
                StravaManager.startAuth(this)
            }
        }

        findViewById<MaterialButton>(R.id.btnHealthContinue).setOnClickListener { goTo(STEP_KEYBOARD) }
        findViewById<TextView>(R.id.btnHealthSkip).setOnClickListener {
            if (profile.healthConnectStatus != STATUS_CONNECTED) profile.healthConnectStatus = STATUS_SKIPPED
            if (profile.healthStravaStatus != STATUS_CONNECTED) profile.healthStravaStatus = STATUS_SKIPPED
            goTo(STEP_KEYBOARD)
        }
    }

    private fun connectHealthConnect() {
        if (!HealthConnectManager.isAvailable(this)) {
            profile.healthConnectStatus = STATUS_UNAVAILABLE
            Toast.makeText(this, "Health Connect isn't installed on this device.", Toast.LENGTH_LONG).show()
            renderHealthStep()
            return
        }
        lifecycleScope.launch {
            if (HealthConnectManager.hasAllPermissions(this@ProfileSetupActivity)) {
                profile.healthConnectStatus = STATUS_CONNECTED
                renderHealthStep()
            } else {
                healthConnectPermissionLauncher.launch(HealthConnectManager.PERMISSIONS)
            }
        }
    }

    private fun renderHealthStep() {
        if (StravaManager.isConnected(this)) profile.healthStravaStatus = STATUS_CONNECTED
        renderConnectButton(findViewById(R.id.btnConnectStrava), profile.healthStravaStatus)

        val healthConnectButton = findViewById<TextView>(R.id.btnConnectHealthConnect)
        if (!HealthConnectManager.isAvailable(this)) {
            renderConnectButton(healthConnectButton, STATUS_UNAVAILABLE)
            return
        }
        lifecycleScope.launch {
            if (HealthConnectManager.hasAllPermissions(this@ProfileSetupActivity)) {
                profile.healthConnectStatus = STATUS_CONNECTED
            }
            renderConnectButton(healthConnectButton, profile.healthConnectStatus)
        }
    }

    private fun renderConnectButton(button: TextView, status: String) {
        when (status) {
            STATUS_CONNECTED -> {
                button.text = "Connected"
                button.isEnabled = false
            }
            STATUS_UNAVAILABLE -> {
                button.text = "Unavailable"
                button.isEnabled = false
            }
            else -> {
                button.text = "Connect"
                button.isEnabled = true
            }
        }
        button.alpha = if (button.isEnabled) 1f else 0.6f
    }

    // MARK: - Step 5: interaction primer

    private fun bindKeyboardStep() {
        findViewById<TextView>(R.id.btnOpenInteractionSettings).setOnClickListener {
            profile.keyloggingEnabled = true
            PermissionUtils.openAccessibilitySettings(this)
        }
        findViewById<TextView>(R.id.btnOpenUsageSettings).setOnClickListener {
            PermissionUtils.openUsageAccessSettings(this)
        }
        findViewById<MaterialButton>(R.id.btnKeyboardOpenSettings).setOnClickListener {
            val interactionGranted = PermissionUtils.isAccessibilityServiceEnabled(this)
            val usageGranted = PermissionUtils.hasUsageStatsPermission(this)
            when {
                interactionGranted && usageGranted -> goTo(STEP_REMINDERS)
                !interactionGranted -> {
                    profile.keyloggingEnabled = true
                    PermissionUtils.openAccessibilitySettings(this)
                }
                else -> PermissionUtils.openUsageAccessSettings(this)
            }
        }
        findViewById<TextView>(R.id.btnKeyboardSkip).setOnClickListener {
            profile.keyloggingEnabled = false
            goTo(STEP_REMINDERS)
        }
    }

    private fun renderKeyboardStep() {
        val interactionGranted = PermissionUtils.isAccessibilityServiceEnabled(this)
        val usageGranted = PermissionUtils.hasUsageStatsPermission(this)

        findViewById<TextView>(R.id.btnOpenInteractionSettings).visibility =
            if (interactionGranted) View.GONE else View.VISIBLE
        findViewById<TextView>(R.id.tvInteractionGranted).visibility =
            if (interactionGranted) View.VISIBLE else View.GONE

        findViewById<TextView>(R.id.btnOpenUsageSettings).visibility =
            if (usageGranted) View.GONE else View.VISIBLE
        findViewById<TextView>(R.id.tvUsageGranted).visibility =
            if (usageGranted) View.VISIBLE else View.GONE

        findViewById<MaterialButton>(R.id.btnKeyboardOpenSettings).text =
            if (interactionGranted && usageGranted) "Continue" else "Open Settings"
    }

    // MARK: - Step 6: reminders primer

    private fun bindRemindersStep() {
        findViewById<MaterialButton>(R.id.btnRemindersContinue).setOnClickListener {
            requestNotifications()
        }
        findViewById<TextView>(R.id.btnRemindersSkip).setOnClickListener {
            profile.notificationsOptIn = false
            goTo(STEP_READY)
        }
        findViewById<TextView>(R.id.btnExactAlarm).setOnClickListener {
            PermissionUtils.openExactAlarmSettings(this)
        }
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !PermissionUtils.hasNotificationPermission(this)
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        profile.notificationsOptIn = PermissionUtils.hasNotificationPermission(this)
        goTo(STEP_READY)
    }

    private fun renderRemindersStep() {
        val exactAlarmGranted = PermissionUtils.hasExactAlarmPermission(this)
        profile.exactAlarmOptIn = exactAlarmGranted
        findViewById<TextView>(R.id.btnExactAlarm).visibility =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !exactAlarmGranted) View.VISIBLE else View.GONE
    }

    // MARK: - Step 7: ready

    private fun bindReadyStep() {
        findViewById<MaterialButton>(R.id.btnStartFirstSession).setOnClickListener { finishProfile() }
        findViewById<TextView>(R.id.btnFinishLater).setOnClickListener { finishProfile() }
        buildHelixStrand()
        displayAppVersion()
    }

    private fun renderReadyStep() {
        findViewById<MaterialButton>(R.id.btnStartFirstSession).isEnabled =
            isAboutComplete() && isTimesComplete()
    }

    private fun buildHelixStrand() {
        val row = findViewById<LinearLayout>(R.id.helixStrandRow)
        row.removeAllViews()
        // One bar per study day: the first is already earned by enrolling.
        for (index in 0 until 14) {
            val bar = View(this).apply {
                setBackgroundResource(
                    if (index == 0) R.drawable.bg_onboarding_helix_active
                    else R.drawable.bg_onboarding_helix_idle
                )
                layoutParams = LinearLayout.LayoutParams(dp(13), LinearLayout.LayoutParams.MATCH_PARENT)
                    .apply { if (index > 0) marginStart = dp(5) }
            }
            row.addView(bar)
        }
    }

    private fun displayAppVersion() {
        try {
            val info = packageManager.getPackageInfo(packageName, 0)
            findViewById<TextView>(R.id.tvAppVersion)?.text =
                "dopa-X Version: ${info.versionName} (${info.longVersionCode})"
        } catch (e: Exception) {
            Log.e(TAG, "Error getting version info", e)
        }
    }

    private fun finishProfile() {
        commitMedications()

        if (profile.gender.isBlank()) profile.gender = "Prefer not to say"
        if (profile.age <= 0) {
            profile.yearOfBirth.toIntOrNull()
                ?.takeIf { it in 1900..currentYear() }
                ?.let { profile.age = currentYear() - it }
        }
        if (profile.testTimeCustom.isBlank()) {
            // A legacy participant may already have chosen a noon window under
            // onboarding v1; inherit it rather than overwriting their answer.
            profile.testTimeCustom = profile.testTimeNoon.ifBlank { "14:00" }
        }
        // faceDistanceMode reads back as ALWAYS when it has never been set, and
        // this screen no longer asks about the camera (Settings does). Write the
        // off state explicitly so an unanswered question can't enable it.
        if (!profile.faceDistanceConfigured) {
            profile.faceDistanceMode = Constants.FACE_DISTANCE_MODE_OFF
        }
        // Never report an opt-in the system hasn't actually granted.
        if (!PermissionUtils.hasNotificationPermission(this)) profile.notificationsOptIn = false
        profile.usageAccessOptIn = PermissionUtils.hasUsageStatsPermission(this)
        profile.exactAlarmOptIn = PermissionUtils.hasExactAlarmPermission(this)

        profile.passiveCollectionActive = true
        profile.profileComplete = true
        profile.onboardingVersion = 2

        // Write to CSV. Use writeProfileSnapshot() instead of formatting the row
        // inline so any future column added to PROFILE_HEADER is wired up in
        // exactly one place.
        val dataManager = com.pdcollect.app.data.DataManager(this, profile)
        dataManager.writeProfileSnapshot()

        lifecycleScope.launch {
            com.pdcollect.app.data.FirebaseSyncManager.saveProfileToCloud(profile, dataManager)
            // Additive Postgres dual-write — must not block the legacy path.
            com.pdcollect.app.data.BackendSyncManager.syncProfile(this@ProfileSetupActivity)
            dataManager.closeAll()
        }

        try {
            com.pdcollect.app.receiver.BatteryReminderReceiver.scheduleBatteryAlarms(this)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to setup battery reminders", e)
        }

        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }

    // MARK: - Shelly pillbox pairing

    private var pairingScanner: com.pdcollect.app.service.ShellyBleScanner? = null
    private var pairingDialog: androidx.appcompat.app.AlertDialog? = null

    private val btPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        if (results.values.all { it }) {
            executeShellyPairing()
        } else {
            Toast.makeText(this, "Bluetooth permissions are required to pair the sensor.", Toast.LENGTH_LONG).show()
        }
    }

    private fun startShellyPairing() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val required = arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            val missing = required.filter {
                androidx.core.content.ContextCompat.checkSelfPermission(this, it) !=
                    android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            if (missing.isNotEmpty()) {
                btPermissionLauncher.launch(missing.toTypedArray())
                return
            }
        }
        executeShellyPairing()
    }

    private fun executeShellyPairing() {
        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            Toast.makeText(this, "Please enable Bluetooth first", Toast.LENGTH_LONG).show()
            return
        }

        pairingScanner = com.pdcollect.app.service.ShellyBleScanner(this, profile, null)

        pairingDialog = AlertDialog.Builder(this)
            .setTitle("Pair Pillbox Sensor")
            .setMessage("Please open your Shelly Pillbox sensor now...")
            .setNegativeButton("Cancel") { _, _ ->
                pairingScanner?.stopScanning()
                pairingScanner = null
            }
            .setCancelable(false)
            .show()

        pairingScanner?.startPairing { macAddress ->
            runOnUiThread {
                pairingDialog?.dismiss()
                profile.shellyMacAddress = macAddress
                Toast.makeText(this, "Paired successfully with: $macAddress", Toast.LENGTH_LONG).show()
                pairingScanner = null
            }
        }
    }
}
