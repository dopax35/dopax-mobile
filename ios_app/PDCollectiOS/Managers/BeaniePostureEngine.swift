import Foundation
import Combine

/// Posture tracking engine — Madgwick-filter gravity vector plus calibration-based
/// classification, and the postureHistory ring buffer that supplies the ML
/// model's posture_input[1, 250, 4] tensor.
///
/// Swift port of Android's PostureEngine.kt (itself already a port of the iOS
/// reference project's PostureEngine.swift), replacing the previous stub that
/// only ever appended zeros ("uncalibrated zeros for now"). Deliberately
/// simplified relative to the reference app: no disk-persisted session log, no
/// sessionPostureTime accumulation — this app has no posture history/charts UI
/// (by design), so postureHistory only needs to hold the rolling window the ML
/// model reads. Android's own port made the same simplification.
///
/// Singleton (matches the existing BeaniePostureEngine.shared access pattern
/// already used throughout BeanieBluetoothService.swift) so both the live BLE
/// service and PostureCalibrationView read/drive the same converging filter.
final class BeaniePostureEngine: ObservableObject {
    static let shared = BeaniePostureEngine()

    @Published private(set) var state: PostureState = .unknown
    @Published private(set) var signedPitchDeg: Double?
    @Published private(set) var currentGravity: (x: Double, y: Double, z: Double) = (0, 0, -1)
    @Published private(set) var calibration: PostureCalibrationProfile

    private let filter = MadgwickFilter(beta: 0.05, sampleRateHz: 25.0)

    private var pitchBuffer: [Double] = []
    private var gyroMagBuffer: [Double] = []
    private var lastSmoothedPitch: Double?

    // Ring buffer of recent gyro-Z values (20s at 25Hz) — used only during
    // calibration capture to detect left/right turn direction (meanGzOverWindow).
    private var gzRingBuffer: [Double] = []
    private let gzRingMax = 500

    // Per-sample posture tuple history — supplies the ML model's posture_input.
    // Each entry is [headAngle, fwdFrac, backFrac, latFrac]. Not padded here;
    // BeanieActivityEngine.startInference() already zero-pads short sequences
    // defensively, and in practice this fills in lockstep with imuRingBuffer.
    private var postureHistory: [[Float]] = []
    private let maxHistory = 1000

    // Scale factors matching BeaniePacketParser / Android PostureEngine parity.
    private let accelScale = 4096.0
    private let gyroScale = 16.384
    private let movingThreshDps = 25.0
    private let spikeThreshDeg = 50.0

    private init() {
        calibration = PostureCalibrationProfile.load()
    }

    // MARK: - Calibration capture support (read by PostureCalibrationView)

    func currentGravityVector() -> (x: Double, y: Double, z: Double) { currentGravity }

    func currentAbsolutePitch() -> Double? { lastSmoothedPitch }

    /// Mean gyro-Z (deg/s) over the most recent windowSec seconds — used during
    /// calibration to detect left/right turn direction.
    func meanGzOverWindow(_ windowSec: Int) -> Double {
        let n = min(gzRingBuffer.count, windowSec * 25)
        guard n > 0 else { return 0.0 }
        return gzRingBuffer.suffix(n).reduce(0, +) / Double(n)
    }

    /// Save and apply a completed posture calibration.
    func applyCalibration(_ newProfile: PostureCalibrationProfile) {
        newProfile.save()
        calibration = newProfile
    }

    // MARK: - ML model posture series

    /// Returns the last n entries from postureHistory, one per IMU sample, each
    /// [headAngle, fwdFrac, backFrac, latFrac]. Feeds posture_input[1,250,4].
    func getPostureSeries(_ n: Int) -> [[Float]] {
        if postureHistory.count >= n {
            return Array(postureHistory.suffix(n))
        }
        return postureHistory
    }

    func reset() {
        postureHistory.removeAll()
        filter.reset()
        pitchBuffer.removeAll()
        gyroMagBuffer.removeAll()
        gzRingBuffer.removeAll()
        lastSmoothedPitch = nil
        state = .unknown
        signedPitchDeg = nil
        currentGravity = (0, 0, -1)
    }

    // MARK: - Main processing entry point

