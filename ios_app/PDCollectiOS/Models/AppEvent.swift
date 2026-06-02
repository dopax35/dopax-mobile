import Foundation

/// An app-lifecycle or foreground/background event — mirrors Android's apps.csv format.
struct AppEvent {
    let timestampMs: Int64   // epoch millis
    let event: String        // "foreground", "background", "active", "inactive"
    let bundleId: String     // always com.pdcollect.ios on iOS (system-wide not possible without entitlement)
    let durationMs: Int64    // time spent in previous state; 0 when first event

    var csvRow: String {
        "\(timestampMs),\(event),\(bundleId),\(durationMs)\n"
    }
}
