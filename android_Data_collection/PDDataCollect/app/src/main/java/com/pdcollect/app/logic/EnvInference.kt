package com.pdcollect.app.logic

import com.pdcollect.app.util.BeanieConstants
import com.pdcollect.app.util.median
import java.util.Date
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// --- Helper Functions ---

fun mad(xs: List<Double>, about: Double): Double {
    if (xs.isEmpty()) return 0.0
    val dev = xs.map { abs(it - about) }
    return median(dev)
}

// --- Robust Clamper (ported from iOS) ---

data class RobustClamperConfig(
    var windowSeconds: Double = 25.0,
    var kMAD: Double = 8.0,
    var minJumpC: Double = 1.0,
    var persistSeconds: Double = 12.0,
    var maxWindowSamples: Int = 200
)

data class RobustClamperResult(
    val raw: Double,
    val clamped: Double,
    val wasClamped: Boolean,
    val isOutlier: Boolean,
    val outlierRunSeconds: Double
)

class RobustClamper(private val cfg: RobustClamperConfig = RobustClamperConfig())
{
    private var bufT = mutableListOf<Date>()
    private var bufX = mutableListOf<Double>()
    private var outlierRunStart: Date? = null

    fun reset()
    {
        bufT.clear()
        bufX.clear()
        outlierRunStart = null
    }

    fun update(time: Date, xRaw: Double): RobustClamperResult
    {
        prune(Date(time.time - (cfg.windowSeconds * 1000).toLong()))

        val windowVals = bufX.filter { it.isFinite() && !it.isNaN() }
        val med = median(windowVals)
        val madVal = mad(windowVals, med)
        val robustScale = if (madVal.isFinite() && !madVal.isNaN()) (1.4826 * madVal) else 0.0
        val thr = max(cfg.minJumpC, cfg.kMAD * robustScale)

        val isOutlier = med.isFinite() && !med.isNaN() && windowVals.size >= 7 && abs(xRaw - med) > thr

        if (isOutlier) {
            if (outlierRunStart == null) outlierRunStart = time
        } else {
            outlierRunStart = null
        }

        val runSeconds = outlierRunStart?.let { (time.time - it.time) / 1000.0 } ?: 0.0
        val shouldEscape = runSeconds >= cfg.persistSeconds

        val clamped: Double
        val wasClamped: Boolean

        if (isOutlier && !shouldEscape) {
            clamped = med
            wasClamped = true
        } else {
            clamped = xRaw
            wasClamped = false
        }

        bufT.add(time)
        bufX.add(clamped)

        if (bufT.size > cfg.maxWindowSamples) {
            val overflow = bufT.size - cfg.maxWindowSamples
            repeat(overflow) { bufT.removeAt(0); bufX.removeAt(0) }
        }

        return RobustClamperResult(xRaw, clamped, wasClamped, isOutlier, runSeconds)
    }

    private fun prune(cutoff: Date) {
        while (bufT.firstOrNull()?.before(cutoff) == true) {
            bufT.removeAt(0)
            bufX.removeAt(0)
        }
    }
}

// --- Main Logic Classes ---

enum class EnvState {
    NOT_WORN,
    PUTTING_ON,
    GOING_INSIDE,
    INSIDE_THERMALIZING,
    INSIDE,
    GOING_OUTSIDE,
    OUTSIDE_THERMALIZING,
    OUTSIDE
}


typealias EnvOverlays = Int
object EnvOverlaysFactory {
    const val NONE = 0
    const val RAPID_T_CHANGE = 1 shl 0
    const val SPIKE_MOVEMENT = 1 shl 1
}

