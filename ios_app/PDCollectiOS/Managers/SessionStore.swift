import Foundation

/// Persistence for the session layer.
///
/// Kept behind a protocol so the state machine can be exercised against an
/// in-memory double. Session state is local-only and additive: it never
/// touches the CSV files, upload markers, or profile that the study pipeline
/// depends on.
protocol SessionStoring: AnyObject {
    func loadProgress(day: String, period: SessionPeriod) -> SessionProgress?
    func save(_ progress: SessionProgress)

    /// Ordered "yyyy-MM-dd" keys of days on which at least one session was
    /// completed. Order is the order they were recorded.
    func loadBaselineDays() -> [String]
    func saveBaselineDays(_ days: [String])

    /// Total sessions finished across the whole baseline period. Counts every
    /// session, not one per day, which is what the day-14 screen's
    /// "14 days, 38 sessions" line reports.
    var completedSessionCount: Int { get set }

    /// Raw values of the daily tasks already done on `day`.
    func loadCompletedTasks(day: String) -> [String]
    func saveCompletedTasks(_ taskIds: [String], day: String)

    var hasSeenBaselineCompletion: Bool { get set }
}

// MARK: - UserDefaults

/// Production store. Keys are prefixed so they cannot collide with the
/// existing profile and gamification entries in the same suite.
final class UserDefaultsSessionStore: SessionStoring {

    private enum Keys {
        static let prefix = "session_"
        static let baselineDays = "session_baseline_days"
        static let seenBaselineCompletion = "session_baseline_completion_seen"
        static let completedSessions = "session_completed_count"

        static func progress(day: String, period: SessionPeriod) -> String {
            "\(prefix)progress_\(day)_\(period.rawValue)"
        }

        static func tasks(day: String) -> String { "\(prefix)tasks_\(day)" }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadProgress(day: String, period: SessionPeriod) -> SessionProgress? {
        guard let data = defaults.data(forKey: Keys.progress(day: day, period: period)) else { return nil }
        return try? decoder.decode(SessionProgress.self, from: data)
    }

    func save(_ progress: SessionProgress) {
        guard let data = try? encoder.encode(progress) else { return }
        defaults.set(data, forKey: Keys.progress(day: progress.day, period: progress.period))
    }

    func loadBaselineDays() -> [String] {
        defaults.stringArray(forKey: Keys.baselineDays) ?? []
    }

    func saveBaselineDays(_ days: [String]) {
        defaults.set(days, forKey: Keys.baselineDays)
    }

    func loadCompletedTasks(day: String) -> [String] {
        defaults.stringArray(forKey: Keys.tasks(day: day)) ?? []
    }

    func saveCompletedTasks(_ taskIds: [String], day: String) {
        defaults.set(taskIds, forKey: Keys.tasks(day: day))
    }

    var hasSeenBaselineCompletion: Bool {
        get { defaults.bool(forKey: Keys.seenBaselineCompletion) }
        set { defaults.set(newValue, forKey: Keys.seenBaselineCompletion) }
    }

    var completedSessionCount: Int {
        get { defaults.integer(forKey: Keys.completedSessions) }
        set { defaults.set(newValue, forKey: Keys.completedSessions) }
    }
}

// MARK: - In-memory

/// Test double, also useful for SwiftUI previews.
final class InMemorySessionStore: SessionStoring {
    private var progress: [String: SessionProgress] = [:]
    private var baselineDays: [String] = []
    private var tasks: [String: [String]] = [:]
    var hasSeenBaselineCompletion = false
    var completedSessionCount = 0

    init() {}

    private func key(_ day: String, _ period: SessionPeriod) -> String { "\(day)_\(period.rawValue)" }

    func loadProgress(day: String, period: SessionPeriod) -> SessionProgress? {
        progress[key(day, period)]
    }

    func save(_ progress: SessionProgress) {
        self.progress[key(progress.day, progress.period)] = progress
    }

    func loadBaselineDays() -> [String] { baselineDays }

    func saveBaselineDays(_ days: [String]) { baselineDays = days }

    func loadCompletedTasks(day: String) -> [String] { tasks[day] ?? [] }

    func saveCompletedTasks(_ taskIds: [String], day: String) { tasks[day] = taskIds }
}
