package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.AutoCompleteTextView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import com.pdcollect.app.R
import com.pdcollect.app.data.UserProfile
import org.json.JSONArray
import org.json.JSONObject
import android.util.Log
import androidx.appcompat.app.AlertDialog
import android.os.Build
import android.widget.TextView
import com.pdcollect.app.util.PermissionUtils
import android.Manifest

class ProfileSetupActivity : AppCompatActivity() {

    private lateinit var profile: UserProfile
    private lateinit var medicationContainer: LinearLayout
    private val medicationViews = mutableListOf<Triple<LinearLayout, EditText, EditText>>() // row, name, dose
    
    // Explicitly using MaterialSwitch to match activity_profile_setup.xml
    private lateinit var switchScreenCapture: com.google.android.material.materialswitch.MaterialSwitch
    private lateinit var switchKeylogging: com.google.android.material.materialswitch.MaterialSwitch
    private lateinit var switchFaceDistance: com.google.android.material.materialswitch.MaterialSwitch
    private lateinit var switchAutoUpload: com.google.android.material.materialswitch.MaterialSwitch
    
    private val requestPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        if (isGranted) {
            Toast.makeText(this, "Camera permission granted for face distance.", Toast.LENGTH_SHORT).show()
            if (findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).checkedRadioButtonId == -1) {
                findViewById<android.widget.RadioButton>(R.id.rbFaceDistanceAppForeground).isChecked = true
            }
            findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).visibility = View.VISIBLE
        } else {
            Toast.makeText(this, "Camera permission is required for face distance.", Toast.LENGTH_LONG).show()
            switchFaceDistance.isChecked = false
            findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).visibility = View.GONE
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_profile_setup)

        profile = UserProfile(this)

        val userIdEdit = findViewById<EditText>(R.id.editUserId)
        val ageEdit = findViewById<EditText>(R.id.editAge)
        val genderSpinner = findViewById<AutoCompleteTextView>(R.id.spinnerGender)
        medicationContainer = findViewById(R.id.medicationContainer)
        val addMedButton = findViewById<Button>(R.id.btnAddMedication)
        val pairShellyButton = findViewById<Button>(R.id.btnPairShelly)
        val saveButton = findViewById<Button>(R.id.btnSave)
        
        switchScreenCapture = findViewById(R.id.switchScreenCapture)
        switchKeylogging = findViewById(R.id.switchKeylogging)
        switchFaceDistance = findViewById(R.id.switchFaceDistance)
        switchAutoUpload = findViewById(R.id.switchAutoUpload)

        updatePermissionStatus()

        val genderAdapter = ArrayAdapter.createFromResource(
            this, R.array.gender_options, android.R.layout.simple_spinner_item
        )
        genderAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        genderSpinner.setAdapter(genderAdapter)
        userIdEdit.setText(profile.userId)

        // Removed old manage buttons as they are now part of the status center

        // Pre-fill only when there is real saved profile data.
        if (hasExistingProfileData()) {
            ageEdit.setText(if (profile.age > 0) profile.age.toString() else "")
            
            val adapter = genderSpinner.adapter
            val genderIndex = if (adapter is ArrayAdapter<*>) {
                (adapter as? ArrayAdapter<String>)?.getPosition(profile.gender) ?: -1
            } else -1
            if (genderIndex >= 0) genderSpinner.setText(profile.gender, false)
            
            switchScreenCapture.isChecked = profile.screenCaptureEnabled
            switchKeylogging.isChecked = profile.keyloggingEnabled
            switchFaceDistance.isChecked = profile.faceDistanceEnabled
            switchAutoUpload.isChecked = profile.autoUploadEnabled
            applyFaceDistanceModeToUi(profile.faceDistanceMode)
            
            loadMedications()
        } else {
            // Fresh setup defaults: passive collection starts after setup is saved,
            // while optional sub-features stay opt-in.
            switchScreenCapture.isChecked = false
            switchKeylogging.isChecked = false
            switchFaceDistance.isChecked = false
            switchAutoUpload.isChecked = true
            applyFaceDistanceModeToUi(com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_OFF)
            addMedicationRow()
        }

        setupPermissionAutomation()

        // Setup the TimePickers
        val editMorning = findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.editTimeMorning)
        val editNoon = findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.editTimeNoon)

        editMorning.setText(profile.testTimeMorning)
        editNoon.setText(profile.testTimeNoon)

        editMorning.setOnClickListener {
            val parts = editMorning.text.toString().split(":")
            val h = parts.getOrNull(0)?.toIntOrNull() ?: 8
            val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
            android.app.TimePickerDialog(this, { _, hour, minute ->
                editMorning.setText(String.format(java.util.Locale.US, "%02d:%02d", hour, minute))
            }, h, m, true).show()
        }

        editNoon.setOnClickListener {
            val parts = editNoon.text.toString().split(":")
            val h = parts.getOrNull(0)?.toIntOrNull() ?: 12
            val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
            android.app.TimePickerDialog(this, { _, hour, minute ->
                editNoon.setText(String.format(java.util.Locale.US, "%02d:%02d", hour, minute))
            }, h, m, true).show()
        }

        addMedButton.setOnClickListener { addMedicationRow() }
        pairShellyButton.setOnClickListener { startShellyPairing() }

        // Pre-select the body-side radios from any saved value (so editing
        // an existing profile shows the previous answer). The save block
        // below reads them back into UserProfile.
        prefillBodySideRadios()

        saveButton.setOnClickListener {
            val previousUserId = profile.userId
            val userId = userIdEdit.text.toString().trim()
            val ageStr = ageEdit.text.toString().trim()
            val gender = genderSpinner.text.toString()

            if (userId.isEmpty()) {
                Toast.makeText(this, "Please enter a User ID", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (ageStr.isEmpty()) {
                Toast.makeText(this, "Please enter age", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            com.pdcollect.app.data.StorageDirectoryResolver.migrateUserDirectory(this, previousUserId, userId)
            profile.userId = userId
            profile.age = ageStr.toIntOrNull() ?: 0
            profile.gender = gender
            profile.medications = buildMedicationsJson()
            
            profile.screenCaptureEnabled = switchScreenCapture.isChecked
            profile.keyloggingEnabled = switchKeylogging.isChecked
            profile.faceDistanceMode = selectedFaceDistanceMode()
            profile.autoUploadEnabled = switchAutoUpload.isChecked
            profile.passiveCollectionActive = true
            
            profile.testTimeMorning = editMorning.text.toString()
            profile.testTimeNoon = editNoon.text.toString()

            // Persist body-side answers from radios. Defaults to "Unknown"
            // if the participant didn't pick — never fabricate handedness.
            profile.dominantHand = readDominantHandFromRadios()
            profile.affectedSide = readAffectedSideFromRadios()

            profile.profileComplete = true

            // Write to CSV. Use writeProfileSnapshot() instead of formatting
            // the row inline so any future column added to PROFILE_HEADER
            // (e.g. the recent dominant_hand / affected_side fields) is wired
            // up in exactly one place.
            val dataManager = com.pdcollect.app.data.DataManager(this@ProfileSetupActivity, profile)
            dataManager.writeProfileSnapshot()
            
            lifecycleScope.launch {
                com.pdcollect.app.data.FirebaseSyncManager.saveProfileToCloud(profile, dataManager)
            }

            try {
                com.pdcollect.app.receiver.BatteryReminderReceiver.scheduleBatteryAlarms(this@ProfileSetupActivity)
            } catch (e: Exception) {
               Log.e("ProfileSetup", "Failed to setup battery reminders", e)
            }

            startActivity(Intent(this@ProfileSetupActivity, MainActivity::class.java))
            finish()
        }

        displayAppVersion()
    }

    private fun hasExistingProfileData(): Boolean {
        val hasMedications = runCatching {
            JSONArray(profile.medications).length() > 0
        }.getOrDefault(false)

        return profile.profileComplete ||
            profile.age > 0 ||
            profile.gender.isNotBlank() ||
            hasMedications ||
            profile.screenCaptureEnabled ||
            profile.keyloggingEnabled ||
            profile.faceDistanceEnabled ||
            !profile.autoUploadEnabled ||
            profile.dominantHand != com.pdcollect.app.util.Constants.PARTICIPANT_HAND_UNKNOWN ||
            profile.affectedSide != com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_UNKNOWN
    }

    /**
     * Pre-select the dominant-hand and affected-side radio groups from the
     * UserProfile. Called after the layout is inflated. If the profile has
     * never had these set (fresh install), both default to "Unknown".
     */
    private fun prefillBodySideRadios() {
        val rgDom = findViewById<android.widget.RadioGroup>(R.id.rgDominantHand)
        rgDom.check(when (profile.dominantHand) {
            com.pdcollect.app.util.Constants.PARTICIPANT_HAND_RIGHT -> R.id.rbDominantRight
            com.pdcollect.app.util.Constants.PARTICIPANT_HAND_LEFT -> R.id.rbDominantLeft
            else -> R.id.rbDominantUnknown
        })

        val rgAff = findViewById<android.widget.RadioGroup>(R.id.rgAffectedSide)
        rgAff.check(when (profile.affectedSide) {
            com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_RIGHT -> R.id.rbAffectedRight
            com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_LEFT -> R.id.rbAffectedLeft
            com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_BOTH -> R.id.rbAffectedBoth
            com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_NONE -> R.id.rbAffectedNone
            else -> R.id.rbAffectedUnknown
        })
    }

    private fun readDominantHandFromRadios(): String =
        when (findViewById<android.widget.RadioGroup>(R.id.rgDominantHand).checkedRadioButtonId) {
            R.id.rbDominantRight -> com.pdcollect.app.util.Constants.PARTICIPANT_HAND_RIGHT
            R.id.rbDominantLeft -> com.pdcollect.app.util.Constants.PARTICIPANT_HAND_LEFT
            else -> com.pdcollect.app.util.Constants.PARTICIPANT_HAND_UNKNOWN
        }

    private fun readAffectedSideFromRadios(): String =
        when (findViewById<android.widget.RadioGroup>(R.id.rgAffectedSide).checkedRadioButtonId) {
            R.id.rbAffectedRight -> com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_RIGHT
            R.id.rbAffectedLeft -> com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_LEFT
            R.id.rbAffectedBoth -> com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_BOTH
            R.id.rbAffectedNone -> com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_NONE
            else -> com.pdcollect.app.util.Constants.PARTICIPANT_SIDE_UNKNOWN
        }

    private fun selectedFaceDistanceMode(): String {
        if (!switchFaceDistance.isChecked) {
            return com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_OFF
        }

        return when (findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).checkedRadioButtonId) {
            R.id.rbFaceDistanceTmtOnly -> com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_TMT_ONLY
            R.id.rbFaceDistanceAlways -> com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_ALWAYS
            else -> com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_APP_FOREGROUND
        }
    }

    private fun applyFaceDistanceModeToUi(mode: String) {
        val group = findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode)
        val enabled = mode != com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_OFF
        switchFaceDistance.isChecked = enabled
        group.visibility = if (enabled) View.VISIBLE else View.GONE
        group.check(
            when (mode) {
                com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_APP_FOREGROUND -> R.id.rbFaceDistanceAppForeground
                com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_OFF -> R.id.rbFaceDistanceAppForeground
                com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_TMT_ONLY -> R.id.rbFaceDistanceTmtOnly
                else -> R.id.rbFaceDistanceAlways
            }
        )
    }

    private fun displayAppVersion() {
        try {
            val pInfo = packageManager.getPackageInfo(packageName, 0)
            val version = pInfo.versionName
            val build = pInfo.longVersionCode
            findViewById<TextView>(R.id.tvAppVersion)?.text = "dopa-X Version: $version ($build)"
        } catch (e: Exception) {
            Log.e("ProfileSetup", "Error getting version info", e)
        }
    }

    private fun loadMedications() {
        if (profile.medications.isEmpty()) {
            addMedicationRow()
            return
        }
        try {
            val array = JSONArray(profile.medications)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                addMedicationRow(obj.getString("name"), obj.getString("dose"))
            }
            if (array.length() == 0) addMedicationRow()
        } catch (e: Exception) {
            addMedicationRow()
        }
    }

    // Navigation now handled via PermissionUtils in updatePermissionStatus

    private fun addMedicationRow(name: String = "", dose: String = "") {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = 8 }
        }

        val nameEdit = EditText(this).apply {
            hint = "Medication name"
            setText(name)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        val doseEdit = EditText(this).apply {
            hint = "Dose"
            setText(dose)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 0.7f)
        }
        val removeBtn = Button(this).apply {
            text = "X"
            setPadding(0, 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(100, LinearLayout.LayoutParams.WRAP_CONTENT, 0.3f)
            setOnClickListener {
                medicationContainer.removeView(row)
                medicationViews.removeAll { it.first == row }
            }
        }

        row.addView(nameEdit)
        row.addView(doseEdit)
        row.addView(removeBtn)
        medicationContainer.addView(row)
        medicationViews.add(Triple(row, nameEdit, doseEdit))
    }

    private fun buildMedicationsJson(): String {
        val array = JSONArray()
        for ((_, nameEdit, doseEdit) in medicationViews) {
            val name = nameEdit.text.toString().trim()
            val dose = doseEdit.text.toString().trim()
            if (name.isNotEmpty()) {
                array.put(JSONObject().apply {
                    put("name", name)
                    put("dose", dose)
                })
            }
        }
        return array.toString()
    }

    private fun setupPermissionAutomation() {
        val faceModeGroup = findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode)

        // Camera — used by the on-device face-distance estimator. We always
        // show a rationale before launching the system permission sheet so
        // the user understands what the camera is for *before* the modal
        // appears. ML Kit runs entirely on-device; no frames leave the phone.
        switchFaceDistance.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked) {
                faceModeGroup.visibility = View.VISIBLE
                if (faceModeGroup.checkedRadioButtonId == -1) {
                    findViewById<android.widget.RadioButton>(R.id.rbFaceDistanceAppForeground).isChecked = true
                }
                if (!PermissionUtils.hasCameraPermission(this)) {
                    AlertDialog.Builder(this)
                        .setTitle("Allow camera for face distance?")
                        .setMessage(
                            "This estimates how far your face is from the screen without storing photos or video.\n\n" +
                                "test battery — useful for interpreting motor data.\n\n" +
                                "or use it during passive collection and tests. Faces are processed " +
                                "on your device by ML Kit; only the distance number is saved."
                        )
                        .setMessage(
                            "This estimates how far your face is from the screen without storing photos or video.\n\n" +
                                "You can keep it conservative so it runs only while dopa-X is open, " +
                                "or use it during passive collection and tests. Faces are processed " +
                                "on your device by ML Kit; only the distance number is saved."
                        )
                        .setPositiveButton("Continue") { _, _ ->
                            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
                        }
                        .setNegativeButton("Not now") { _, _ ->
                            switchFaceDistance.isChecked = false
                            findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).visibility = View.GONE
                        }
                        .show()
                }
            } else if (PermissionUtils.hasCameraPermission(this)) {
                findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).visibility = View.GONE
                showRevokeDialog("Camera", "Face Distance") { PermissionUtils.openAppSettings(this) }
            } else {
                findViewById<android.widget.RadioGroup>(R.id.rgFaceDistanceMode).visibility = View.GONE
            }
        }

        faceModeGroup.setOnCheckedChangeListener { _, checkedId ->
            if (!switchFaceDistance.isChecked) return@setOnCheckedChangeListener
            if (checkedId == R.id.rbFaceDistanceAlways &&
                !PermissionUtils.isAccessibilityServiceEnabled(this)
            ) {
                showAccessibilityGuide(
                    title = "Allow interaction access for background face distance?",
                    featureSummary =
                        "To measure face distance while other apps are open, dopa-X needs to know which app is currently on screen."
                ) {
                    findViewById<android.widget.RadioButton>(R.id.rbFaceDistanceAppForeground).isChecked = true
                }
            }
        }

        // Accessibility Service — used to capture which app you're typing in
        // and a *redacted* category for each key (digit / letter / space /
        // punct / backspace). The literal characters typed are never recorded
        // and password fields are skipped entirely.
        switchKeylogging.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked && !PermissionUtils.isAccessibilityServiceEnabled(this)) {
                showAccessibilityGuide(
                    title = "Allow interaction logging?",
                    featureSummary =
                        "This records typing rhythm — the rate, rhythm, and corrections of your keystrokes — without storing the actual letters you type."
                ) {
                    switchKeylogging.isChecked = false
                }
            } else if (!isChecked &&
                PermissionUtils.isAccessibilityServiceEnabled(this) &&
                selectedFaceDistanceMode() != com.pdcollect.app.util.Constants.FACE_DISTANCE_MODE_ALWAYS
            ) {
                showRevokeDialog("Interaction access (Accessibility)", "Interaction Logging") {
                    PermissionUtils.openAccessibilitySettings(this)
                }
            }
        }

        // Visual Context (screen capture) — currently disabled in the build
        // but the toggle is left in for future activation. The two extra
        // permissions (overlay + usage access) are pre-requested here so
        // when the feature is re-enabled the participant doesn't get
        // bounced through three system screens in a row.
        switchScreenCapture.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked) {
                if (!android.provider.Settings.canDrawOverlays(this)) {
                    AlertDialog.Builder(this)
                        .setTitle("Allow recording-status indicator?")
                        .setMessage(
                            "Visual Context shows a small floating dot on your screen whenever recording " +
                                "is active, so you always know when dopa-X is capturing.\n\n" +
                                "The next screen asks for \"Display over other apps\" — this is what lets " +
                                "the dot stay visible above whatever app you're using."
                        )
                        .setPositiveButton("Continue") { _, _ ->
                            val intent = Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                android.net.Uri.parse("package:$packageName"))
                            startActivity(intent)
                        }
                        .setNegativeButton("Cancel") { _, _ -> switchScreenCapture.isChecked = false }
                        .show()
                } else if (!PermissionUtils.hasUsageStatsPermission(this)) {
                    AlertDialog.Builder(this)
                        .setTitle("Allow app-usage detection?")
                        .setMessage(
                            "So research data can be matched to the right activity (e.g. \"typed for " +
                                "5 min in WhatsApp\"), dopa-X needs to know which app is in the foreground.\n\n" +
                                "On the next screen, scroll to \"dopa-X\" and toggle \"Permit usage access\" on. " +
                                "No app contents are read — only the package name (e.g. com.whatsapp)."
                        )
                        .setPositiveButton("Go to Settings") { _, _ ->
                            PermissionUtils.openUsageAccessSettings(this)
                        }
                        .setNegativeButton("Cancel") { _, _ -> switchScreenCapture.isChecked = false }
                        .show()
                }
            } else {
                if (PermissionUtils.hasUsageStatsPermission(this) || PermissionUtils.canDrawOverlays(this)) {
                    showRevokeDialog("Usage Access / Overlay", "Visual Context") {
                        PermissionUtils.openAppSettings(this)
                    }
                }
            }
        }
    }

    private fun showRevokeDialog(permName: String, featureName: String, action: () -> Unit) {
        AlertDialog.Builder(this)
            .setTitle("Permission still granted")
            .setMessage(
                "You turned off \"$featureName\", so dopa-X has stopped using it — but Android still " +
                    "lists the \"$permName\" permission as allowed in your phone settings.\n\n" +
                    "If you'd like to remove it for full peace of mind, open Settings now."
            )
            .setPositiveButton("Open Settings") { _, _ -> action() }
            .setNegativeButton("Leave it", null)
            .show()
    }

    private fun showAccessibilityGuide(
        title: String,
        featureSummary: String,
        onCancel: () -> Unit
    ) {
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(PermissionUtils.accessibilitySettingsHelp(featureSummary))
            .setPositiveButton("Open Accessibility Settings") { _, _ ->
                PermissionUtils.openAccessibilitySettings(this)
            }
            .setNegativeButton("Cancel") { _, _ -> onCancel() }
            .setCancelable(false)
            .show()
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStatus()
    }

    override fun onDestroy() {
        super.onDestroy()
        pairingScanner?.stopScanning()
        pairingScanner = null
        pairingDialog?.dismiss()
        pairingDialog = null
    }

    /**
     * One row in the permission status list. We split *what the feature is*
     * from *why it needs the permission* so the user can decide informedly.
     */
    private data class PermissionEntry(
        val name: String,            // Plain-English feature name
        val purpose: String,         // What it does + why this permission is needed
        val isGranted: Boolean,
        val openSettings: () -> Unit
    )

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
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val required = arrayOf(android.Manifest.permission.BLUETOOTH_SCAN, android.Manifest.permission.BLUETOOTH_CONNECT)
            val missing = required.filter {
                androidx.core.content.ContextCompat.checkSelfPermission(this, it) != android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            if (missing.isNotEmpty()) {
                btPermissionLauncher.launch(missing.toTypedArray())
                return
            }
        }
        executeShellyPairing()
    }

    private fun executeShellyPairing() {
        val btManager = getSystemService(android.content.Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            Toast.makeText(this, "Please enable Bluetooth first", Toast.LENGTH_LONG).show()
            return
        }

        pairingScanner = com.pdcollect.app.service.ShellyBleScanner(this, profile, null)
        
        pairingDialog = androidx.appcompat.app.AlertDialog.Builder(this)
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

    private fun updatePermissionStatus() {
        val container = findViewById<LinearLayout>(R.id.permissionStatusContainer) ?: return
        container.removeAllViews()

        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val entries = mutableListOf(
            PermissionEntry(
                name = "Interaction Logging",
                purpose = "Records typing rhythm. Also used by face distance if you choose background tracking across other apps.",
                isGranted = PermissionUtils.isAccessibilityServiceEnabled(this),
                openSettings = { PermissionUtils.openAccessibilitySettings(this) }
            ),
            PermissionEntry(
                name = "App Usage Detection",
                purpose = "Tags data with which app you're in (e.g. WhatsApp). Reads app names only — not their contents.",
                isGranted = PermissionUtils.hasUsageStatsPermission(this),
                openSettings = { PermissionUtils.openUsageAccessSettings(this) }
            ),
            PermissionEntry(
                name = "Recording Indicator",
                purpose = "A small floating dot shows whenever dopa-X is recording. Needs \"Display over other apps\".",
                isGranted = PermissionUtils.canDrawOverlays(this),
                openSettings = { PermissionUtils.openOverlaySettings(this) }
            ),
            PermissionEntry(
                name = "Face Distance",
                purpose = "Uses the camera to estimate face-to-screen distance in the mode you choose below.",
                isGranted = PermissionUtils.hasCameraPermission(this),
                openSettings = { PermissionUtils.openAppSettings(this) }
            )
        )

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            entries.add(
                PermissionEntry(
                    name = "Test Reminders",
                    purpose = "Lets dopa-X post the daily prompt notifications at your scheduled times.",
                    isGranted = PermissionUtils.hasNotificationPermission(this),
                    openSettings = { PermissionUtils.openAppSettings(this) }
                )
            )
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            entries.add(
                PermissionEntry(
                    name = "On-Time Reminders",
                    purpose = "Allows the daily prompt to fire exactly at your chosen time, not delayed by battery saver.",
                    isGranted = PermissionUtils.hasExactAlarmPermission(this),
                    openSettings = { PermissionUtils.openExactAlarmSettings(this) }
                )
            )
        }

        // Theme-aware status colors. We avoid encoding state in color *alone*
        // (the leading icon + status text both signal it) so this works for
        // color-blind users too.
        val grantedColor = androidx.core.content.ContextCompat.getColor(this, R.color.primary)
        val ungrantedColor = androidx.core.content.ContextCompat.getColor(this, R.color.tertiary)
        val onSurface = androidx.core.content.ContextCompat.getColor(this, R.color.on_surface)
        val secondary = androidx.core.content.ContextCompat.getColor(this, R.color.secondary)

        for (entry in entries) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(4), dp(12), dp(4), dp(12))
                isClickable = true
                isFocusable = true
                val typedValue = android.util.TypedValue()
                theme.resolveAttribute(android.R.attr.selectableItemBackground, typedValue, true)
                setBackgroundResource(typedValue.resourceId)
                setOnClickListener { entry.openSettings() }
                contentDescription = "${entry.name}. " +
                    (if (entry.isGranted) "Allowed. " else "Not allowed. ") +
                    entry.purpose + " Tap to open settings."
            }

            val icon = TextView(this).apply {
                text = if (entry.isGranted) "✓" else "!"
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 18f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(if (entry.isGranted) grantedColor else ungrantedColor)
                gravity = android.view.Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(dp(28), LinearLayout.LayoutParams.WRAP_CONTENT)
                    .apply { marginEnd = dp(12); topMargin = dp(2) }
            }

            // Two-line text block: bold feature name + secondary explanation.
            val textCol = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            val nameTv = TextView(this).apply {
                text = entry.name
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(onSurface)
            }
            val purposeTv = TextView(this).apply {
                text = entry.purpose
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(secondary)
                setLineSpacing(0f, 1.15f)
            }
            val statusTv = TextView(this).apply {
                text = if (entry.isGranted) "Allowed — tap to manage" else "Not allowed — tap to grant"
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 11f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(if (entry.isGranted) grantedColor else ungrantedColor)
                (layoutParams as? LinearLayout.LayoutParams)?.topMargin = dp(2)
            }
            textCol.addView(nameTv)
            textCol.addView(purposeTv)
            textCol.addView(statusTv)

            val arrow = TextView(this).apply {
                text = "›"
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 22f)
                setTextColor(secondary)
                gravity = android.view.Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.MATCH_PARENT
                ).apply { marginStart = dp(8) }
            }

            row.addView(icon)
            row.addView(textCol)
            row.addView(arrow)

            // Light divider between rows (skip after the last).
            container.addView(row)
            if (entry !== entries.last()) {
                val divider = android.view.View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT, dp(1)
                    )
                    setBackgroundColor(androidx.core.content.ContextCompat
                        .getColor(this@ProfileSetupActivity, R.color.surface_container_high))
                }
                container.addView(divider)
            }
        }
    }
}

