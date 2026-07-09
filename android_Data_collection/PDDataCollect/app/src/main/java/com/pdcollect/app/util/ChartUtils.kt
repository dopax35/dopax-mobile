package com.pdcollect.app.util

import java.util.Date
import kotlin.math.floor

/**
 * Time series utilities matching iOS TimeSeriesUtils.swift exactly
 *
 * Provides helpers for preparing and binning time-series points.
 */

/**
 * Compute the median of a list of doubles
 */
fun median(xs: List<Double>): Double {
    if (xs.isEmpty()) return Double.NaN
    val sorted = xs.sorted()
    val n = sorted.size
    return if (n % 2 == 1) {
        sorted[n / 2]
    } else {
        0.5 * (sorted[n / 2 - 1] + sorted[n / 2])
    }
}

/**
 * Filter points to finite values and sort by time.
 * Generic version using selector functions.
 */
fun <T> List<T>.finiteSortedBy(
    timeValueSelector: (T) -> Date,
    valueSelector: (T) -> Double
): List<T> {
    val finite = this.filter { valueSelector(it).isFinite() && !valueSelector(it).isNaN() }
    if (finite.size <= 1) return finite
    return finite.sortedBy { timeValueSelector(it) }
}

/**
 * Bin points by a fixed bin size (seconds) by averaging values that fall in the same bin.
 * Generic version using selector functions.
 *
 * @param timeValueSelector Function to get the time from a point
 * @param valueSelector Function to get the value from a point
 * @param factory Function to create a new point from time and value
 * @param binSeconds Size of each bin in seconds
 */
fun <T> List<T>.binned(
    timeValueSelector: (T) -> Date,
    valueSelector: (T) -> Double,
    factory: (Date, Double) -> T,
    binSeconds: Double
): List<T> {
    if (this.size <= 2 || binSeconds <= 0) return this

    // Use a map to accumulate bucket data
    data class Bucket(var sum: Double = 0.0, var count: Int = 0)

    val buckets = mutableMapOf<Long, Bucket>()

    for (p in this) {
        val time = timeValueSelector(p)
        val value = valueSelector(p)

        // Calculate bucket key from time
        val timeMs = time.time
        val binMs = (binSeconds * 1000).toLong()
        val key = (timeMs / binMs) * binMs

        val bucket = buckets.getOrPut(key) { Bucket() }
        bucket.sum += value
        bucket.count++
    }

    // Sort keys and build output
    val sortedKeys = buckets.keys.sorted()
    val out = mutableListOf<T>()

    for (key in sortedKeys) {
        val bucket = buckets[key] ?: continue
        if (bucket.count > 0) {
            val avgValue = bucket.sum / bucket.count
            val time = Date(key)
            out.add(factory(time, avgValue))
        }
    }

    return out
}

/**
 * Choose a bin size based on total span to avoid rendering thousands of points.
 * Matches iOS TimeSeriesUtils.recommendedBinSeconds exactly.
 *
 * @param forSpan Total time span in seconds
 * @return Recommended bin size in seconds
 */
fun recommendedBinSeconds(forSpan: Double): Double
{
    val minute = 60.0
    val fiveMin = 5.0 * 60.0
    val fifteenMin = 15.0 * 60.0
    val hour = 60.0 * 60.0
    val day = 24.0 * 60.0 * 60.0

    return when {
        forSpan <= 2 * hour -> minute
        forSpan <= 12 * hour -> fiveMin
        forSpan <= 48 * hour -> fifteenMin
        forSpan <= 7 * day -> hour
        else -> day
    }
}

/**
 * Calculate the standard deviation of a list of doubles
 */
fun standardDeviation(values: List<Double>): Double {
    if (values.size < 2) return Double.NaN
    val mean = values.average()
    val variance = values.sumOf { (it - mean) * (it - mean) } / (values.size - 1)
    return kotlin.math.sqrt(variance)
}

/**
 * Calculate the slope (linear regression) of time-series data
 *
 * @param times List of times
 * @param values List of values
 * @param startTime Reference time for calculating x values
 * @return Slope in units per second
 */
fun calculateSlope(times: List<Date>, values: List<Double>, startTime: Date): Double {
    if (times.size < 2 || times.size != values.size) return 0.0

    val n = times.size.toDouble()
    val xs = times.map { (it.time - startTime.time) / 1000.0 }
    val ys = values

    val sumX = xs.sum()
    val sumY = ys.sum()
    val sumXY = xs.zip(ys).sumOf { it.first * it.second }
    val sumX2 = xs.sumOf { it * it }

    val denominator = n * sumX2 - sumX * sumX
    if (denominator == 0.0) return 0.0

    return (n * sumXY - sumX * sumY) / denominator
}
