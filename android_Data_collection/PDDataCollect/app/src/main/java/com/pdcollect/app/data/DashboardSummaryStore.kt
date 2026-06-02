package com.pdcollect.app.data

import android.content.Context
import com.pdcollect.app.util.AnalysisEngine
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.PDAnalysisEngine
import com.pdcollect.app.util.TimeUtils
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

class DashboardSummaryStore(
    private val context: Context,
    private val userProfile: UserProfile,
    private val dataManager: DataManager
) {

    data class TimePoint(val minuteOfDay: Int, val value: Float)
    data class EventMarker(val minuteOfDay: Int, val label: String, val type: String)
    data class TrendPoint(val label: String, val value: Float)
    data class TrendSeries(val name: String, val unit: String, val points: List<TrendPoint>)
    data class DailyComparisonDay(
        val date: String,
        val isToday: Boolean,
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val markers: List<EventMarker>
    )
    data class DashboardMetrics(
        val dailySourceDate: String?,
        val dailyStrideLength: List<TimePoint>,
        val dailyStrideSpeed: List<TimePoint>,
        val dailyTremorPower: List<TimePoint>,
        val dailyMarkers: List<EventMarker>,
        val dailyComparison: List<DailyComparisonDay> = emptyList(),
        val gaitTrend: List<TrendSeries>,
        val testTrend: List<TrendSeries>
    )

    private data class StatBucket(
        var sum: Float = 0f,
        var count: Int = 0,
        var max: Float = 0f
    ) {
        fun add(value: Float) {
            if (!value.isFinite()) return
            sum += value
            count++
            if (value > max) max = value
        }

        fun meanOrNull(): Float? = if (count > 0) sum / count else null
    }

    private data class SensorSummary(
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val maxStrideLength: Float,
        val maxStrideSpeed: Float,
        val maxTremorPower: Float
    )

    private data class MetricBounds(
        val minValue: Float,
        val maxValue: Float
    )

    private data class CurrentDayRenderContext(
        val today: LocalDate,
        val currentMinuteOfDay: Int
    ) {
        val todayDateString: String = today.format(DateTimeFormatter.ISO_LOCAL_DATE)
    }

    private val zoneId: ZoneId = ZoneId.systemDefault()
    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    fun getDashboardMetrics(trendDays: Int = 0): DashboardMetrics {
        ensureRecentSummaries(trendDays)
        return buildDashboardMetrics(loadRoot(), trendDays)
    }

    fun getDashboardMetricsFast(
        trendDays: Int = 0,
        maxSyncDates: Int = DEFAULT_FAST_SYNC_MAX_DATES
    ): DashboardMetrics {
        ensureRecentSummariesLimited(trendDays, maxSyncDates)
        return buildDashboardMetrics(loadRoot(), trendDays)
    }

    fun getCachedDashboardMetrics(trendDays: Int = 0): DashboardMetrics {
        return buildDashboardMetrics(loadRoot(), trendDays)
    }

    fun refreshCachedSummaries(
        trendDays: Int = 0,
        maxSyncDates: Int = DEFAULT_FAST_SYNC_MAX_DATES
    ) {
        ensureRecentSummariesLimited(trendDays, maxSyncDates)
    }

    private fun buildDashboardMetrics(root: JSONObject, trendDays: Int): DashboardMetrics {
        val dates = root.optJSONObject("dates") ?: JSONObject()
        val dailySelection = selectDailySummary(dates)
        val renderContext = currentDayRenderContext()
        return DashboardMetrics(
            dailySourceDate = dailySelection.first,
            dailyStrideLength = clipTimePointsToCurrentTime(
                dateStr = dailySelection.first,
                points = readTimePoints(dailySelection.second, "stride_length"),
                renderContext = renderContext
            ),
            dailyStrideSpeed = clipTimePointsToCurrentTime(
                dateStr = dailySelection.first,
                points = readTimePoints(dailySelection.second, "stride_speed"),
                renderContext = renderContext
            ),
            dailyTremorPower = clipTimePointsToCurrentTime(
                dateStr = dailySelection.first,
                points = readTimePoints(dailySelection.second, "tremor_power"),
                renderContext = renderContext
            ),
            dailyMarkers = clipMarkersToCurrentTime(
                dateStr = dailySelection.first,
                markers = readMarkers(dailySelection.second),
                renderContext = renderContext
            ),
            dailyComparison = buildDailyComparison(dates, renderContext),
            gaitTrend = buildTrendSeries(dates, trendDays, listOf(
                Triple("Max Stride Length", "m", "max_stride_length"),
                Triple("Max Stride Speed", "m/s", "max_stride_speed"),
                Triple("Max Tremor Power", "%", "max_tremor_power")
            )),
            testTrend = buildTrendSeries(dates, trendDays, listOf(
                Triple("TMT A", "ms", "tmt_a"),
                Triple("TMT B", "ms", "tmt_b"),
                Triple("Tapping Ratio", "ratio", "tapping_ratio"),
                Triple("Tapping Asymmetry", "%", "tapping_asymmetry")
            ))
        )
    }

    private fun buildDailyComparison(
        dates: JSONObject,
        renderContext: CurrentDayRenderContext
    ): List<DailyComparisonDay> {
        return (0L..2L).mapNotNull { offset ->
            val date = renderContext.today.minusDays(offset).format(dateFormatter)
            val summary = dates.optJSONObject(date) ?: return@mapNotNull null
            DailyComparisonDay(
                date = date,
                isToday = offset == 0L,
                strideLength = clipTimePointsToCurrentTime(
                    dateStr = date,
                    points = readTimePoints(summary, "stride_length"),
                    renderContext = renderContext
                ),
                strideSpeed = clipTimePointsToCurrentTime(
                    dateStr = date,
                    points = readTimePoints(summary, "stride_speed"),
                    renderContext = renderContext
                ),
                tremorPower = clipTimePointsToCurrentTime(
                    dateStr = date,
                    points = readTimePoints(summary, "tremor_power"),
                    renderContext = renderContext
                ),
                markers = clipMarkersToCurrentTime(
                    dateStr = date,
                    markers = readMarkers(summary),
                    renderContext = renderContext
                )
            )
        }
    }

    private fun currentDayRenderContext(): CurrentDayRenderContext {
        val now = ZonedDateTime.now(zoneId)
        return CurrentDayRenderContext(
            today = now.toLocalDate(),
            currentMinuteOfDay = now.hour * 60 + now.minute
        )
    }

    private fun clipTimePointsToCurrentTime(
        dateStr: String?,
        points: List<TimePoint>,
        renderContext: CurrentDayRenderContext
    ): List<TimePoint> {
        if (dateStr != renderContext.todayDateString) return points

        val currentMinute = renderContext.currentMinuteOfDay
        val visible = points.filter { it.minuteOfDay <= currentMinute }.toMutableList()
        val activeBinPoint = points
            .firstOrNull { point ->
                point.minuteOfDay > currentMinute &&
                    pointRepresentsCurrentBin(point.minuteOfDay, currentMinute)
            }
            ?: return visible

        visible += TimePoint(currentMinute, activeBinPoint.value)
        return visible
            .groupBy { it.minuteOfDay }
            .map { (minute, bucket) -> TimePoint(minute, bucket.last().value) }
            .sortedBy { it.minuteOfDay }
    }

    private fun clipMarkersToCurrentTime(
        dateStr: String?,
        markers: List<EventMarker>,
        renderContext: CurrentDayRenderContext
    ): List<EventMarker> {
        if (dateStr != renderContext.todayDateString) return markers
        return markers.filter { it.minuteOfDay <= renderContext.currentMinuteOfDay }
    }

    private fun pointRepresentsCurrentBin(pointMinuteOfDay: Int, currentMinuteOfDay: Int): Boolean {
        val binStartMinute = (pointMinuteOfDay - BIN_MINUTES / 2).coerceAtLeast(0)
        return binStartMinute <= currentMinuteOfDay
    }

    fun cacheSummaryForDate(dateStr: String) {
        ensureSummary(dateStr)
    }

    fun preserveSummaryThenDeleteDate(dateStr: String): Boolean {
        forceWriteSummaryBeforeDeletion(dateStr)
        val dir = File(baseDir(), dateStr)
        return if (dir.exists() && dir.isDirectory) dir.deleteRecursively() else false
    }

    fun cleanupUploadedRawData(daysToKeep: Int = Constants.RAW_RETENTION_DAYS) {
        val base = baseDir()
        if (!base.exists()) return

        val cutoff = LocalDate.now().minusDays(daysToKeep.toLong())
        base.listFiles()
            ?.filter { it.isDirectory && isDateDir(it.name) }
            ?.forEach { dir ->
                val dirDate = runCatching { LocalDate.parse(dir.name, dateFormatter) }.getOrNull() ?: return@forEach
                if (!dirDate.isBefore(cutoff)) return@forEach
                val uploadedMarker = File(dir, ".uploaded")
                if (!uploadedMarker.exists()) return@forEach

                forceWriteSummaryBeforeDeletion(dir.name)
                dir.deleteRecursively()
                android.util.Log.d(TAG, "Deleted uploaded raw data for ${dir.name} (kept graph cache)")
            }
    }

    fun clearCache() {
        cacheFile().delete()
    }

    fun rebuildDashboardSummariesFromScratch(): String {
        rebuildSummariesFromRawFiles()
        val root = loadRoot()
        val dates = root.optJSONObject("dates") ?: JSONObject()
        val liveDates = listAvailableDates()
        val daysProcessed = liveDates.size
        val totalSteps = liveDates.sumOf { date ->
            estimateStepsFromSummary(dates.optJSONObject(date))
        }
        return "Rebuilt $daysProcessed days. Found approximately $totalSteps steps."
    }

    private fun estimateStepsFromSummary(summary: JSONObject?): Int {
        // Rough estimation: each stride is 2 steps.
        return readTimePoints(summary, "stride_length").size * 2
    }

    fun listAvailableDates(): List<String> {
        val base = baseDir()
        if (!base.exists()) return emptyList()
        return base.listFiles()
            ?.filter { it.isDirectory && isDateDir(it.name) }
            ?.map { it.name }
            ?.sorted()
            ?: emptyList()
    }

    fun rebuildSummariesFromRawFiles() {
        val root = migrateLegacyRoot(loadRoot())
        val dates = root.optJSONObject("dates") ?: JSONObject().also { root.put("dates", it) }
        val base = baseDir()
        if (base.exists()) {
            base.listFiles()
                ?.filter { it.isDirectory && isDateDir(it.name) }
                ?.sortedBy { it.name }
                ?.forEach { dir ->
                    val sensorFile = File(dir, Constants.SENSORS_FILE)
                    val currentFileSize = if (sensorFile.exists()) sensorFile.length() else 0L
                    val sourceMtime = computeSourceSignature(dir)
                    val existing = dates.optJSONObject(dir.name)
                    dates.put(dir.name, buildSummary(dir, sourceMtime, 0L, currentFileSize, existing))
                }
        }
        saveRoot(root)
    }

    private fun ensureRecentSummaries(trendDays: Int) {
        val base = baseDir()
        base.listFiles()
            ?.filter { it.isDirectory && isDateDir(it.name) && isWithinWindow(it.name, trendDays) }
            ?.forEach { ensureSummary(it.name) }
    }

    private fun ensureRecentSummariesLimited(trendDays: Int, maxSyncDates: Int) {
        val base = baseDir()
        val allDirs = base.listFiles()
            ?.filter { it.isDirectory && isDateDir(it.name) && isWithinWindow(it.name, trendDays) }
            ?.sortedByDescending { it.name }
            .orEmpty()
        if (allDirs.isEmpty()) return

        val targetDates = LinkedHashSet<String>()
        val today = TimeUtils.todayDateString()
        allDirs.firstOrNull { it.name == today }?.let { targetDates += it.name }

        val cachedDates = loadRoot().optJSONObject("dates") ?: JSONObject()
        selectDailySummary(cachedDates).first?.let { targetDates += it }

        val maxTargets = maxSyncDates.coerceAtLeast(1)
        for (dir in allDirs.asSequence()
            .filter { it.name !in targetDates }
            .filter { hasDashboardSourceData(it) }
            .filter { isFastSummaryCandidate(it, cachedDates) }
        ) {
            if (targetDates.size >= maxTargets) break
            targetDates += dir.name
        }

        targetDates.forEach { ensureSummary(it) }
    }

    private fun forceWriteSummaryBeforeDeletion(dateStr: String) {
        val dir = File(baseDir(), dateStr)
        if (!dir.exists() || !dir.isDirectory) return

        val root = loadRoot()
        val dates = root.optJSONObject("dates") ?: JSONObject().also { root.put("dates", it) }
        val existing = dates.optJSONObject(dateStr)
        val sensorFile = File(dir, Constants.SENSORS_FILE)
        val currentFileSize = if (sensorFile.exists()) sensorFile.length() else 0L
        val sourceMtime = computeSourceSignature(dir)

        val freshSummary = if (currentFileSize > DELETION_SENSOR_SCAN_MAX_BYTES) {
            android.util.Log.d(
                TAG,
                "Skipping large sensor summary rebuild before deleting $dateStr ($currentFileSize bytes)"
            )
            buildDeletionSummaryWithoutSensorScan(dir, sourceMtime, currentFileSize, existing)
        } else {
            buildSummary(dir, sourceMtime, 0L, currentFileSize, existing)
        }
        freshSummary.put("raw_deleted", true)
        dates.put(dateStr, freshSummary)
        saveRoot(root)
    }

    private fun buildDeletionSummaryWithoutSensorScan(
        dateDir: File,
        sourceMtime: Long,
        currentSensorFileSize: Long,
        existing: JSONObject?
    ): JSONObject {
        val dateStr = dateDir.name
        val markers = computeMarkers(
            medicationFile = File(dateDir, Constants.MEDICATION_FILE),
            activityFile = File(dateDir, Constants.PHYSICAL_ACTIVITY_FILE)
        )
        val tmtStats = computeTmtTrend(File(dateDir, Constants.TMT_RESULTS_FILE))
        val tappingRatio = computeTappingRatio(File(dateDir, Constants.TEST_FINGER_TAPPING_FILE))
        val tappingAsymmetry = computeTappingAsymmetry(File(dateDir, Constants.TEST_FINGER_TAPPING_FILE))

        fun existingArray(key: String): JSONArray {
            return existing?.optJSONArray(key) ?: JSONArray()
        }

        fun existingTrend(key: String): Double {
            return existing
                ?.optDouble(key, Double.NaN)
                ?.takeIf { isValidTrendValue(key, it) }
                ?: 0.0
        }

        fun freshOrExisting(key: String, fresh: Float): Double {
            return if (fresh > 0f) fresh.toDouble() else existingTrend(key)
        }

        return JSONObject().apply {
            put("date", dateStr)
            put("source_mtime", sourceMtime)
            put("sensor_file_size", currentSensorFileSize)
            put("sensor_scan_pos", existing?.optLong("sensor_scan_pos", 0L) ?: 0L)
            put("stride_length", existingArray("stride_length"))
            put("stride_speed", existingArray("stride_speed"))
            put("tremor_power", existingArray("tremor_power"))
            put("max_stride_length", existingTrend("max_stride_length"))
            put("max_stride_speed", existingTrend("max_stride_speed"))
            put("max_tremor_power", existingTrend("max_tremor_power"))
            put("markers", writeMarkers(markers))
            put("tmt_a", freshOrExisting("tmt_a", tmtStats.first))
            put("tmt_b", freshOrExisting("tmt_b", tmtStats.second))
            put("tapping_ratio", freshOrExisting("tapping_ratio", tappingRatio))
            put("tapping_asymmetry", freshOrExisting("tapping_asymmetry", tappingAsymmetry))
        }
    }

    private fun ensureSummary(dateStr: String) {
        val dir = File(baseDir(), dateStr)
        val root = loadRoot()
        val dates = root.optJSONObject("dates") ?: JSONObject().also { root.put("dates", it) }
        val existing = dates.optJSONObject(dateStr)

        if (existing?.optBoolean("raw_deleted", false) == true) return

        if (!dir.exists() || !dir.isDirectory) return

        val isToday = dateStr == TimeUtils.todayDateString()
        val sensorFile = File(dir, Constants.SENSORS_FILE)
        val currentFileSize = if (sensorFile.exists()) sensorFile.length() else 0L
        val cachedSize = existing?.optLong("sensor_file_size", -1L) ?: -1L
        val sourceMtime = computeSourceSignature(dir)
        val cachedSourceMtime = existing?.optLong("source_mtime", -1L) ?: -1L
        val needsRepair = existing?.let { summaryNeedsRepair(it, dir, currentFileSize) } ?: false

        val sensorUnchanged = cachedSize >= 0L && cachedSize == currentFileSize
        val sourceUnchanged = cachedSourceMtime == sourceMtime
        if (!isToday && sensorUnchanged && sourceUnchanged && existing != null && !needsRepair) return

        val resumePos = if (needsRepair) {
            0L
        } else if (isToday && existing != null && cachedSize == currentFileSize) {
            -1L 
        } else if (isToday && existing != null && cachedSize in 1 until currentFileSize) {
            existing.optLong("sensor_scan_pos", 0L)
        } else {
            0L
        }

        val freshSummary = buildSummary(dir, sourceMtime, resumePos, currentFileSize, existing)
        dates.put(dateStr, freshSummary)
        saveRoot(root)
    }

    private fun buildSummary(
        dateDir: File,
        sourceMtime: Long,
        resumeScanPos: Long = 0L,
        currentFileSize: Long = 0L,
        existing: JSONObject? = null
    ): JSONObject {
        val dateStr = dateDir.name
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)

        val sensorResult = if (resumeScanPos == -1L) {
            null
        } else {
            computeSensorSummaryIncremental(sensorFile, resumeScanPos)
        }

        val markers = computeMarkers(
            medicationFile = File(dateDir, Constants.MEDICATION_FILE),
            activityFile = File(dateDir, Constants.PHYSICAL_ACTIVITY_FILE)
        )
        val tmtStats = computeTmtTrend(File(dateDir, Constants.TMT_RESULTS_FILE))
        val tappingRatio = computeTappingRatio(File(dateDir, Constants.TEST_FINGER_TAPPING_FILE))
        val tappingAsymmetry = computeTappingAsymmetry(File(dateDir, Constants.TEST_FINGER_TAPPING_FILE))

        return JSONObject().apply {
            put("date", dateStr)
            put("source_mtime", sourceMtime)
            put("sensor_file_size", currentFileSize)

            if (sensorResult != null) {
                val merged = mergeSensorResults(
                    if (sensorResult.replacesExisting) null else existing,
                    sensorResult
                )
                put("sensor_scan_pos", sensorResult.newScanPos)
                put("stride_length", writeTimePoints(merged.strideLength))
                put("stride_speed", writeTimePoints(merged.strideSpeed))
                put("tremor_power", writeTimePoints(merged.tremorPower))
                put("max_stride_length", merged.maxStrideLength.toDouble())
                put("max_stride_speed", merged.maxStrideSpeed.toDouble())
                put("max_tremor_power", merged.maxTremorPower.toDouble())
            } else if (existing != null) {
                put("sensor_scan_pos", existing.optLong("sensor_scan_pos", 0L))
                listOf("stride_length", "stride_speed", "tremor_power").forEach { key ->
                    existing.optJSONArray(key)?.let { put(key, it) }
                }
                put(
                    "max_stride_length",
                    existing.optDouble("max_stride_length", Double.NaN)
                        .takeIf { isValidTrendValue("max_stride_length", it) } ?: 0.0
                )
                put(
                    "max_stride_speed",
                    existing.optDouble("max_stride_speed", Double.NaN)
                        .takeIf { isValidTrendValue("max_stride_speed", it) } ?: 0.0
                )
                put(
                    "max_tremor_power",
                    existing.optDouble("max_tremor_power", Double.NaN)
                        .takeIf { isValidTrendValue("max_tremor_power", it) } ?: 0.0
                )
            }

            put("markers", writeMarkers(markers))
            put("tmt_a", tmtStats.first.toDouble())
            put("tmt_b", tmtStats.second.toDouble())
            put("tapping_ratio", tappingRatio.toDouble())
            put("tapping_asymmetry", tappingAsymmetry.toDouble())
        }
    }

    private data class IncrementalSensorResult(
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val maxStrideLength: Float,
        val maxStrideSpeed: Float,
        val maxTremorPower: Float,
        val newScanPos: Long,
        val replacesExisting: Boolean = false
    )

    private fun computeSensorSummaryIncremental(
        sensorFile: File,
        startPos: Long
    ): IncrementalSensorResult {
        val empty = IncrementalSensorResult(
            emptyList(), emptyList(), emptyList(), 0f, 0f, 0f,
            newScanPos = startPos
        )
        if (!sensorFile.exists()) return empty

        val canUseFullPdAnalysis = startPos == 0L && sensorFile.length() <= FULL_PD_ANALYSIS_MAX_BYTES
        val pdAnalysisResult = if (canUseFullPdAnalysis) runCatching {
            val series = readSensorSeries(sensorFile)
            if (series.size >= 3) {
                val analysis = PDAnalysisEngine.analyze(series, BIN_MINUTES, zoneId)
                val hasGraphData = analysis.stepLength.isNotEmpty() ||
                    analysis.speed.isNotEmpty() ||
                    analysis.tremorPower.isNotEmpty()
                if (hasGraphData) {
                    IncrementalSensorResult(
                        strideLength = analysis.stepLength.map { TimePoint(it.minuteOfDay, it.value) },
                        strideSpeed = analysis.speed.map { TimePoint(it.minuteOfDay, it.value) },
                        tremorPower = analysis.tremorPower.map { TimePoint(it.minuteOfDay, it.value) },
                        maxStrideLength = analysis.maxStepLength,
                        maxStrideSpeed = analysis.maxSpeed,
                        maxTremorPower = analysis.maxTremorPower,
                        newScanPos = sensorFile.length(),
                        replacesExisting = true
                    )
                } else {
                    null
                }
            } else {
                null
            }
        }.onFailure {
            android.util.Log.w(TAG, "PDAnalysis sensor analyzer failed; falling back to legacy gait parser", it)
        }.getOrNull()
        else null
        if (pdAnalysisResult != null) return pdAnalysisResult

        val strideLengthBuckets = Array(BIN_COUNT) { StatBucket() }
        val strideSpeedBuckets = Array(BIN_COUNT) { StatBucket() }
        val tremorBuckets = Array(BIN_COUNT) { StatBucket() }

        var currentTremorBin = -1
        val tremorTs = mutableListOf<Long>()
        val tremorGx = mutableListOf<Double>()
        val tremorGy = mutableListOf<Double>()
        val tremorGz = mutableListOf<Double>()
        var lastGyroDownsampleTs = 0L
        var lastAccelDownsampleTs = 0L
        var lowPassMag = 0f
        var prev2Hp = 0f
        var prev1Hp = 0f
        var prev1Ts = 0L
        var havePrev1 = false
        var havePrev2 = false
        var minSincePeak = 0f
        var lastStepTs = Long.MIN_VALUE
        var maxStrideLength = 0f
        var maxStrideSpeed = 0f
        var maxTremorPower = 0f
        var newScanPos = startPos

        fun flushTremorBin(binIndex: Int) {
            if (binIndex !in 0 until BIN_COUNT || tremorTs.size < 20) return
            val sampleRateHz = estimateSampleRateHz(tremorTs)
            if (sampleRateHz <= 0.0) return
            try {
                val ratio = (AnalysisEngine.computeTremorPowerRatio(
                    tremorGx.toDoubleArray(),
                    tremorGy.toDoubleArray(),
                    tremorGz.toDoubleArray(),
                    sampleRateHz
                ) * 100.0).toFloat().coerceIn(0f, 100f)
                tremorBuckets[binIndex].add(ratio)
                if (ratio > maxTremorPower) maxTremorPower = ratio
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Tremor calc failed at bin $binIndex", e)
            }
        }

        try {
            java.io.RandomAccessFile(sensorFile, "r").use { raf ->
                raf.seek(startPos)
                if (startPos > 0L) raf.readLine()

                var line: String?
                while (raf.readLine().also { line = it } != null) {
                    val l = line ?: break
                    newScanPos = raf.filePointer

                    val cols = l.split(",")
                    if (cols.size < 7) continue

                    val timestampNs = cols[0].trim().toLongOrNull() ?: continue
                    val accelX = cols[1].trim().toFloatOrNull() ?: continue
                    val accelY = cols[2].trim().toFloatOrNull() ?: continue
                    val accelZ = cols[3].trim().toFloatOrNull() ?: continue
                    val gyroX = cols[4].trim().toDoubleOrNull() ?: continue
                    val gyroY = cols[5].trim().toDoubleOrNull() ?: continue
                    val gyroZ = cols[6].trim().toDoubleOrNull() ?: continue

                    val minute = minuteOfDay(timestampNs / 1_000_000L)
                    if (minute !in 0 until MINUTES_PER_DAY) continue
                    val binIndex = minute / BIN_MINUTES

                    if (binIndex != currentTremorBin) {
                        flushTremorBin(currentTremorBin)
                        currentTremorBin = binIndex
                        tremorTs.clear(); tremorGx.clear(); tremorGy.clear(); tremorGz.clear()
                        lastGyroDownsampleTs = 0L
                    }

                    if (timestampNs - lastGyroDownsampleTs >= GYRO_DOWNSAMPLE_NS) {
                        tremorTs.add(timestampNs)
                        tremorGx.add(gyroX); tremorGy.add(gyroY); tremorGz.add(gyroZ)
                        lastGyroDownsampleTs = timestampNs
                    }

                    if (timestampNs - lastAccelDownsampleTs < ACCEL_DOWNSAMPLE_NS) continue
                    lastAccelDownsampleTs = timestampNs

                    val mag = sqrt((accelX * accelX + accelY * accelY + accelZ * accelZ).toDouble()).toFloat()
                    if (lowPassMag == 0f) lowPassMag = mag
                    lowPassMag = 0.92f * lowPassMag + 0.08f * mag
                    val hp = mag - lowPassMag

                    if (!havePrev1) { prev1Hp = hp; prev1Ts = timestampNs; havePrev1 = true; minSincePeak = hp; continue }
                    if (!havePrev2) { prev2Hp = prev1Hp; prev1Hp = hp; prev1Ts = timestampNs; havePrev2 = true; minSincePeak = min(minSincePeak, hp); continue }

                    minSincePeak = min(minSincePeak, hp)
                    if (prev1Hp > prev2Hp && prev1Hp >= hp && prev1Hp > STEP_THRESHOLD) {
                        if (lastStepTs == Long.MIN_VALUE) {
                            lastStepTs = prev1Ts; minSincePeak = prev1Hp
                        } else {
                            val intervalMs = ((prev1Ts - lastStepTs) / 1_000_000L).toInt()
                            if (intervalMs in MIN_STEP_INTERVAL_MS..MAX_STEP_INTERVAL_MS) {
                                val amplitude = max(prev1Hp - minSincePeak, 0.05f).toDouble()
                                val stepLengthM = (STEP_LENGTH_FACTOR * amplitude.pow(0.25)).toFloat().coerceIn(0.25f, 1.6f)
                                val strideLengthM = (stepLengthM * 2f).coerceIn(0.5f, 3.2f)
                                val speedMps = (stepLengthM / (intervalMs / 1000f)).coerceIn(0.2f, 3.2f)
                                strideLengthBuckets[binIndex].add(strideLengthM)
                                strideSpeedBuckets[binIndex].add(speedMps)
                                if (strideLengthM > maxStrideLength) maxStrideLength = strideLengthM
                                if (speedMps > maxStrideSpeed) maxStrideSpeed = speedMps
                                lastStepTs = prev1Ts; minSincePeak = prev1Hp
                            } else if (intervalMs > MAX_STEP_INTERVAL_MS) {
                                // Long idle gaps happen often in real passive data; re-anchor on the
                                // latest plausible peak instead of letting one stale peak suppress
                                // every later step in the file.
                                lastStepTs = prev1Ts
                                minSincePeak = prev1Hp
                            }
                        }
                    }
                    prev2Hp = prev1Hp; prev1Hp = hp; prev1Ts = timestampNs
                }
            }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "computeSensorSummaryIncremental error", e)
            return empty
        }

        flushTremorBin(currentTremorBin)

        val stridePoints = strideLengthBuckets.mapIndexedNotNull { index, bucket ->
            bucket.meanOrNull()?.let { TimePoint(index * BIN_MINUTES + BIN_MINUTES / 2, it) }
        }
        val tremorPoints = tremorBuckets.mapIndexedNotNull { index, bucket ->
            bucket.meanOrNull()?.let { TimePoint(index * BIN_MINUTES + BIN_MINUTES / 2, it) }
        }

        return IncrementalSensorResult(
            strideLength = stridePoints,
            strideSpeed = strideSpeedBuckets.mapIndexedNotNull { index, bucket ->
                bucket.meanOrNull()?.let { TimePoint(index * BIN_MINUTES + BIN_MINUTES / 2, it) }
            },
            tremorPower = tremorPoints,
            maxStrideLength = maxStrideLength,
            maxStrideSpeed = maxStrideSpeed,
            maxTremorPower = maxTremorPower,
            newScanPos = newScanPos
        )
    }

    private fun readSensorSeries(sensorFile: File): PDAnalysisEngine.SensorSeries {
        val builder = PDAnalysisEngine.SensorSeries.Builder()
        sensorFile.bufferedReader().useLines { lines ->
            lines.drop(1).forEach { line ->
                if (line.isBlank()) return@forEach
                val cols = line.split(',')
                if (cols.size < 7) return@forEach
                val timestampNs = cols[0].trim().toLongOrNull() ?: return@forEach
                val accelX = cols[1].trim().toDoubleOrNull() ?: return@forEach
                val accelY = cols[2].trim().toDoubleOrNull() ?: return@forEach
                val accelZ = cols[3].trim().toDoubleOrNull() ?: return@forEach
                val gyroX = cols[4].trim().toDoubleOrNull() ?: return@forEach
                val gyroY = cols[5].trim().toDoubleOrNull() ?: return@forEach
                val gyroZ = cols[6].trim().toDoubleOrNull() ?: return@forEach
                builder.add(timestampNs, accelX, accelY, accelZ, gyroX, gyroY, gyroZ)
            }
        }
        return builder.build()
    }

    private fun mergeSensorResults(
        existing: JSONObject?,
        fresh: IncrementalSensorResult
    ): SensorSummary {
        fun merge(freshPoints: List<TimePoint>, existingKey: String): List<TimePoint> {
            val existingPoints = existing?.let { readTimePointsFromJson(it, existingKey) } ?: emptyList()
            val map = LinkedHashMap<Int, Float>()
            existingPoints.forEach { map[it.minuteOfDay] = it.value }
            freshPoints.forEach { map[it.minuteOfDay] = it.value }
            return map.map { (min, v) -> TimePoint(min, v) }.sortedBy { it.minuteOfDay }
        }

        val existingMaxStride = existing
            ?.optDouble("max_stride_length", Double.NaN)
            ?.takeIf { isValidTrendValue("max_stride_length", it) }
            ?.toFloat() ?: 0f
        val existingMaxSpeed = existing
            ?.optDouble("max_stride_speed", Double.NaN)
            ?.takeIf { isValidTrendValue("max_stride_speed", it) }
            ?.toFloat() ?: 0f
        val existingMaxTremor = existing
            ?.optDouble("max_tremor_power", Double.NaN)
            ?.takeIf { isValidTrendValue("max_tremor_power", it) }
            ?.toFloat() ?: 0f

        return SensorSummary(
            strideLength    = merge(fresh.strideLength, "stride_length"),
            strideSpeed     = merge(fresh.strideSpeed,  "stride_speed"),
            tremorPower     = merge(fresh.tremorPower,  "tremor_power"),
            maxStrideLength = maxOf(existingMaxStride, fresh.maxStrideLength),
            maxStrideSpeed  = maxOf(existingMaxSpeed,  fresh.maxStrideSpeed),
            maxTremorPower  = maxOf(existingMaxTremor, fresh.maxTremorPower)
        )
    }

    private fun readTimePointsFromJson(obj: JSONObject, key: String): List<TimePoint> {
        val array = obj.optJSONArray(key) ?: return emptyList()
        return buildList {
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val minute = item.optInt("minute", -1)
                val value = item.optDouble("value", Double.NaN)
                if (isValidMetricPoint(key, minute, value)) {
                    add(TimePoint(minute, value.toFloat()))
                }
            }
        }.sortedBy { it.minuteOfDay }
    }

    private fun computeMarkers(medicationFile: File, activityFile: File): List<EventMarker> {
        val markers = mutableListOf<EventMarker>()

        if (medicationFile.exists()) {
            medicationFile.bufferedReader().useLines { lines ->
                lines.drop(1).forEach { line ->
                    val cols = splitCsvLine(line)
                    if (cols.size >= 4) {
                        val takenMs = cols[1].trim().toLongOrNull() ?: return@forEach
                        markers.add(EventMarker(minuteOfDay(takenMs), "Med", "medication"))
                    }
                }
            }
        }

        if (activityFile.exists()) {
            activityFile.bufferedReader().useLines { lines ->
                lines.drop(1).forEach { line ->
                    val cols = splitCsvLine(line)
                    if (cols.size >= 3) {
                        val label = cols[1].trim().take(3).ifBlank { "Ex" }
                        val timeMs = cols[2].trim().toLongOrNull() ?: return@forEach
                        markers.add(EventMarker(minuteOfDay(timeMs), label, "exercise"))
                    }
                }
            }
        }

        return markers.sortedBy { it.minuteOfDay }
    }

    private fun computeTmtTrend(tmtFile: File): Pair<Float, Float> {
        if (!tmtFile.exists()) return 0f to 0f
        var bestA = Float.MAX_VALUE
        var bestB = Float.MAX_VALUE
        tmtFile.bufferedReader().useLines { lines ->
            lines.drop(1).forEach { line ->
                val cols = splitCsvLine(line)
                if (cols.size < 5) return@forEach
                val type = cols[2].trim()
                val totalTime = cols[3].trim().toFloatOrNull() ?: return@forEach
                when (type) {
                    "A" -> if (totalTime < bestA) bestA = totalTime
                    "B" -> if (totalTime < bestB) bestB = totalTime
                }
            }
        }
        return (if (bestA < Float.MAX_VALUE) bestA else 0f) to (if (bestB < Float.MAX_VALUE) bestB else 0f)
    }

    private fun computeTappingRatio(tappingFile: File): Float {
        if (!tappingFile.exists()) return 0f
        var rightCount = 0
        var leftCount = 0
        tappingFile.bufferedReader().useLines { lines ->
            lines.drop(1).forEach { line ->
                val cols = splitCsvLine(line)
                if (cols.size < 5) return@forEach
                if (!cols[2].trim().equals("SAMPLE", ignoreCase = true)) return@forEach
                when (cols[4].trim()) {
                    Constants.PARTICIPANT_HAND_RIGHT -> rightCount++
                    Constants.PARTICIPANT_HAND_LEFT -> leftCount++
                }
            }
        }
        val dominantIsLeft = userProfile.dominantHand == Constants.PARTICIPANT_HAND_LEFT
        val dominant = if (dominantIsLeft) leftCount else rightCount
        val nondominant = if (dominantIsLeft) rightCount else leftCount
        return when {
            dominant > 0 && nondominant > 0 -> dominant.toFloat() / nondominant.toFloat()
            rightCount > 0 && leftCount > 0 -> rightCount.toFloat() / leftCount.toFloat()
            else -> 0f
        }
    }

    private fun computeTappingAsymmetry(tappingFile: File): Float {
        if (!tappingFile.exists()) return 0f
        var rightCount = 0
        var leftCount = 0
        tappingFile.bufferedReader().useLines { lines ->
            lines.drop(1).forEach { line ->
                val cols = splitCsvLine(line)
                if (cols.size < 5) return@forEach
                if (!cols[2].trim().equals("SAMPLE", ignoreCase = true)) return@forEach
                when (cols[4].trim()) {
                    Constants.PARTICIPANT_HAND_RIGHT -> rightCount++
                    Constants.PARTICIPANT_HAND_LEFT -> leftCount++
                }
            }
        }
        return PDAnalysisEngine.asymmetryIndex(leftCount.toDouble(), rightCount.toDouble()).toFloat()
    }

    private fun selectDailySummary(dates: JSONObject): Pair<String?, JSONObject?> {
        val today = TimeUtils.todayDateString()
        val todaySummary = dates.optJSONObject(today)
        if (hasDailyChartData(todaySummary)) return today to todaySummary
        val fallbackDate = dates.keys().asSequence()
            .filter { isDateDir(it) }
            .sortedDescending()
            .firstOrNull { hasDailyChartData(dates.optJSONObject(it)) }
            ?: return today.takeIf { todaySummary != null } to todaySummary
        return fallbackDate to dates.optJSONObject(fallbackDate)
    }

    private fun hasDailyChartData(summary: JSONObject?): Boolean {
        if (summary == null) return false
        return listOf("stride_length", "stride_speed", "tremor_power").any { key ->
            readTimePoints(summary, key).isNotEmpty()
        }
    }

    private fun summaryNeedsRepair(existing: JSONObject, dateDir: File, currentSensorFileSize: Long): Boolean {
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)
        if (currentSensorFileSize > 0L &&
            fileHasDataRows(sensorFile) &&
            (!hasDailyChartData(existing) ||
                summaryHasInvalidSensorCache(existing) ||
                summaryHasInvalidTrendCache(existing))
        ) {
            return true
        }
        val tmtFile = File(dateDir, Constants.TMT_RESULTS_FILE)
        if (fileHasDataRows(tmtFile) && existing.optDouble("tmt_a", 0.0) <= 0.0) return true
        return false
    }

    private fun summaryHasInvalidSensorCache(summary: JSONObject): Boolean {
        return listOf("stride_length", "stride_speed", "tremor_power").any { key ->
            val rawArray = summary.optJSONArray(key) ?: return@any false
            rawArray.length() > 0 && readTimePoints(summary, key).size != rawArray.length()
        }
    }

    private fun summaryHasInvalidTrendCache(summary: JSONObject): Boolean {
        return listOf("max_stride_length", "max_stride_speed", "max_tremor_power").any { key ->
            val value = summary.optDouble(key, Double.NaN)
            value.isFinite() && value != 0.0 && !isValidTrendValue(key, value)
        }
    }

    private fun fileHasDataRows(file: File): Boolean {
        if (!file.exists() || !file.isFile || file.length() == 0L) return false
        return runCatching {
            file.bufferedReader().useLines { lines ->
                lines.drop(1).any { it.isNotBlank() }
            }
        }.getOrDefault(false)
    }

    private fun hasDashboardSourceData(dateDir: File): Boolean {
        return listOf(
            Constants.SENSORS_FILE,
            Constants.TMT_RESULTS_FILE,
            Constants.TEST_FINGER_TAPPING_FILE
        ).any { fileName -> fileHasDataRows(File(dateDir, fileName)) }
    }

    private fun hasCheapDashboardSourceData(dateDir: File): Boolean {
        return listOf(
            Constants.TMT_RESULTS_FILE,
            Constants.TEST_FINGER_TAPPING_FILE
        ).any { fileName -> fileHasDataRows(File(dateDir, fileName)) }
    }

    private fun isFastSummaryCandidate(dateDir: File, cachedDates: JSONObject): Boolean {
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)
        val currentSensorFileSize = if (sensorFile.exists()) sensorFile.length() else 0L
        val existing = cachedDates.optJSONObject(dateDir.name)
        if (existing != null && existing.optBoolean("raw_deleted", false)) return true
        if (existing != null) {
            val cachedSize = existing.optLong("sensor_file_size", -1L)
            val cachedSourceMtime = existing.optLong("source_mtime", -1L)
            val sourceMtime = computeSourceSignature(dateDir)
            val needsRepair = summaryNeedsRepair(existing, dateDir, currentSensorFileSize)
            if (cachedSize == currentSensorFileSize && cachedSourceMtime == sourceMtime && !needsRepair) {
                return true
            }
        }

        if (hasCheapDashboardSourceData(dateDir)) return true
        return sensorFile.exists() &&
            currentSensorFileSize <= FAST_SYNC_SENSOR_MAX_BYTES &&
            fileHasDataRows(sensorFile)
    }

    private fun buildTrendSeries(
        dates: JSONObject,
        trendDays: Int,
        definitions: List<Triple<String, String, String>>
    ): List<TrendSeries> {
        val sortedDates = dates.keys().asSequence()
            .filter { isWithinWindow(it, trendDays) }
            .sorted()
            .toList()

        return definitions.map { (name, unit, key) ->
            TrendSeries(
                name = name,
                unit = unit,
                points = sortedDates.mapNotNull { date ->
                    val day = dates.optJSONObject(date) ?: return@mapNotNull null
                    val value = day.optDouble(key, Double.NaN)
                    if (!isValidTrendValue(key, value)) return@mapNotNull null
                    TrendPoint(label = date, value = value.toFloat())
                }
            )
        }
    }

    private fun readTimePoints(summary: JSONObject?, key: String): List<TimePoint> {
        if (summary == null) return emptyList()
        val array = summary.optJSONArray(key) ?: return emptyList()
        return buildList {
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val minute = item.optInt("minute", -1)
                val value = item.optDouble("value", Double.NaN)
                if (isValidMetricPoint(key, minute, value)) {
                    add(TimePoint(minute, value.toFloat()))
                }
            }
        }.sortedBy { it.minuteOfDay }
    }

    private fun readMarkers(summary: JSONObject?): List<EventMarker> {
        if (summary == null) return emptyList()
        val array = summary.optJSONArray("markers") ?: return emptyList()
        return buildList {
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                add(EventMarker(item.optInt("minute"), item.optString("label"), item.optString("type")))
            }
        }
    }

    private fun writeTimePoints(points: List<TimePoint>): JSONArray = JSONArray().apply {
        points
            .filter { it.minuteOfDay in 0 until MINUTES_PER_DAY && it.value.isFinite() }
            .forEach { point ->
            put(JSONObject().apply {
                put("minute", point.minuteOfDay)
                put("value", point.value.toDouble())
            })
        }
    }

    private fun writeMarkers(markers: List<EventMarker>): JSONArray = JSONArray().apply {
        markers.forEach { marker ->
            put(JSONObject().apply {
                put("minute", marker.minuteOfDay)
                put("label", marker.label)
                put("type", marker.type)
            })
        }
    }

    private fun computeSourceSignature(dateDir: File): Long {
        return listOf(
            File(dateDir, Constants.SENSORS_FILE),
            File(dateDir, Constants.MEDICATION_FILE),
            File(dateDir, Constants.PHYSICAL_ACTIVITY_FILE),
            File(dateDir, Constants.TMT_RESULTS_FILE),
            File(dateDir, Constants.TEST_FINGER_TAPPING_FILE)
        ).filter { it.exists() }.maxOfOrNull { it.lastModified() } ?: 0L
    }

    private fun isValidMetricPoint(key: String, minuteOfDay: Int, value: Double): Boolean {
        if (minuteOfDay !in 0 until MINUTES_PER_DAY || !value.isFinite()) return false
        val bounds = metricBoundsForKey(key) ?: return value >= 0.0
        return value in bounds.minValue.toDouble()..bounds.maxValue.toDouble()
    }

    private fun isValidTrendValue(key: String, value: Double): Boolean {
        if (!value.isFinite()) return false
        return when (key) {
            "max_stride_length" -> value in 0.05..5.0
            "max_stride_speed" -> value in 0.05..6.0
            "max_tremor_power" -> value in 0.0..100.0
            "tmt_a", "tmt_b" -> value in 1.0..600_000.0
            "tapping_ratio" -> value in 0.05..20.0
            "tapping_asymmetry" -> value >= 0.0
            else -> value > 0.0
        }
    }

    private fun metricBoundsForKey(key: String): MetricBounds? {
        return when (key) {
            "stride_length" -> MetricBounds(0.05f, 5.0f)
            "stride_speed" -> MetricBounds(0.05f, 6.0f)
            "tremor_power" -> MetricBounds(0f, 100f)
            else -> null
        }
    }

    private fun estimateSampleRateHz(timestampsNs: List<Long>): Double {
        if (timestampsNs.size < 3) return 0.0
        val intervals = mutableListOf<Long>()
        for (i in 1 until timestampsNs.size) {
            val delta = timestampsNs[i] - timestampsNs[i - 1]
            if (delta > 0) intervals.add(delta)
        }
        if (intervals.isEmpty()) return 0.0
        val median = intervals.sorted()[intervals.size / 2].toDouble()
        return if (median > 0.0) 1e9 / median else 0.0
    }

    private fun minuteOfDay(epochMs: Long): Int {
        val local = Instant.ofEpochMilli(epochMs).atZone(zoneId)
        return local.hour * 60 + local.minute
    }

    private fun isWithinWindow(dateStr: String, trendDays: Int): Boolean {
        if (trendDays <= 0) return isDateDir(dateStr)
        val date = runCatching { LocalDate.parse(dateStr, dateFormatter) }.getOrNull() ?: return false
        val cutoff = LocalDate.now().minusDays(trendDays.toLong())
        return !date.isBefore(cutoff)
    }

    private fun isDateDir(name: String): Boolean = DATE_REGEX.matches(name)

    private fun baseDir(): File = File(dataManager.getStoragePath())

    private fun cacheFile(): File = File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}")

    private fun freshRoot() = JSONObject().apply {
        put("version", CACHE_VERSION)
        put("dates", JSONObject())
    }

    private fun loadRoot(): JSONObject {
        val file = cacheFile()
        if (!file.exists()) return freshRoot()
        val root = runCatching { JSONObject(file.readText()) }.getOrElse { return freshRoot() }
        if (root.optInt("version", 0) < CACHE_VERSION) return migrateLegacyRoot(root)
        return root
    }

    private fun migrateLegacyRoot(root: JSONObject): JSONObject {
        val migrated = freshRoot()
        val oldDates = root.optJSONObject("dates") ?: return migrated
        val newDates = migrated.optJSONObject("dates") ?: return migrated
        oldDates.keys().forEach { date ->
            val day = oldDates.optJSONObject(date) ?: return@forEach
            if (day.optBoolean("raw_deleted", false) || hasCachedGraphOrTrendData(day)) {
                newDates.put(date, day)
            }
        }
        return migrated
    }

    private fun hasCachedGraphOrTrendData(summary: JSONObject): Boolean {
        if (hasDailyChartData(summary)) return true
        return listOf(
            "max_stride_length",
            "max_stride_speed",
            "max_tremor_power",
            "tmt_a",
            "tmt_b",
            "tapping_ratio"
        ).any { key ->
            isValidTrendValue(key, summary.optDouble(key, Double.NaN))
        }
    }

    private fun saveRoot(root: JSONObject) {
        root.put("version", CACHE_VERSION)
        cacheFile().writeText(root.toString())
    }

    private fun splitCsvLine(line: String): List<String> {
        val cols = mutableListOf<String>()
        val sb = StringBuilder()
        var inQuotes = false
        line.forEach { ch ->
            when {
                ch == '"' -> inQuotes = !inQuotes
                ch == ',' && !inQuotes -> {
                    cols.add(sb.toString())
                    sb.clear()
                }
                else -> sb.append(ch)
            }
        }
        cols.add(sb.toString())
        return cols
    }

    companion object {
        private const val TAG = "DashboardSummaryStore"
        private const val CACHE_VERSION = 9
        internal const val DEFAULT_FAST_SYNC_MAX_DATES = 4
        internal const val FAST_SYNC_SENSOR_MAX_BYTES = 160L * 1024L * 1024L
        private const val FULL_PD_ANALYSIS_MAX_BYTES = 24L * 1024L * 1024L
        private const val DELETION_SENSOR_SCAN_MAX_BYTES = 32L * 1024L * 1024L
        private const val BIN_MINUTES = 15
        private const val BIN_COUNT = 24 * 60 / BIN_MINUTES
        private const val MINUTES_PER_DAY = 24 * 60
        // Tremor needs the native gyro rate; 40 ms downsampling aliases 25 Hz phones below
        // the 3-10 Hz tremor band's Nyquist requirement and produces an empty graph.
        private const val GYRO_DOWNSAMPLE_NS = 0L
        private const val ACCEL_DOWNSAMPLE_NS = 40_000_000L
        private const val STEP_THRESHOLD = 0.10f
        private const val MIN_STEP_INTERVAL_MS = 200
        private const val MAX_STEP_INTERVAL_MS = 2000
        private const val STEP_LENGTH_FACTOR = 0.45
        private val DATE_REGEX = Regex("\\d{4}-\\d{2}-\\d{2}")
    }
}
