import Foundation

struct QuestionnaireResponse {
    let timestamp: Date
    let symptomsSeverity: Int   // 1–5
    let motorFunction: Int      // 1–5
    let sleepQuality: Int       // 1–5
    let moodRating: Int         // 1–5
    let overallWellbeing: Int   // 1–5
    let notes: String

    var csvRow: String {
        let ts = ISO8601DateFormatter().string(from: timestamp)
        let safeNotes = notes.replacingOccurrences(of: "\"", with: "\"\"")
        return "\(ts),\(symptomsSeverity),\(motorFunction),\(sleepQuality),\(moodRating),\(overallWellbeing),\"\(safeNotes)\"\n"
    }
}
