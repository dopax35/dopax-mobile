package com.pdcollect.app.util

import java.time.Instant
import java.time.ZoneId
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

object PDAnalysisEngine {
    class SensorSeries private constructor(
        val timestampNs: LongArray,
        val accelX: DoubleArray,
        val accelY: DoubleArray,
        val accelZ: DoubleArray,
        val gyroX: DoubleArray,
        val gyroY: DoubleArray,
        val gyroZ: DoubleArray
    ) {
        val size: Int get() = timestampNs.size

        class Builder(initialCapacity: Int = 8192) {
            private var timestampNs = LongArray(initialCapacity)
            private var accelX = DoubleArray(initialCapacity)
            private var accelY = DoubleArray(initialCapacity)
            private var accelZ = DoubleArray(initialCapacity)
            private var gyroX = DoubleArray(initialCapacity)
            private var gyroY = DoubleArray(initialCapacity)
            private var gyroZ = DoubleArray(initialCapacity)
            private var count = 0

            fun add(tsNs: Long, ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double) {
                ensureCapacity(count + 1)
                timestampNs[count] = tsNs
                accelX[count] = ax
                accelY[count] = ay
                accelZ[count] = az
                gyroX[count] = gx
                gyroY[count] = gy
                gyroZ[count] = gz
                count++
            }

            fun build(): SensorSeries {
                return SensorSeries(
                    timestampNs.copyOf(count),
                    accelX.copyOf(count),
                    accelY.copyOf(count),
                    accelZ.copyOf(count),
                    gyroX.copyOf(count),
                    gyroY.copyOf(count),
                    gyroZ.copyOf(count)
                )
            }

            private fun ensureCapacity(target: Int) {
                if (target <= timestampNs.size) return
                val next = max(target, timestampNs.size * 2)
                timestampNs = timestampNs.copyOf(next)
                accelX = accelX.copyOf(next)
                accelY = accelY.copyOf(next)
                accelZ = accelZ.copyOf(next)
                gyroX = gyroX.copyOf(next)
                gyroY = gyroY.copyOf(next)
                gyroZ = gyroZ.copyOf(next)
            }
        }
    }

    data class BinnedPoint(val minuteOfDay: Int, val value: Float)

    data class Result(
        val stepLength: List<BinnedPoint>,
        val speed: List<BinnedPoint>,
        val tremorPower: List<BinnedPoint>,
        val maxStepLength: Float,
        val maxSpeed: Float,
        val maxTremorPower: Float
    )

    private data class Bucket(var sum: Double = 0.0, var count: Int = 0) {
        fun add(value: Double) {
            if (!value.isFinite()) return
            sum += value
            count++
        }

        fun mean(): Float? = if (count > 0) (sum / count).toFloat() else null
    }

