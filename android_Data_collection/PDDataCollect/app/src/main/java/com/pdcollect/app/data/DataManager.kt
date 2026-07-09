package com.pdcollect.app.data

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.TimeUtils
import com.pdcollect.app.util.AnalysisEngine
import com.pdcollect.app.util.UploadState
import java.io.BufferedWriter
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FileWriter
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class DataManager(private val context: Context, private val userProfile: UserProfile) {

    private val writers = mutableMapOf<String, BufferedWriter>()
    private var currentDate = TimeUtils.todayDateString()
    private val dashboardSummaryStore = DashboardSummaryStore(context, userProfile, this)

    // ── Background I/O thread ───────────────────────────────────────────────
    private val ioThread = HandlerThread("DataManager-IO").apply { start() }
    private val ioHandler = Handler(ioThread.looper)

    private val flushRunnable = object : Runnable {
        override fun run() {
            if (ioThread.isAlive) {
                flushAllWriters()
                ioHandler.postDelayed(this, FLUSH_INTERVAL_MS)
            }
        }
    }

    fun startPeriodicFlush() {
        ioHandler.removeCallbacks(flushRunnable)
        ioHandler.postDelayed(flushRunnable, FLUSH_INTERVAL_MS)
    }

    fun stopPeriodicFlush() {
        ioHandler.removeCallbacks(flushRunnable)
    }

    @Synchronized
    private fun flushAllWriters() {
        writers.values.forEach { writer ->
            try { writer.flush() } catch (_: Exception) {}
        }
    }

    private fun baseDir(): File {
        return StorageDirectoryResolver.resolveBaseDir(context, userProfile)
    }

    private fun dayDir(): File {
        val dir = File(baseDir(), currentDate)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    @Synchronized
    fun initializePassiveLogs() {
        android.util.Log.d("DataManager", "Initializing passive logs...")
        getWriter(Constants.TOUCH_FILE, Constants.TOUCH_HEADER)
        getWriter(Constants.KEYS_FILE, Constants.KEYS_HEADER)
        getWriter(Constants.APPS_FILE, Constants.APPS_HEADER)
        getWriter(Constants.FACE_DISTANCE_FILE, Constants.FACE_DISTANCE_HEADER)
        getWriter(Constants.SENSORS_FILE, Constants.SENSORS_HEADER)
        getWriter(Constants.MEDICATION_FILE, Constants.MEDICATION_HEADER)
        getWriter(Constants.PHYSICAL_ACTIVITY_FILE, Constants.PHYSICAL_ACTIVITY_HEADER)
        getWriter(Constants.HR_FILE, Constants.HR_HEADER)
        getWriter(Constants.BLINK_FILE, Constants.BLINK_HEADER)
        getWriter(Constants.VOICE_LOG_FILE, Constants.VOICE_LOG_HEADER)
    }

    @Synchronized
    fun initializeBeanieLogs() {
        getWriter(Constants.BEANIE_TEMP_FILE, Constants.BEANIE_TEMP_HEADER)
        getWriter(Constants.BEANIE_IMU_FILE, Constants.BEANIE_IMU_HEADER)
    }

    @Synchronized
    private fun getWriter(filename: String, header: String): BufferedWriter {
        val today = TimeUtils.todayDateString()
        if (today != currentDate) {
            // Safe rotation: flush and clear current writers but DON'T quit the thread
            writers.values.forEach { writer ->
                try {
                    writer.flush()
                    writer.close()
                } catch (_: Exception) {}
            }
            writers.clear()
            currentDate = today
        }

        val key = "$currentDate/$filename"
        writers[key]?.let { return it }

        val file = File(dayDir(), filename)
        val needsHeader = !file.exists() || file.length() == 0L
        val writer = BufferedWriter(FileWriter(file, true))
        if (needsHeader) {
            writer.write(header)
            writer.newLine()
            writer.flush()
        }
        writers[key] = writer
        return writer
    }

    fun writeSensorData(rows: List<String>) {
        val snapshot = rows.toList()
        ioHandler.post {
            val writer = getWriter(Constants.SENSORS_FILE, Constants.SENSORS_HEADER)
            for (row in snapshot) {
                writer.write(row)
                writer.newLine()
            }
        }
    }

    fun writeTouchEvent(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.TOUCH_FILE, Constants.TOUCH_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeKeyEvent(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.KEYS_FILE, Constants.KEYS_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeAppEvent(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.APPS_FILE, Constants.APPS_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeFaceDistanceData(row: String) {
        ioHandler.post {
            try {
                val writer = getWriter(Constants.FACE_DISTANCE_FILE, Constants.FACE_DISTANCE_HEADER)
                writer.write(row)
                writer.newLine()
            } catch (e: Exception) {
                android.util.Log.e("DataManager", "Error writing face distance data", e)
            }
        }
    }

    @Synchronized
    fun writeTmtResult(row: String) {
        val writer = getWriter(Constants.TMT_RESULTS_FILE, Constants.TMT_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    @Synchronized
    fun writeProfileData(row: String) {
        val writer = getWriter(Constants.PROFILE_FILE, Constants.PROFILE_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    @Synchronized
    fun writeProfileSnapshot() {
        writeProfileData(buildProfileRow(userProfile))
    }

    @Synchronized
    fun writeQuestionnaireData(row: String) {
        val writer = getWriter(Constants.QUESTIONNAIRE_FILE, Constants.QUESTIONNAIRE_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    fun writeFingerTappingData(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.TEST_FINGER_TAPPING_FILE, Constants.FINGER_TAPPING_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeHandTurningData(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.TEST_HAND_TURNING_FILE, Constants.HAND_TURNING_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeSpiralData(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.TEST_SPIRAL_FILE, Constants.SPIRAL_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeLegAgilityData(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.TEST_LEG_AGILITY_FILE, Constants.LEG_AGILITY_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    @Synchronized
    fun writeMedicationData(row: String) {
        val writer = getWriter(Constants.MEDICATION_FILE, Constants.MEDICATION_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    @Synchronized
    fun writePhysicalActivityData(row: String) {
        val writer = getWriter(Constants.PHYSICAL_ACTIVITY_FILE, Constants.PHYSICAL_ACTIVITY_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    @Synchronized
    fun writeVoiceLogData(row: String) {
        val writer = getWriter(Constants.VOICE_LOG_FILE, Constants.VOICE_LOG_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    @Synchronized
    fun writeBlinkData(row: String) {
        val writer = getWriter(Constants.BLINK_FILE, Constants.BLINK_HEADER)
        writer.write(row)
        writer.newLine()
        writer.flush()
    }

    fun writeHeartRateData(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.HR_FILE, Constants.HR_HEADER)
            writer.write(row)
            writer.newLine()
        }
    }

    fun writeBeanieTemperatureData(row: String) {
        ioHandler.post {
            val writer = getWriter(Constants.BEANIE_TEMP_FILE, Constants.BEANIE_TEMP_HEADER)
            writer.write(row)
            writer.newLine()
            writer.flush()
        }
    }

    fun writeBeanieImuData(rows: List<String>) {
        val snapshot = rows.toList()
        ioHandler.post {
            val writer = getWriter(Constants.BEANIE_IMU_FILE, Constants.BEANIE_IMU_HEADER)
            for (row in snapshot) {
                writer.write(row)
                writer.newLine()
            }
            writer.flush()
        }
    }

    fun closeAll() {
        val latch = java.util.concurrent.CountDownLatch(1)
        ioHandler.post { latch.countDown() }
        try { latch.await(5, java.util.concurrent.TimeUnit.SECONDS) } catch (_: InterruptedException) {}

        synchronized(this) {
            stopPeriodicFlush()
            writers.values.forEach { writer ->
                try {
                    writer.flush()
                    writer.close()
                } catch (_: Exception) {}
            }
            writers.clear()
            ioThread.quitSafely()
        }
    }

    fun getDataSizeBytes(): Long {
        val base = baseDir()
        if (!base.exists()) return 0
        return base.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    fun getStoragePath(): String = baseDir().absolutePath

    fun getDayDir(): File = dayDir()

    fun getYesterdayDateString(): String {
        val yesterday = LocalDate.now().minusDays(1)
        return yesterday.format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
    }

    fun getYesterdayDir(): File? {
        val dir = File(baseDir(), getYesterdayDateString())
        return if (dir.exists() && dir.isDirectory) dir else null
    }

    fun zipYesterdayData(): File? {
        val yesterdayDir = getYesterdayDir() ?: return null
        val dateStr = getYesterdayDateString()
        val zipFile = File(context.cacheDir, "PDCollect_${userProfile.userId}_$dateStr.zip")
        if (zipFile.exists()) zipFile.delete()

        ZipOutputStream(FileOutputStream(zipFile)).use { zos ->
            yesterdayDir.walkTopDown().filter { it.isFile && shouldIncludeInZip(it) }.forEach { file ->
                val entryName = file.relativeTo(yesterdayDir).path
                zos.putNextEntry(ZipEntry("$dateStr/$entryName"))
                FileInputStream(file).use { fis ->
                    fis.copyTo(zos)
                }
                zos.closeEntry()
            }
            addMlPredictionsEntry(zos, dateStr)
        }
        return zipFile
    }

    data class DateEntry(
        val date: String,
        val sizeBytes: Long,
        val fileCount: Int,
        val isUploaded: Boolean
    )

    fun listAvailableDates(): List<DateEntry> {
        val base = baseDir()
        if (!base.exists()) return emptyList()
        val datePattern = Regex("\\d{4}-\\d{2}-\\d{2}")
        return base.listFiles()
            ?.filter { it.isDirectory && datePattern.matches(it.name) }
            ?.map { dir ->
                var sizeBytes = 0L
                var fileCount = 0
                dir.walkTopDown()
                    .filter { it.isFile }
                    .forEach { file ->
                        sizeBytes += file.length()
                        fileCount++
                    }
                DateEntry(dir.name, sizeBytes, fileCount, UploadState.isUploaded(dir))
            }
            ?.sortedByDescending { it.date }
            ?: emptyList()
    }

    fun zipDateData(dateStr: String): File? {
        val dateDir = File(baseDir(), dateStr)
        if (!dateDir.exists() || !dateDir.isDirectory) return null

        val zipFile = File(context.cacheDir, "PDCollect_${userProfile.userId}_$dateStr.zip")
        if (zipFile.exists()) zipFile.delete()

        ZipOutputStream(FileOutputStream(zipFile)).use { zos ->
            dateDir.walkTopDown().filter { it.isFile && shouldIncludeInZip(it) }.forEach { file ->
                val entryName = file.relativeTo(dateDir).path
                zos.putNextEntry(ZipEntry("$dateStr/$entryName"))
                FileInputStream(file).use { fis ->
                    fis.copyTo(zos)
                }
                zos.closeEntry()
            }
            addMlPredictionsEntry(zos, dateStr)
        }
        return zipFile
    }

    /**
     * ml_predictions.json (Beanie activity/ML inference log) lives at
     * context.filesDir, not inside the per-date directory the zip walk above
     * covers, so it's added as an explicit extra entry here — filtered to just
     * this date, since the on-disk file spans every date in one flat array.
     * No-ops if there are no ML predictions for this date (e.g. no Beanie used).
     */
    private fun addMlPredictionsEntry(zos: ZipOutputStream, dateStr: String) {
        val json = com.pdcollect.app.logic.MLPredictionStore.getInstance(context)
            .entriesForDateAsJSON(dateStr) ?: return
        zos.putNextEntry(ZipEntry("$dateStr/ml_predictions.json"))
        zos.write(json.toByteArray(Charsets.UTF_8))
        zos.closeEntry()
    }

    fun dateHasRecordedData(dateStr: String): Boolean {
        val dateDir = File(baseDir(), dateStr)
        if (!dateDir.exists() || !dateDir.isDirectory) return false
        return dateDir.listFiles()?.any { file ->
            file.isFile &&
                shouldIncludeInZip(file) &&
                runCatching {
                    file.bufferedReader().useLines { lines ->
                        lines.drop(1).any { it.isNotBlank() }
                    }
                }.getOrDefault(false)
        } == true
    }

    fun deleteDateData(dateStr: String): Boolean {
        return dashboardSummaryStore.preserveSummaryThenDeleteDate(dateStr)
    }

    @Synchronized
    fun wipeAllData(): Boolean {
        closeAll()
        val base = baseDir()
        val deletedTree = if (base.exists()) base.deleteRecursively() else true
        runCatching {
            context.cacheDir.listFiles()
                ?.filter { it.name.startsWith("PDCollect_") && it.name.endsWith(".zip") }
                ?.forEach { it.delete() }
        }
        runCatching { dashboardSummaryStore.clearCache() }
        return deletedTree
    }

    fun cleanupOldData(daysToKeep: Int = 365) {
        val base = baseDir()
        if (!base.exists()) return
        
        val datePattern = Regex("\\d{4}-\\d{2}-\\d{2}")
        val cutoff = LocalDate.now().minusDays(daysToKeep.toLong())
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

        base.listFiles()?.filter { it.isDirectory && datePattern.matches(it.name) }?.forEach { dir ->
            try {
                val dirDate = LocalDate.parse(dir.name, formatter)
                if (dirDate.isBefore(cutoff)) {
                    dir.deleteRecursively()
                }
            } catch (_: Exception) {}
        }
        
        // Storage Optimization: Cleanup old crash logs (> 30 days)
        runCatching {
            val crashDir = File(context.getExternalFilesDir(null), "crash_logs")
            if (crashDir.exists()) {
                val crashCutoff = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000)
                crashDir.listFiles()?.filter { it.lastModified() < crashCutoff }?.forEach { it.delete() }
            }
        }
    }

    fun cleanupUploadedRawData(daysToKeep: Int = Constants.RAW_RETENTION_DAYS) {
        dashboardSummaryStore.cleanupUploadedRawData(daysToKeep)
    }

    fun getDashboardMetrics(trendDays: Int = 0): DashboardSummaryStore.DashboardMetrics {
        return dashboardSummaryStore.getDashboardMetrics(trendDays)
    }

    fun getDashboardMetricsFast(
        trendDays: Int = 0,
        maxSyncDates: Int = DashboardSummaryStore.DEFAULT_FAST_SYNC_MAX_DATES
    ): DashboardSummaryStore.DashboardMetrics {
        return dashboardSummaryStore.getDashboardMetricsFast(trendDays, maxSyncDates)
    }

    fun getCachedDashboardMetrics(trendDays: Int = 0): DashboardSummaryStore.DashboardMetrics {
        return dashboardSummaryStore.getCachedDashboardMetrics(trendDays)
    }

    fun refreshDashboardGraphCache(
        trendDays: Int = 0,
        maxSyncDates: Int = DashboardSummaryStore.DEFAULT_FAST_SYNC_MAX_DATES
    ) {
        dashboardSummaryStore.refreshCachedSummaries(trendDays, maxSyncDates)
    }

    fun rebuildDashboardSummariesFromScratch(): String {
        return dashboardSummaryStore.rebuildDashboardSummariesFromScratch()
    }

    data class TmtSession(
        val dateLabel: String,
        val testType: String,
        val totalTimeMs: Long,
        val wrongTargetErrors: Int,
        val liftOffErrors: Int
    )

    data class TappingSession(
        val dateLabel: String,
        val rightCount: Int,
        val leftCount: Int,
        val bias: Int
    )

    fun getHistoricalTmtData(days: Int = 365): List<TmtSession> {
        val results = mutableListOf<TmtSession>()
        val dirs = recentDateDirs(days)
        for (dir in dirs) {
            val file = File(dir, Constants.TMT_RESULTS_FILE)
            if (!file.exists()) continue
            try {
                file.bufferedReader().useLines { lines ->
                    lines.drop(1).forEach { line ->
                        val cols = splitCsvLine(line)
                        if (cols.size >= 6) {
                            results.add(TmtSession(
                                dateLabel = dir.name,
                                testType  = cols[2].trim(),
                                totalTimeMs = cols[3].trim().toLongOrNull() ?: 0L,
                                wrongTargetErrors = cols[4].trim().toIntOrNull() ?: 0,
                                liftOffErrors     = cols[5].trim().toIntOrNull() ?: 0
                            ))
                        }
                    }
                }
            } catch (e: Exception) {}
        }
        return results
    }

    fun getHistoricalTappingData(days: Int = 365): List<TappingSession> {
        val perDay = mutableMapOf<String, Pair<Int, Int>>()
        val dirs = recentDateDirs(days)
        for (dir in dirs) {
            val file = File(dir, Constants.TEST_FINGER_TAPPING_FILE)
            if (!file.exists()) continue
            var right = 0; var left = 0
            try {
                file.bufferedReader().useLines { lines ->
                    lines.drop(1).forEach { line ->
                        val cols = line.split(",")
                        if (cols.size >= 2) {
                            when (cols[1].trim().lowercase()) {
                                "right" -> right++
                                "left"  -> left++
                            }
                        }
                    }
                }
            } catch (e: Exception) {}
            if (right + left > 0) perDay[dir.name] = Pair(right, left)
        }
        return perDay.entries.sortedBy { it.key }.map { (date, counts) ->
            TappingSession(date, counts.first, counts.second, counts.first - counts.second)
        }
    }

    fun getRecentHrvRmssd(days: Int = 365): Pair<Float, Float> {
        val dirs = recentDateDirs(days)
        val dailyRmssd = mutableListOf<Float>()
        var todayRmssd = 0f

        for ((idx, dir) in dirs.withIndex()) {
            val file = File(dir, Constants.HR_FILE)
            if (!file.exists()) continue
            val rrList = mutableListOf<Float>()
            try {
                file.bufferedReader().useLines { lines ->
                    lines.drop(1).forEach { line ->
                        val cols = line.split(",")
                        if (cols.size >= 3) {
                            cols[2].trim().toFloatOrNull()?.let { rrList.add(it) }
                        }
                    }
                }
            } catch (e: Exception) {}
            val rmssd = AnalysisEngine.computeRmssd(rrList)
            if (rmssd > 0f) {
                dailyRmssd.add(rmssd)
                if (idx == dirs.size - 1) todayRmssd = rmssd
            }
        }

        val avg = if (dailyRmssd.isNotEmpty()) dailyRmssd.average().toFloat() else 0f
        return Pair(todayRmssd, avg)
    }

    fun getHistoricalTremorRatio(days: Int = 365, maxRows: Int = 5000): Pair<Float, Float> {
        val dirs = recentDateDirs(days)
        val dailyRatios = mutableListOf<Float>()
        var todayRatio = 0f

        for ((idx, dir) in dirs.withIndex()) {
            val file = File(dir, Constants.SENSORS_FILE)
            if (!file.exists()) continue

            val gyroX = mutableListOf<Double>()
            val gyroY = mutableListOf<Double>()
            val gyroZ = mutableListOf<Double>()
            val tsNs  = mutableListOf<Long>()

            try {
                for (line in tailReadFile(file, maxRows)) {
                    if (line.isBlank()) continue
                    val cols = line.split(",")
                    if (cols.size < 7) continue
                    val ts = cols[0].trim().toLongOrNull() ?: continue
                    val gx = cols[4].trim().toDoubleOrNull() ?: continue
                    val gy = cols[5].trim().toDoubleOrNull() ?: continue
                    val gz = cols[6].trim().toDoubleOrNull() ?: continue
                    tsNs.add(ts)
                    gyroX.add(gx)
                    gyroY.add(gy)
                    gyroZ.add(gz)
                }
            } catch (e: Exception) { continue }

            if (gyroX.size < 20) continue

            val intervals = (1 until tsNs.size).map { (tsNs[it] - tsNs[it - 1]).toDouble() }
            val medianIntervalNs = if (intervals.isNotEmpty()) intervals.sorted()[intervals.size / 2] else 0.0
            val sampleRateHz = if (medianIntervalNs > 0) 1e9 / medianIntervalNs else 50.0

            val ratio = AnalysisEngine.computeTremorPowerRatio(
                gyroX.toDoubleArray(), gyroY.toDoubleArray(), gyroZ.toDoubleArray(),
                sampleRateHz
            ).toFloat().coerceIn(0f, 1f)

            if (ratio > 0f) {
                dailyRatios.add(ratio)
                if (idx == dirs.size - 1) todayRatio = ratio
            }
        }

        val avg = if (dailyRatios.isNotEmpty()) dailyRatios.average().toFloat() else 0f
        return Pair(todayRatio, avg)
    }

    private fun recentDateDirs(days: Int): List<File> {
        val base = baseDir()
        val datePattern = Regex("\\d{4}-\\d{2}-\\d{2}")
        return base.listFiles()
            ?.filter { it.isDirectory && datePattern.matches(it.name) }
            ?.sortedByDescending { it.name }
            ?.take(days)
            ?.reversed()
            ?: emptyList()
    }

    private fun tailReadFile(file: File, maxLines: Int, avgLineLenHint: Int = 120): List<String> {
        val fileLen = file.length()
        if (fileLen == 0L) return emptyList()

        val readBytes = (maxLines.toLong() * avgLineLenHint).coerceAtMost(fileLen)
        val startPos = (fileLen - readBytes).coerceAtLeast(0L)

        return try {
            java.io.RandomAccessFile(file, "r").use { raf ->
                raf.seek(startPos)
                val buf = ByteArray(readBytes.toInt())
                val actualRead = raf.read(buf, 0, buf.size)
                if (actualRead <= 0) return emptyList()

                val chunk = String(buf, 0, actualRead, Charsets.UTF_8)
                val lines = chunk.lines()
                val complete = if (startPos > 0) lines.drop(1) else lines.drop(1)
                complete.filter { it.isNotBlank() }.takeLast(maxLines)
            }
        } catch (e: Exception) { emptyList() }
    }

    private fun splitCsvLine(line: String): List<String> {
        val cols = mutableListOf<String>()
        val sb = StringBuilder()
        var inQuotes = false
        for (ch in line) {
            when {
                ch == '"' -> inQuotes = !inQuotes
                ch == ',' && !inQuotes -> { cols.add(sb.toString().trim()); sb.clear() }
                else -> sb.append(ch)
            }
        }
        cols.add(sb.toString().trim())
        return cols
    }

    private fun shouldIncludeInZip(file: File): Boolean {
        return file.name != ".uploaded" && file.name != ".uploading"
    }

    companion object {
        private const val FLUSH_INTERVAL_MS = 5_000L
        fun buildProfileRow(p: UserProfile): String {
            return "${System.currentTimeMillis()},${p.userId},${p.age},${p.gender},${p.dominantHand},${p.affectedSide},${p.medications}"
        }
    }
}
                                                                                                                                                                                                                                                                                                                                                                                         