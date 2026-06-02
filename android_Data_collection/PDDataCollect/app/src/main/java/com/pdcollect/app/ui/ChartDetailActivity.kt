package com.pdcollect.app.ui

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.appbar.MaterialToolbar
import com.pdcollect.app.R
import com.pdcollect.app.data.DashboardSummaryStore
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.view.DailyMetricChartView
import com.pdcollect.app.ui.view.TrendSummaryChartView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

class ChartDetailActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var chartContainer: FrameLayout
    private lateinit var toolbar: MaterialToolbar
    private lateinit var chartKind: String
    private var refreshJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        setContentView(R.layout.activity_chart_detail)

        chartKind = intent.getStringExtra(EXTRA_CHART_KIND).orEmpty()
        if (chartKind.isBlank()) {
            finish()
            return
        }

        toolbar = findViewById(R.id.topAppBar)
        toolbar.setNavigationOnClickListener { onBackPressedDispatcher.onBackPressed() }
        findViewById<View>(R.id.btnBackToDashboard).setOnClickListener {
            onBackPressedDispatcher.onBackPressed()
        }
        chartContainer = findViewById(R.id.chartContainer)

        val profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        installChartView()
        renderCharts()
    }

    override fun onDestroy() {
        refreshJob?.cancel()
        if (::dataManager.isInitialized) {
            dataManager.closeAll()
        }
        super.onDestroy()
    }

    private fun installChartView() {
        chartContainer.removeAllViews()
        val layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        val chartView = when (chartKind) {
            CHART_DAILY_STRIDE_LENGTH,
            CHART_DAILY_STRIDE_SPEED,
            CHART_DAILY_TREMOR_POWER -> {
                DailyMetricChartView(this).apply {
                    setInteractiveZoomEnabled(true)
                    this.layoutParams = layoutParams
                }
            }

            else -> {
                TrendSummaryChartView(this).apply {
                    setInteractiveZoomEnabled(true)
                    this.layoutParams = layoutParams
                }
            }
        }
        chartContainer.addView(chartView)
    }

    private fun renderCharts() {
        val hasStoredDays = dataManager.listAvailableDates().isNotEmpty()
        bindMetrics(
            metrics = dataManager.getCachedDashboardMetrics(trendDays = 0),
            hasStoredDays = hasStoredDays,
            loading = true
        )

        refreshJob?.cancel()
        refreshJob = lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    dataManager.getDashboardMetricsFast(
                        trendDays = 0,
                        maxSyncDates = DashboardSummaryStore.DEFAULT_FAST_SYNC_MAX_DATES
                    ) to dataManager.listAvailableDates().isNotEmpty()
                }.getOrNull()
            }
            if (result != null && !isDestroyed && !isFinishing) {
                val (metrics, refreshedHasStoredDays) = result
                bindMetrics(metrics, refreshedHasStoredDays, loading = false)
            }
        }
    }

    private fun bindMetrics(
        metrics: DashboardSummaryStore.DashboardMetrics,
        hasStoredDays: Boolean,
        loading: Boolean
    ) {
        when (chartKind) {
            CHART_DAILY_STRIDE_LENGTH -> bindDailyChart(
                title = "Stride Length",
                unit = "m",
                points = recentPrimaryAndComparison(metrics) { it.strideLength },
                markers = metrics.dailyComparison.firstOrNull { it.isToday }?.markers.orEmpty(),
                emptyHint = "Walk with the phone in your pocket to capture gait data",
                hasStoredDays = hasStoredDays,
                loading = loading
            )

            CHART_DAILY_STRIDE_SPEED -> bindDailyChart(
                title = "Stride Speed",
                unit = "m/s",
                points = recentPrimaryAndComparison(metrics) { it.strideSpeed },
                markers = metrics.dailyComparison.firstOrNull { it.isToday }?.markers.orEmpty(),
                emptyHint = "Walk with the phone in your pocket to capture gait data",
                hasStoredDays = hasStoredDays,
                loading = loading
            )

            CHART_DAILY_TREMOR_POWER -> bindDailyChart(
                title = "Tremor Window Power",
                unit = "%",
                points = recentPrimaryAndComparison(metrics) { it.tremorPower },
                markers = metrics.dailyComparison.firstOrNull { it.isToday }?.markers.orEmpty(),
                emptyHint = "Tremor data will appear once sensors are collecting",
                hasStoredDays = hasStoredDays,
                loading = loading
            )

            CHART_TREND_GAIT -> bindTrendChart(
                title = "Peak Gait Trends",
                subtitle = "Per-day maxima; pinch to zoom and drag to pan",
                series = metrics.gaitTrend,
                emptyHint = "Walk daily with the app running to see multi-day gait trends here"
            )

            CHART_TREND_TESTS -> bindTrendChart(
                title = "Assessment Trends",
                subtitle = "TMT A, TMT B, and tapping ratio across days",
                series = metrics.testTrend,
                emptyHint = "Complete the Trail Making Tests on multiple days to see trends here"
            )
        }
    }

    private fun bindDailyChart(
        title: String,
        unit: String,
        points: Pair<List<DashboardSummaryStore.TimePoint>, List<DailyMetricChartView.ComparisonLine>>,
        markers: List<DashboardSummaryStore.EventMarker>,
        emptyHint: String,
        hasStoredDays: Boolean,
        loading: Boolean
    ) {
        toolbar.title = title
        val dailyChart = chartContainer.getChildAt(0) as DailyMetricChartView
        val comparisonLines = points.second
        dailyChart.setData(
            title = title,
            subtitle = when {
                loading && hasStoredDays -> "Preparing recent summaries..."
                else -> buildDailySubtitle(
                    hasTodayData = points.first.isNotEmpty(),
                    hasMarkers = markers.isNotEmpty() || comparisonLines.any { it.markers.isNotEmpty() }
                )
            },
            unit = unit,
            points = points.first,
            comparisonLines = comparisonLines,
            markers = markers,
            emptyHint = emptyHint
        )
    }

    private fun bindTrendChart(
        title: String,
        subtitle: String,
        series: List<DashboardSummaryStore.TrendSeries>,
        emptyHint: String
    ) {
        toolbar.title = title
        val trendChart = chartContainer.getChildAt(0) as TrendSummaryChartView
        trendChart.setSeries(
            title = title,
            subtitle = subtitle,
            series = series,
            emptyHint = emptyHint
        )
    }

    private fun recentPrimaryAndComparison(
        metrics: DashboardSummaryStore.DashboardMetrics,
        selector: (DashboardSummaryStore.DailyComparisonDay) -> List<DashboardSummaryStore.TimePoint>
    ): Pair<List<DashboardSummaryStore.TimePoint>, List<DailyMetricChartView.ComparisonLine>> {
        val todayLine = metrics.dailyComparison.firstOrNull { it.isToday }?.let(selector).orEmpty()
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
            when (LocalDate.parse(date)) {
                LocalDate.now().minusDays(1) -> "Yesterday"
                LocalDate.now().minusDays(2) -> "2 days ago"
                else -> LocalDate.parse(date).format(DateTimeFormatter.ofPattern("MMM d", Locale.US))
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

    companion object {
        private const val EXTRA_CHART_KIND = "chart_kind"

        const val CHART_DAILY_STRIDE_LENGTH = "daily_stride_length"
        const val CHART_DAILY_STRIDE_SPEED = "daily_stride_speed"
        const val CHART_DAILY_TREMOR_POWER = "daily_tremor_power"
        const val CHART_TREND_GAIT = "trend_gait"
        const val CHART_TREND_TESTS = "trend_tests"

        fun intent(context: Context, chartKind: String): Intent {
            return Intent(context, ChartDetailActivity::class.java)
                .putExtra(EXTRA_CHART_KIND, chartKind)
        }
    }
}
