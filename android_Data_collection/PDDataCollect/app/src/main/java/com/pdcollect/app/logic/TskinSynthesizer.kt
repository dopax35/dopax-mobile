package com.pdcollect.app.logic

import java.util.Date
import kotlin.math.*

/**
 * TskinSynthesizer - Warmup prediction with slope boost and handoff blending
 *
 * Ported from iOS EnvInference.swift TskinSynthesizer class
 *
 * This provides sophisticated temperature prediction during the warmup phase
 * after putting on the beanie, using:
 * - Classic lowpass filtering with rate limiting
 * - Warmup tracking with slope boost
 * - Robust clamping for outlier rejection
 * - Smooth handoff blending between prediction and classic smoothing
 */

private fun clamp(x: Double, lo: Double, hi: Double): Double = min(max(x, lo), hi)

// --- Helper Classes ---

internal class EMAFilter {
    private var y: Double? = null
    private var lastT: Date? = null

    fun reset() {
        y = null
        lastT = null
    }

    fun update(time: Date, x: Double, tau: Double): Double {
        if (y == null) {
            y = x
            lastT = time
            return x
        }
        val dt = max(0.001, (time.time - (lastT?.time ?: time.time)) / 1000.0)
        val alpha = dt / (tau + dt)
        y = (y ?: x) + alpha * (x - (y ?: x))
        lastT = time
        return y!!
    }
}

internal class AsymRateLimiter {
    var y: Double? = null
        private set

    fun reset() {
        y = null
    }

    fun update(x: Double, dt: Double, upCPerMin: Double, downCPerMin: Double): Double {
        if (y == null) {
            y = x
            return x
        }
        val dtClamped = max(0.001, dt)
        val upStep = (upCPerMin / 60.0) * dtClamped
        val dnStep = (downCPerMin / 60.0) * dtClamped
        val lo = (y ?: x) - dnStep
        val hi = (y ?: x) + upStep
        val out = clamp(x, lo, hi)
        y = out
        return out
    }
}

internal class RollingWindow(private val windowSec: Double, private val maxN: Int = 400)
{
    private var t = mutableListOf<Date>()
    private var x = mutableListOf<Double>()

    fun reset()
    {
        t.clear()
        x.clear()
    }

    fun push(time: Date, value: Double)
    {
        val cutoff = Date(time.time - (windowSec * 1000).toLong())
        while (t.firstOrNull()?.before(cutoff) == true) {
            t.removeAt(0)
            x.removeAt(0)
        }
        t.add(time)
        x.add(value)
        if (t.size > maxN) {
            val overflow = t.size - maxN
            repeat(overflow) {
                t.removeAt(0)
                x.removeAt(0)
            }
        }
    }

    fun std(): Double
    {
        if (x.size < 8) return 0.0
        val m = x.average()
        val v = x.sumOf { (it - m) * (it - m) } / (x.size - 1)
        return sqrt(v)
    }

    fun slopeOver(seconds: Double, now: Date): Double
    {
        if (x.size < 2) return 0.0
        val cutoff = Date(now.time - (seconds * 1000).toLong())
        var idx = 0
        while (idx < t.size && t[idx].before(cutoff)) {
            idx++
        }
        if (idx >= t.size) return 0.0
        val dt = max(0.001, (now.time - t[idx].time) / 1000.0)
        return (x.last() - x[idx]) / dt
    }
}

// --- Main Synthesizer ---

data class TskinOutput(
    val rawModel: Double,
    val safeLowpass: Double,
    val predictedStable: Double?,
    val confidence: Double,
    val synthC: Double,
    val displayValid: Boolean,
    val displayC: Double?,
    val isThermalizing: Boolean
)

/**
 * TskinSynthesizer provides temperature smoothing and warmup prediction
 * matching the iOS implementation exactly.
 */
class TskinSynthesizer {
    // Physiological bounds
    private val physLo = 30.0
    private val physHi = 39.5

    // Not-worn detection
    private val notWornBelowTemp = 30.0
    private val notWornDeltaMax = 0.2
    private val notWornMaxSlopeCPerMin = 0.5

