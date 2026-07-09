import Foundation

/// Quaternion-based AHRS sensor fusion filter. Swift port of Android's
/// MadgwickFilter.kt (which is itself a port of the iOS reference project's
/// PostureEngine.swift MadgwickFilter) — kept byte-for-byte identical in its
/// math so both platforms converge to the same gravity vector / pitch for a
/// given IMU stream.
final class MadgwickFilter {
    private var q0: Double = 1.0
    private var q1: Double = 0.0
    private var q2: Double = 0.0
    private var q3: Double = 0.0
    private let beta: Double
    private let dt: Double

    init(beta: Double = 0.05, sampleRateHz: Double = 25.0) {
        self.beta = beta
        self.dt = 1.0 / sampleRateHz
    }

    func reset() {
        q0 = 1.0; q1 = 0.0; q2 = 0.0; q3 = 0.0
    }

    /// Directly set the filter's orientation quaternion — used to warm-start
    /// convergence from a previously-calibrated neutral gravity vector instead
    /// of re-converging from identity on every reconnect.
    func setQuaternion(w: Double, x: Double, y: Double, z: Double) {
        q0 = w; q1 = x; q2 = y; q3 = z
    }

    func update(ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double) {
        let gxR = gx * .pi / 180.0
        let gyR = gy * .pi / 180.0
        let gzR = gz * .pi / 180.0

        var qDot0 = 0.5 * (-q1 * gxR - q2 * gyR - q3 * gzR)
        var qDot1 = 0.5 * ( q0 * gxR + q2 * gzR - q3 * gyR)
        var qDot2 = 0.5 * ( q0 * gyR - q1 * gzR + q3 * gxR)
        var qDot3 = 0.5 * ( q0 * gzR + q1 * gyR - q2 * gxR)

        let aNorm = sqrt(ax * ax + ay * ay + az * az)
        if aNorm > 0 {
            let axN = ax / aNorm, ayN = ay / aNorm, azN = az / aNorm
            let f1 = 2.0 * (q1 * q3 - q0 * q2) - axN
            let f2 = 2.0 * (q0 * q1 + q2 * q3) - ayN
            let f3 = 1.0 - 2.0 * (q1 * q1 + q2 * q2) - azN

            let j11 = -2.0 * q2, j12 = 2.0 * q3, j13 = -2.0 * q0, j14 = 2.0 * q1
            let j21 = 2.0 * q1, j22 = 2.0 * q0, j23 = 2.0 * q3, j24 = 2.0 * q2
            let j31 = 0.0, j32 = -4.0 * q1, j33 = -4.0 * q2, j34 = 0.0

            var s0 = j11 * f1 + j21 * f2 + j31 * f3
            var s1 = j12 * f1 + j22 * f2 + j32 * f3
            var s2 = j13 * f1 + j23 * f2 + j33 * f3
            var s3 = j14 * f1 + j24 * f2 + j34 * f3

            let sNorm = sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3)
            if sNorm > 0 { s0 /= sNorm; s1 /= sNorm; s2 /= sNorm; s3 /= sNorm }

            qDot0 -= beta * s0; qDot1 -= beta * s1
            qDot2 -= beta * s2; qDot3 -= beta * s3
        }

        q0 += qDot0 * dt; q1 += qDot1 * dt; q2 += qDot2 * dt; q3 += qDot3 * dt
        let qNorm = sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
        if qNorm > 0 { q0 /= qNorm; q1 /= qNorm; q2 /= qNorm; q3 /= qNorm }
    }

    var pitchDeg: Double {
        let sinP = 2.0 * (q0 * q1 + q2 * q3)
        let cosP = 1.0 - 2.0 * (q1 * q1 + q2 * q2)
        return atan2(sinP, cosP) * 180.0 / .pi
    }

    var gravityVector: (x: Double, y: Double, z: Double) {
        (
            2.0 * (q1 * q3 - q0 * q2),
            2.0 * (q0 * q1 + q2 * q3),
            1.0 - 2.0 * (q1 * q1 + q2 * q2)
        )
    }
}
