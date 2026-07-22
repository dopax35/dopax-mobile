import Foundation

/// A gaze and pupil tracking sample — logs left and right eye gaze coordinates/angles
/// to detect eye movement jumps (saccades) and inter-eye asymmetry over time.
struct GazeSample {
    let timestampMs: Int64       // epoch millis
    let leftGazeX: Float         // left pupil gaze horizontal component (yaw angle / coordinate)
    let leftGazeY: Float         // left pupil gaze vertical component (pitch angle / coordinate)
    let rightGazeX: Float        // right pupil gaze horizontal component (yaw angle / coordinate)
    let rightGazeY: Float        // right pupil gaze vertical component (pitch angle / coordinate)
    let leftBlink: Float         // left eye open probability / blink state (0.0 = closed, 1.0 = open)
    let rightBlink: Float        // right eye open probability / blink state (0.0 = closed, 1.0 = open)
    let lookAtX: Float           // 3D look-at point X (camera / face space)
    let lookAtY: Float           // 3D look-at point Y
    let lookAtZ: Float           // 3D look-at point Z
    let method: String           // "arkit_truedepth" or "vision_landmarks_fallback"

    var csvRow: String {
        let posix = Locale(identifier: "en_US_POSIX")
        return "\(timestampMs),"
        + "\(safeFormat(leftGazeX, format: "%.4f", locale: posix)),"
        + "\(safeFormat(leftGazeY, format: "%.4f", locale: posix)),"
        + "\(safeFormat(rightGazeX, format: "%.4f", locale: posix)),"
        + "\(safeFormat(rightGazeY, format: "%.4f", locale: posix)),"
        + "\(safeFormat(leftBlink, format: "%.3f", locale: posix)),"
        + "\(safeFormat(rightBlink, format: "%.3f", locale: posix)),"
        + "\(safeFormat(lookAtX, format: "%.4f", locale: posix)),"
        + "\(safeFormat(lookAtY, format: "%.4f", locale: posix)),"
        + "\(safeFormat(lookAtZ, format: "%.4f", locale: posix)),"
        + "\(method)\n"
    }

    private func safeFormat(_ val: Float, format: String, locale: Locale) -> String {
        guard val.isFinite else { return "0.0000" }
        return String(format: format, locale: locale, val)
    }
}