data class EnvThresholds(
    var notWornAbsDeltaMax: Double = 0.3,
    var wornAbsDeltaMin: Double = 0.6,
    var transInnerRateMax: Double = 0.010,
    var transDeltaRateMin: Double = 0.0015,
    var transDeltaSlack: Double = 0.0010,

    // UPDATED: Use constants from BeanieConstants (now more conservative)
    var outRateTrigger: Double = BeanieConstants.ENV_TRANSITION_OUTER_SLOPE_MIN_C_PER_SEC,

    // UPDATED: Require larger 30s delta (was 0.42)
    var outDelta30Trigger: Double = 0.6,

    var outDelta60Trigger: Double = BeanieConstants.ENV_TRANSITION_NET_OUTER_CHANGE_60S_MIN_C,

    // UPDATED: Use longer confirmation time from constants (was 15s, now 30s)
    var transMinHoldSeconds: Double = BeanieConstants.ENV_TRANSITION_CONFIRM_SECONDS,

    var outRateStable: Double = 0.0040,
    var outDelta30Stable: Double = 0.12,

    // UPDATED: Require more time at stable before leaving transition (was 45)
    var gateASeconds: Double = 90.0,

    var inRateStable: Double = 0.008,
    var deltaStdStable: Double = 0.30,

    // UPDATED: Require more time for full stabilization (was 75)
    var gateBSeconds: Double = 120.0,

    // UPDATED: Reduce max putting on time (was 15 min)
    var puttingOnMaxSeconds: Double = 10.0 * 60.0,

    var rapidInRate: Double = 0.05,
    var rapidMinHoldSeconds: Double = 15.0,

    // UPDATED: Longer spike cooldown (was 25)
    var spikeCooldownSeconds: Double = 45.0,

    // NEW: Minimum dwell time in a stable state before allowing transitions
    var minimumDwellSeconds: Double = 180.0
)

class EnvInferencer(private val thr: EnvThresholds = EnvThresholds())
{
    var state: EnvState = EnvState.NOT_WORN
        private set
    var overlays: EnvOverlays = EnvOverlaysFactory.NONE
        private set

    private var gateAScore: Double = 0.0
    private var gateBScore: Double = 0.0
    private var rapidScore: Double = 0.0
    private var goingOutsideScore: Double = 0.0
    private var goingInsideScore: Double = 0.0
    private var stateStart: Date? = null
    private var lastSampleTime: Date? = null
    private var spikeCooldownUntil: Date? = null
    private var outerBufT = mutableListOf<Date>()
    private var outerBufX = mutableListOf<Double>()
    private val outerWindowSeconds: Double = 60.0
    private val outerMaxSamples: Int = 300

    // iOS parity: Track inner sensor for motion artifact detection
    private var innerBufT = mutableListOf<Date>()
    private var innerBufX = mutableListOf<Double>()

    private var deltaBufT = mutableListOf<Date>()
    private var deltaBufX = mutableListOf<Double>()
    private val deltaWindowSeconds: Double = 60.0
    private val deltaMaxSamples: Int = 300

    fun reset() {
        state = EnvState.NOT_WORN
        overlays = EnvOverlaysFactory.NONE
        rapidScore = 0.0; gateAScore = 0.0; gateBScore = 0.0
        goingOutsideScore = 0.0; goingInsideScore = 0.0
        stateStart = null; lastSampleTime = null
        spikeCooldownUntil = null
        deltaBufT.clear(); deltaBufX.clear()
        outerBufT.clear(); outerBufX.clear()
        innerBufT.clear(); innerBufX.clear()
    }

