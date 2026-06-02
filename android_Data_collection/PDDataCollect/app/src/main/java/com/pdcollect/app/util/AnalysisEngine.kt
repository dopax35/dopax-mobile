package com.pdcollect.app.util

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * AnalysisEngine: On-device clinical feature computation.
 *
 * Tremor Power Ratio is ported from PDAnalysis/FeatureExtractors/basic_functions.py
 * (compute_sensor_attributes, lines 203-220), using a stable cascaded IIR
 * bandpass instead of SciPy's zero-phase sosfiltfilt.
 *
 * HRV RMSSD uses the standard clinical definition:
 *   sqrt( mean( diff(RR_intervals)^2 ) )
 */
object AnalysisEngine {

    // -------------------------------------------------------------------------
    // Tremor Power Ratio  (ported from basic_functions.py lines 203-220)
    // -------------------------------------------------------------------------

    private const val TREMOR_LOW_HZ = 3.0
    private const val TREMOR_HIGH_HZ = 10.0

    /**
     * Compute the ratio of 3-10 Hz (tremor band) power to total gyro power.
     *
     * @param gyroX  Array of gyroscope X values (rad/s)
     * @param gyroY  Array of gyroscope Y values (rad/s)
     * @param gyroZ  Array of gyroscope Z values (rad/s)
     * @param sampleRateHz  Sampling rate of the sensor (typically 50-100 Hz)
     * @return  Ratio in range [0, 1]; 0 if insufficient data
     */
    fun computeTremorPowerRatio(
        gyroX: DoubleArray,
        gyroY: DoubleArray,
        gyroZ: DoubleArray,
        sampleRateHz: Double
    ): Double {
        if (gyroX.size < 10) return 0.0
        if (!sampleRateHz.isFinite() || sampleRateHz <= TREMOR_LOW_HZ * 2.0) return 0.0

        val n = gyroX.size
        val highHz = minOf(TREMOR_HIGH_HZ, sampleRateHz * 0.45)
        if (highHz <= TREMOR_LOW_HZ) return 0.0

        val centerHz = sqrt(TREMOR_LOW_HZ * highHz)
        val q = centerHz / (highHz - TREMOR_LOW_HZ)
        val filtX = applyBandpassTwice(gyroX, sampleRateHz, centerHz, q)
        val filtY = applyBandpassTwice(gyroY, sampleRateHz, centerHz, q)
        val filtZ = applyBandpassTwice(gyroZ, sampleRateHz, centerHz, q)

        var instPowerSum = 0.0
        var totalPowerSum = 0.0
        for (i in 0 until n) {
            instPowerSum += filtX[i] * filtX[i] + filtY[i] * filtY[i] + filtZ[i] * filtZ[i]
            totalPowerSum += gyroX[i] * gyroX[i] + gyroY[i] * gyroY[i] + gyroZ[i] * gyroZ[i]
        }

        // Return ratio. If total power is extremely low (sitting on desk), return 0.
        // Otherwise, return the ratio.
        if (totalPowerSum <= 1e-6) return 0.0
        val ratio = instPowerSum / totalPowerSum
        return if (ratio.isFinite()) ratio.coerceIn(0.0, 1.0) else 0.0
    }

    private fun applyBandpassTwice(
        values: DoubleArray,
        sampleRateHz: Double,
        centerHz: Double,
        q: Double
    ): DoubleArray {
        val first = applyBiquadBandpass(values, sampleRateHz, centerHz, q)
        return applyBiquadBandpass(first, sampleRateHz, centerHz, q)
    }

    private fun applyBiquadBandpass(
        values: DoubleArray,
        sampleRateHz: Double,
        centerHz: Double,
        q: Double
    ): DoubleArray {
        val omega = 2.0 * PI * centerHz / sampleRateHz
        val alpha = sin(omega) / (2.0 * q)
        val a0 = 1.0 + alpha
        val b0 = alpha / a0
        val b1 = 0.0
        val b2 = -alpha / a0
        val a1 = -2.0 * cos(omega) / a0
        val a2 = (1.0 - alpha) / a0

        val out = DoubleArray(values.size)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for (i in values.indices) {
            val x0 = values[i].takeIf { it.isFinite() } ?: 0.0
            val y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            out[i] = if (y0.isFinite()) y0 else 0.0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = out[i]
        }
        return out
    }