    fun analyze(series: SensorSeries, binMinutes: Int, zoneId: ZoneId): Result {
        if (series.size < 3) return emptyResult()

        val fs = estimateSampleRateHz(series.timestampNs)
        if (!fs.isFinite() || fs <= 0.0) return emptyResult()

        val n = series.size
        val accelMag = DoubleArray(n)
        for (i in 0 until n) {
            accelMag[i] = sqrt(
                series.accelX[i] * series.accelX[i] +
                    series.accelY[i] * series.accelY[i] +
                    series.accelZ[i] * series.accelZ[i]
            )
        }
        val accelDetrended = detrendLinear(accelMag)

        val win = (2.0 * fs).roundToInt().coerceAtLeast(4)
        val step = (0.5 * fs).roundToInt().coerceAtLeast(1)
        if (n < win) {
            return Result(
                emptyList(),
                emptyList(),
                computeTremor(series, binMinutes, zoneId),
                0f,
                0f,
                computeTremor(series, binMinutes, zoneId).maxOfOrNull { it.value } ?: 0f
            )
        }

        val labelsWalking = BooleanArray(n)
        val speed = DoubleArray(n)
        val stepLength = DoubleArray(n)
        val nfft = nextPowerOfTwo(win)
        val bandBins = buildList {
            for (k in 1..nfft / 2) {
                val freq = k * fs / nfft
                if (freq in STEP_FREQ_MIN..STEP_FREQ_MAX) add(k)
            }
        }

        var start = 0
        while (start + win <= n) {
            val end = start + win
            val accelVar = variance(accelDetrended, start, end)
            val gyroVar = (
                variance(series.gyroX, start, end) +
                    variance(series.gyroY, start, end) +
                    variance(series.gyroZ, start, end)
                ) / 3.0

            var totalPower = 0.0
            for (i in start until end) {
                val v = accelDetrended[i]
                totalPower += v * v
            }

            var peakPower = 0.0
            var peakFreq = 0.0
            if (totalPower > 1e-12) {
                for (bin in bandBins) {
                    val p = goertzelPower(accelDetrended, start, win, bin, nfft)
                    if (p > peakPower) {
                        peakPower = p
                        peakFreq = bin * fs / nfft
                    }
                }
            }
            val peakRatio = peakPower / (totalPower + 1e-12)

            if (accelVar > ACCEL_VAR_THRESH && peakRatio > STEP_PEAK_THRESH && gyroVar > GYRO_VAR_THRESH) {
                var minAccel = Double.POSITIVE_INFINITY
                var maxAccel = Double.NEGATIVE_INFINITY
                for (i in start until end) {
                    minAccel = min(minAccel, accelMag[i])
                    maxAccel = max(maxAccel, accelMag[i])
                }
                val winStepLength = (WEINBERG_K * (maxAccel - minAccel).coerceAtLeast(0.0).pow(0.25))
                    .coerceIn(STEP_LEN_MIN, STEP_LEN_MAX)
                val winSpeed = (winStepLength * peakFreq).coerceIn(SPEED_MIN, SPEED_MAX)

                val center = (start + win / 2.0).roundToInt()
                val halfStep = (step / 2.0).roundToInt().coerceAtLeast(1)
                val labelStart = max(0, center - halfStep)
                val labelEnd = min(n, center + halfStep)
                for (i in labelStart until labelEnd) {
                    labelsWalking[i] = true
                    speed[i] = winSpeed
                    stepLength[i] = winStepLength
                }
            }
            start += step
        }

        smoothLabels(labelsWalking, (10.0 * fs).roundToInt().coerceAtLeast(1))
        for (i in 0 until n) {
            if (!labelsWalking[i]) {
                speed[i] = 0.0
                stepLength[i] = 0.0
            }
        }

        val smoothWindow = (2.0 * fs).roundToInt().coerceAtLeast(1)
        val smoothSpeed = smoothWalkingSignal(speed, labelsWalking, smoothWindow)
        val smoothStepLength = smoothWalkingSignal(stepLength, labelsWalking, smoothWindow)

        val binCount = 24 * 60 / binMinutes
        val speedBuckets = Array(binCount) { Bucket() }
        val stepBuckets = Array(binCount) { Bucket() }
        var maxSpeed = 0f
        var maxStepLength = 0f
        for (i in 0 until n) {
            if (!labelsWalking[i]) continue
            val minute = minuteOfDay(series.timestampNs[i] / 1_000_000L, zoneId)
            if (minute !in 0 until 24 * 60) continue
            val bin = minute / binMinutes
            val spd = smoothSpeed[i]
            val len = smoothStepLength[i]
            if (spd > 0.0) {
                speedBuckets[bin].add(spd)
                if (spd.toFloat() > maxSpeed) maxSpeed = spd.toFloat()
            }
            if (len > 0.0) {
                stepBuckets[bin].add(len)
                if (len.toFloat() > maxStepLength) maxStepLength = len.toFloat()
            }
        }

        val tremor = computeTremor(series, binMinutes, zoneId)
        return Result(
            stepLength = pointsFromBuckets(stepBuckets, binMinutes),
            speed = pointsFromBuckets(speedBuckets, binMinutes),
            tremorPower = tremor,
            maxStepLength = maxStepLength,
            maxSpeed = maxSpeed,
            maxTremorPower = tremor.maxOfOrNull { it.value } ?: 0f
        )
    }

    private fun computeTremor(series: SensorSeries, binMinutes: Int, zoneId: ZoneId): List<BinnedPoint> {
        val binCount = 24 * 60 / binMinutes
        val buckets = Array(binCount) { mutableListOf<Int>() }
        for (i in 0 until series.size) {
            val minute = minuteOfDay(series.timestampNs[i] / 1_000_000L, zoneId)
            if (minute in 0 until 24 * 60) buckets[minute / binMinutes].add(i)
        }

        return buildList {
            for (bin in buckets.indices) {
                val indexes = buckets[bin]
                if (indexes.size < 20) continue
                val ts = LongArray(indexes.size)
                val gx = DoubleArray(indexes.size)
                val gy = DoubleArray(indexes.size)
                val gz = DoubleArray(indexes.size)
                indexes.forEachIndexed { outIndex, sourceIndex ->
                    ts[outIndex] = series.timestampNs[sourceIndex]
                    gx[outIndex] = series.gyroX[sourceIndex]
                    gy[outIndex] = series.gyroY[sourceIndex]
                    gz[outIndex] = series.gyroZ[sourceIndex]
                }
                val fs = estimateSampleRateHz(ts)
                if (fs <= 0.0) continue
                val ratio = (AnalysisEngine.computeTremorPowerRatio(gx, gy, gz, fs) * 100.0)
                    .toFloat()
                    .coerceIn(0f, 100f)
                add(BinnedPoint(bin * binMinutes + binMinutes / 2, ratio))
            }
        }
    }

    private fun pointsFromBuckets(buckets: Array<Bucket>, binMinutes: Int): List<BinnedPoint> {
        return buckets.mapIndexedNotNull { index, bucket ->
            bucket.mean()?.let { BinnedPoint(index * binMinutes + binMinutes / 2, it) }
        }
    }

