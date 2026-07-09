package com.pdcollect.app.logic

import android.content.Context
import kotlin.math.sqrt
import kotlin.math.abs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.pdcollect.app.service.BeaniePacketParser

class PostureEngine private constructor(val context: Context)
{
    @Suppress("StaticFieldLeak")   // stores applicationContext, not Activity — safe
    companion object {
        @Volatile private var instance: PostureEngine? = null

        /** Shared instance — fed live IMU data by BeanieService and read by
         *  PostureCalibrationActivity/View during a calibration capture session. */
        fun getInstance(context: Context): PostureEngine =
            instance ?: synchronized(this) {
                instance ?: PostureEngine(context.applicationContext).also { instance = it }
            }
    }

    private val filter = MadgwickFilter()

    // v2.6: MutableStateFlow so calibration updates propagate live to the UI.
    private val _calibration = MutableStateFlow(PostureCalibrationProfile.load(context))
    val calibration = _calibration.asStateFlow()

    private val _state = MutableStateFlow(PostureState.UNKNOWN)
    val state = _state.asStateFlow()

    private val _currentGravity = MutableStateFlow(Triple(0.0, 0.0, -1.0))
    val currentGravity = _currentGravity.asStateFlow()

    // iOS parity: signed pitch in degrees.
    // When hasAxisFrame is true: fwdFrac × gravTiltRangeDeg (same formula as iOS).
    // When legacy (no axis frame): rawDelta × forwardPitchSign.
    private val _signedPitchDeg = MutableStateFlow<Double?>(null)
    val signedPitchDeg = _signedPitchDeg.asStateFlow()

    private val pitchBuffer    = mutableListOf<Double>()
    private val gyroMagBuffer  = mutableListOf<Double>()
    private var lastSmoothedPitch: Double? = null

    // Ring buffer of recent gyro-Z values for left/right turn sign detection.
    // iOS: meanGz(windowSec:) averages gyro.z over the hold window.
    private val gzRingBuf = ArrayDeque<Double>(500)  // 20s at 25 Hz

    // ── postureHistory ring buffer — iOS PostureEngine parity ─────────────────
    // Per-sample posture tuple accumulated inside the Madgwick filter loop.
    // iOS: postureHistory.append((fwd * angRange, fwd, back, lat)) every sample.
    // Max 1000 entries (~40s at 25 Hz) — enough to supply the V5 model's 250-sample
    // posture input while also covering the optional 1000-sample long-model path.
    //
    // Each FloatArray is [headAngle, fwdFrac, backFrac, latFrac] — exactly the
    // four channels expected by posture_input[1, 250, 4].
    //   headAngle = fwdFrac × angularRange  (signed degrees, same as iOS signedPitchDeg)
    //   fwdFrac   = dot(delta, fwdAxis) / fwdRange
    //   backFrac  = dot(delta, backAxis) / backRange   (0 if no back calibration)
    //   latFrac   = dot(delta, latAxis) / latHalfRange (0 if no lateral calibration)
    //
    // When the device is uncalibrated all four values are 0.0 — the model was trained
    // with zeroed posture input for uncalibrated sessions so inference still runs.
    private val postureHistoryList = ArrayDeque<FloatArray>()
    private val MAX_POSTURE_HISTORY = 1000

    // ── Scale factors matching iOS PostureEngine ──────────────────────────────
    private val accelScale       = 4096.0
    private val gyroScale        = 16.384
    private val movingThreshDps  = 25.0
    private val spikeThreshDeg   = 50.0

    // ── Lying-detection threshold (iOS parity) ───────────────────────────────
    // If the dominant axis displacement fraction is ≥ 0.6 we classify the head
    // as near-horizontal (lying down). Must be checked BEFORE upright classification.
    private val lyingThreshFrac  = 0.6

    // ─────────────────────────────────────────────────────────────────────────

    /** Current gravity unit vector — used by PostureCalibrationSheet during capture. */
    @Suppress("unused")
    fun currentGravityVector(): Triple<Double, Double, Double> = _currentGravity.value

    /** Absolute pitch from the converged Madgwick filter, null until first sample. */
    @Suppress("unused")
    fun currentAbsolutePitch(): Double? = lastSmoothedPitch

    /** Mean gyro-Z (°/s) over the most recent windowSec seconds.
     *  iOS parity: meanGz(windowSec:) — used during calibration to detect turn direction. */
    @Suppress("unused")
    fun meanGzOverWindow(windowSec: Int): Double {
        val n = minOf(gzRingBuf.size, windowSec * 25)
        if (n == 0) return 0.0
        return gzRingBuf.takeLast(n).average()
    }

