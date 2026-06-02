package com.pdcollect.app.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BlinkDetectorTest {

    @Test
    fun emitsBlinkForValidClosedThenOpenSequence() {
        val detector = BlinkDetector()

        assertNull(detector.onProbabilities(0L, 0.92f, 0.91f))
        assertNull(detector.onProbabilities(50L, 0.10f, 0.12f))
        val event = detector.onProbabilities(120L, 0.84f, 0.87f)

        assertNotNull(event)
        assertEquals(120L, event!!.timestampMs)
        assertEquals(0.10f, event.leftTroughProb, 0.0001f)
        assertEquals(0.12f, event.rightTroughProb, 0.0001f)
        assertEquals(1.0f, event.blinkRatePerMin, 0.0001f)
    }

    @Test
    fun ignoresSingleFrameGlitch() {
        val detector = BlinkDetector()

        assertNull(detector.onProbabilities(0L, 0.92f, 0.91f))
        assertNull(detector.onProbabilities(10L, 0.11f, 0.10f))
        assertNull(detector.onProbabilities(20L, 0.90f, 0.92f))
    }

    @Test
    fun computesRollingRateAcrossWindow() {
        val detector = BlinkDetector()

        fun blink(startMs: Long, reopenMs: Long) {
            detector.onProbabilities(startMs - 40L, 0.9f, 0.9f)
            detector.onProbabilities(startMs, 0.1f, 0.12f)
            detector.onProbabilities(reopenMs, 0.9f, 0.9f)
        }

        blink(0L, 80L)
        blink(20_000L, 20_090L)
        val third = run {
            detector.onProbabilities(39_960L, 0.9f, 0.9f)
            detector.onProbabilities(40_000L, 0.1f, 0.1f)
            detector.onProbabilities(40_100L, 0.9f, 0.9f)
        }

        assertNotNull(third)
        assertEquals(4.5f, third!!.blinkRatePerMin, 0.05f)
    }
}