    fun update(
        time: Date, innerC: Double, outerC: Double, dTin: Double, dTout: Double,
        dDelta: Double, absDelta: Double, spikeWasClamped: Boolean
    ): Pair<EnvState, EnvOverlays> {
        val dt = lastSampleTime?.let { max(0.001, (time.time - it.time) / 1000.0) } ?: 1.0
        lastSampleTime = time

        appendOuter(time, outerC)
        appendInner(time, innerC)  // iOS parity: Track inner sensor
        val dOuter30 = outerDelta(30.0, time, outerC) ?: 0.0
        val dOuter60 = outerDelta(60.0, time, outerC) ?: 0.0

        overlays = EnvOverlaysFactory.NONE

        // iOS parity: Better motion artifact detection
        // Motion artifact: BOTH sensors move together rapidly, similar rates
        val dTinCPerMin = dTin * 60.0
        val dToutCPerMin = dTout * 60.0
        val bothMovingFast = abs(dTinCPerMin) > BeanieConstants.MOTION_ARTIFACT_BOTH_SENSORS_SLOPE_C_PER_MIN &&
                abs(dToutCPerMin) > BeanieConstants.MOTION_ARTIFACT_BOTH_SENSORS_SLOPE_C_PER_MIN
        val sameDirection = (dTinCPerMin >= 0 && dToutCPerMin >= 0) || (dTinCPerMin <= 0 && dToutCPerMin <= 0)
        val similarRates = abs(dTinCPerMin - dToutCPerMin) < 3.0  // Within 3°C/min of each other
        val motionArtifactDetected = bothMovingFast && sameDirection && similarRates

        // Real transition: outer changes MORE than inner, and they may go different directions
        val outerDominantForSpike = abs(dTout) > abs(dTin) * BeanieConstants.ENV_TRANSITION_OUTER_DOMINANCE_RATIO_MIN
        val likelyRealOuterTransition = outerDominantForSpike &&
                ((abs(dOuter60) >= thr.outDelta60Trigger * 0.60) ||
                        (abs(dOuter30) >= thr.outDelta30Trigger * 0.60) ||
                        (abs(dTout) >= thr.outRateTrigger * 0.80))

        // iOS parity: Mark as spike if motion artifact and NOT a real transition
        val treatClampAsMotionSpike = (spikeWasClamped || motionArtifactDetected) && !likelyRealOuterTransition
        if (treatClampAsMotionSpike) {
            overlays = overlays or EnvOverlaysFactory.SPIKE_MOVEMENT
            spikeCooldownUntil = Date(time.time + (thr.spikeCooldownSeconds * 1000).toLong())
        }

        if (abs(dTin) > thr.rapidInRate) {
            rapidScore = min(1000.0, rapidScore + dt)
        } else {
            rapidScore = max(0.0, rapidScore - 2.0 * dt)
        }
        if (rapidScore >= thr.rapidMinHoldSeconds) {
            overlays = overlays or EnvOverlaysFactory.RAPID_T_CHANGE
        }

        val deltaT = innerC - outerC
        pushDelta(time, deltaT)
        val deltaStd60 = stdDeltaWindow()

        val notWornGate = (deltaT < 0.1) || (absDelta < thr.notWornAbsDeltaMax)
        val wornGate = (deltaT >= 0.30) && (absDelta > thr.wornAbsDeltaMin)

        if (notWornGate && !wornGate) {
            transition(EnvState.NOT_WORN, time)
            resetScores()
            outerBufT.clear(); outerBufX.clear()
            innerBufT.clear(); innerBufX.clear()
            deltaBufT.clear(); deltaBufX.clear()
            lastSampleTime = null
            return Pair(state, overlays)
        }

        if (state == EnvState.NOT_WORN && wornGate) {
            transition(EnvState.PUTTING_ON, time)
            resetScores()
        }

        val inSpikeCooldown = spikeCooldownUntil?.let { time.before(it) } ?: false
        if (inSpikeCooldown) {
            overlays = overlays or EnvOverlaysFactory.SPIKE_MOVEMENT
        }

        // NEW: Check minimum dwell time in stable states
        val inMinimumDwell = stateStart?.let {
            val elapsed = (time.time - it.time) / 1000.0
            (state == EnvState.INSIDE || state == EnvState.OUTSIDE) && elapsed < thr.minimumDwellSeconds
        } ?: false

        // iOS parity: Transition evidence suppression with motion artifact detection
        val transSuppressed = inSpikeCooldown ||
                (motionArtifactDetected && !likelyRealOuterTransition) ||
                (spikeWasClamped && !likelyRealOuterTransition) ||
                (overlays and EnvOverlaysFactory.RAPID_T_CHANGE != 0 && !likelyRealOuterTransition)

        val innerStableForTransition = (abs(dTin) <= thr.transInnerRateMax) ||
                (abs(dTin) <= abs(dTout) * (1.0 / BeanieConstants.ENV_TRANSITION_OUTER_DOMINANCE_RATIO_MIN))

        // iOS parity: Require outer to dominate inner for transition evidence
        val outerDominant = abs(dTout) > abs(dTin) * BeanieConstants.ENV_TRANSITION_OUTER_DOMINANCE_RATIO_MIN

        val outerDownCoherent = (dOuter60 <= -thr.outDelta60Trigger * 0.85) && (dOuter30 <= -thr.outDelta30Trigger * 0.60)
        val outerUpCoherent = (dOuter60 >= thr.outDelta60Trigger * 0.85) && (dOuter30 >= thr.outDelta30Trigger * 0.60)
        val deltaSupportsOutside = (dDelta >= (thr.transDeltaRateMin - thr.transDeltaSlack))
        val deltaSupportsInside = (dDelta <= -(thr.transDeltaRateMin - thr.transDeltaSlack))
        val rateOutside = (dTout < -thr.outRateTrigger) && (dOuter60 <= -thr.outDelta60Trigger * 0.60)
        val rateInside = (dTout > thr.outRateTrigger) && (dOuter60 >= thr.outDelta60Trigger * 0.60)

        // iOS parity: Include outerDominant in transition evidence
        val goingOutsideEvidence = !transSuppressed && innerStableForTransition && outerDominant && deltaSupportsOutside && (outerDownCoherent || rateOutside)
        val goingInsideEvidence = !transSuppressed && innerStableForTransition && outerDominant && deltaSupportsInside && (outerUpCoherent || rateInside)

        // ========== iOS parity: MULTI-CONDITION ABSOLUTE ENVIRONMENT DETECTION ==========
        // Require MULTIPLE conditions to trigger absolute detection
        // This prevents false positives from single-condition triggers

        // Calculate heat flux for absolute detection (deltaT already defined above)
        val heatFluxCalPerSec = BeanieConstants.HEAT_FLUX_KCAL_PER_K_PER_SEC * deltaT * 1000.0

        // Count OUTSIDE conditions
        var outsideConditions = 0

        // Condition 1: Low outer temp (cold environment)
        if (outerC < 24.0) outsideConditions += 1
        if (outerC < 20.0) outsideConditions += 1  // Very cold = stronger signal

        // Condition 2: Large delta T (high heat loss)
        if (absDelta >= 4.0) outsideConditions += 1
        if (absDelta >= 6.0) outsideConditions += 1  // Very large delta = stronger signal

        // Condition 3: High heat flux
        if (heatFluxCalPerSec >= 120.0) outsideConditions += 1
        if (heatFluxCalPerSec >= 180.0) outsideConditions += 1  // Very high flux = stronger signal

        // Need at least 2 conditions for "clearly outside"
        // Need 3+ conditions for "absolutely outside" (can skip thermalizing)
        val clearlyOutside = outsideConditions >= 2
        val absolutelyOutsideStrong = outsideConditions >= 3

        // Count INSIDE conditions
        var insideConditions = 0

        // Condition 1: Warm outer temp (room temperature)
        if (outerC >= 27.0) insideConditions += 1
        if (outerC >= 29.0) insideConditions += 1  // Very warm = stronger signal

        // Condition 2: Small delta T
        if (absDelta < 2.5) insideConditions += 1
        if (absDelta < 1.8) insideConditions += 1  // Very small delta = stronger signal

        // Condition 3: Low heat flux
        if (heatFluxCalPerSec <= 60.0) insideConditions += 1
        if (heatFluxCalPerSec <= 45.0) insideConditions += 1  // Very low flux = stronger signal

        // Need at least 2 conditions for "clearly inside" (and NOT clearly outside)
        val clearlyInside = insideConditions >= 2 && !clearlyOutside
        val absolutelyInsideStrong = insideConditions >= 3 && !clearlyOutside

        // Combine rate-based with absolute detection
        val goingOutWithAbsolute = goingOutsideEvidence || clearlyOutside
        val goingInWithAbsolute = goingInsideEvidence || (clearlyInside && !clearlyOutside)

        // iOS parity: Check minimum dwell time before allowing transitions from stable states
        val dwellTime = stateStart?.let { (time.time - it.time) / 1000.0 } ?: 0.0
        val canLeaveStableState = dwellTime >= thr.minimumDwellSeconds

        when (state) {
            EnvState.PUTTING_ON -> {
                if (!inSpikeCooldown) {
                    // iOS parity: Check for strong absolute outside detection first
                    if (absolutelyOutsideStrong) {
                        transition(EnvState.OUTSIDE, time); resetScores()
                    } else if (updateGoingOutsideHold(goingOutWithAbsolute, dt, thr.transMinHoldSeconds)) {
                        transition(EnvState.GOING_OUTSIDE, time); resetScores()
                    } else if (updateGoingInsideHold(goingInWithAbsolute, dt, thr.transMinHoldSeconds)) {
                        transition(EnvState.GOING_INSIDE, time); resetScores()
                    } else {
                        val gateA = (abs(dTout) < thr.outRateStable) && (abs(dOuter30) < thr.outDelta30Stable)
                        gateAScore = scoreAccumulate(gateAScore, gateA, dt)
                        if (gateAScore >= thr.gateASeconds) {
                            transition(EnvState.INSIDE_THERMALIZING, time); resetScores()
                        }
                    }
                }
                if (stateStart?.let { time.time - it.time > thr.puttingOnMaxSeconds * 1000 } == true) {
                    transition(EnvState.INSIDE_THERMALIZING, time)
                }
            }
            EnvState.GOING_OUTSIDE -> {
                if (!inSpikeCooldown) {
                    // iOS parity: Can skip to OUTSIDE if absolute detection is strong
                    if (absolutelyOutsideStrong) {
                        transition(EnvState.OUTSIDE, time); resetScores()
                    } else {
                        val gateA = (abs(dTout) < thr.outRateStable) && (abs(dOuter30) < thr.outDelta30Stable)
                        gateAScore = scoreAccumulate(gateAScore, gateA, dt)
                        if (gateAScore >= thr.gateASeconds) {
                            transition(EnvState.OUTSIDE_THERMALIZING, time); resetScores()
                        }
                    }
                }
            }
            EnvState.GOING_INSIDE -> {
                if (!inSpikeCooldown) {
                    // iOS parity: Can skip to INSIDE if absolute detection is strong
                    if (absolutelyInsideStrong) {
                        transition(EnvState.INSIDE, time); resetScores()
                    } else {
                        val gateA = (abs(dTout) < thr.outRateStable) && (abs(dOuter30) < thr.outDelta30Stable)
                        gateAScore = scoreAccumulate(gateAScore, gateA, dt)
                        if (gateAScore >= thr.gateASeconds) {
                            transition(EnvState.INSIDE_THERMALIZING, time); resetScores()
                        }
                    }
                }
            }
            EnvState.OUTSIDE_THERMALIZING -> {
                if (!inSpikeCooldown) {
                    val gateB = (abs(dTin) < thr.inRateStable) && (deltaStd60.isFinite() && (deltaStd60 < thr.deltaStdStable))
                    gateBScore = scoreAccumulate(gateBScore, gateB, dt)
                    if (gateBScore >= thr.gateBSeconds) {
                        transition(EnvState.OUTSIDE, time); resetScores()
                    }
                    // iOS parity: Check for going inside - need strong evidence
                    if (absolutelyInsideStrong) {
                        transition(EnvState.INSIDE, time); resetScores()
                    } else if (updateGoingInsideHold(goingInWithAbsolute, dt, thr.transMinHoldSeconds)) {
                        transition(EnvState.GOING_INSIDE, time); resetScores()
                    }
                }
                // iOS parity: Force to outside if absolute outside conditions met for long enough
                if (absolutelyOutsideStrong && dwellTime > 30) {
                    transition(EnvState.OUTSIDE, time); resetScores()
                }
            }
            EnvState.INSIDE_THERMALIZING -> {
                if (!inSpikeCooldown) {
                    // iOS parity: Check for strong absolute outside first - can jump directly
                    if (absolutelyOutsideStrong) {
                        transition(EnvState.OUTSIDE, time); resetScores()
                    } else if (canLeaveStableState && updateGoingOutsideHold(goingOutWithAbsolute, dt, thr.transMinHoldSeconds)) {
                        transition(EnvState.GOING_OUTSIDE, time); resetScores()
                    } else {
                        val gateB = (abs(dTin) < thr.inRateStable) && (deltaStd60.isFinite() && (deltaStd60 < thr.deltaStdStable))
                        gateBScore = scoreAccumulate(gateBScore, gateB, dt)
                        if (gateBScore >= thr.gateBSeconds) {
                            transition(EnvState.INSIDE, time); resetScores()
                        }
                    }
                }
                // iOS parity: Force to goingOutside if clearly outside for long enough
                if (clearlyOutside && dwellTime > 30) {
                    transition(EnvState.GOING_OUTSIDE, time); resetScores()
                }
            }
            EnvState.OUTSIDE -> {
                if (!inSpikeCooldown) {
                    // iOS parity: Stay outside if still clearly outside
                    if (clearlyOutside && !absolutelyInsideStrong) {
                        // Stay in outside state
                    } else if (absolutelyInsideStrong) {
                        transition(EnvState.INSIDE, time); resetScores()
                    } else if (canLeaveStableState && updateGoingInsideHold(goingInWithAbsolute, dt, thr.transMinHoldSeconds)) {
                        transition(EnvState.GOING_INSIDE, time); resetScores()
                    }
                }
                // iOS parity: Force to inside if absolutely inside for long enough
                if (absolutelyInsideStrong && dwellTime > 60) {
                    transition(EnvState.INSIDE, time); resetScores()
                }
            }
            EnvState.INSIDE -> {
                if (!inSpikeCooldown) {
                    // iOS parity: Check for strong absolute outside detection
                    if (absolutelyOutsideStrong) {
                        transition(EnvState.OUTSIDE, time); resetScores()
                    } else if (canLeaveStableState && updateGoingOutsideHold(goingOutWithAbsolute, dt, thr.transMinHoldSeconds)) {
                        transition(EnvState.GOING_OUTSIDE, time); resetScores()
                    }
                }
                // iOS parity: Force to goingOutside if clearly outside for long enough
                if (clearlyOutside && dwellTime > 60) {
                    transition(EnvState.GOING_OUTSIDE, time); resetScores()
                }
            }
            else -> { /* NOT_WORN is handled before the when block */ }
        }
        return Pair(state, overlays)
    }

