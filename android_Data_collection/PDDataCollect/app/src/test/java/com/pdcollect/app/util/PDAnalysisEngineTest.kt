package com.pdcollect.app.util

import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import kotlin.math.PI
import kotlin.math.sin

class PDAnalysisEngineTest {
    @Test
    fun analyze_detectsWalkingWithPdAnalysisMotionClassifier() {
        val builder = PDAnalysisEngine.SensorSeries.Builder()
        val baseNs = 1_700_000_000_000_000_000L
        val sampleRateHz = 50.0
        val samplePeriodNs = (1_000_000_000L / sampleRateHz).toLong()

        repeat((20 * sampleRateHz).toInt()) { index ->
            val t = index / sampleRateHz
            val stepWave = sin(2.0 * PI * 2.0 * t)
            val accel = 9.8 + 1.2 * stepWave
            val gyro = 1.0 * sin(2.0 * PI * 2.0 * t + PI / 4.0)
            builder.add(
                baseNs + index * samplePeriodNs,
                accel,
                0.0,
                0.0,
                gyro,
                gyro * 0.5,
                -gyro * 0.25
            )
        }

        val result = PDAnalysisEngine.analyze(builder.build(), binMinutes = 15, zoneId = ZoneId.of("UTC"))

        assertTrue(result.stepLength.isNotEmpty())
        assertTrue(result.speed.isNotEmpty())
        assertTrue(result.maxStepLength in 0.3f..1.2f)
        assertTrue(result.maxSpeed in 0.3f..3.0f)
    }

    @Test
    fun analyze_keepsStationaryDataOutOfWalkingGraphs() {
        val builder = PDAnalysisEngine.SensorSeries.Builder()
        val baseNs = 1_700_000_000_000_000_000L
        val samplePeriodNs = 20_000_000L

        repeat(500) { index ->
            builder.add(
                baseNs + index * samplePeriodNs,
                0.0,
                0.0,
                9.8,
                0.0,
                0.0,
                0.0
            )
        }

        val result = PDAnalysisEngine.analyze(builder.build(), binMinutes = 15, zoneId = ZoneId.of("UTC"))

        assertTrue(result.stepLength.isEmpty())
        assertTrue(result.speed.isEmpty())
    }
}
