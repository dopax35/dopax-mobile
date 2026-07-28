package com.pdcollect.app.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.pdcollect.app.util.Constants
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.zip.ZipFile

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DataManagerTest {

    private lateinit var context: Context
    private lateinit var userProfile: UserProfile
    private lateinit var dataManager: DataManager
    private lateinit var baseDir: File

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        userProfile = UserProfile(context)
        userProfile.userId = "test_user"
        dataManager = DataManager(context, userProfile)
        baseDir = File(context.getExternalFilesDir(null), "${Constants.BASE_DIR}/test_user")
    }

    @After
    fun tearDown() {
        dataManager.closeAll()
        // Clean up test files
        File(context.getExternalFilesDir(null), Constants.BASE_DIR).deleteRecursively()
        context.cacheDir.listFiles()?.filter { it.name.startsWith("PDCollect_") }?.forEach { it.delete() }
        context.filesDir.listFiles()?.filter { it.name.contains("dashboard_graph_cache") }?.forEach { it.delete() }
    }

    @Test
    fun writeSensorData_createsFileWithHeaderAndData() {
        val rows = listOf(
            "1000000,1.0,2.0,3.0,0.1,0.2,0.3,10.0,20.0,30.0",
            "2000000,1.1,2.1,3.1,0.11,0.21,0.31,10.1,20.1,30.1"
        )
        dataManager.writeSensorData(rows)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.SENSORS_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.SENSORS_HEADER, lines[0])
        assertEquals(rows[0], lines[1])
        assertEquals(rows[1], lines[2])
        assertEquals(3, lines.size)
    }

    @Test
    fun writeTouchEvent_createsFileWithHeaderAndData() {
        val row = "1234567890,TAP,500,800,com.example.app"
        dataManager.writeTouchEvent(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.TOUCH_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.TOUCH_HEADER, lines[0])
        assertEquals(row, lines[1])
    }

    @Test
    fun writeKeyEvent_createsFileWithHeaderAndData() {
        val row = "1234567890,a,false,com.example.app"
        dataManager.writeKeyEvent(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.KEYS_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.KEYS_HEADER, lines[0])
        assertEquals(row, lines[1])
    }

    @Test
    fun writeAppEvent_createsFileWithHeaderAndData() {
        val row = "1234567890,OPEN,com.example.app,com.example.app.MainActivity"
        dataManager.writeAppEvent(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.APPS_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.APPS_HEADER, lines[0])
        assertEquals(row, lines[1])
    }

    @Test
    fun listAvailableDates_withMultipleDirs_sortedNewestFirst() {
        // Create date directories with files
        val dates = listOf("2024-01-15", "2024-01-17", "2024-01-16")
        for (date in dates) {
            val dir = File(baseDir, date)
            dir.mkdirs()
            File(dir, "test.csv").writeText("header\nrow1\nrow2")
        }

        val result = dataManager.listAvailableDates()
        assertEquals(3, result.size)
        assertEquals("2024-01-17", result[0].date)
        assertEquals("2024-01-16", result[1].date)
        assertEquals("2024-01-15", result[2].date)
    }

    @Test
    fun listAvailableDates_withEmptyBaseDir_returnsEmptyList() {
        // baseDir exists but has no date subdirectories
        baseDir.mkdirs()
        val result = dataManager.listAvailableDates()
        assertTrue(result.isEmpty())
    }

    @Test
    fun listAvailableDates_ignoresNonDateDirectories() {
        baseDir.mkdirs()
        File(baseDir, "2024-01-15").mkdirs().also {
            File(baseDir, "2024-01-15/test.csv").writeText("data")
        }
        File(baseDir, "not-a-date").mkdirs()
        File(baseDir, "screenshots").mkdirs()
        File(baseDir, "12345").mkdirs()

        val result = dataManager.listAvailableDates()
        assertEquals(1, result.size)
        assertEquals("2024-01-15", result[0].date)
    }

    @Test
    fun listAvailableDates_reportsCorrectSizeAndCount() {
        val dateDir = File(baseDir, "2024-01-15")
        dateDir.mkdirs()
        File(dateDir, "file1.csv").writeText("abcdef") // 6 bytes
        File(dateDir, "file2.csv").writeText("xyz")     // 3 bytes

        val result = dataManager.listAvailableDates()
        assertEquals(1, result.size)
        assertEquals(9L, result[0].sizeBytes) // total size
        assertEquals(2, result[0].fileCount)   // file count
    }

    @Test
    fun zipDateData_createsValidZip() {
        val dateStr = "2024-01-15"
        val dateDir = File(baseDir, dateStr)
        dateDir.mkdirs()
        File(dateDir, "sensors.csv").writeText("header\ndata1")
        File(dateDir, "touch.csv").writeText("header\ndata2")

        val zipFile = dataManager.zipDateData(dateStr)
        assertNotNull(zipFile)
        assertTrue(zipFile!!.exists())

        ZipFile(zipFile).use { zip ->
            val entries = zip.entries().toList().map { it.name }.sorted()
            assertEquals(2, entries.size)
            assertTrue(entries.contains("$dateStr/sensors.csv"))
            assertTrue(entries.contains("$dateStr/touch.csv"))
        }
    }

    @Test
    fun zipDateData_excludesUploadMarkerFiles() {
        val dateStr = "2024-01-15"
        val dateDir = File(baseDir, dateStr)
        dateDir.mkdirs()
        File(dateDir, "sensors.csv").writeText("header\ndata1")
        File(dateDir, ".uploaded").writeText("already uploaded")
        File(dateDir, ".uploading").writeText("in progress")

        val zipFile = dataManager.zipDateData(dateStr)
        assertNotNull(zipFile)

        ZipFile(zipFile!!).use { zip ->
            val entries = zip.entries().toList().map { it.name }
            assertTrue(entries.contains("$dateStr/sensors.csv"))
            assertFalse(entries.contains("$dateStr/.uploaded"))
            assertFalse(entries.contains("$dateStr/.uploading"))
        }
    }

    @Test
    fun dateHasRecordedData_ignoresHeaderOnlyFilesAndUploadMarkers() {
        val dateStr = "2024-01-15"
        val dateDir = File(baseDir, dateStr)
        dateDir.mkdirs()
        File(dateDir, Constants.SENSORS_FILE).writeText(Constants.SENSORS_HEADER + "\n")
        File(dateDir, ".uploaded").writeText("already uploaded")

        assertFalse(dataManager.dateHasRecordedData(dateStr))

        File(dateDir, Constants.TOUCH_FILE).writeText(Constants.TOUCH_HEADER + "\n123,TAP,1,2,app")

        assertTrue(dataManager.dateHasRecordedData(dateStr))
    }

    @Test
    fun zipDateData_nonexistentDate_returnsNull() {
        val result = dataManager.zipDateData("2099-12-31")
        assertNull(result)
    }

    @Test
    fun deleteDateData_removesDirectoryAndContents() {
        val dateStr = "2024-01-15"
        val dateDir = File(baseDir, dateStr)
        dateDir.mkdirs()
        File(dateDir, "sensors.csv").writeText("data")
        val subDir = File(dateDir, "screenshots")
        subDir.mkdirs()
        File(subDir, "img.jpg").writeText("imgdata")

        assertTrue(dataManager.deleteDateData(dateStr))
        assertFalse(dateDir.exists())
    }

    @Test
    fun deleteDateData_nonexistentDate_returnsFalse() {
        assertFalse(dataManager.deleteDateData("2099-12-31"))
    }

    @Test
    fun getDataSizeBytes_correctTotalAcrossFiles() {
        val dateDir = File(baseDir, "2024-01-15")
        dateDir.mkdirs()
        val content1 = "abcdefghij" // 10 bytes
        val content2 = "12345"      // 5 bytes
        File(dateDir, "file1.csv").writeText(content1)
        File(dateDir, "file2.csv").writeText(content2)

        val size = dataManager.getDataSizeBytes()
        assertEquals(15L, size)
    }

    @Test
    fun writeFaceDistanceData_createsFileWithHeaderAndData() {
        val row = "1234567890,tmt,true,true,61.5000,812.4000,45.3000,0.9100,5.5000,-2.3000,ipd_intrinsics"
        dataManager.writeFaceDistanceData(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.FACE_DISTANCE_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.FACE_DISTANCE_HEADER, lines[0])
        assertEquals(row, lines[1])
        assertEquals(2, lines.size)
    }

    @Test
    fun writeGazeData_createsFileWithHeaderAndData() {
        val row = "1234567890,-0.1200,0.0400,-0.1100,0.0380,1.0000,1.0000,0.0000,0.0000,0.0000,mlkit_face_landmarks"
        dataManager.writeGazeData(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.GAZE_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.GAZE_HEADER, lines[0])
        assertEquals(row, lines[1])
        assertEquals(2, lines.size)
    }

    @Test
    fun writeFaceDistanceData_noFaceDetected_matchesHeaderColumnCount() {
        val row = "1234567890,always_on,false,false,-1.0000,-1.0000,-1.0000,0.0000,0.0000,0.0000,no_face"
        dataManager.writeFaceDistanceData(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.FACE_DISTANCE_FILE)
        val lines = file.readLines()
        val headerCols = lines[0].split(",").size
        val dataCols = lines[1].split(",").size
        assertEquals(headerCols, dataCols)
    }

    @Test
    fun writeFaceDistanceData_multipleRows_appendsCorrectly() {
        val rows = listOf(
            "1000,always_on,true,true,58.1000,790.4000,44.5000,0.8800,4.1000,-1.5000,ipd_intrinsics",
            "6000,always_on,false,false,-1.0000,-1.0000,-1.0000,0.0000,0.0000,0.0000,no_face",
            "11000,tmt,true,true,63.9000,812.4000,47.6000,0.9300,2.0000,-0.8000,ipd_intrinsics_median5"
        )
        for (row in rows) {
            dataManager.writeFaceDistanceData(row)
        }
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.FACE_DISTANCE_FILE)
        val lines = file.readLines()
        assertEquals(4, lines.size) // header + 3 data rows
        assertEquals(Constants.FACE_DISTANCE_HEADER, lines[0])
        assertEquals(rows[0], lines[1])
        assertEquals(rows[1], lines[2])
        assertEquals(rows[2], lines[3])
    }

    @Test
    fun writeBeanieTemperatureData_createsFileWithHeaderAndData() {
        val row = "1234567890,Beanie AA,AA:BB:CC:DD:EE:FF,profile_x,30.10,29.20,31.23,1.24,87"
        dataManager.writeBeanieTemperatureData(row)
        dataManager.closeAll()

        val file = File(dataManager.getDayDir(), Constants.BEANIE_TEMP_FILE)
        assertTrue(file.exists())
        val lines = file.readLines()
        assertEquals(Constants.BEANIE_TEMP_HEADER, lines[0])
        assertEquals(row, lines[1])
    }

    @Test
    fun initializePassiveLogs_createsAllDailyFiles() {
        dataManager.initializePassiveLogs()
        dataManager.closeAll()

        val dayDir = dataManager.getDayDir()
        assertTrue(File(dayDir, Constants.BEANIE_TEMP_FILE).exists())
        assertTrue(File(dayDir, Constants.BEANIE_IMU_FILE).exists())
        assertTrue(File(dayDir, Constants.SENSORS_FILE).exists())
        assertTrue(File(dayDir, Constants.TEST_FINGER_TAPPING_FILE).exists())
    }

    @Test
    fun deleteDateData_preservesTrendSummaryInCache() {
        val dateStr = LocalDate.now().minusDays(5).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(baseDir, dateStr)
        dateDir.mkdirs()
        File(dateDir, Constants.TMT_RESULTS_FILE).writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,A,1234,0,\"[]\",\"[]\",\"[]\""
        )

        assertTrue(dataManager.deleteDateData(dateStr))
        assertFalse(dateDir.exists())

        val metrics = dataManager.getCachedDashboardMetrics(180)
        val tmtSeries = metrics.testTrend.first { it.name == "TMT A" }
        val cachedPoint = tmtSeries.points.firstOrNull { it.label == dateStr }
        assertNotNull(cachedPoint)
        assertEquals(1234f, cachedPoint!!.value)
    }

    @Test
    fun cleanupUploadedRawData_deletesOnlyUploadedDirsOlderThanRetention_andKeepsCachedTrend() {
        val formatter = DateTimeFormatter.ISO_LOCAL_DATE
        val oldUploadedDate = LocalDate.now().minusDays(20).format(formatter)
        val recentUploadedDate = LocalDate.now().minusDays(5).format(formatter)
        val oldUnuploadedDate = LocalDate.now().minusDays(21).format(formatter)

        val oldUploadedDir = File(baseDir, oldUploadedDate).apply { mkdirs() }
        val recentUploadedDir = File(baseDir, recentUploadedDate).apply { mkdirs() }
        val oldUnuploadedDir = File(baseDir, oldUnuploadedDate).apply { mkdirs() }

        File(oldUploadedDir, Constants.TMT_RESULTS_FILE).writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,A,2345,1,\"[]\",\"[]\",\"[]\""
        )
        File(recentUploadedDir, Constants.TMT_RESULTS_FILE).writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,B,3456,0,\"[]\",\"[]\",\"[]\""
        )
        File(oldUploadedDir, ".uploaded").writeText("")
        File(recentUploadedDir, ".uploaded").writeText("")

        dataManager.cleanupUploadedRawData(daysToKeep = 14)

        assertFalse(oldUploadedDir.exists())
        assertTrue(recentUploadedDir.exists())
        assertTrue(oldUnuploadedDir.exists())

        val metrics = dataManager.getDashboardMetrics(180)
        val tmtASeries = metrics.testTrend.first { it.name == "TMT A" }
        val cachedPoint = tmtASeries.points.firstOrNull { it.label == oldUploadedDate }
        assertNotNull(cachedPoint)
        assertEquals(2345f, cachedPoint!!.value)
    }

    @Test
    fun getDashboardMetrics_refreshesOlderSummaryWhenNonSensorLogsChange() {
        val dateStr = LocalDate.now().minusDays(3).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(baseDir, dateStr).apply { mkdirs() }
        val tmtFile = File(dateDir, Constants.TMT_RESULTS_FILE)

        tmtFile.writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,A,1234,0,\"[]\",\"[]\",\"[]\""
        )

        var metrics = dataManager.getDashboardMetrics(180)
        var tmtSeries = metrics.testTrend.first { it.name == "TMT A" }
        assertEquals(1234f, tmtSeries.points.first { it.label == dateStr }.value)

        tmtFile.writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,A,987,0,\"[]\",\"[]\",\"[]\""
        )
        assertTrue(tmtFile.setLastModified(System.currentTimeMillis() + 2_000L))

        metrics = dataManager.getDashboardMetrics(180)
        tmtSeries = metrics.testTrend.first { it.name == "TMT A" }
        assertEquals(987f, tmtSeries.points.first { it.label == dateStr }.value)
    }

    @Test
    fun getDashboardMetrics_usesMostRecentStoredDayWhenTodayHasNoDailyData() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val yesterday = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)

        val cacheRoot = JSONObject().apply {
            put("version", 9)
            put("dates", JSONObject().apply {
                put(today, JSONObject().apply {
                    put("date", today)
                    put("stride_length", JSONArray())
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                })
                put(yesterday, JSONObject().apply {
                    put("date", yesterday)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", 720)
                        put("value", 1.23)
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(cacheRoot.toString())

        val metrics = dataManager.getDashboardMetrics(180)

        assertEquals(yesterday, metrics.dailySourceDate)
        assertEquals(1, metrics.dailyStrideLength.size)
        assertEquals(720, metrics.dailyStrideLength.first().minuteOfDay)
        assertEquals(1.23f, metrics.dailyStrideLength.first().value)
    }

    @Test
    fun getDashboardMetrics_ignoresInvalidCachedDailyPointsWhenSelectingFallbackDay() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val yesterday = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)

        val cacheRoot = JSONObject().apply {
            put("version", 9)
            put("dates", JSONObject().apply {
                put(today, JSONObject().apply {
                    put("date", today)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", 720)
                        put("value", 9.99e12)
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                })
                put(yesterday, JSONObject().apply {
                    put("date", yesterday)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", 720)
                        put("value", 1.23)
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(cacheRoot.toString())

        val metrics = dataManager.getDashboardMetrics(180)

        assertEquals(yesterday, metrics.dailySourceDate)
        assertEquals(1, metrics.dailyStrideLength.size)
        assertEquals(1.23f, metrics.dailyStrideLength.first().value)
    }

    @Test
    fun getCachedDashboardMetrics_exposesTodayAndPreviousTwoDaysForDailyComparison() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val yesterday = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val twoDaysAgo = LocalDate.now().minusDays(2).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val currentMinute = ZonedDateTime.now(ZoneId.systemDefault()).let { it.hour * 60 + it.minute }
        val todayPointMinute = (currentMinute - 10).coerceAtLeast(0)
        val todayMarkerMinute = (currentMinute - 5).coerceAtLeast(0)

        val cacheRoot = JSONObject().apply {
            put("version", 9)
            put("dates", JSONObject().apply {
                put(today, JSONObject().apply {
                    put("date", today)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", todayPointMinute)
                        put("value", 1.1)
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray().put(JSONObject().apply {
                        put("minute", todayMarkerMinute)
                        put("label", "Med")
                        put("type", "medication")
                    }))
                })
                put(yesterday, JSONObject().apply {
                    put("date", yesterday)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", 720)
                        put("value", 1.2)
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray().put(JSONObject().apply {
                        put("minute", 600)
                        put("label", "Med")
                        put("type", "medication")
                    }))
                })
                put(twoDaysAgo, JSONObject().apply {
                    put("date", twoDaysAgo)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", 720)
                        put("value", 1.3)
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray().put(JSONObject().apply {
                        put("minute", 660)
                        put("label", "Med")
                        put("type", "medication")
                    }))
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(cacheRoot.toString())

        val metrics = dataManager.getCachedDashboardMetrics(180)

        assertEquals(listOf(today, yesterday, twoDaysAgo), metrics.dailyComparison.map { it.date })
        assertTrue(metrics.dailyComparison.first().isToday)
        assertEquals(1.1f, metrics.dailyComparison[0].strideLength.first().value)
        assertEquals(1.2f, metrics.dailyComparison[1].strideLength.first().value)
        assertEquals(1.3f, metrics.dailyComparison[2].strideLength.first().value)
        assertEquals(todayMarkerMinute, metrics.dailyComparison[0].markers.first().minuteOfDay)
        assertEquals(600, metrics.dailyComparison[1].markers.first().minuteOfDay)
        assertEquals(660, metrics.dailyComparison[2].markers.first().minuteOfDay)
    }

    @Test
    fun getCachedDashboardMetrics_clipsTodaySeriesAndMarkersToCurrentTime() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val now = ZonedDateTime.now(ZoneId.systemDefault())
        val currentMinute = now.hour * 60 + now.minute
        val pastMinute = (currentMinute - 10).coerceAtLeast(0)
        val currentBinFutureMinute = if (currentMinute < 1439) currentMinute + 1 else currentMinute
        val farFutureMinute = (currentMinute + 8).takeIf { it <= 1439 }
        val futureMarkerMinute = if (currentMinute < 1439) currentMinute + 1 else currentMinute

        val strideLength = JSONArray().apply {
            put(JSONObject().apply {
                put("minute", pastMinute)
                put("value", 1.0)
            })
            put(JSONObject().apply {
                put("minute", currentBinFutureMinute)
                put("value", 2.0)
            })
            farFutureMinute?.let { futureMinute ->
                put(JSONObject().apply {
                    put("minute", futureMinute)
                    put("value", 3.0)
                })
            }
        }
        val markers = JSONArray().apply {
            put(JSONObject().apply {
                put("minute", pastMinute)
                put("label", "Med")
                put("type", "medication")
            })
            put(JSONObject().apply {
                put("minute", futureMarkerMinute)
                put("label", "Med")
                put("type", "medication")
            })
        }

        val cacheRoot = JSONObject().apply {
            put("version", 9)
            put("dates", JSONObject().apply {
                put(today, JSONObject().apply {
                    put("date", today)
                    put("stride_length", strideLength)
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", markers)
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(cacheRoot.toString())

        val metrics = dataManager.getCachedDashboardMetrics(180)
        val todayComparison = metrics.dailyComparison.first { it.isToday }

        assertTrue(todayComparison.strideLength.all { it.minuteOfDay <= currentMinute })
        assertEquals(currentMinute, todayComparison.strideLength.last().minuteOfDay)
        assertEquals(2.0f, todayComparison.strideLength.last().value)
        farFutureMinute?.let { assertFalse(todayComparison.strideLength.any { point -> point.value == 3.0f }) }
        assertTrue(todayComparison.markers.all { it.minuteOfDay <= currentMinute })
        assertTrue(metrics.dailyStrideLength.all { it.minuteOfDay <= currentMinute })
        assertTrue(metrics.dailyMarkers.all { it.minuteOfDay <= currentMinute })
    }

    @Test
    fun getDashboardMetrics_withTrendDaysZero_includesOlderUndeletedDates() {
        val oldDate = LocalDate.now().minusDays(250).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val oldDir = File(baseDir, oldDate).apply { mkdirs() }
        File(oldDir, Constants.TMT_RESULTS_FILE).writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,B,3456,0,\"[]\",\"[]\",\"[]\""
        )

        val metrics = dataManager.getDashboardMetrics(0)
        val tmtBSeries = metrics.testTrend.first { it.name == "TMT B" }
        val cachedPoint = tmtBSeries.points.firstOrNull { it.label == oldDate }

        assertNotNull(cachedPoint)
        assertEquals(3456f, cachedPoint!!.value)
    }

    @Test
    fun getDashboardMetricsFast_scansRecentDataBearingDayWhenTodayOnlyHasHeaders() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val yesterday = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val todayDir = File(baseDir, today).apply { mkdirs() }
        File(todayDir, Constants.SENSORS_FILE).writeText(Constants.SENSORS_HEADER + "\n")

        val yesterdayDir = File(baseDir, yesterday).apply { mkdirs() }
        val baseNs = LocalDate.parse(yesterday)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L

        File(yesterdayDir, Constants.SENSORS_FILE).writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$baseNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val metrics = dataManager.getDashboardMetricsFast(0)

        assertEquals(yesterday, metrics.dailySourceDate)
        assertTrue(metrics.dailyStrideLength.isNotEmpty())
    }

    @Test
    fun getDashboardMetricsFast_scansFallbackDayWhenTodayRowsProduceNoChartPoints() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val yesterday = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val todayDir = File(baseDir, today).apply { mkdirs() }
        val todayNs = LocalDate.parse(today)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L
        File(todayDir, Constants.SENSORS_FILE).writeText(
            Constants.SENSORS_HEADER + "\n" +
                "$todayNs,0.0,0.0,9.8,0.0,0.0,0.0,0.0,0.0,0.0"
        )

        val yesterdayDir = File(baseDir, yesterday).apply { mkdirs() }
        val baseNs = LocalDate.parse(yesterday)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L
        File(yesterdayDir, Constants.SENSORS_FILE).writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$baseNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val metrics = dataManager.getDashboardMetricsFast(0, maxSyncDates = 2)

        assertEquals(yesterday, metrics.dailySourceDate)
        assertTrue(metrics.dailyStrideLength.isNotEmpty())
    }

    @Test
    fun getDashboardMetricsFast_skipsHugeUncachedHistoricalSensorFiles() {
        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val oldDate = LocalDate.now().minusDays(2).format(DateTimeFormatter.ISO_LOCAL_DATE)

        val todayDir = File(baseDir, today).apply { mkdirs() }
        val todayNs = LocalDate.parse(today)
            .atTime(1, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L
        File(todayDir, Constants.SENSORS_FILE).writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$todayNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${todayNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${todayNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${todayNs + 1_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${todayNs + 1_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val oldDir = File(baseDir, oldDate).apply { mkdirs() }
        val oldSensorFile = File(oldDir, Constants.SENSORS_FILE)
        oldSensorFile.writeText(
            Constants.SENSORS_HEADER + "\n" +
                "$todayNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0\n"
        )
        java.io.RandomAccessFile(oldSensorFile, "rw").use { raf ->
            raf.setLength(DashboardSummaryStore.FAST_SYNC_SENSOR_MAX_BYTES + 1024L)
        }

        val metrics = dataManager.getDashboardMetricsFast(0, maxSyncDates = 4)

        assertEquals(today, metrics.dailySourceDate)
        assertTrue(metrics.dailyStrideLength.isNotEmpty())
        val cacheFile = File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}")
        val dates = JSONObject(cacheFile.readText()).getJSONObject("dates")
        assertTrue(dates.has(today))
        assertFalse(dates.has(oldDate))
    }

    @Test
    fun getDashboardMetrics_migratesStaleCacheByRescanningLiveRawData_andKeepsRawDeletedHistory() {
        val liveDate = LocalDate.now().minusDays(5).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val deletedDate = LocalDate.now().minusDays(30).format(DateTimeFormatter.ISO_LOCAL_DATE)

        File(baseDir, liveDate).apply { mkdirs() }
        File(baseDir, "$liveDate/${Constants.TMT_RESULTS_FILE}").writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,A,1234,0,\"[]\",\"[]\",\"[]\""
        )

        val staleCache = JSONObject().apply {
            put("version", 3)
            put("dates", JSONObject().apply {
                put(liveDate, JSONObject().apply {
                    put("date", liveDate)
                    put("tmt_a", 0)
                    put("tmt_b", 0)
                    put("tapping_ratio", 0)
                    put("stride_length", JSONArray())
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                })
                put(deletedDate, JSONObject().apply {
                    put("date", deletedDate)
                    put("tmt_a", 2222)
                    put("tmt_b", 0)
                    put("tapping_ratio", 0)
                    put("stride_length", JSONArray())
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                    put("raw_deleted", true)
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(staleCache.toString())

        val metrics = dataManager.getDashboardMetrics(180)
        val tmtASeries = metrics.testTrend.first { it.name == "TMT A" }

        assertEquals(1234f, tmtASeries.points.first { it.label == liveDate }.value)
        assertEquals(2222f, tmtASeries.points.first { it.label == deletedDate }.value)
    }

    @Test
    fun getDashboardMetrics_repairsCurrentVersionSensorCacheFromRawLogs() {
        val dateStr = LocalDate.now().minusDays(2).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(baseDir, dateStr).apply { mkdirs() }
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)
        val baseNs = LocalDate.parse(dateStr)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L

        sensorFile.writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$baseNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val staleCache = JSONObject().apply {
            put("version", 9)
            put("dates", JSONObject().apply {
                put(dateStr, JSONObject().apply {
                    put("date", dateStr)
                    put("source_mtime", sensorFile.lastModified())
                    put("sensor_file_size", sensorFile.length())
                    put("sensor_scan_pos", sensorFile.length())
                    put("tmt_a", 0)
                    put("tmt_b", 0)
                    put("tapping_ratio", 0)
                    put("stride_length", JSONArray())
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(staleCache.toString())

        val metrics = dataManager.getDashboardMetrics(0)

        assertEquals(dateStr, metrics.dailySourceDate)
        assertTrue(metrics.dailyStrideLength.isNotEmpty())
        assertTrue(metrics.gaitTrend.first { it.name == "Max Stride Length" }.points.any { it.label == dateStr })
    }

    @Test
    fun getDashboardMetrics_repairsInvalidCurrentVersionSensorCacheFromRawLogs() {
        val dateStr = LocalDate.now().minusDays(2).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(baseDir, dateStr).apply { mkdirs() }
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)
        val baseNs = LocalDate.parse(dateStr)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L

        sensorFile.writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$baseNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val staleCache = JSONObject().apply {
            put("version", 9)
            put("dates", JSONObject().apply {
                put(dateStr, JSONObject().apply {
                    put("date", dateStr)
                    put("source_mtime", sensorFile.lastModified())
                    put("sensor_file_size", sensorFile.length())
                    put("sensor_scan_pos", sensorFile.length())
                    put("tmt_a", 0)
                    put("tmt_b", 0)
                    put("tapping_ratio", 0)
                    put("stride_length", JSONArray().put(JSONObject().apply {
                        put("minute", 720)
                        put("value", Float.MAX_VALUE.toDouble())
                    }))
                    put("stride_speed", JSONArray())
                    put("tremor_power", JSONArray())
                    put("markers", JSONArray())
                    put("max_stride_length", Float.MAX_VALUE.toDouble())
                    put("max_stride_speed", 0.0)
                    put("max_tremor_power", 0.0)
                })
            })
        }
        File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}").writeText(staleCache.toString())

        val metrics = dataManager.getDashboardMetrics(0)

        assertEquals(dateStr, metrics.dailySourceDate)
        assertTrue(metrics.dailyStrideLength.isNotEmpty())
        assertTrue(metrics.dailyStrideLength.all { it.value.isFinite() && it.value < 10f })
        assertTrue(metrics.gaitTrend.first { it.name == "Max Stride Length" }.points.any { it.label == dateStr })
    }

    @Test
    fun rebuildDashboardSummariesFromScratch_rewritesCacheFromDateDirectories() {
        val dateStr = LocalDate.now().minusDays(2).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(baseDir, dateStr).apply { mkdirs() }
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)
        val baseNs = LocalDate.parse(dateStr)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L

        sensorFile.writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$baseNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 1_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val cacheFile = File(context.filesDir, "${userProfile.userId}_${Constants.GRAPH_CACHE_FILE}")
        cacheFile.writeText(
            JSONObject().apply {
                put("version", 9)
                put("dates", JSONObject().apply {
                    put(dateStr, JSONObject().apply {
                        put("date", dateStr)
                        put("source_mtime", sensorFile.lastModified())
                        put("sensor_file_size", sensorFile.length())
                        put("sensor_scan_pos", sensorFile.length())
                        put("stride_length", JSONArray())
                        put("stride_speed", JSONArray())
                        put("tremor_power", JSONArray())
                        put("markers", JSONArray())
                        put("tmt_a", 0)
                        put("tmt_b", 0)
                        put("tapping_ratio", 0)
                    })
                })
            }.toString()
        )

        val message = dataManager.rebuildDashboardSummariesFromScratch()
        val rebuiltRoot = JSONObject(cacheFile.readText())
        val rebuiltDay = rebuiltRoot.getJSONObject("dates").getJSONObject(dateStr)

        assertTrue(message.contains("Rebuilt 1 days"))
        assertTrue(rebuiltDay.getJSONArray("stride_length").length() > 0)
        assertTrue(rebuiltDay.optDouble("max_stride_length", 0.0) > 0.0)
    }

    @Test
    fun getDashboardMetrics_recoversAfterInitialLongPeakGapInPassiveSensorData() {
        val dateStr = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(baseDir, dateStr).apply { mkdirs() }
        val sensorFile = File(dateDir, Constants.SENSORS_FILE)
        val baseNs = LocalDate.parse(dateStr)
            .atTime(12, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli() * 1_000_000L

        sensorFile.writeText(
            Constants.SENSORS_HEADER + "\n" + listOf(
                "$baseNs,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 400_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 800_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 3_200_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 3_600_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 4_000_000_000L},20.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0",
                "${baseNs + 4_400_000_000L},9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0"
            ).joinToString("\n")
        )

        val metrics = dataManager.getDashboardMetrics(0)

        assertEquals(dateStr, metrics.dailySourceDate)
        assertTrue(metrics.dailyStrideLength.isNotEmpty())
        assertTrue(metrics.gaitTrend.first { it.name == "Max Stride Length" }.points.any { it.label == dateStr })
    }

    @Test
    fun getDashboardMetrics_recoversLegacyUserDirectoryWhenCurrentUserIdHasNoData() {
        val legacyUserId = "LEGACY1"
        val requestedUserId = "EMPTY01"
        val legacyBaseDir = File(context.getExternalFilesDir(null), "${Constants.BASE_DIR}/$legacyUserId")
        val dateStr = LocalDate.now().minusDays(4).format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(legacyBaseDir, dateStr).apply { mkdirs() }
        File(dateDir, Constants.TMT_RESULTS_FILE).writeText(
            Constants.TMT_HEADER + "\n" +
                "1,2,A,2345,0,\"[]\",\"[]\",\"[]\""
        )

        userProfile.userId = requestedUserId
        val recoveringManager = DataManager(context, userProfile)

        val metrics = recoveringManager.getDashboardMetrics(0)
        val tmtSeries = metrics.testTrend.first { it.name == "TMT A" }

        assertEquals(legacyUserId, userProfile.userId)
        assertEquals(2345f, tmtSeries.points.first { it.label == dateStr }.value)
        recoveringManager.closeAll()
    }
}
