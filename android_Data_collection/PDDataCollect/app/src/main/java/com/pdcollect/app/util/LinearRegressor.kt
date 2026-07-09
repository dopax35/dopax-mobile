package com.pdcollect.app.util

import kotlin.math.abs

/**---------------------------------------------------------------------------------
 * Kotlin implementation of the Linear Regression logic for dT/dt calculations.
 ---------------------------------------------------------------------------------*/
object LinearRegressor
{
    /**
     * Calculates the slope (m) of the provided points over a specific window.
     * * @param points List of Pair<Double, Double> where first is Time (Seconds) and second is Value.
     * @param windowSeconds The duration of the window to analyze (e.g., 60.0).
     * @return The slope in Units/Second, or null if insufficient data.
     */
    fun calculateSlope(points: List<Pair<Double, Double>>, windowSeconds: Double): Double?
    {
        // v2.6: Sanity check
        if (points.isEmpty())
            return null

        // v2.6: Use the timestamp of the last point as the reference "now" instead of raw millis
        val lastT = points.last().first
        val window = points.filter { (lastT - it.first) <= windowSeconds }

        // val now = System.currentTimeMillis()
        // val window = points.filter { (now - it.first) <= (windowSeconds * 1000) }
        if (window.size < 3)
            return null

        val n = window.size.toDouble()
        // val t0 = window.last().first / 1000.0
        val t0 = lastT // v2.6: simpler that avoids overflow or precision errors

        var sumX  = 0.0
        var sumY  = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0

        for (p in window)
        {
            // val x = (p.first / 1000.0) - t0
            val x = p.first - t0 // Switching to Double seconds instead of Long ms
            val y = p.second
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        val denominator = (n * sumX2 - (sumX * sumX))
        if (abs(denominator) < 1e-9)
            return null

        // Result is in Units per Second (°C/s)
        return (n * sumXY - sumX * sumY) / denominator
    }
}
