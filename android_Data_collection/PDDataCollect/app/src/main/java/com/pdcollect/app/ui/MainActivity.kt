package com.pdcollect.app.ui

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.receiver.BatteryReminderReceiver
import com.pdcollect.app.receiver.EveningReminderReceiver
import com.pdcollect.app.service.AntHRService
import com.pdcollect.app.service.BeanieStatusStore
import com.pdcollect.app.service.BeanieService
import com.pdcollect.app.service.FaceDistanceService
import com.pdcollect.app.service.PDCollectService
import com.pdcollect.app.ui.view.DailyMetricChartView
import com.pdcollect.app.ui.view.TrendSummaryChartView
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.PermissionUtils
import com.pdcollect.app.util.SetupVerificationManager
import com.pdcollect.app.util.TimeUtils
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.pdcollect.app.worker.DashboardCacheWorker
import com.pdcollect.app.worker.DataUploadWorker

class MainActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_OPEN_REPORTING = "open_reporting"
    }

    private lateinit var profile: UserProfile
    private lateinit var dataManager: DataManager

    private lateinit var appUpdateManager: AppUpdateManager
    private val immediateUpdateRequestCode = 9001

    private lateinit var cardVitalSigns: com.google.android.material.card.MaterialCardView
    private lateinit var tvLiveBpm: TextView
    private lateinit var tvLiveHrv: TextView

    private lateinit var cardBeanieVitals: com.google.android.material.card.MaterialCardView
    private lateinit var tvBeanieSkinTemp: TextView
    private lateinit var tvBeanieHeatFlux: TextView
    private var dashboardRefreshJob: Job? = null

    private val hrUpdateReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val connected = intent.getBooleanExtra(AntHRService.EXTRA_CONNECTED, false)
            val bpm = intent.getIntExtra(AntHRService.EXTRA_BPM, 0)
            val hrv = intent.getFloatExtra(AntHRService.EXTRA_HRV, 0f)

            if (connected) {
                cardVitalSigns.visibility = android.view.View.VISIBLE
                tvLiveBpm.text = if (bpm > 0) "$bpm BPM" else "-- BPM"
                tvLiveHrv.text = if (hrv > 0) "${hrv.toInt()} ms" else "-- ms"
            } else {
                cardVitalSigns.visibility = android.view.View.GONE
            }
        }
    }

    private val beanieUpdateReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val connected = intent.getBooleanExtra(BeanieService.EXTRA_CONNECTED, false)
            val tskin = if (intent.hasExtra(BeanieService.EXTRA_TSKIN_C)) {
                intent.getDoubleExtra(BeanieService.EXTRA_TSKIN_C, Double.NaN)
            } else {
                Double.NaN
            }
            val heatFlux = if (intent.hasExtra(BeanieService.EXTRA_HEAT_FLUX)) {
                intent.getDoubleExtra(BeanieService.EXTRA_HEAT_FLUX, Double.NaN)
            } else {
                Double.NaN
            }
            renderBeanieVitals(
                connected = connected,
                tskin = tskin,
                heatFlux = heatFlux,
                serviceRunning = true
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        profile = UserProfile(this)

        appUpdateManager = AppUpdateManagerFactory.create(this)
        checkForAppUpdate()

        if (!profile.consentGiven) {
            startActivity(Intent(this, ConsentActivity::class.java))
            finish()
            return
        }
        if (!profile.profileComplete) {
            startActivity(Intent(this, ProfileSetupActivity::class.java))
            finish()
            return
        }

        recreateDataManager()

        setContentView(R.layout.activity_main)
        WalkthroughDialog.showIfNeeded(this)

        cardVitalSigns = findViewById(R.id.cardVitalSigns)
        tvLiveBpm = findViewById(R.id.tvLiveBpm)
        tvLiveHrv = findViewById(R.id.tvLiveHrv)

        cardBeanieVitals = findViewById(R.id.cardBeanieVitals)
        tvBeanieSkinTemp = findViewById(R.id.tvBeanieSkinTemp)
        tvBeanieHeatFlux = findViewById(R.id.tvBeanieHeatFlux)
        setupChartDetailLaunchers()

        val drawerLayout = findViewById<androidx.drawerlayout.widget.DrawerLayout>(R.id.drawerLayout)
        findViewById<android.view.View>(R.id.topAppBar).setOnLongClickListener {
            lifecycleScope.launch {
                Toast.makeText(this@MainActivity, "Rebuilding dashboard summaries...", Toast.LENGTH_SHORT).show()
                withContext(Dispatchers.IO) {
                    dataManager.rebuildDashboardSummariesFromScratch()
                }
                Toast.makeText(this@MainActivity, "Dashboard summaries rebuilt", Toast.LENGTH_LONG).show()
                populateDashboardCharts()
            }
            true
        }
        observeDashboardCacheRefresh()

        findViewById<com.google.android.material.appbar.MaterialToolbar>(R.id.topAppBar)
            .setNavigationOnClickListener {
                it.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
                drawerLayout.openDrawer(androidx.core.view.GravityCompat.START)
            }

        findViewById<com.google.android.material.navigation.NavigationView>(R.id.navigationView)
            .setNavigationItemSelectedListener { item ->
                when (item.itemId) {
                    R.id.nav_settings -> startActivity(Intent(this, SettingsActivity::class.java))
                    R.id.nav_data_privacy -> startActivity(Intent(this, DataExportActivity::class.java))
                    R.id.nav_hr_monitor -> startActivity(Intent(this, HRDevicePickerActivity::class.java))
                    R.id.nav_beanie_monitor -> startActivity(Intent(this, BeanieDevicePickerActivity::class.java))
                    R.id.nav_debug -> startActivity(Intent(this, DebugDataPreviewActivity::class.java))
                    R.id.nav_passive_collection -> togglePassiveCollection()
                }
                drawerLayout.closeDrawer(androidx.core.view.GravityCompat.START)
                true
            }

        findViewById<android.view.View>(R.id.btnNavigationTmt).setOnClickListener {
            startActivity(Intent(this, TrailMakingTestActivity::class.java))
        }

        findViewById<android.view.View>(R.id.btnNavigationReport).setOnClickListener {
            showUserReportingMenu()
        }

        findViewById<android.view.View>(R.id.btnActiveTests)?.setOnClickListener {
            startActivity(Intent(this, ActiveTestsActivity::class.java))
        }

        findViewById<android.view.View>(R.id.btnVoiceSample)?.setOnClickListener {
            startActivity(Intent(this, VoiceSampleActivity::class.java))
        }

        findViewById<android.view.View>(R.id.btnRepairSetup)?.setOnClickListener {
            handleRepairAction()
        }

        findViewById<android.view.View>(R.id.viewDebugTrigger)?.setOnClickListener {
            it.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            startActivity(Intent(this, DebugDataPreviewActivity::class.java))
        }

        scheduleDailyUploadWorker()
        updateSetupHealth()
    }

    private fun checkForAppUpdate() {
        appUpdateManager.appUpdateInfo.addOnSuccessListener { appUpdateInfo ->
            if (appUpdateInfo.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
            ) {
                appUpdateManager.startUpdateFlowForResult(
                    appUpdateInfo,
                    AppUpdateType.IMMEDIATE,
                    this,
                    immediateUpdateRequestCode
                )
            }
        }
    }

    private fun scheduleDailyUploadWorker() {
        DataUploadWorker.scheduleDaily(this)
        DashboardCacheWorker.schedulePeriodic(this)
    }

    override fun onResume() {
        super.onResume()
        profile = UserProfile(this)
        recreateDataManager()
        dataManager.initializePassiveLogs()

        val filter = IntentFilter(AntHRService.ACTION_HR_UPDATE)
        val beanieFilter = IntentFilter(BeanieService.ACTION_BEANIE_UPDATE)
        ContextCompat.registerReceiver(
            this,
            beanieUpdateReceiver,
            beanieFilter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        ContextCompat.registerReceiver(
            this,
            hrUpdateReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        syncBeanieUi()

        appUpdateManager.appUpdateInfo.addOnSuccessListener { appUpdateInfo ->
            if (appUpdateInfo.updateAvailability() ==
                UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
            ) {
                appUpdateManager.startUpdateFlowForResult(
                    appUpdateInfo,
                    AppUpdateType.IMMEDIATE,
                    this,
                    immediateUpdateRequestCode
                )
            }
        }

        android.util.Log.d(
            "MainActivity",
            "Profile status: userId=${profile.userId}, faceDistanceMode=${profile.faceDistanceMode}, " +
                "keyloggingEnabled=${profile.keyloggingEnabled}"
        )

        if (profile.consentGiven && profile.profileComplete) {
            syncPassiveServices()
            updateStatus()
            populateDashboardCharts()
            updateSetupHealth()
            BatteryReminderReceiver.scheduleBatteryAlarms(this)
            EveningReminderReceiver.scheduleEveningAlarm(this)
            dataManager.writeProfileSnapshot()
        }

        if (intent.getBooleanExtra(EXTRA_OPEN_REPORTING, false)) {
            intent.removeExtra(EXTRA_OPEN_REPORTING)
            showUserReportingMenu()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(hrUpdateReceiver)
            unregisterReceiver(beanieUpdateReceiver)
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        dashboardRefreshJob?.cancel()
        if (::dataManager.isInitialized) {
            dataManager.closeAll()
        }
        super.onDestroy()
    }

    private fun updateStatus() {
        val navView = findViewById<com.google.android.material.navigation.NavigationView>(R.id.navigationView)
        val passiveToggleItem = navView.menu.findItem(R.id.nav_passive_collection)
        passiveToggleItem.title = if (profile.passiveCollectionActive) {
            "Stop Passive Collection"
        } else {
            "Start Passive Collection"
        }

        dataManager.writeProfileSnapshot()
    }

    private fun populateDashboardCharts() {
        val hasStoredDays = dataManager.listAvailableDates().isNotEmpty()
        val cachedMetrics = dataManager.getCachedDashboardMetrics(trendDays = 0)
        bindDashboardMetrics(
            cachedMetrics,
            dailySubtitleOverride = when {
                !dashboardMetricsEmpty(cachedMetrics) -> null
                hasStoredDays -> "Preparing recent summaries..."
                else -> "Daily profile with moving average"
            }
        )
        dashboardRefreshJob?.cancel()
        val manager = dataManager
        dashboardRefreshJob = lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val metrics = manager.getDashboardMetricsFast(
                        trendDays = 0,
                        maxSyncDates = com.pdcollect.app.data.DashboardSummaryStore.DEFAULT_FAST_SYNC_MAX_DATES
                    )
                    metrics to manager.listAvailableDates().isNotEmpty()
                }.onFailure {
                    android.util.Log.e("MainActivity", "Error refreshing dashboard data", it)
                }.getOrNull()
            }

            if (result != null && manager === dataManager && !isDestroyed && !isFinishing) {
                val (metrics, refreshedHasStoredDays) = result
                bindDashboardMetrics(
                    metrics,
                    dailySubtitleOverride = if (dashboardMetricsEmpty(metrics) && refreshedHasStoredDays) {
                        "Preparing recent summaries..."
                    } else {
                        null
                    }
                )
            }
        }
        DashboardCacheWorker.enqueueRefresh(this, initialDelaySeconds = 0)
    }

    private fun observeDashboardCacheRefresh() {
        WorkManager.getInstance(this)
            .getWorkInfosForUniqueWorkLiveData(DashboardCacheWorker.ONE_TIME_WORK_NAME)
            .observe(this) { infos ->
                if (infos.none { it.state == WorkInfo.State.SUCCEEDED }) return@observe
                if (isDestroyed || isFinishing || !::dataManager.isInitialized) return@observe

                val hasStoredDays = dataManager.listAvailableDates().isNotEmpty()
                val metrics = dataManager.getCachedDashboardMetrics(trendDays = 0)
                bindDashboardMetrics(
                    metrics,
                    dailySubtitleOverride = if (dashboardMetricsEmpty(metrics) && hasStoredDays) {
                        "Preparing recent summaries..."
                    } else {
                        null
                    }
                )
            }
    }

    private fun bindDashboardMetrics(
        metrics: com.pdcollect.app.data.DashboardSummaryStore.DashboardMetrics,
        dailySubtitleOverride: String? = null
    ) {
        val todayMarkers = metrics.dailyComparison.firstOrNull { it.isToday }?.markers.orEmpty()
        val (todayStrideLength, previousStrideLength) = dailyComparisonLines(metrics) { it.strideLength }
        val (todayStrideSpeed, previousStrideSpeed) = dailyComparisonLines(metrics) { it.strideSpeed }
        val (todayTremorPower, previousTremorPower) = dailyComparisonLines(metrics) { it.tremorPower }
        val (todayAsymmetry, previousAsymmetry) = dailyComparisonLines(metrics) { it.asymmetry }
        val dailySubtitle = dailySubtitleOverride ?: buildDailySubtitle(
            hasTodayData = todayStrideLength.isNotEmpty() || todayStrideSpeed.isNotEmpty() || todayTremorPower.isNotEmpty() || todayAsymmetry.isNotEmpty(),
            hasMarkers = todayMarkers.isNotEmpty() ||
                previousStrideLength.any { it.markers.isNotEmpty() } ||
                previousStrideSpeed.any { it.markers.isNotEmpty() } ||
                previousTremorPower.any { it.markers.isNotEmpty() }
        )

        findViewById<DailyMetricChartView>(R.id.chartDailyStrideLength).setData(
            title = "Stride Length",
            subtitle = dailySubtitle,
            unit = "m",
            points = todayStrideLength,
            comparisonLines = previousStrideLength,
            markers = todayMarkers,
            emptyHint = "Walk with the phone in your pocket to capture gait data"
        )
        findViewById<DailyMetricChartView>(R.id.chartDailyStrideSpeed).setData(
            title = "Stride Speed",
            subtitle = dailySubtitle,
            unit = "m/s",
            points = todayStrideSpeed,
            comparisonLines = previousStrideSpeed,
            markers = todayMarkers,
            emptyHint = "Walk with the phone in your pocket to capture gait data"
        )
        findViewById<DailyMetricChartView>(R.id.chartDailyTremorPower).setData(
            title = "Tremor Window Power",
            subtitle = dailySubtitle,
            unit = "%",
            points = todayTremorPower,
            comparisonLines = previousTremorPower,
            markers = todayMarkers,
            emptyHint = "Tremor data will appear once sensors are collecting"
        )
        findViewById<DailyMetricChartView>(R.id.chartDailyAsymmetry).setData(
            title = "Gait Asymmetry",
            subtitle = dailySubtitle,
            unit = "%",
            points = todayAsymmetry,
            comparisonLines = previousAsymmetry,
            markers = todayMarkers,
            emptyHint = "Asymmetry data will appear once gait is detected"
        )
        findViewById<TrendSummaryChartView>(R.id.chartTrendGait).setSeries(
            title = "Peak Gait Trends",
            subtitle = "Per-day maxima; each line uses its own scale",
            series = metrics.gaitTrend,
            emptyHint = "Walk daily with the app running to see multi-day gait trends here"
        )
        findViewById<TrendSummaryChartView>(R.id.chartTrendTests).setSeries(
            title = "Assessment Trends",
            subtitle = "TMT A, TMT B, and tapping ratio across days",
            series = metrics.testTrend.filter { it.name != "Tapping Asymmetry" },
            emptyHint = "Complete the Trail Making Tests on multiple days to see trends here"
        )
        findViewById<TrendSummaryChartView>(R.id.chartTrendAsymmetry).setSeries(
            title = "Asymmetry Trends",
            subtitle = "Bilateral asymmetry (%) across active tests",
            series = metrics.testTrend.filter { it.name == "Tapping Asymmetry" },
            emptyHint = "Complete bilateral tests like Finger Tapping to see asymmetry here"
        )
    }

    private fun dailyComparisonLines(
        metrics: com.pdcollect.app.data.DashboardSummaryStore.DashboardMetrics,
        selector: (com.pdcollect.app.data.DashboardSummaryStore.DailyComparisonDay) -> List<com.pdcollect.app.data.DashboardSummaryStore.TimePoint>
    ): Pair<
        List<com.pdcollect.app.data.DashboardSummaryStore.TimePoint>,
        List<DailyMetricChartView.ComparisonLine>
        > {
        val todayLine = metrics.dailyComparison
            .firstOrNull { it.isToday }
            ?.let(selector)
            .orEmpty()
        val previousLines = metrics.dailyComparison
            .filterNot { it.isToday }
            .map { day ->
                DailyMetricChartView.ComparisonLine(
                    label = formatRecentDayLabel(day.date),
                    points = selector(day),
                    markers = day.markers
                )
            }
        return todayLine to previousLines
    }

    private fun formatRecentDayLabel(date: String): String {
        return runCatching {
            when (java.time.LocalDate.parse(date)) {
                java.time.LocalDate.now().minusDays(1) -> "Yesterday"
                java.time.LocalDate.now().minusDays(2) -> "2 days ago"
                else -> date
            }
        }.getOrDefault(date)
    }

    private fun buildDailySubtitle(hasTodayData: Boolean, hasMarkers: Boolean): String {
        val base = if (hasTodayData) {
            "Blue solid = today to now, grey dashed = previous days"
        } else {
            "No data for today yet; grey dashed = recent days"
        }
        return if (hasMarkers) "$base, medication ticks: solid today, dashed previous" else base
    }

    private fun setupChartDetailLaunchers() {
        findViewById<DailyMetricChartView>(R.id.chartDailyStrideLength).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_STRIDE_LENGTH))
        }
        findViewById<DailyMetricChartView>(R.id.chartDailyStrideSpeed).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_STRIDE_SPEED))
        }
        findViewById<DailyMetricChartView>(R.id.chartDailyTremorPower).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_TREMOR_POWER))
        }
        findViewById<DailyMetricChartView>(R.id.chartDailyAsymmetry).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_ASYMMETRY))
        }
        findViewById<TrendSummaryChartView>(R.id.chartTrendGait).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_TREND_GAIT))
        }
        findViewById<TrendSummaryChartView>(R.id.chartTrendTests).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_TREND_TESTS))
        }
        // Asymmetry can use the tests detail view for now, or just not be clickable
    }

    private fun emptyDashboardMetrics(): com.pdcollect.app.data.DashboardSummaryStore.DashboardMetrics {
        fun emptyTrend(name: String, unit: String) =
            com.pdcollect.app.data.DashboardSummaryStore.TrendSeries(name, unit, emptyList())
        return com.pdcollect.app.data.DashboardSummaryStore.DashboardMetrics(
            dailySourceDate = null,
            dailyStrideLength = emptyList(),
            dailyStrideSpeed = emptyList(),
            dailyTremorPower = emptyList(),
            dailyAsymmetry = emptyList(),
            dailyMarkers = emptyList(),
            gaitTrend = listOf(
                emptyTrend("Max Stride Length", "m"),
                emptyTrend("Max Stride Speed", "m/s"),
                emptyTrend("Max Tremor Power", "%")
            ),
            testTrend = listOf(
                emptyTrend("TMT A", "ms"),
                emptyTrend("TMT B", "ms"),
                emptyTrend("Tapping Ratio", "ratio"),
                emptyTrend("Tapping Asymmetry", "%")
            )
        )
    }

    private fun dashboardMetricsEmpty(metrics: com.pdcollect.app.data.DashboardSummaryStore.DashboardMetrics): Boolean {
        return metrics.dailyStrideLength.isEmpty() &&
            metrics.dailyStrideSpeed.isEmpty() &&
            metrics.dailyTremorPower.isEmpty() &&
            metrics.dailyAsymmetry.isEmpty() &&
            metrics.gaitTrend.all { it.points.isEmpty() } &&
            metrics.testTrend.all { it.points.isEmpty() }
    }

    private fun isAnyRunning(): Boolean {
        return isServiceRunning(PDCollectService::class.java) ||
            isServiceRunning(FaceDistanceService::class.java) ||
            isServiceRunning(AntHRService::class.java) ||
            isServiceRunning(BeanieService::class.java)
    }

    @Suppress("DEPRECATION")
    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        return manager.getRunningServices(Int.MAX_VALUE)
            .any { it.service.className == serviceClass.name }
    }

    private fun togglePassiveCollection() {
        if (profile.passiveCollectionActive || isAnyPassiveCollectorRunning()) {
            stopDataCollection()
        } else {
            startDataCollection()
        }
    }

    private fun showUserReportingMenu() {
        val items = arrayOf(
            "Record Medication",
            "Daily Questionnaire",
            "Record Physical Activity"
        )
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("User Reporting")
            .setItems(items) { _, which ->
                when (which) {
                    0 -> showMedicationTimePicker()
                    1 -> startActivity(Intent(this, QuestionnaireActivity::class.java))
                    2 -> showPhysicalActivityDialog()
                }
            }
            .show()
    }

    private fun showPhysicalActivityDialog() {
        val types = Constants.PHYSICAL_ACTIVITY_TYPES.toTypedArray()

        val container = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(48, 16, 48, 16)
        }
        val spinner = android.widget.Spinner(this).apply {
            adapter = android.widget.ArrayAdapter(
                this@MainActivity,
                android.R.layout.simple_spinner_dropdown_item,
                types
            )
        }
        container.addView(spinner)

        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Record Physical Activity")
            .setView(container)
            .setPositiveButton("Set Time & Save") { _, _ ->
                showPhysicalActivityTimePicker(spinner.selectedItem.toString())
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showPhysicalActivityTimePicker(type: String) {
        val calendar = java.util.Calendar.getInstance()
        val hour = calendar.get(java.util.Calendar.HOUR_OF_DAY)
        val minute = calendar.get(java.util.Calendar.MINUTE)

        android.app.TimePickerDialog(this, { _, h, m ->
            val now = System.currentTimeMillis()
            val actCalendar = java.util.Calendar.getInstance()
            actCalendar.set(java.util.Calendar.HOUR_OF_DAY, h)
            actCalendar.set(java.util.Calendar.MINUTE, m)
            val actTime = actCalendar.timeInMillis

            dataManager.writePhysicalActivityData("$now,$type,$actTime")
            Toast.makeText(
                this,
                "$type recorded at ${String.format(java.util.Locale.US, "%02d:%02d", h, m)}",
                Toast.LENGTH_LONG
            ).show()
            populateDashboardCharts()
        }, hour, minute, true).show()
    }

    private fun showMedicationTimePicker() {
        val meds = mutableListOf<org.json.JSONObject>()
        try {
            val array = org.json.JSONArray(profile.medications)
            for (i in 0 until array.length()) {
                meds.add(array.getJSONObject(i))
            }
        } catch (_: Exception) {
        }

        if (meds.isEmpty()) {
            Toast.makeText(this, "Please set medications in Settings first", Toast.LENGTH_LONG).show()
            return
        }

        val items = meds.map { "${it.getString("name")} (${it.getString("dose")})" }.toTypedArray()

        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Which medication?")
            .setItems(items) { _, which ->
                val selectedMed = meds[which]
                val medName = selectedMed.getString("name")
                val medDose = selectedMed.getString("dose")

                val calendar = java.util.Calendar.getInstance()
                val hour = calendar.get(java.util.Calendar.HOUR_OF_DAY)
                val minute = calendar.get(java.util.Calendar.MINUTE)

                android.app.TimePickerDialog(this, { _, h, m ->
                    val now = System.currentTimeMillis()
                    val medCalendar = java.util.Calendar.getInstance()
                    medCalendar.set(java.util.Calendar.HOUR_OF_DAY, h)
                    medCalendar.set(java.util.Calendar.MINUTE, m)
                    medCalendar.set(java.util.Calendar.SECOND, 0)
                    medCalendar.set(java.util.Calendar.MILLISECOND, 0)

                    val medTime = medCalendar.timeInMillis
                    dataManager.writeMedicationData("$now,$medTime,$medName,$medDose")
                    Toast.makeText(
                        this,
                        "$medName recorded at ${String.format(java.util.Locale.US, "%02d:%02d", h, m)}",
                        Toast.LENGTH_LONG
                    ).show()
                    populateDashboardCharts()
                }, hour, minute, true).show()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun startDataCollection() {
        profile.passiveCollectionActive = true
        syncPassiveServices()
        BatteryReminderReceiver.scheduleBatteryAlarms(this)
        Toast.makeText(this, "Passive collection started", Toast.LENGTH_SHORT).show()
        updateStatus()
    }

    private fun stopDataCollection() {
        profile.passiveCollectionActive = false
        syncPassiveServices()
        val msg = if (profile.hrDeviceAddress.isNotBlank() || profile.beanieDeviceAddress.isNotBlank()) {
            "Passive phone collection stopped; paired wearables stay connected"
        } else {
            "Passive collection stopped"
        }
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
        updateStatus()
    }

    private fun syncPassiveServices() {
        syncPassiveCollectionServices()
        syncPeripheralMonitorServices()
    }

    private fun syncPassiveCollectionServices() {
        if (!profile.passiveCollectionActive) {
            PDCollectService.stop(this)
            FaceDistanceService.stop(this)
            return
        }

        if (!isServiceRunning(PDCollectService::class.java)) {
            PDCollectService.start(this)
        }

        val shouldRunFaceDistance = when (profile.faceDistanceMode) {
            Constants.FACE_DISTANCE_MODE_ALWAYS ->
                hasCameraPermission() && PermissionUtils.isAccessibilityServiceEnabled(this)
            Constants.FACE_DISTANCE_MODE_APP_FOREGROUND ->
                hasCameraPermission()
            else -> false
        }
        if (shouldRunFaceDistance) {
            if (!isServiceRunning(FaceDistanceService::class.java)) {
                FaceDistanceService.start(this)
            }
        } else {
            FaceDistanceService.stop(this)
        }
    }

    private fun syncPeripheralMonitorServices() {
        if (profile.hrDeviceAddress.isNotBlank()) {
            if (!isServiceRunning(AntHRService::class.java)) {
                AntHRService.start(this)
            }
        } else {
            AntHRService.stop(this)
        }

        if (profile.beanieDeviceAddress.isNotBlank()) {
            if (!isServiceRunning(BeanieService::class.java)) {
                BeanieService.start(this)
            }
        } else {
            BeanieService.stop(this)
        }
    }

    private fun isAnyPassiveCollectorRunning(): Boolean {
        return isServiceRunning(PDCollectService::class.java) ||
            isServiceRunning(FaceDistanceService::class.java)
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        syncPassiveServices()
        updateStatus()
        updateSetupHealth()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == immediateUpdateRequestCode && resultCode != Activity.RESULT_OK) {
            Toast.makeText(this, "Application update is mandatory.", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    private fun updateSetupHealth() {
        val health = SetupVerificationManager.checkHealth(this)
        val card = findViewById<com.google.android.material.card.MaterialCardView>(R.id.cardSetupRequired)
        val msgView = findViewById<TextView>(R.id.tvSetupMessage)

        if (health.status == SetupVerificationManager.HealthStatus.OPTIMAL) {
            card?.visibility = android.view.View.GONE
        } else {
            card?.visibility = android.view.View.VISIBLE
            msgView?.text = if (health.missingItems.isNotEmpty()) {
                "Required: ${health.missingItems.joinToString(", ")}"
            } else {
                "Critical configuration items are missing."
            }
        }
    }

    private fun handleRepairAction() {
        val currentProfile = UserProfile(this)
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager

        if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
            return
        }

        if (!PermissionUtils.hasExactAlarmPermission(this)) {
            PermissionUtils.openExactAlarmSettings(this)
            return
        }

        val needsAccessibility = currentProfile.keyloggingEnabled ||
                (currentProfile.passiveCollectionActive &&
                    currentProfile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS)
        if (needsAccessibility &&
            !PermissionUtils.isAccessibilityServiceEnabled(this)
        ) {
            PermissionUtils.openAccessibilitySettings(this)
            return
        }

        requestPermissions()
    }

    private fun requestPermissions() {
        val perms = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (profile.faceDistanceEnabled &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            perms.add(Manifest.permission.CAMERA)
        }

        if (perms.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, perms.toTypedArray(), 1)
        }
    }

    private fun syncBeanieUi() {
        val snapshot = BeanieStatusStore.load(this)
        renderBeanieVitals(
            connected = snapshot?.connected == true,
            tskin = snapshot?.tskinC ?: Double.NaN,
            heatFlux = snapshot?.heatFluxCalPerSec ?: Double.NaN,
            serviceRunning = isServiceRunning(BeanieService::class.java)
        )
    }

    private fun recreateDataManager() {
        dashboardRefreshJob?.cancel()
        dashboardRefreshJob = null
        if (::dataManager.isInitialized) {
            dataManager.closeAll()
        }
        dataManager = DataManager(this, profile)
    }

    private fun renderBeanieVitals(
        connected: Boolean,
        tskin: Double,
        heatFlux: Double,
        serviceRunning: Boolean
    ) {
        val hasLiveReading = tskin.isFinite() || heatFlux.isFinite()
        if (!serviceRunning && (!connected || !hasLiveReading)) {
            cardBeanieVitals.visibility = android.view.View.GONE
            return
        }

        cardBeanieVitals.visibility = android.view.View.VISIBLE
        tvBeanieSkinTemp.text = when {
            tskin.isFinite() -> String.format(java.util.Locale.US, "%.2f C", tskin)
            serviceRunning -> "Waiting..."
            else -> "-- C"
        }
        tvBeanieHeatFlux.text = when {
            heatFlux.isFinite() -> String.format(java.util.Locale.US, "%.2f cal/s", heatFlux)
            serviceRunning -> "Waiting..."
            else -> "-- cal/s"
        }
    }
}
