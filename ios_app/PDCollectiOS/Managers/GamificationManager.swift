import Foundation

// MARK: - GamificationManager
// Tracks user compliance, streaks, personal bests, and completion state.

class GamificationManager: ObservableObject {

    // MARK: - Keys
    private enum Keys {
        static let streakCount    = "gm_streak_count"
        static let lastTestDate   = "gm_last_test_date"
        static let personalBestPrefix = "gm_pb_"
        static func pbKey(_ type: String) -> String { personalBestPrefix + type }
        static func lastCompletedKey(_ type: String) -> String { "gm_last_\(type)" }
    }

    private let ud = UserDefaults.standard

    // MARK: - Published
    @Published var currentStreak: Int = 0
    @Published var todayCompletedTypes: Set<String> = []

    // MARK: - Init
    init() {
        refresh()
    }

    // MARK: - Refresh / Load
    func refresh() {
        currentStreak = computeStreak()
        todayCompletedTypes = loadTodayCompleted()
    }

    // MARK: - Record a completed test
    /// Call this immediately after saving a test result.
    func recordCompletion(testType: String, score: Double, higherIsBetter: Bool = true) {
        let typeCompletionKey = Keys.lastCompletedKey(testType)

        // Update last-completed timestamp
        ud.set(Date(), forKey: typeCompletionKey)

        // Update streak
        let lastDate = ud.object(forKey: Keys.lastTestDate) as? Date
        let today = Calendar.current.startOfDay(for: Date())
        if let last = lastDate {
            let lastDay = Calendar.current.startOfDay(for: last)
            let diff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                // Consecutive day — extend streak
                ud.set(currentStreak + 1, forKey: Keys.streakCount)
            } else if diff > 1 {
                // Streak broken
                ud.set(1, forKey: Keys.streakCount)
            }
            // diff == 0 means same day, don't increment again
        } else {
            ud.set(1, forKey: Keys.streakCount)
        }
        ud.set(Date(), forKey: Keys.lastTestDate)

        // Update personal best
        let pbKey = Keys.pbKey(testType)
        let currentPB = ud.double(forKey: pbKey)
        let isNewPB: Bool
        if higherIsBetter {
            isNewPB = score > currentPB
        } else {
            isNewPB = currentPB == 0 || score < currentPB
        }
        if isNewPB { ud.set(score, forKey: pbKey) }

        // Refresh published state
        refresh()
    }

    // MARK: - Queries

    func isPersonalBest(testType: String, score: Double, higherIsBetter: Bool = true) -> Bool {
        let pb = ud.double(forKey: Keys.pbKey(testType))
        if pb == 0 { return true }
        return higherIsBetter ? score > pb : score < pb
    }

    func personalBest(testType: String) -> Double? {
        let v = ud.double(forKey: Keys.pbKey(testType))
        return v == 0 ? nil : v
    }

    /// Returns how many days ago a test type was last completed (nil = never)
    func daysSinceLastCompleted(testType: String) -> Int? {
        guard let last = ud.object(forKey: Keys.lastCompletedKey(testType)) as? Date else { return nil }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: last),
            to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return days
    }

    func isCompletedToday(testType: String) -> Bool {
        todayCompletedTypes.contains(testType)
    }

    // Streak emoji / color helper
    var streakEmoji: String {
        switch currentStreak {
        case 0:     return "💤"
        case 1:     return "✨"
        case 2...4: return "🔥"
        case 5...9: return "⚡️"
        default:    return "🏆"
        }
    }

    var streakColor: String {  // name of SwiftUI Color
        switch currentStreak {
        case 0:     return "gray"
        case 1...2: return "yellow"
        case 3...6: return "orange"
        default:    return "red"
        }
    }

    /// Motivational message based on streak
    var motivationalMessage: String {
        switch currentStreak {
        case 0:    return "Start your streak today! Every test helps."
        case 1:    return "Great start! Come back tomorrow to build your streak."
        case 2:    return "Two days running! You're building a habit."
        case 3...5: return "🔥 \(currentStreak)-day streak! Your data is getting more valuable."
        case 6...9: return "⚡️ Incredible — \(currentStreak) days straight! Keep going."
        default:   return "🏆 \(currentStreak)-day streak! You're a champion."
        }
    }

    /// Trend message comparing current score to personal best
    func trendMessage(testType: String, score: Double, higherIsBetter: Bool = true) -> String {
        guard let pb = personalBest(testType: testType) else { return "First attempt — baseline set!" }
        if isPersonalBest(testType: testType, score: score, higherIsBetter: higherIsBetter) {
            return "🏅 New personal best!"
        }
        let pct = abs(score - pb) / (pb + 1e-12) * 100
        if higherIsBetter {
            return score >= pb * 0.95 ? "↑ Near your best" : String(format: "↓ %.0f%% below best", pct)
        } else {
            return score <= pb * 1.05 ? "↓ Near your best" : String(format: "↑ %.0f%% above best", pct)
        }
    }

    // MARK: - Private Helpers

    private func dateKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func computeStreak() -> Int {
        ud.integer(forKey: Keys.streakCount)
    }

    private func loadTodayCompleted() -> Set<String> {
        let today = Calendar.current.startOfDay(for: Date())
        let types = ["finger_tapping", "hand_turning", "spiral_tracing", "leg_agility",
                     "trail_making_A", "trail_making_B"]
        return Set(types.filter { type in
            guard let last = ud.object(forKey: Keys.lastCompletedKey(type)) as? Date else { return false }
            return Calendar.current.startOfDay(for: last) == today
        })
    }
}
