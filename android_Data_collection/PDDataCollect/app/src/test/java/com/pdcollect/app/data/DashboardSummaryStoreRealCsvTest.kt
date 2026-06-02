package com.pdcollect.app.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.pdcollect.app.util.Constants
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DashboardSummaryStoreRealCsvTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val userProfile = UserProfile(context).apply { userId = "real_csv_user" }
    private val dataManager = DataManager(context, userProfile)

    @After
    fun tearDown() {
        dataManager.closeAll()
        File(context.getExternalFilesDir(null), Constants.BASE_DIR).deleteRecursively()
        context.filesDir.listFiles()
            ?.filter { it.name.contains(Constants.GRAPH_CACHE_FILE) }
            ?.forEach { it.delete() }
    }

    @Test
    fun dashboard_streamingAnalyzerBuildsGraphsFromPhoneSensorCsv() {
        val csvPath = System.getProperty("pdcollect.sensorCsv").orEmpty()
            .ifBlank { System.getenv("PDCOLLECT_SENSOR_CSV").orEmpty() }
        assumeTrue("Set -Dpdcollect.sensorCsv or PDCOLLECT_SENSOR_CSV to run this diagnostic", csvPath.isNotBlank())
        val source = File(csvPath)
        assumeTrue("Diagnostic CSV does not exist: $csvPath", source.isFile)

        val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        val dateDir = File(dataManager.getStoragePath(), today).apply { mkdirs() }
        source.copyTo(File(dateDir, Constants.SENSORS_FILE), overwrite = true)

        dataManager.refreshDashboardGraphCache(trendDays = 0, maxSyncDates = 1)
        val metrics = dataManager.getCachedDashboardMetrics(trendDays = 0)
        val dailyPoints = metrics.dailyStrideLength.size +
            metrics.dailyStrideSpeed.size +
            metrics.dailyTremorPower.size
        println(
            "Dashboard real CSV: source=${metrics.dailySourceDate}, " +
                "stride=${metrics.dailyStrideLength.size}, speed=${metrics.dailyStrideSpeed.size}, " +
                "tremor=${metrics.dailyTremorPower.size}"
        )

        assertTrue("Expected graph points from current phone sensor CSV", dailyPoints > 0)
        assertTrue("Expected tremor graph points from current phone sensor CSV", metrics.dailyTremorPower.isNotEmpty())
    }
}