    private fun detrendLinear(values: DoubleArray): DoubleArray {
        val n = values.size
        if (n < 2) return values.copyOf()

        var sumX = 0.0
        var sumY = 0.0
        var sumXX = 0.0
        var sumXY = 0.0
        for (i in 0 until n) {
            val x = i.toDouble()
            val y = values[i]
            sumX += x
            sumY += y
            sumXX += x * x
            sumXY += x * y
        }
        val denom = n * sumXX - sumX * sumX
        val slope = if (denom != 0.0) (n * sumXY - sumX * sumY) / denom else 0.0
        val intercept = (sumY - slope * sumX) / n
        return DoubleArray(n) { i -> values[i] - (intercept + slope * i) }
    }

    private fun smoothLabels(labelsWalking: BooleanArray, minSamples: Int) {
        var i = 0
        while (i < labelsWalking.size) {
            var j = i + 1
            while (j < labelsWalking.size && labelsWalking[j] == labelsWalking[i]) j++
            if (j - i < minSamples && i > 0) {
                val replacement = labelsWalking[i - 1]
                for (k in i until j) labelsWalking[k] = replacement
            }
            i = j
        }
    }

    private fun smoothWalkingSignal(values: DoubleArray, walking: BooleanArray, window: Int): DoubleArray {
        val out = DoubleArray(values.size)
        val walkingIndexes = IntArray(walking.count { it })
        val walkingValues = DoubleArray(walkingIndexes.size)
        var count = 0
        for (i in values.indices) {
            if (walking[i]) {
                walkingIndexes[count] = i
                walkingValues[count] = values[i]
                count++
            }
        }
        if (count == 0) return out

        val prefix = DoubleArray(count + 1)
        for (i in 0 until count) prefix[i + 1] = prefix[i] + walkingValues[i]
        val half = window / 2
        for (i in 0 until count) {
            val from = max(0, i - half)
            val to = min(count, i + half + 1)
            out[walkingIndexes[i]] = (prefix[to] - prefix[from]) / (to - from)
        }
        return out
    }

    private fun variance(values: DoubleArray, start: Int, endExclusive: Int): Double {
        val n = endExclusive - start
        if (n < 2) return 0.0
        var sum = 0.0
        for (i in start until endExclusive) sum += values[i]
        val mean = sum / n
        var ss = 0.0
        for (i in start until endExclusive) {
            val d = values[i] - mean
            ss += d * d
        }
        return ss / (n - 1)
    }

    private fun goertzelPower(values: DoubleArray, start: Int, length: Int, bin: Int, nfft: Int): Double {
        val omega = 2.0 * PI * bin / nfft
        val coeff = 2.0 * cos(omega)
        var sPrev = 0.0
        var sPrev2 = 0.0
        for (i in 0 until length) {
            val s = values[start + i] + coeff * sPrev - sPrev2
            sPrev2 = sPrev
            sPrev = s
        }
        return sPrev2 * sPrev2 + sPrev * sPrev - coeff * sPrev * sPrev2
    }

    private fun nextPowerOfTwo(value: Int): Int {
        if (value <= 1) return 1
        return 1 shl ceil(ln(value.toDouble()) / ln(2.0)).toInt()
    }

    private fun estimateSampleRateHz(timestampsNs: LongArray): Double {
        if (timestampsNs.size < 3) return 0.0
        val intervals = LongArray(timestampsNs.size - 1)
        var count = 0
        for (i in 1 until timestampsNs.size) {
            val delta = timestampsNs[i] - timestampsNs[i - 1]
            if (delta > 0) intervals[count++] = delta
        }
        if (count == 0) return 0.0
        val copy = intervals.copyOf(count)
        copy.sort()
        val median = copy[count / 2].toDouble()
        return if (median > 0.0) 1e9 / median else 0.0
    }

    private fun minuteOfDay(epochMs: Long, zoneId: ZoneId): Int {
        val local = Instant.ofEpochMilli(epochMs).atZone(zoneId)
        return local.hour * 60 + local.minute
    }

    private fun emptyResult(): Result = Result(emptyList(), emptyList(), emptyList(), 0f, 0f, 0f)

    private const val ACCEL_VAR_THRESH = 0.02
    private const val STEP_FREQ_MIN = 0.7
    private const val STEP_FREQ_MAX = 3.5
    private const val STEP_PEAK_THRESH = 0.1
    private const val GYRO_VAR_THRESH = 0.02
    private const val WEINBERG_K = 0.45
    private const val STEP_LEN_MIN = 0.3
    private const val STEP_LEN_MAX = 1.2
    private const val SPEED_MIN = 0.3
    private const val SPEED_MAX = 3.0

    fun asymmetryIndex(left: Double, right: Double): Double {
        if (left <= 0.0 && right <= 0.0) return 0.0
        val avg = (left + right) / 2.0
        return if (avg > 0.0) {
            (kotlin.math.abs(left - right) / avg) * 100.0
        } else {
            0.0
        }
    }
}