    private fun transition(newState: EnvState, time: Date) {
        if (state != newState) {
            state = newState
            stateStart = time
        }
    }

    private fun resetScores() {
        gateAScore = 0.0
        gateBScore = 0.0
        goingOutsideScore = 0.0
        goingInsideScore = 0.0
        rapidScore = 0.0
    }

    private fun scoreAccumulate(score: Double, good: Boolean, dt: Double): Double =
        if (good) min(1000.0, score + dt) else max(0.0, score - 0.5 * dt)

    private fun updateGoingOutsideHold(evidence: Boolean, dt: Double, targetSeconds: Double): Boolean {
        if (evidence) {
            goingOutsideScore = min(targetSeconds, goingOutsideScore + dt)
            goingInsideScore = max(0.0, goingInsideScore - dt)
        } else {
            goingOutsideScore = max(0.0, goingOutsideScore - 0.5 * dt)
        }
        return goingOutsideScore >= targetSeconds
    }

    private fun updateGoingInsideHold(evidence: Boolean, dt: Double, targetSeconds: Double): Boolean {
        if (evidence) {
            goingInsideScore = min(targetSeconds, goingInsideScore + dt)
            goingOutsideScore = max(0.0, goingOutsideScore - dt)
        } else {
            goingInsideScore = max(0.0, goingInsideScore - 0.5 * dt)
        }
        return goingInsideScore >= targetSeconds
    }