    /**
     * Compute 4th-order Butterworth bandpass IIR filter coefficients via
     * bilinear transform. Returns Pair(b, a) for a direct-form II transposed filter.
     *
     * Implemented as two cascaded 2nd-order sections (SOS), then combined.
     * For robustness, we use the pre-warped bilinear transform formula.
     */
    private fun butterworth4BandpassCoeffs(
        lowHz: Double, highHz: Double, fs: Double
    ): Pair<DoubleArray, DoubleArray> {
        val nyq = fs / 2.0
        val low = lowHz / nyq
        val high = highHz / nyq

        // Pre-warp
        val wl = Math.tan(Math.PI * low)
        val wh = Math.tan(Math.PI * high)
        val bw = wh - wl
        val w0 = sqrt(wl * wh)

        // 2nd-order bandpass prototype (Q = w0/bw for each stage)
        // We implement two identical 2nd-order BPF stages in series
        val q = w0 / bw

        // Single 2nd-order section: s^2 + (w0/Q)*s + w0^2
        // Bilinear substitution gives discrete-time coefficients
        val denom0 = 1.0 + (w0 / q) + w0 * w0
        val b0 = (w0 / q) / denom0
        val b1 = 0.0
        val b2 = -(w0 / q) / denom0
        val a1 = (2.0 * (w0 * w0 - 1.0)) / denom0
        val a2 = (1.0 - (w0 / q) + w0 * w0) / denom0

        // Cascade two identical sections → convolve coefficients
        val b = conv(doubleArrayOf(b0, b1, b2), doubleArrayOf(b0, b1, b2))
        val a = conv(doubleArrayOf(1.0, a1, a2), doubleArrayOf(1.0, a1, a2))

        return Pair(b, a)
    }

    /** 1D polynomial convolution */
    private fun conv(a: DoubleArray, b: DoubleArray): DoubleArray {
        val result = DoubleArray(a.size + b.size - 1)
        for (i in a.indices) for (j in b.indices) result[i + j] += a[i] * b[j]
        return result
    }

    /** Apply IIR filter (direct-form II transposed) */
    private fun applyIirFilter(b: DoubleArray, a: DoubleArray, x: DoubleArray): DoubleArray {
        val nb = b.size
        val na = a.size
        val n = x.size
        val y = DoubleArray(n)
        val z = DoubleArray(maxOf(nb, na))

        val a0 = if (a[0] != 0.0) a[0] else 1.0
        for (m in 0 until n) {
            y[m] = b[0] / a0 * x[m] + z[0]
            for (k in 1 until maxOf(nb, na) - 1) {
                val bk = if (k < nb) b[k] else 0.0
                val ak = if (k < na) a[k] else 0.0
                z[k - 1] = bk / a0 * x[m] - ak / a0 * y[m] + z[k]
            }
            val bLast = if (nb > 1) b[nb - 1] else 0.0
            val aLast = if (na > 1) a[na - 1] else 0.0
            z[maxOf(nb, na) - 2] = bLast / a0 * x[m] - aLast / a0 * y[m]
        }
        return y
    }

    // -------------------------------------------------------------------------
    // HRV RMSSD
    // -------------------------------------------------------------------------

    /**
     * Compute RMSSD (Root Mean Square of Successive Differences) of RR intervals.
     *
     * @param rrIntervalsMs  List of RR intervals in milliseconds (must be > 5 values)
     * @return  RMSSD in milliseconds, or 0f if insufficient data
     */
    fun computeRmssd(rrIntervalsMs: List<Float>): Float {
        if (rrIntervalsMs.size < 2) return 0f

        // Filter physiologically impossible values (< 300ms or > 2000ms)
        val valid = rrIntervalsMs.filter { it in 300f..2000f }
        if (valid.size < 2) return 0f

        var sumSqDiff = 0.0
        for (i in 1 until valid.size) {
            val diff = (valid[i] - valid[i - 1]).toDouble()
            sumSqDiff += diff * diff
        }

        return sqrt(sumSqDiff / (valid.size - 1)).toFloat()
    }

    /**
     * Normalize RMSSD to [0, 1] range for radar chart display.
     * Clinical reference: 20ms = low HRV (poor), 80ms = good HRV.
     */
    fun normalizeRmssd(rmssdMs: Float): Float {
        return ((rmssdMs - 10f) / 90f).coerceIn(0f, 1f)
    }
}
