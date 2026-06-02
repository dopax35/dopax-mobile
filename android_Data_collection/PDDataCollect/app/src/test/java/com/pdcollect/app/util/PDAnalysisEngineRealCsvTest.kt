package com.pdcollect.app.util

import org.junit.Assume.assumeTrue
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.ZoneId

class PDAnalysisEngineRealCsvTest {
    @Test
    fun analyze_phoneSensorCsv_smoke() {
        val csvPath = System.getProperty("pdcollect.sensorCsv").orEmpty()
            .ifBlank { System.getenv("PDCOLLECT_SENSOR_CSV").orEmpty() }
        assumeTrue("Set -Dpdcollect.sensorCsv or PDCOLLECT_SENSOR_CSV to run this diagnostic", csvPath.isNotBlank())
        val file = File(csvPath)
        assumeTrue("Diagnostic CSV does not exist: $csvPath", file.isFile)

        val builder = PDAnalysisEngine.SensorSeries.Builder()
        file.bufferedReader().useLines { lines ->
            lines.drop(1).forEach { line ->
                val cols = line.split(',')
                if (cols.size < 7) return@forEach
                builder.add(
                    cols[0].trim().toLongOrNull() ?: return@forEach,
                    cols[1].trim().toDoubleOrNull() ?: return@forEach,
                    cols[2].trim().toDoubleOrNull() ?: return@forEach,
                    cols[3].trim().toDoubleOrNull() ?: return@forEach,
                    cols[4].trim().toDoubleOrNull() ?: return@forEach,
                    cols[5].trim().toDoubleOrNull() ?: return@forEach,
                    cols[6].trim().toDoubleOrNull() ?: return@forEach
                )
            }
        }

        val series = builder.build()
        val startedAt = System.currentTimeMillis()
        val result = PDAnalysisEngine.analyze(series, binMinutes = 15, zoneId = ZoneId.systemDefault())
        val elapsedMs = System.currentTimeMillis() - startedAt
        println(
            "PDAnalysis real CSV: rows=${series.size}, " +
                "stride=${result.stepLength.size}, speed=${result.speed.size}, " +
                "tremor=${result.tremorPower.size}, elapsedMs=$elapsedMs"
        )

        assertTrue("Expected tremor buckets from phone sensor CSV", result.tremorPower.isNotEmpty())
        assertTrue("Expected finite tremor values", result.tremorPower.all { it.value.isFinite() })
    }
}