    private fun appendOuter(time: Date, outer: Double) {
        outerBufT.add(time); outerBufX.add(outer)
        val cutoff = Date(time.time - (outerWindowSeconds * 1000).toLong())
        while (outerBufT.firstOrNull()?.before(cutoff) == true) {
            outerBufT.removeAt(0)
            outerBufX.removeAt(0)
        }
        if (outerBufT.size > outerMaxSamples) {
            val overflow = outerBufT.size - outerMaxSamples
            repeat(overflow) { outerBufT.removeAt(0); outerBufX.removeAt(0) }
        }
    }

    // iOS parity: Track inner sensor for motion artifact detection
    private fun appendInner(time: Date, inner: Double) {
        innerBufT.add(time); innerBufX.add(inner)
        val cutoff = Date(time.time - (outerWindowSeconds * 1000).toLong())
        while (innerBufT.firstOrNull()?.before(cutoff) == true) {
            innerBufT.removeAt(0)
            innerBufX.removeAt(0)
        }
        if (innerBufT.size > outerMaxSamples) {
            val overflow = innerBufT.size - outerMaxSamples
            repeat(overflow) { innerBufT.removeAt(0); innerBufX.removeAt(0) }
        }
    }

    private fun outerDelta(seconds: Double, now: Date, currentOuter: Double): Double? {
        val target = Date(now.time - (seconds * 1000).toLong())
        val pastValue = valueAtOrBefore(target, outerBufT, outerBufX) ?: return null
        return currentOuter - pastValue
    }

    private fun valueAtOrBefore(target: Date, times: List<Date>, values: List<Double>): Double? {
        for (i in times.indices.reversed()) {
            if (!times[i].after(target)) return values[i]
        }
        return null
    }

    private fun pushDelta(time: Date, x: Double) {
        val cutoff = Date(time.time - (deltaWindowSeconds * 1000).toLong())
        while (deltaBufT.firstOrNull()?.before(cutoff) == true) {
            deltaBufT.removeAt(0)
            deltaBufX.removeAt(0)
        }
        deltaBufT.add(time); deltaBufX.add(x)
        if (deltaBufT.size > deltaMaxSamples) {
            val overflow = deltaBufT.size - deltaMaxSamples
            repeat(overflow) { deltaBufT.removeAt(0); deltaBufX.removeAt(0) }
        }
    }

    private fun stdDeltaWindow(): Double {
        if (deltaBufX.size < 8) return 0.0
        val m = deltaBufX.average()
        val v = deltaBufX.sumOf { (it - m) * (it - m) } / (deltaBufX.size - 1)
        return sqrt(v)
    }
}