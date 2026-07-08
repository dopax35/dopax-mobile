package com.pdcollect.app.ui

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.work.WorkManager
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.receiver.BatteryReminderReceiver
import com.pdcollect.app.service.AntHRService
import com.pdcollect.app.service.BeanieStatusStore
import com.pdcollect.app.service.BeanieService
import com.pdcollect.app.service.FaceDistanceService
import com.pdcollect.app.service.PDCollectService
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.PermissionUtils
import java.util.Locale

class SettingsActivity : AppCompatActivity() {

    private lateinit var profile: UserProfile
    private lateinit var settingsDataManager: DataManager
    private lateinit var tvBeanieDevice: TextView
    private lateinit var tvBeanieStatus: TextView
    private lateinit var tvBeanieTemp: TextView
    private lateinit var tvBeanieHeatFlux: TextView
    private lateinit var viewBeanieStatusDot: android.view.View
    private lateinit var switchKeyLogging: androidx.appcompat.widget.SwitchCompat
    private lateinit var switchFaceDistance: androidx.appcompat.widget.SwitchCompat
    private lateinit var faceDistanceModeGroup: RadioGroup
    private lateinit var medicationContainer: LinearLayout
    private val medicationViews = mutableListOf<Triple<LinearLayout, EditText, EditText>>()

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

