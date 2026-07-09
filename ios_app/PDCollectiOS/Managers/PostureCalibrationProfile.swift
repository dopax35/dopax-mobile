import Foundation

/// Swift port of Android's PostureCalibrationProfile.kt (itself ported from the
/// iOS reference project's PostureCalibrationProfile). Captures the axis frame
/// derived from 5 calibration-capture gravity vectors (neutral, chin-down,
/// look-up, left, right) so PostureEngine can turn a live gravity vector into
/// fwd/back/lat fractions for posture classification + the ML model's
/// posture_input tensor.
///
/// Persisted as JSON to Documents (no SharedPreferences/UserDefaults equivalent
/// needed cross-platform — a small Codable file is the simplest faithful port).
struct PostureCalibrationProfile: Codable {
    var calibratedAt: Double = 0            // epoch seconds; 0 = not calibrated
    var neutralPitchDeg: Double = 0.0
    var pitchRangeDeg: Double = 0.0
    var upPitchRangeDeg: Double = 0.0
    var forwardPitchSign: Double = 1.0
    var leftTurnGzSign: Double = 1.0

    var neutralGravX: Double = 0.0
    var neutralGravY: Double = 0.0
    var neutralGravZ: Double = 0.0

    var fwdAxisX: Double = 0.0
    var fwdAxisY: Double = 0.0
    var fwdAxisZ: Double = 0.0
    var fwdRange: Double = 0.0
    var gravTiltRangeDeg: Double = 0.0

    var backAxisX: Double = 0.0
    var backAxisY: Double = 0.0
    var backAxisZ: Double = 0.0
    var backRange: Double = 0.0

    var latAxisX: Double = 0.0
    var latAxisY: Double = 0.0
    var latAxisZ: Double = 0.0
    var latHalfRange: Double = 0.0

    var isCalibrated: Bool { calibratedAt > 1.0 }
    var hasAxisFrame: Bool {
        (fwdAxisX * fwdAxisX + fwdAxisY * fwdAxisY + fwdAxisZ * fwdAxisZ) > 0.5 && fwdRange > 0.01
    }
    var hasBackAxis: Bool {
        (backAxisX * backAxisX + backAxisY * backAxisY + backAxisZ * backAxisZ) > 0.5 && backRange > 0.01
    }

    // MARK: - Classification thresholds (Android/iOS-reference parity)

    static let fwdGreatFrac: Double = 0.20
    static let fwdGoodFrac: Double = 0.45
    static let backThreshFrac: Double = 0.30
    static let latMildFrac: Double = 0.30
    static let latPoorFrac: Double = 0.60
    /// Lying detection — if the dominant axis gravity displacement fraction is
    /// >= 0.6 the head/beanie is classified as near-horizontal (lying down).
    static let lyingDeltaThresh: Double = 0.6

    // MARK: - Persistence

    private static let storageFilename = "posture_calibration.json"
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(storageFilename)
    }

    static func load() -> PostureCalibrationProfile {
        guard let data = try? Data(contentsOf: fileURL),
              let profile = try? JSONDecoder().decode(PostureCalibrationProfile.self, from: data) else {
            return PostureCalibrationProfile()
        }
        return profile
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
