import Foundation

/// Questionnaire response — schema matches Android's questionnaire.csv exactly.
/// Android header: timestamp_ms,date,time,q1_text,q2_score,q3_score,q4_score,q5_score,
///                 q6_sleep_yesno,q6_sleep_score,q6_smell_yesno,q6_smell_score,
///                 q6_const_yesno,q6_const_score,q6_anxiety_yesno,q6_anxiety_score,
///                 q6_depr_yesno,q6_depr_score
struct QuestionnaireResponse {
    let timestampMs: Int64      // epoch milliseconds — matches Android timestamp_ms
    let q1Text: String          // free text: how are you feeling today?
    let q2Score: Int            // motor symptoms 1–5
    let q3Score: Int            // motor function 1–5
    let q4Score: Int            // sleep quality 1–5
    let q5Score: Int            // mood 1–5
    let q6SleepYesNo: Bool      // sleep problems yes/no
    let q6SleepScore: Int       // sleep problem severity 1–5
    let q6SmellYesNo: Bool      // smell problems yes/no
    let q6SmellScore: Int       // smell problem severity 1–5
    let q6ConstYesNo: Bool      // constipation yes/no
    let q6ConstScore: Int       // constipation severity 1–5
    let q6AnxietyYesNo: Bool    // anxiety yes/no
    let q6AnxietyScore: Int     // anxiety severity 1–5
    let q6DeprYesNo: Bool       // depression yes/no
    let q6DeprScore: Int        // depression severity 1–5

    var csvRow: String {
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000.0)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let dateStr = dateFmt.string(from: date)
        let timeStr = timeFmt.string(from: date)
        let safeQ1 = q1Text.replacingOccurrences(of: ",", with: ";")
                           .replacingOccurrences(of: "\n", with: " ")

        return "\(timestampMs),\(dateStr),\(timeStr),\(safeQ1),\(q2Score),\(q3Score),\(q4Score),\(q5Score)," +
               "\(q6SleepYesNo),\(q6SleepScore),\(q6SmellYesNo),\(q6SmellScore)," +
               "\(q6ConstYesNo),\(q6ConstScore),\(q6AnxietyYesNo),\(q6AnxietyScore)," +
               "\(q6DeprYesNo),\(q6DeprScore)\n"
    }
}
