package com.pdcollect.app.logic

import android.content.Context
import kotlin.math.sqrt

data class PostureCalibrationProfile(
    var calibratedAt: Long = 0L,
    var neutralPitchDeg:  Double = 0.0,
    var pitchRangeDeg:    Double = 0.0,
    var upPitchRangeDeg:  Double = 0.0,
    var forwardPitchSign: Double = 1.0,
    var leftTurnGzSign:   Double = 1.0,
    var neutralGravX: Double = 0.0, var neutralGravY: Double = 0.0, var neutralGravZ: Double = 0.0,
    var fwdAxisX: Double = 0.0, var fwdAxisY: Double = 0.0, var fwdAxisZ: Double = 0.0,
    var fwdRange: Double = 0.0,
    var gravTiltRangeDeg: Double = 0.0,
    var backAxisX: Double = 0.0, var backAxisY: Double = 0.0, var backAxisZ: Double = 0.0,
    var backRange: Double = 0.0,
    var latAxisX: Double = 0.0, var latAxisY: Double = 0.0, var latAxisZ: Double = 0.0,
    var latHalfRange: Double = 0.0
) {
    val isCalibrated: Boolean get() = calibratedAt > 1000L
    val hasAxisFrame: Boolean get() =
        (fwdAxisX*fwdAxisX + fwdAxisY*fwdAxisY + fwdAxisZ*fwdAxisZ) > 0.5 && fwdRange > 0.01
    val hasBackAxis: Boolean get() =
        (backAxisX*backAxisX + backAxisY*backAxisY + backAxisZ*backAxisZ) > 0.5 && backRange > 0.01

    companion object {
        const val FWD_GREAT_FRAC   = 0.20
        const val FWD_GOOD_FRAC    = 0.45
        const val BACK_THRESH_FRAC = 0.30
        // Lateral thresholds — mild tilt vs significant tilt
        const val LAT_MILD_FRAC    = 0.30
        const val LAT_POOR_FRAC    = 0.60
        // Lying detection — if dominant axis gravity displacement ≥ 0.6 → lying
        // iOS: PostureCalibrationProfile.lyingDeltaThresh = 0.6 (used in export cal row)
        const val LYING_DELTA_THRESH = 0.6
        private const val PREFS_NAME = "posture_prefs"

        fun load(context: Context): PostureCalibrationProfile {
            val p = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            fun d(k: String, def: Double = 0.0) = Double.fromBits(p.getLong(k, def.toBits()))
            return PostureCalibrationProfile(
                calibratedAt = p.getLong("calAt", 0L),
                neutralPitchDeg  = d("nPD"),  pitchRangeDeg    = d("pRD"),
                upPitchRangeDeg  = d("uPRD"), forwardPitchSign = d("fPS", 1.0),
                leftTurnGzSign   = d("lGS", 1.0),
                neutralGravX = d("nGX"), neutralGravY = d("nGY"), neutralGravZ = d("nGZ"),
                fwdAxisX = d("fAX"), fwdAxisY = d("fAY"), fwdAxisZ = d("fAZ"),
                fwdRange = d("fR"),  gravTiltRangeDeg = d("gTRD"),
                backAxisX = d("bAX"), backAxisY = d("bAY"), backAxisZ = d("bAZ"),
                backRange = d("bR"),
                latAxisX = d("lAX"), latAxisY = d("lAY"), latAxisZ = d("lAZ"),
                latHalfRange = d("lHR")
            )
        }

        @Suppress("unused")
        fun gravDistance(nx: Double, ny: Double, nz: Double, cx: Double, cy: Double, cz: Double): Double {
            val dx = cx-nx; val dy = cy-ny; val dz = cz-nz
            return sqrt(dx*dx + dy*dy + dz*dz)
        }

        /** Returns [ux, uy, uz, magnitude] or null if movement too small. */
        @Suppress("unused")
        fun makeAxis(nx: Double, ny: Double, nz: Double, gx: Double, gy: Double, gz: Double): DoubleArray? {
            val dx = gx-nx; val dy = gy-ny; val dz = gz-nz
            val mag = sqrt(dx*dx + dy*dy + dz*dz)
            if (mag < 0.01) return null
            return doubleArrayOf(dx/mag, dy/mag, dz/mag, mag)
        }
    }

    fun save(context: Context) {
        val p = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        p.edit().apply {
            putLong("calAt", calibratedAt)
            putLong("nPD",  neutralPitchDeg.toBits()); putLong("pRD",  pitchRangeDeg.toBits())
            putLong("uPRD", upPitchRangeDeg.toBits()); putLong("fPS",  forwardPitchSign.toBits())
            putLong("lGS",  leftTurnGzSign.toBits())
            putLong("nGX",  neutralGravX.toBits()); putLong("nGY",  neutralGravY.toBits()); putLong("nGZ",  neutralGravZ.toBits())
            putLong("fAX",  fwdAxisX.toBits()); putLong("fAY",  fwdAxisY.toBits()); putLong("fAZ",  fwdAxisZ.toBits())
            putLong("fR",   fwdRange.toBits()); putLong("gTRD", gravTiltRangeDeg.toBits())
            putLong("bAX",  backAxisX.toBits()); putLong("bAY",  backAxisY.toBits()); putLong("bAZ",  backAxisZ.toBits())
            putLong("bR",   backRange.toBits())
            putLong("lAX",  latAxisX.toBits()); putLong("lAY",  latAxisY.toBits()); putLong("lAZ",  latAxisZ.toBits())
            putLong("lHR",  latHalfRange.toBits())
            apply()
        }
    }
}