    // Put-on detection
    private val plateauNeedSec = 45.0
    private val putOnFastRiseC = 2.5
    private val putOnConfirmRiseC = 4.0
    private val putOnMinSlopeCPerSec = 0.02
    private val putOnMinDeltaAfterOn = 0.35

    // Warmup timing
    private val hideFirstSec = 60.0
    private val predictorEndSec = 180.0
    private val handoffBlendSec = 25.0

    // Classic smoothing parameters
    private val classicTau = 15.0
    private val classicUpCPerMin = 8.0
    private val classicDownCPerMin = 5.0

    // Warm tracking parameters - UPDATED to match iOS exactly
    private val warmInputTau = 4.0           // iOS: 4 (was 6)
    private val warmTrackUpCPerMin = 28.0    // iOS: 28 (was 12)
    private val warmTrackDownCPerMin = 6.0   // iOS: 6 (was 4)
    private val warmTrackTau = 8.0

    // Slope boost parameters - UPDATED to match iOS exactly
    private val slopeWinSec = 25.0           // iOS: 25 (was 15)
    private val slopeClamp = 0.05            // iOS: 0.05 (was 0.025)
    private val boostTau = 95.0              // iOS: 95 (was 120)
    private val maxBoost = 2.2               // iOS: 2.2 (was 1.5)

    // Display rate limiting - UPDATED to match iOS exactly
    private val displayUpCPerMin = 12.0      // iOS: 12 (was 6)
    private val displayDownCPerMin = 10.0    // iOS: 10 (was 4)

    // Filters and state
    private val detInner = EMAFilter()
    private val detOuter = EMAFilter()
    private val detDelta = EMAFilter()
    private val classicLP = EMAFilter()
    private val classicLimiter = AsymRateLimiter()

    // Warmup tracking (iOS parity)
    private val warmInputLP = EMAFilter()
    private val warmTrackLimiter = AsymRateLimiter()
    private val warmTrackLP = EMAFilter()
    private val displayLimiter = AsymRateLimiter()

    // Robust clampers
    private val classicClamper: RobustClamper
    private val warmClamper: RobustClamper

    // Rolling windows
    private val classicWin = RollingWindow(30.0, 300)
    private val warmTrackWin = RollingWindow(40.0, 400)

    // State tracking
    private var plateauSec = 0.0
    private var plateauInnerBuf = mutableListOf<Double>()
    private val plateauBufMaxN = 180
    private var putOnOnset: Date? = null
    private var putOnConfirm: Date? = null
    private var isThermal = false
    private var lastDetTime: Date? = null
    private var lastDetInner: Double? = null
    private var lastDetOuter: Double? = null
    private var recent = mutableListOf<RecentSample>()
    private val recentWinSec = 25.0

    private data class RecentSample(val t: Date, val i: Double, val o: Double, val d: Double)

    init {
        // Classic clamper config
        val classicConfig = RobustClamperConfig(
            windowSeconds = 20.0,
            kMAD = 6.0,
            minJumpC = 0.9,
            persistSeconds = 12.0,
            maxWindowSamples = 250
        )
        classicClamper = RobustClamper(classicConfig)

        // Warm clamper config
        val warmConfig = RobustClamperConfig(
            windowSeconds = 15.0,
            kMAD = 6.0,
            minJumpC = 0.8,
            persistSeconds = 8.0,
            maxWindowSamples = 250
        )
        warmClamper = RobustClamper(warmConfig)
    }

    fun reset() {
        detInner.reset()
        detOuter.reset()
        detDelta.reset()
        classicLP.reset()
        classicLimiter.reset()
        classicClamper.reset()

        warmInputLP.reset()
        warmTrackLimiter.reset()
        warmTrackLP.reset()
        warmClamper.reset()
        warmTrackWin.reset()
        displayLimiter.reset()

        classicWin.reset()

        plateauSec = 0.0
        plateauInnerBuf.clear()
        putOnOnset = null
        putOnConfirm = null
        isThermal = false
        lastDetTime = null
        lastDetInner = null
        lastDetOuter = null
        recent.clear()
    }