    /// Process a batch of IMU samples through the Madgwick filter + posture
    /// classifier. Call ONCE per BLE packet with the packet's full sample
    /// array — this loops internally (mirrors Android's PostureEngine.process(),
    /// which is why BeanieService.kt calls it once per packet rather than once
    /// per sample; the old feedScaledImuSample() per-sample call was a compile
    /// error there for the same reason).
    func process(samples: [BeaniePacketParser.IMUSample]) {
        guard !samples.isEmpty else { return }

        let cal = calibration

        for s in samples {
            let ax = Double(s.axRaw) / accelScale
            let ay = Double(s.ayRaw) / accelScale
            let az = Double(s.azRaw) / accelScale
            let gx = Double(s.gxRaw) / gyroScale
            let gy = Double(s.gyRaw) / gyroScale
            let gz = Double(s.gzRaw) / gyroScale

            filter.update(ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz)

            gyroMagBuffer.append(sqrt(gx * gx + gy * gy + gz * gz))
            if gyroMagBuffer.count > 5 { gyroMagBuffer.removeFirst() }

            gzRingBuffer.append(gz)
            if gzRingBuffer.count > gzRingMax { gzRingBuffer.removeFirst() }

            let grav = filter.gravityVector
            let tuple = computePostureTuple(grav: grav, cal: cal)
            postureHistory.append([tuple.headAngle, tuple.fwdFrac, tuple.backFrac, tuple.latFrac])
            if postureHistory.count > maxHistory {
                postureHistory.removeFirst(postureHistory.count - maxHistory)
            }
        }

        // Pitch smoothing — 5-sample median, matches Android/reference.
        let rawPitch = filter.pitchDeg
        pitchBuffer.append(rawPitch)
        if pitchBuffer.count > 5 { pitchBuffer.removeFirst() }
        let smoothPitch = pitchBuffer.sorted()[pitchBuffer.count / 2]

        let isSpike: Bool = {
            guard let last = lastSmoothedPitch else { return false }
            return abs(smoothPitch - last) > spikeThreshDeg
        }()
        lastSmoothedPitch = smoothPitch

        let grav = filter.gravityVector
        currentGravity = grav
        let avgGyroMag = gyroMagBuffer.isEmpty ? 0.0 : gyroMagBuffer.reduce(0, +) / Double(gyroMagBuffer.count)

        guard cal.isCalibrated else {
            signedPitchDeg = nil
            state = .unknown
            return
        }

        // signedPitchDeg — reference/Android parity.
        if cal.hasAxisFrame {
            let dx = grav.x - cal.neutralGravX
            let dy = grav.y - cal.neutralGravY
            let dz = grav.z - cal.neutralGravZ
            let fwdFrac = (dx * cal.fwdAxisX + dy * cal.fwdAxisY + dz * cal.fwdAxisZ) / cal.fwdRange
            let angularRange = cal.gravTiltRangeDeg > 5.0 ? cal.gravTiltRangeDeg : 45.0
            signedPitchDeg = fwdFrac * angularRange
        } else {
            let rawDelta = smoothPitch - cal.neutralPitchDeg
            signedPitchDeg = rawDelta * cal.forwardPitchSign
        }

        // Classification.
        if isSpike || avgGyroMag > movingThreshDps {
            state = .moving
        } else if cal.hasAxisFrame {
            state = classifyWithFrame(grav: grav, cal: cal)
        } else {
            state = classifyLegacy(pitch: smoothPitch, cal: cal)
        }
    }

    // MARK: - Per-sample posture tuple

    private func computePostureTuple(
        grav: (x: Double, y: Double, z: Double),
        cal: PostureCalibrationProfile
    ) -> (headAngle: Float, fwdFrac: Float, backFrac: Float, latFrac: Float) {
        guard cal.isCalibrated, cal.hasAxisFrame else {
            return (0, 0, 0, 0)
        }

        let dx = grav.x - cal.neutralGravX
        let dy = grav.y - cal.neutralGravY
        let dz = grav.z - cal.neutralGravZ

        let fwdFrac = Float((dx * cal.fwdAxisX + dy * cal.fwdAxisY + dz * cal.fwdAxisZ) / max(cal.fwdRange, 0.001))

        let backFrac: Float = cal.hasBackAxis
            ? Float((dx * cal.backAxisX + dy * cal.backAxisY + dz * cal.backAxisZ) / max(cal.backRange, 0.001))
            : 0

        let latFrac: Float = cal.latHalfRange > 0.01
            ? Float((dx * cal.latAxisX + dy * cal.latAxisY + dz * cal.latAxisZ) / cal.latHalfRange)
            : 0

        let angularRange = cal.gravTiltRangeDeg > 5.0 ? cal.gravTiltRangeDeg : 45.0
        let headAngle = fwdFrac * Float(angularRange)

        return (headAngle, fwdFrac, backFrac, latFrac)
    }

    // MARK: - Axis-frame classification (reference PostureEngine.swift parity)

    private func classifyWithFrame(grav: (x: Double, y: Double, z: Double), cal: PostureCalibrationProfile) -> PostureState {
        let dx = grav.x - cal.neutralGravX
        let dy = grav.y - cal.neutralGravY
        let dz = grav.z - cal.neutralGravZ

        let fwdFrac = (dx * cal.fwdAxisX + dy * cal.fwdAxisY + dz * cal.fwdAxisZ) / cal.fwdRange
        let backFrac = cal.hasBackAxis
            ? (dx * cal.backAxisX + dy * cal.backAxisY + dz * cal.backAxisZ) / cal.backRange
            : 0.0
        let latFrac = cal.latHalfRange > 0.01
            ? (dx * cal.latAxisX + dy * cal.latAxisY + dz * cal.latAxisZ) / cal.latHalfRange
            : 0.0

        let absFwd = abs(fwdFrac) * cal.fwdRange
        let absBack = cal.hasBackAxis ? abs(backFrac) * cal.backRange : 0.0
        let absLat = cal.latHalfRange > 0.01 ? abs(latFrac) * cal.latHalfRange : 0.0

        let maxAbs = max(absFwd, max(absBack, absLat))
        if maxAbs >= PostureCalibrationProfile.lyingDeltaThresh {
            if absBack >= absFwd && absBack >= absLat { return .lyingBack }
            if absFwd > absBack && absFwd >= absLat { return .lyingFront }
            return .lyingSide
        }

        if cal.hasBackAxis && backFrac > PostureCalibrationProfile.backThreshFrac { return .headBack }
        if fwdFrac > PostureCalibrationProfile.fwdGoodFrac { return .poor }
        if fwdFrac > PostureCalibrationProfile.fwdGreatFrac { return .mildBad }
        return .upright
    }

    // MARK: - Legacy classification (no axis frame, pre-v5 calibration)

    private func classifyLegacy(pitch: Double, cal: PostureCalibrationProfile) -> PostureState {
        let delta = (pitch - cal.neutralPitchDeg) * cal.forwardPitchSign
        let range = cal.pitchRangeDeg > 5.0 ? cal.pitchRangeDeg : 45.0
        let frac = delta / range

        if frac > PostureCalibrationProfile.fwdGoodFrac { return .poor }
        if frac > PostureCalibrationProfile.fwdGreatFrac { return .mildBad }
        return .upright
    }
}