    private val cameraPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            Toast.makeText(this, "Camera permission granted for face distance.", Toast.LENGTH_SHORT).show()
            if (faceDistanceModeGroup.checkedRadioButtonId == -1) {
                findViewById<android.widget.RadioButton>(R.id.rbFaceDistanceAppForeground).isChecked = true
            }
            faceDistanceModeGroup.visibility = View.VISIBLE
            profile.faceDistanceMode = selectedFaceDistanceMode()
            syncFaceDistanceService()
        } else {
            Toast.makeText(this, "Camera permission is required for face distance.", Toast.LENGTH_LONG).show()
            switchFaceDistance.isChecked = false
            faceDistanceModeGroup.visibility = View.GONE
        }
        updatePermissionStatus()
    }

    private val beanieReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            updateBeanieUi(
                connected = intent.getBooleanExtra(BeanieService.EXTRA_CONNECTED, false),
                deviceName = intent.getStringExtra(BeanieService.EXTRA_DEVICE_NAME) ?: "",
                status = intent.getStringExtra(BeanieService.EXTRA_STATUS) ?: BeanieService.STATUS_IDLE,
                tskinC = if (intent.hasExtra(BeanieService.EXTRA_TSKIN_C)) {
                    intent.getDoubleExtra(BeanieService.EXTRA_TSKIN_C, Double.NaN)
                } else {
                    Double.NaN
                },
                heatFlux = if (intent.hasExtra(BeanieService.EXTRA_HEAT_FLUX)) {
                    intent.getDoubleExtra(BeanieService.EXTRA_HEAT_FLUX, Double.NaN)
                } else {
                    Double.NaN
                }
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        profile = UserProfile(this)
        settingsDataManager = DataManager(this, profile)
        settingsDataManager.initializePassiveLogs()
        tvBeanieDevice = findViewById(R.id.tvBeanieDevice)
        tvBeanieStatus = findViewById(R.id.tvBeanieStatus)
        tvBeanieTemp = findViewById(R.id.tvBeanieTemp)
        tvBeanieHeatFlux = findViewById(R.id.tvBeanieHeatFlux)
        viewBeanieStatusDot = findViewById(R.id.viewBeanieStatusDot)
        switchKeyLogging = findViewById(R.id.switchKeyLogging)
        switchFaceDistance = findViewById(R.id.switchFaceDistance)
        faceDistanceModeGroup = findViewById(R.id.rgFaceDistanceMode)
        medicationContainer = findViewById(R.id.medicationContainer)

        val tvInfo = findViewById<TextView>(R.id.tvSettingsInfo)
        tvInfo.text = buildString {
            appendLine("User ID: ${profile.userId}")
            appendLine("Data directory: ${settingsDataManager.getStoragePath()}")
            appendLine("Data size: ${"%.2f".format(settingsDataManager.getDataSizeBytes() / (1024.0 * 1024.0))} MB")
            appendLine()
            appendLine("Permissions below can be turned on or off in your phone settings.")
        }

        switchKeyLogging.isChecked = profile.keyloggingEnabled
        applyFaceDistanceModeToUi(profile.faceDistanceMode)
        bindFeatureToggles()
        bindMedicationEditor()
        updatePermissionStatus()

        findViewById<Button>(R.id.btnManageBeanie).apply {
            isEnabled = false
            text = "Disabled"
        }
        refreshBeanieUiFromProfile()

        // Body-side metadata is stamped into new motor-test rows only.
        bindDominantHand()
        bindAffectedSide()

        findViewById<Button>(R.id.btnStopAll).setOnClickListener {
            PDCollectService.stop(this)
            AntHRService.stop(this)
            BeanieService.stop(this)
            tvInfo.append("\n\nAll services stopped.")
        }

        findViewById<Button>(R.id.btnDebugPreview).setOnClickListener {
            startActivity(Intent(this, DebugDataPreviewActivity::class.java))
        }

        findViewById<Button>(R.id.btnResetConsent).setOnClickListener {
            profile.consentGiven = false
            profile.profileComplete = false
            PDCollectService.stop(this)
            BeanieService.stop(this)
            startActivity(Intent(this, ConsentActivity::class.java))
            finish()
        }

        findViewById<Button>(R.id.btnWithdrawFromStudy).setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle("Withdraw from study?")
                .setMessage(
                    "This will:\n\n" +
                        "- Stop all data collection immediately\n" +
                        "- Cancel scheduled uploads and test reminders\n" +
                        "- Delete every file this app has saved on your device\n" +
                        "- Reset your profile and consent\n\n" +
                        "Data already uploaded to research servers is not affected " +
                        "by this action - to request its removal, contact the research " +
                "team using the email in the Privacy Policy.\n\n" +
                        "This cannot be undone. Continue?"
                )
                .setPositiveButton("Withdraw and delete") { _, _ -> performWithdrawal(settingsDataManager) }
                .setNegativeButton("Cancel", null)
                .show()
        }
    }

    override fun onResume() {
        super.onResume()
        refreshBeanieUiFromProfile()
        updatePermissionStatus()
        syncFaceDistanceService()
        ContextCompat.registerReceiver(
            this,
            beanieReceiver,
            IntentFilter(BeanieService.ACTION_BEANIE_UPDATE),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(beanieReceiver)
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        pairingScanner?.stopScanning()
        pairingScanner = null
        pairingDialog?.dismiss()
        pairingDialog = null
        // settingsDataManager calls initializePassiveLogs(), which opens ~11
        // BufferedWriters up front (touch/keys/apps/sensors/etc) plus a
        // background HandlerThread. Without closeAll() here, every visit to
        // Settings left all of that open for the rest of the app process.
        // Guarded the same way MainActivity guards its own DataManager, in
        // case onCreate() returns early before settingsDataManager is set.
        if (::settingsDataManager.isInitialized) {
            settingsDataManager.closeAll()
        }
    }

    private fun bindFeatureToggles() {
        switchKeyLogging.setOnCheckedChangeListener { _, isChecked ->
            profile.keyloggingEnabled = isChecked
            if (isChecked && !PermissionUtils.isKeyboardEnabled(this)) {
                // Keyboard not yet enabled — guide user to enable it
                AlertDialog.Builder(this)
                    .setTitle("Enable PDCollect Keyboard")
                    .setMessage(
                        "To measure your typing rhythm, please enable the PDCollect Keyboard.\n\n" +
                            "Tap \"Open Settings\", then:\n" +
                            "General Management → Keyboard → On-screen keyboards → PDCollect Keyboard\n\n" +
                            "The keyboard logs only typing speed and word length — never the text you type."
                    )
                    .setPositiveButton("Open Settings") { _, _ ->
                        PermissionUtils.openKeyboardSettings(this)
                    }
                    .setNegativeButton("Not now", null)
                    .show()
            }
            syncFaceDistanceService()
            updatePermissionStatus()
        }

        switchFaceDistance.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked) {
                faceDistanceModeGroup.visibility = View.VISIBLE
                if (faceDistanceModeGroup.checkedRadioButtonId == -1) {
                    findViewById<android.widget.RadioButton>(R.id.rbFaceDistanceAppForeground).isChecked = true
                }
                if (!PermissionUtils.hasCameraPermission(this)) {
                    AlertDialog.Builder(this)
                        .setTitle("Allow camera for face distance?")
                        .setMessage(
                            "This estimates how far your face is from the screen without storing photos or video. " +
                                "You can keep it conservative so it runs only while dopa-X is open."
                        )
                        .setPositiveButton("Continue") { _, _ ->
                            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                        }
                        .setNegativeButton("Not now") { _, _ ->
                            switchFaceDistance.isChecked = false
                            faceDistanceModeGroup.visibility = View.GONE
                        }
                        .show()
                } else {
                    profile.faceDistanceMode = selectedFaceDistanceMode()
                    syncFaceDistanceService()
                }
            } else {
                profile.faceDistanceEnabled = false
                faceDistanceModeGroup.visibility = View.GONE
                syncFaceDistanceService()
                if (PermissionUtils.hasCameraPermission(this)) {
                    showRevokeDialog("Camera", "Face Distance") {
                        PermissionUtils.openAppSettings(this)
                    }
                }
            }
            updatePermissionStatus()
        }

        faceDistanceModeGroup.setOnCheckedChangeListener { _, checkedId ->
            if (!switchFaceDistance.isChecked) return@setOnCheckedChangeListener
            if (checkedId == -1) return@setOnCheckedChangeListener

            profile.faceDistanceMode = selectedFaceDistanceMode()
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
            syncFaceDistanceService()
            updatePermissionStatus()
        }
    }

    private fun selectedFaceDistanceMode(): String {
        if (!switchFaceDistance.isChecked) {
            return Constants.FACE_DISTANCE_MODE_OFF
        }
        return when (faceDistanceModeGroup.checkedRadioButtonId) {
            R.id.rbFaceDistanceAlways -> Constants.FACE_DISTANCE_MODE_ALWAYS
            R.id.rbFaceDistanceTmtOnly -> Constants.FACE_DISTANCE_MODE_TMT_ONLY
            else -> Constants.FACE_DISTANCE_MODE_APP_FOREGROUND
        }
    }

    private fun applyFaceDistanceModeToUi(mode: String) {
        val enabled = mode != Constants.FACE_DISTANCE_MODE_OFF
        switchFaceDistance.isChecked = enabled
        faceDistanceModeGroup.visibility = if (enabled) View.VISIBLE else View.GONE
        faceDistanceModeGroup.check(
            when (mode) {
                Constants.FACE_DISTANCE_MODE_OFF -> R.id.rbFaceDistanceAppForeground
                Constants.FACE_DISTANCE_MODE_ALWAYS -> R.id.rbFaceDistanceAlways
                Constants.FACE_DISTANCE_MODE_TMT_ONLY -> R.id.rbFaceDistanceTmtOnly
                else -> R.id.rbFaceDistanceAppForeground
            }
        )
    }

    private fun syncFaceDistanceService() {
        val shouldRunFaceDistance = when (profile.faceDistanceMode) {
            Constants.FACE_DISTANCE_MODE_ALWAYS ->
                PermissionUtils.hasCameraPermission(this) && PermissionUtils.isAccessibilityServiceEnabled(this)
            Constants.FACE_DISTANCE_MODE_APP_FOREGROUND ->
                PermissionUtils.hasCameraPermission(this)
            else -> false
        }
        if (profile.passiveCollectionActive && shouldRunFaceDistance) {
            FaceDistanceService.start(this)
        } else {
            FaceDistanceService.stop(this)
        }
    }

    private fun bindMedicationEditor() {
        medicationContainer.removeAllViews()
        medicationViews.clear()
        loadMedications()

        findViewById<Button>(R.id.btnAddMedication).setOnClickListener {
            addMedicationRow()
        }
        findViewById<Button>(R.id.btnSaveMedications).setOnClickListener {
            profile.medications = buildMedicationsJson()
            settingsDataManager.writeProfileSnapshot()
            Toast.makeText(this, "Medications saved", Toast.LENGTH_SHORT).show()
        }
        findViewById<Button>(R.id.btnPairShelly).setOnClickListener {
            startShellyPairing()
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

    private fun loadMedications() {
        val stored = profile.medications
        val added = runCatching {
            val array = org.json.JSONArray(stored)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                addMedicationRow(
                    name = obj.optString("name"),
                    dose = obj.optString("dose")
                )
            }
            array.length()
        }.getOrDefault(0)

        if (added == 0) {
            addMedicationRow()
        }
    }

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
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            )
        }
        val doseEdit = EditText(this).apply {
            hint = "Dose"
            setText(dose)
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                0.7f
            )
        }
        val removeBtn = Button(this).apply {
            text = "X"
            setPadding(0, 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                100,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                0.3f
            )
            setOnClickListener {
                medicationContainer.removeView(row)
                medicationViews.removeAll { it.first == row }
                if (medicationViews.isEmpty()) {
                    addMedicationRow()
                }
            }
        }

        row.addView(nameEdit)
        row.addView(doseEdit)
        row.addView(removeBtn)
        medicationContainer.addView(row)
        medicationViews.add(Triple(row, nameEdit, doseEdit))
    }

    private fun buildMedicationsJson(): String {
        val array = org.json.JSONArray()
        for ((_, nameEdit, doseEdit) in medicationViews) {
            val name = nameEdit.text.toString().trim()
            val dose = doseEdit.text.toString().trim()
            if (name.isNotEmpty()) {
                array.put(org.json.JSONObject().apply {
                    put("name", name)
                    put("dose", dose)
                })
            }
        }
        return array.toString()
    }

    private fun bindDominantHand() {
        val group = findViewById<RadioGroup>(R.id.rgDominantHand)
        val checkedId = when (profile.dominantHand) {
            Constants.PARTICIPANT_HAND_RIGHT -> R.id.rbDominantRight
            Constants.PARTICIPANT_HAND_LEFT -> R.id.rbDominantLeft
            else -> R.id.rbDominantUnknown
        }
        group.check(checkedId)
        group.setOnCheckedChangeListener { _, id ->
            profile.dominantHand = when (id) {
                R.id.rbDominantRight -> Constants.PARTICIPANT_HAND_RIGHT
                R.id.rbDominantLeft -> Constants.PARTICIPANT_HAND_LEFT
                else -> Constants.PARTICIPANT_HAND_UNKNOWN
            }
        }
    }

    private fun bindAffectedSide() {
        val group = findViewById<RadioGroup>(R.id.rgAffectedSide)
        val checkedId = when (profile.affectedSide) {
            Constants.PARTICIPANT_SIDE_RIGHT -> R.id.rbAffectedRight
            Constants.PARTICIPANT_SIDE_LEFT -> R.id.rbAffectedLeft
            Constants.PARTICIPANT_SIDE_BOTH -> R.id.rbAffectedBoth
            Constants.PARTICIPANT_SIDE_NONE -> R.id.rbAffectedNone
            else -> R.id.rbAffectedUnknown
        }
        group.check(checkedId)
        group.setOnCheckedChangeListener { _, id ->
            profile.affectedSide = when (id) {
                R.id.rbAffectedRight -> Constants.PARTICIPANT_SIDE_RIGHT
                R.id.rbAffectedLeft -> Constants.PARTICIPANT_SIDE_LEFT
                R.id.rbAffectedBoth -> Constants.PARTICIPANT_SIDE_BOTH
                R.id.rbAffectedNone -> Constants.PARTICIPANT_SIDE_NONE
                else -> Constants.PARTICIPANT_SIDE_UNKNOWN
            }
        }
    }

    private fun refreshBeanieUiFromProfile() {
        if (profile.beanieDeviceAddress.isBlank()) {
            updateBeanieUi(
                connected = false,
                deviceName = "",
                status = "Not set up",
                tskinC = Double.NaN,
                heatFlux = Double.NaN
            )
            return
        }

        val snapshot = BeanieStatusStore.load(this)
        updateBeanieUi(
            connected = snapshot?.connected == true,
            deviceName = snapshot?.deviceName?.takeIf { it.isNotBlank() }
                ?: profile.beanieDeviceName.ifBlank { profile.beanieDeviceAddress },
            status = snapshot?.status ?: "Checking status...",
            tskinC = snapshot?.tskinC ?: Double.NaN,
            heatFlux = snapshot?.heatFluxCalPerSec ?: Double.NaN
        )
    }

    private fun updateBeanieUi(
        connected: Boolean,
        deviceName: String,
        status: String,
        tskinC: Double,
        heatFlux: Double
    ) {
        tvBeanieDevice.text = "Beanie support disabled"
        tvBeanieStatus.text = "Disabled"
        viewBeanieStatusDot.backgroundTintList = android.content.res.ColorStateList.valueOf(
            ContextCompat.getColor(this, R.color.gray_50)
        )
        tvBeanieTemp.text = "-- C"
        tvBeanieHeatFlux.text = "-- cal/s"
    }

    private data class PermissionEntry(
        val name: String,
        val purpose: String,
        val isGranted: Boolean,
        val requiredNow: Boolean,
        val openSettings: () -> Unit
    )

    private fun updatePermissionStatus() {
        val container = findViewById<LinearLayout>(R.id.permissionStatusContainer) ?: return
        container.removeAllViews()

        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val entries = mutableListOf(
            PermissionEntry(
                name = "PDCollect Keyboard",
                purpose = "Enables typing-rhythm measurement (word length, backspace rate). Bilingual Hebrew/English. Never logs what you type.",
                isGranted = PermissionUtils.isKeyboardEnabled(this),
                requiredNow = profile.keyloggingEnabled,
                openSettings = { PermissionUtils.openKeyboardSettings(this) }
            ),

            PermissionEntry(
                name = "Interaction access",
                purpose = "Required for face distance background tracking across all apps.",
                isGranted = PermissionUtils.isAccessibilityServiceEnabled(this),
                requiredNow = profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS,
                openSettings = {
                    showAccessibilityGuide(
                        title = "Manage interaction access",
                        featureSummary =
                            "Use this screen to turn dopa-X interaction access on or off."
                    ) {}
                }
            ),

            PermissionEntry(
                name = "Camera",
                purpose = "Needed for face distance in conservative, background, or TMT-only modes.",
                isGranted = PermissionUtils.hasCameraPermission(this),
                requiredNow = profile.faceDistanceEnabled,
                openSettings = {
                    if (PermissionUtils.hasCameraPermission(this)) {
                        PermissionUtils.openAppSettings(this)
                    } else {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    }
                }
            ),
            PermissionEntry(
                name = "Background reliability",
                purpose = "Lets passive collection keep running without being paused by battery optimization.",
                isGranted = PermissionUtils.isIgnoringBatteryOptimizations(this),
                requiredNow = profile.passiveCollectionActive,
                openSettings = { PermissionUtils.openBatteryOptimizationSettings(this) }
            )
        )

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            entries.add(
                PermissionEntry(
                    name = "Notifications",
                    purpose = "Lets dopa-X show daily prompts and ongoing collection status.",
                    isGranted = PermissionUtils.hasNotificationPermission(this),
                    requiredNow = false,
                    openSettings = { PermissionUtils.openNotificationSettings(this) }
                )
            )
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            entries.add(
                PermissionEntry(
                    name = "On-time reminders",
                    purpose = "Lets the daily prompt fire at the chosen time instead of waiting for battery saver.",
                    isGranted = PermissionUtils.hasExactAlarmPermission(this),
                    requiredNow = true,
                    openSettings = { PermissionUtils.openExactAlarmSettings(this) }
                )
            )
        }

        val grantedColor = ContextCompat.getColor(this, R.color.primary)
        val ungrantedColor = ContextCompat.getColor(this, R.color.tertiary)
        val onSurface = ContextCompat.getColor(this, R.color.on_surface)
        val secondary = ContextCompat.getColor(this, R.color.secondary)

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
            }

            val icon = TextView(this).apply {
                text = if (entry.isGranted) "OK" else "!"
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(if (entry.isGranted) grantedColor else ungrantedColor)
                gravity = android.view.Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(dp(28), LinearLayout.LayoutParams.WRAP_CONTENT)
                    .apply { marginEnd = dp(12); topMargin = dp(2) }
            }

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
                text = when {
                    entry.isGranted -> "Allowed - tap to manage"
                    entry.requiredNow -> "Needed now - tap to open"
                    else -> "Optional - tap to enable"
                }
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 11f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(if (entry.isGranted) grantedColor else ungrantedColor)
            }
            textCol.addView(nameTv)
            textCol.addView(purposeTv)
            textCol.addView(statusTv)

            val arrow = TextView(this).apply {
                text = ">"
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 18f)
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
            container.addView(row)
            if (entry !== entries.last()) {
                val divider = View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        dp(1)
                    )
                    setBackgroundColor(ContextCompat.getColor(this@SettingsActivity, R.color.surface_container_high))
                }
                container.addView(divider)
            }
        }
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
            .show()
    }

    private fun showRevokeDialog(permName: String, featureName: String, action: () -> Unit) {
        AlertDialog.Builder(this)
            .setTitle("Permission still granted")
            .setMessage(
                "You turned off \"$featureName\", so dopa-X has stopped using it — but Android still " +
                    "lists the \"$permName\" permission as allowed in your phone settings.\n\n" +
                    "If you'd like to remove it fully, open Settings now."
            )
            .setPositiveButton("Open Settings") { _, _ -> action() }
            .setNegativeButton("Leave it", null)
            .show()
    }
    private fun performWithdrawal(dataManager: DataManager) {
        runCatching { PDCollectService.stop(this) }
        runCatching { AntHRService.stop(this) }
        runCatching { BeanieService.stop(this) }

        runCatching {
            val wm = WorkManager.getInstance(this)
            wm.cancelAllWorkByTag("auto_upload")
            wm.cancelAllWorkByTag("auto_upload_dispatcher")
        }

        runCatching { BatteryReminderReceiver.cancelBatteryAlarms(this) }

        val wiped = runCatching { dataManager.wipeAllData() }.getOrDefault(false)
        runCatching { profile.clearAll() }

        val msg = if (wiped) {
            "Your data has been deleted. Please also disable \"dopa-X\" in Accessibility Settings to fully stop background capture."
        } else {
            "Withdrawal completed but some files could not be deleted. Please uninstall the app to fully remove residual data."
        }
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()

        runCatching { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        finishAffinity()
    }
}

