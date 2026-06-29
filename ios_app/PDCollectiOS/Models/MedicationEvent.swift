import Foundation

/// A medication intake event — when the user took a specific medication.
/// Matches Android's medication.csv format.
struct MedicationEvent {
    let timestampMs: Int64   // when the event was recorded
    let takenMs: Int64       // user-selected time of intake
    let medName: String
    let dosage: String

    var csvRow: String {
        "\(timestampMs),\(takenMs),\(medName),\(dosage)\n"
    }
}
