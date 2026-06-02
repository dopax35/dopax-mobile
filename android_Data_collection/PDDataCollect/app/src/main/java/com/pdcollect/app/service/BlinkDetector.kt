package com.pdcollect.app.service

class BlinkDetector(
    private val closeThreshold: Float = 0.25f,
    private val openThreshold: Float = 0.50f,
    private val rollingWindowMs: Long = 60_000L,
    private val minClosedDurationMs: Long = 50L,
    private val maxClosedDurationMs: Long = 1_500L,
    private val minInterBlinkMs: Long = 120L
) {

    data class BlinkEvent(
        val timestampMs: Long,
        val leftTroughProb: Float,
        val rightTroughProb: Float,
        val blinkRatePerMin: Float
    )

    private var eyesOpen = true
    private var closedStartMs = 0L
    private var leftEyeTrough = 1f
    private var rightEyeTrough = 1f
    private var lastBlinkTimestampMs = Long.MIN_VALUE
    private val blinkTimestampsMs = ArrayDeque<Long>()

    fun onProbabilities(
        timestampMs: Long,
        leftProb: Float,
        rightProb: Float
    ): BlinkEvent? {
        val avgProb = (leftProb + rightProb) / 2f

        if (eyesOpen) {
            if (avgProb < closeThreshold) {
                eyesOpen = false
                closedStartMs = timestampMs
                leftEyeTrough = leftProb
                rightEyeTrough = rightProb
            }
            return null
        }

        if (leftProb < leftEyeTrough) leftEyeTrough = leftProb
        if (rightProb < rightEyeTrough) rightEyeTrough = rightProb

        if (avgProb < openThreshold) {
            return null
        }

        eyesOpen = true
        val closedDurationMs = timestampMs - closedStartMs
        if (closedDurationMs !in minClosedDurationMs..maxClosedDurationMs) {
            resetTroughs()
            return null
        }
        if (lastBlinkTimestampMs != Long.MIN_VALUE &&
            timestampMs - lastBlinkTimestampMs < minInterBlinkMs
        ) {
            resetTroughs()
            return null
        }

        lastBlinkTimestampMs = timestampMs
        blinkTimestampsMs.addLast(timestampMs)

        val cutoff = timestampMs - rollingWindowMs
        while (blinkTimestampsMs.isNotEmpty() && blinkTimestampsMs.first() < cutoff) {
            blinkTimestampsMs.removeFirst()
        }

        val windowMs = if (blinkTimestampsMs.size >= 2) {
            (timestampMs - blinkTimestampsMs.first()).coerceAtLeast(1_000L)
        } else {
            rollingWindowMs
        }
        val rate = blinkTimestampsMs.size.toFloat() * 60_000f / windowMs
        val event = BlinkEvent(timestampMs, leftEyeTrough, rightEyeTrough, rate)
        resetTroughs()
        return event
    }

    private fun resetTroughs() {
        leftEyeTrough = 1f
        rightEyeTrough = 1f
    }
}