    fun update(time: Date, innerC: Double, outerC: Double, dt: Double, c1: Double): TskinOutput
    {
        val rawModel = innerC + c1 * (innerC - outerC)
        val dtC = clamp(dt, 0.001, 30.0)

        // Detection filtering
        val iSm = detInner.update(time, innerC, 3.0)
        val oSm = detOuter.update(time, outerC, 3.0)
        val dSm = detDelta.update(time, innerC - outerC, 4.0)

        // Derivative calculation
        var dInner = 0.0
        var dOuter = 0.0
        if (lastDetTime != null && lastDetInner != null && lastDetOuter != null) {
            val dtDet = max(0.001, (time.time - lastDetTime!!.time) / 1000.0)
            dInner = (iSm - lastDetInner!!) / dtDet
            dOuter = (oSm - lastDetOuter!!) / dtDet
        }
        lastDetTime = time
        lastDetInner = iSm
        lastDetOuter = oSm

        // Recent sample tracking
        recent.add(RecentSample(time, iSm, oSm, dSm))
        val cutoff = Date(time.time - (recentWinSec * 1000).toLong())
        while (recent.firstOrNull()?.t?.before(cutoff) == true) {
            recent.removeAt(0)
        }
        if (recent.size > 200) {
            recent.removeAt(0)
        }

        // Not-worn detection
        val belowTemp = (iSm < notWornBelowTemp) && (oSm < notWornBelowTemp)
        val smallDelta = abs(dSm) < notWornDeltaMax
        val slowChange = (abs(dInner) < notWornMaxSlopeCPerMin / 60.0) &&
                (abs(dOuter) < notWornMaxSlopeCPerMin / 60.0)
        val notWornCandidate = belowTemp && smallDelta && slowChange

        // Plateau tracking for put-on detection
        if (notWornCandidate) {
            plateauSec += dtC
            plateauInnerBuf.add(iSm)
            if (plateauInnerBuf.size > plateauBufMaxN) {
                plateauInnerBuf.removeAt(0)
            }
        } else {
            plateauSec = 0.0
            plateauInnerBuf.clear()
        }

        // Exit thermal state if not worn
        if (isThermal && notWornCandidate) {
            isThermal = false
            putOnOnset = null
            putOnConfirm = null
            warmTrackWin.reset()
            displayLimiter.reset()
        }

        val isWorn = !notWornCandidate

        // Classic smoothing pipeline
        val classicInput = if (isWorn) clamp(rawModel, physLo, physHi) else rawModel
        val classicClampRes = classicClamper.update(time, classicInput)
        val classicLPv = classicLP.update(time, classicClampRes.clamped, classicTau)
        val classicSmoothed = classicLimiter.update(classicLPv, dtC, classicUpCPerMin, classicDownCPerMin)

        classicWin.push(time, classicSmoothed)
        val classicStd = classicWin.std()
        val classicSlope = classicWin.slopeOver(20.0, time)
        val isStableNow = classicStd.isFinite() && !classicStd.isNaN() &&
                classicStd < 0.12 && abs(classicSlope) < 0.005

        // Put-on detection
        if (!isThermal && plateauSec >= plateauNeedSec) {
            val baseline = if (plateauInnerBuf.isEmpty()) iSm
            else plateauInnerBuf.sum() / max(1, plateauInnerBuf.size)
            val rise = iSm - baseline
            val deltaOK = abs(dSm) >= putOnMinDeltaAfterOn

            if (rise >= putOnFastRiseC ||
                (rise >= putOnConfirmRiseC && deltaOK) ||
                (dInner >= putOnMinSlopeCPerSec && rise >= 1.5 && deltaOK)
            ) {
                putOnConfirm = time
                putOnOnset = backdateOnset(time)
                isThermal = true
                plateauSec = 0.0
                plateauInnerBuf.clear()

                // Reset warmup filters
                warmInputLP.reset()
                warmTrackLimiter.reset()
                warmTrackLP.reset()
                warmClamper.reset()
                warmTrackWin.reset()
                displayLimiter.reset()
            }
        }

        // Warm tracking with slope boost
        var predictedStable: Double? = null
        var conf = 0.0
        var warmTargetForDisplay: Double? = null

        if (isThermal && putOnConfirm != null) {
            val age = (time.time - putOnConfirm!!.time) / 1000.0

            // Warm input pipeline
            val warmInput = warmInputLP.update(time, clamp(rawModel, 20.0, physHi), warmInputTau)
            val warmClamp = warmClamper.update(time, warmInput).clamped
            val warmTrack = warmTrackLimiter.update(warmClamp, dtC, warmTrackUpCPerMin, warmTrackDownCPerMin)
            val warmTrackSm = warmTrackLP.update(time, warmTrack, warmTrackTau)

            warmTrackWin.push(time, warmTrackSm)

            // Slope boost calculation (iOS parity)
            val slope = max(0.0, min(slopeClamp, warmTrackWin.slopeOver(slopeWinSec, time)))
            val boost = min(maxBoost, boostTau * slope)
            val pred = clamp(warmTrackSm + boost, 20.0, physHi)
            predictedStable = pred
            conf = if (isStableNow) 0.85 else 0.45

            // Overshoot adjustment based on age
            val overshootMax = when {
                age < 120 -> 1.0
                age < 180 -> 0.6
                else -> 0.35
            }
            val overshootAdj = if (isStableNow) min(overshootMax, 0.25) else overshootMax
            val predCapped = min(pred, classicSmoothed + overshootAdj)
            val predFloored = max(predCapped, classicSmoothed - 0.10)
            val warmTarget = if (isStableNow) {
                0.88 * classicSmoothed + 0.12 * predFloored
            } else {
                predFloored
            }
            warmTargetForDisplay = warmTarget
        }

        val synthC = if (isWorn) classicSmoothed else rawModel

        if (!isWorn) {
            return TskinOutput(
                rawModel = rawModel,
                safeLowpass = classicSmoothed,
                predictedStable = null,
                confidence = 0.0,
                synthC = synthC,
                displayValid = false,
                displayC = null,
                isThermalizing = false
            )
        }

        // Display output calculation
        var displayValid = true
        var displayC: Double?
        var isThermalizing: Boolean

        if (isThermal && putOnConfirm != null) {
            isThermalizing = true
            val age = (time.time - putOnConfirm!!.time) / 1000.0

            if (age < hideFirstSec) {
                displayValid = false
                displayC = null
            } else {
                val warmTarget = warmTargetForDisplay ?: classicSmoothed
                val target: Double
                if (age < predictorEndSec) {
                    target = warmTarget
                } else {
                    val w = clamp((age - predictorEndSec) / handoffBlendSec, 0.0, 1.0)
                    target = (1.0 - w) * warmTarget + w * classicSmoothed
                    if (w >= 1.0) {
                        isThermalizing = false
                    }
                }

                // Apply display rate limiting
                displayC = if (displayLimiter.y == null) {
                    displayLimiter.update(target, dtC, 999.0, 999.0)
                    target
                } else {
                    displayLimiter.update(target, dtC, displayUpCPerMin, displayDownCPerMin)
                }
            }
        } else {
            displayLimiter.reset()
            isThermalizing = false
            displayC = classicSmoothed
        }

        return TskinOutput(
            rawModel = rawModel,
            safeLowpass = classicSmoothed,
            predictedStable = predictedStable,
            confidence = conf,
            synthC = synthC,
            displayValid = displayValid,
            displayC = displayC,
            isThermalizing = isThermalizing
        )
    }

    private fun backdateOnset(confirmTime: Date): Date {
        if (recent.size < 2) return confirmTime
        val baseInner = recent.first().i
        for (sample in recent.reversed()) {
            if (sample.i - baseInner < 0.3) {
                return sample.t
            }
        }
        return recent.last().t
    }
}