    /** Save and apply a completed posture calibration. */
    fun applyCalibration(newProfile: PostureCalibrationProfile) {
        newProfile.save(context)
        _calibration.value = newProfile
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: – generatePostureSeries (iOS parity)
    // ─────────────────────────────────────────────────────────────────────────
    //
    // Returns the last `n` entries from postureHistory — one FloatArray per IMU
    // sample, each containing [headAngle, fwdFrac, backFrac, latFrac].
    //
    // Called by BeanieService just before startInference() to supply the
    // posture_input[1, 250, 4] tensor to the V5 ActivityEngine model.
    //
    // iOS: PostureEngine.shared.generatePostureSeries(from: imuSamples300, calibration:)
    //      reads from self.postureHistory.suffix(samples.count) — same pattern.

    fun generatePostureSeries(n: Int): List<FloatArray> {
        val history = postureHistoryList
        return if (history.size >= n) {
            history.toList().takeLast(n)
        } else {
            history.toList()
        }
    }

    /** Alias matching the task spec call site. */
    fun getPostureSeries(n: Int): List<FloatArray> = generatePostureSeries(n)

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: – Reset posture history
    // ─────────────────────────────────────────────────────────────────────────

    fun resetHistory() {
        postureHistoryList.clear()
        filter.reset()
        pitchBuffer.clear()
        gyroMagBuffer.clear()
        lastSmoothedPitch = null
        _state.value = PostureState.UNKNOWN
        _signedPitchDeg.value = null
        _currentGravity.value = Triple(0.0, 0.0, -1.0)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: – Main processing entry point
    // ─────────────────────────────────────────────────────────────────────────

    fun process(samples: List<BeaniePacketParser.ImuSample>)
    {
        if (samples.isEmpty()) return

        val cal = calibration.value

        for (s in samples) {
            val ax = s.axRaw / accelScale
            val ay = s.ayRaw / accelScale
            val az = s.azRaw / accelScale
            val gx = s.gxRaw / gyroScale
            val gy = s.gyRaw / gyroScale
            val gz = s.gzRaw / gyroScale

            filter.update(ax, ay, az, gx, gy, gz)

            gyroMagBuffer.add(sqrt(gx*gx + gy*gy + gz*gz))
            if (gyroMagBuffer.size > 5) gyroMagBuffer.removeAt(0)

            // Ring buffer for mean-gz (used during calibration left/right capture)
            gzRingBuf.addLast(gz)
            if (gzRingBuf.size > 500) gzRingBuf.removeFirst()

            // ── postureHistory per-sample append (iOS PostureEngine parity) ───
            val grav = filter.gravityVector
            val (headAngle, fwdFrac, backFrac, latFrac) = computePostureTuple(grav, cal)
            postureHistoryList.addLast(floatArrayOf(headAngle, fwdFrac, backFrac, latFrac))
            if (postureHistoryList.size > MAX_POSTURE_HISTORY) {
                postureHistoryList.removeFirst()
            }
        }

        // ── Pitch smoothing (5-sample median, same as iOS) ────────────────────
        val rawPitch = filter.pitchDeg
        pitchBuffer.add(rawPitch)
        if (pitchBuffer.size > 5) pitchBuffer.removeAt(0)
        val smoothPitch = pitchBuffer.sorted()[pitchBuffer.size / 2]

        // Spike detection (iOS: abs(smooth - last) > spikeThreshDeg)
        val isSpike = lastSmoothedPitch?.let { abs(smoothPitch - it) > spikeThreshDeg } ?: false
        lastSmoothedPitch = smoothPitch

        val grav = filter.gravityVector
        _currentGravity.value = grav
        val avgGyroMag = if (gyroMagBuffer.isEmpty()) 0.0 else gyroMagBuffer.average()

        if (!cal.isCalibrated) {
            _signedPitchDeg.value = null
            _state.value = PostureState.UNKNOWN
            return
        }

        // ── signedPitchDeg — iOS parity ───────────────────────────────────────
        if (cal.hasAxisFrame) {
            val dx = grav.first  - cal.neutralGravX
            val dy = grav.second - cal.neutralGravY
            val dz = grav.third  - cal.neutralGravZ
            val fwdFrac  = (dx * cal.fwdAxisX + dy * cal.fwdAxisY + dz * cal.fwdAxisZ) / cal.fwdRange
            val angularRange = if (cal.gravTiltRangeDeg > 5.0) cal.gravTiltRangeDeg else 45.0
            _signedPitchDeg.value = fwdFrac * angularRange
        } else {
            val rawDelta = smoothPitch - cal.neutralPitchDeg
            _signedPitchDeg.value = rawDelta * cal.forwardPitchSign
        }

        // ── Classification ────────────────────────────────────────────────────
        _state.value = when {
            isSpike || avgGyroMag > movingThreshDps -> PostureState.MOVING
            cal.hasAxisFrame -> classifyWithFrame(grav, cal)
            else             -> classifyLegacy(smoothPitch, cal)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: – Per-sample posture tuple
    // ─────────────────────────────────────────────────────────────────────────

    private data class PostureTuple(
        val headAngle: Float,
        val fwdFrac:   Float,
        val backFrac:  Float,
        val latFrac:   Float
    )

    private fun computePostureTuple(
        grav: Triple<Double, Double, Double>,
        cal:  PostureCalibrationProfile
    ): PostureTuple {
        if (!cal.isCalibrated || !cal.hasAxisFrame) {
            return PostureTuple(0f, 0f, 0f, 0f)
        }

        val dx = grav.first  - cal.neutralGravX
        val dy = grav.second - cal.neutralGravY
        val dz = grav.third  - cal.neutralGravZ

        val fwdFrac  = ((dx * cal.fwdAxisX + dy * cal.fwdAxisY + dz * cal.fwdAxisZ) /
                maxOf(cal.fwdRange, 0.001)).toFloat()

        val backFrac = if (cal.hasBackAxis) {
            ((dx * cal.backAxisX + dy * cal.backAxisY + dz * cal.backAxisZ) /
                    maxOf(cal.backRange, 0.001)).toFloat()
        } else 0f

        val latFrac  = if (cal.latHalfRange > 0.01) {
            ((dx * cal.latAxisX + dy * cal.latAxisY + dz * cal.latAxisZ) /
                    cal.latHalfRange).toFloat()
        } else 0f

        val angularRange = if (cal.gravTiltRangeDeg > 5.0) cal.gravTiltRangeDeg else 45.0
        val headAngle = (fwdFrac * angularRange.toFloat())

        return PostureTuple(headAngle, fwdFrac, backFrac, latFrac)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: – Axis-frame classification (iOS PostureEngine.swift parity)
    // ─────────────────────────────────────────────────────────────────────────

    private fun classifyWithFrame(
        grav: Triple<Double, Double, Double>,
        cal:  PostureCalibrationProfile
    ): PostureState
    {
        val dx = grav.first  - cal.neutralGravX
        val dy = grav.second - cal.neutralGravY
        val dz = grav.third  - cal.neutralGravZ

        val fwdFrac = (dx * cal.fwdAxisX + dy * cal.fwdAxisY + dz * cal.fwdAxisZ) / cal.fwdRange

        val backFrac = if (cal.hasBackAxis)
            (dx * cal.backAxisX + dy * cal.backAxisY + dz * cal.backAxisZ) / cal.backRange
        else 0.0

        val latFrac = if (cal.latHalfRange > 0.01)
            (dx * cal.latAxisX + dy * cal.latAxisY + dz * cal.latAxisZ) / cal.latHalfRange
        else 0.0

        // ── Lying detection (iOS parity) ──────────────────────────────────────
        val absFwd  = abs(fwdFrac)  * cal.fwdRange
        val absBack = if (cal.hasBackAxis) abs(backFrac) * cal.backRange else 0.0
        val absLat  = if (cal.latHalfRange > 0.01) abs(latFrac) * cal.latHalfRange else 0.0

        val maxAbs = maxOf(absFwd, absBack, absLat)
        if (maxAbs >= lyingThreshFrac) {
            return when {
                absBack >= absFwd && absBack >= absLat -> PostureState.LYING_BACK
                absFwd  >  absBack && absFwd  >= absLat -> PostureState.LYING_FRONT
                else -> PostureState.LYING_SIDE
            }
        }

        // ── Upright-range classification (iOS parity) ─────────────────────────
        return when {
            cal.hasBackAxis && backFrac > PostureCalibrationProfile.BACK_THRESH_FRAC ->
                PostureState.HEAD_BACK
            fwdFrac > PostureCalibrationProfile.FWD_GOOD_FRAC  -> PostureState.POOR
            fwdFrac > PostureCalibrationProfile.FWD_GREAT_FRAC -> PostureState.MILD_BAD
            else -> PostureState.UPRIGHT
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: – Legacy classification (no axis frame, pre-v5 calibration)
    // ─────────────────────────────────────────────────────────────────────────

    private fun classifyLegacy(pitch: Double, cal: PostureCalibrationProfile): PostureState
    {
        val delta = (pitch - cal.neutralPitchDeg) * cal.forwardPitchSign
        val range = if (cal.pitchRangeDeg > 5.0) cal.pitchRangeDeg else 45.0
        val frac  = delta / range

        return when {
            frac > PostureCalibrationProfile.FWD_GOOD_FRAC  -> PostureState.POOR
            frac > PostureCalibrationProfile.FWD_GREAT_FRAC -> PostureState.MILD_BAD
            else -> PostureState.UPRIGHT
        }
    }
}
