import Foundation

/// A single in-app touch or scroll event — mirrors Android's touch.csv format.
struct TouchEvent {
    let timestampMs: Int64   // epoch millis
    let action: String       // "tap", "scroll_x", "scroll_y"
    let x: Float             // screen x (points)
    let y: Float             // screen y (points)
    let pressure: Float      // UITouch.force / maximumPossibleForce (0.0–1.0); 0 if unavailable
    let tapIntervalMs: Int64 // ms since the previous tap (0 for first tap)

    var csvRow: String {
        // en_US_POSIX: force "." decimals regardless of device region — see
        // the note in PhysicalActivityEvent.csvRow for why this matters.
        let posix = Locale(identifier: "en_US_POSIX")
        return "\(timestampMs),\(action),\(String(format: "%.1f", locale: posix, x)),\(String(format: "%.1f", locale: posix, y)),"
        + "\(String(format: "%.3f", locale: posix, pressure)),\(tapIntervalMs)\n"
    }
}
