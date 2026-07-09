package com.pdcollect.app.logic

import kotlin.math.*

class MadgwickFilter(val beta: Double = 0.05, sampleRateHz: Double = 25.0)
{
    private var q0 = 1.0; private var q1 = 0.0; private var q2 = 0.0; private var q3 = 0.0
    private val dt = 1.0 / sampleRateHz

    fun reset() { q0 = 1.0; q1 = 0.0; q2 = 0.0; q3 = 0.0 }

    fun update(ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double) {
        val gxR = gx * PI / 180.0
        val gyR = gy * PI / 180.0
        val gzR = gz * PI / 180.0

        var qDot0 = 0.5 * (-q1 * gxR - q2 * gyR - q3 * gzR)
        var qDot1 = 0.5 * ( q0 * gxR + q2 * gzR - q3 * gyR)
        var qDot2 = 0.5 * ( q0 * gyR - q1 * gzR + q3 * gxR)
        var qDot3 = 0.5 * ( q0 * gzR + q1 * gyR - q2 * gxR)

        val aNorm = sqrt(ax * ax + ay * ay + az * az)
        if (aNorm > 0) {
            val axN = ax / aNorm; val ayN = ay / aNorm; val azN = az / aNorm
            val f1 = 2.0 * (q1 * q3 - q0 * q2) - axN
            val f2 = 2.0 * (q0 * q1 + q2 * q3) - ayN
            val f3 = 1.0 - 2.0 * (q1 * q1 + q2 * q2) - azN

            val j11 = -2.0 * q2; val j12 = 2.0 * q3; val j13 = -2.0 * q0; val j14 = 2.0 * q1
            val j21 = 2.0 * q1; val j22 = 2.0 * q0; val j23 = 2.0 * q3; val j24 = 2.0 * q2
            val j31 = 0.0; val j32 = -4.0 * q1; val j33 = -4.0 * q2; val j34 = 0.0

            var s0 = j11 * f1 + j21 * f2 + j31 * f3
            var s1 = j12 * f1 + j22 * f2 + j32 * f3
            var s2 = j13 * f1 + j23 * f2 + j33 * f3
            var s3 = j14 * f1 + j24 * f2 + j34 * f3

            val sNorm = sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3)
            if (sNorm > 0) { s0 /= sNorm; s1 /= sNorm; s2 /= sNorm; s3 /= sNorm }

            qDot0 -= beta * s0; qDot1 -= beta * s1
            qDot2 -= beta * s2; qDot3 -= beta * s3
        }

        q0 += qDot0 * dt; q1 += qDot1 * dt; q2 += qDot2 * dt; q3 += qDot3 * dt
        val qNorm = sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
        if (qNorm > 0) { q0 /= qNorm; q1 /= qNorm; q2 /= qNorm; q3 /= qNorm }
    }

    val pitchDeg: Double get() {
        val sinP = 2.0 * (q0 * q1 + q2 * q3)
        val cosP = 1.0 - 2.0 * (q1 * q1 + q2 * q2)
        return atan2(sinP, cosP) * 180.0 / PI
    }

    val gravityVector: Triple<Double, Double, Double> get() = Triple(
        2.0 * (q1 * q3 - q0 * q2),
        2.0 * (q0 * q1 + q2 * q3),
        1.0 - 2.0 * (q1 * q1 + q2 * q2)
    )
}
