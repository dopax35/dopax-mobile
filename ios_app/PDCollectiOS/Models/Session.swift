import Foundation

// MARK: - Session domain model
//
// The daily protocol from the Dopa-X design: three time-windowed sessions a
// day, each running the same ordered battery of nine tests. See
// DASHBOARD_SESSION_FLOW_PLAN.md.
//
// Everything here is pure Foundation and free of app singletons so the state
// machine can be unit-tested against an injected clock.

// MARK: - Period

/// One of the three daily session windows.
enum SessionPeriod: String, CaseIterable, Codable {
    case morning
    case noon
    case night

    /// Title shown on the session hub, e.g. "Evening session".
    var title: String {
        switch self {
        case .morning: return "Morning session"
        case .noon:    return "Noon session"
        case .night:   return "Evening session"
        }
    }

    /// Title on the Today card. Deliberately differs from `title` for `.night`:
    /// the card reads "Night Session" while the hub and completion copy call
    /// the same window "evening".
    var cardTitle: String {
        switch self {
        case .morning: return "Morning Session"
        case .noon:    return "Noon Session"
        case .night:   return "Night Session"
        }
    }

    /// Fills the "Your ___ session is complete." line on the completion screen.
    var completionNoun: String {
        switch self {
        case .morning: return "morning"
        case .noon:    return "noon"
        case .night:   return "evening"
        }
    }
}

// MARK: - Time of day

/// A wall-clock time with no date attached, e.g. 18:00.
struct TimeOfDay: Equatable, Comparable, Codable {
    let hour: Int
    let minute: Int

    var minutesFromMidnight: Int { hour * 60 + minute }

    init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses "18:00", tolerating surrounding whitespace.
    init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        self.init(hour: h, minute: m)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

// MARK: - Window

/// The time range a session may be started and completed in.
///
/// A window is attributed to the calendar day its *start* falls on. A window
/// whose end is at or before its start is taken to cross midnight, so
/// 22:00-01:00 belongs to the day it began.
struct SessionWindow: Equatable, Codable {
    let start: TimeOfDay
    let end: TimeOfDay

    var crossesMidnight: Bool { end.minutesFromMidnight <= start.minutesFromMidnight }

    init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// Parses the "08:00-10:00" form the profile stores. En dashes and spaces
    /// around the separator are tolerated because the value is user-editable.
    init?(_ text: String) {
        let normalised = text.replacingOccurrences(of: "–", with: "-")
        let parts = normalised.split(separator: "-")
        guard parts.count == 2,
              let start = TimeOfDay(String(parts[0])),
              let end = TimeOfDay(String(parts[1])) else { return nil }
        self.init(start: start, end: end)
    }

    /// The concrete interval for the occurrence that *starts* on `day`.
    func occurrence(startingOn day: Date, calendar: Calendar = .current) -> DateInterval {
        let midnight = calendar.startOfDay(for: day)
        let startDate = calendar.date(byAdding: .minute, value: start.minutesFromMidnight, to: midnight) ?? midnight
        let endOffset = crossesMidnight
            ? end.minutesFromMidnight + 24 * 60
            : end.minutesFromMidnight
        let endDate = calendar.date(byAdding: .minute, value: endOffset, to: midnight) ?? midnight
        return DateInterval(start: startDate, end: endDate)
    }

    /// Chosen so a window that is open exactly at its end minute still counts
    /// as open; `DateInterval.contains` is inclusive of the end instant.
    func isOpen(at now: Date, onDayOf day: Date, calendar: Calendar = .current) -> Bool {
        occurrence(startingOn: day, calendar: calendar).contains(now)
    }

    func hasClosed(at now: Date, onDayOf day: Date, calendar: Calendar = .current) -> Bool {
        now > occurrence(startingOn: day, calendar: calendar).end
    }

    func opensLater(than now: Date, onDayOf day: Date, calendar: Calendar = .current) -> Bool {
        now < occurrence(startingOn: day, calendar: calendar).start
    }

    /// Whole minutes left before the window closes, or nil once it has.
    func minutesRemaining(at now: Date, onDayOf day: Date, calendar: Calendar = .current) -> Int? {
        let end = occurrence(startingOn: day, calendar: calendar).end
        guard now <= end else { return nil }
        return Int((end.timeIntervalSince(now) / 60).rounded(.down))
    }

    /// "18:00 - 20:00", the form the hub's window chip uses.
    var displayRange: String {
        String(format: "%02d:%02d - %02d:%02d", start.hour, start.minute, end.hour, end.minute)
    }
}

// MARK: - Schedule

/// The three windows for a participant. Malformed stored values fall back to
/// the default rather than throwing: a bad string must never stop a
/// participant from running their session.
struct SessionSchedule: Equatable {
    private let windows: [SessionPeriod: SessionWindow]

    static let defaultMorning = SessionWindow(start: TimeOfDay(hour: 8, minute: 0)!,
                                              end: TimeOfDay(hour: 10, minute: 0)!)
    static let defaultNoon = SessionWindow(start: TimeOfDay(hour: 12, minute: 0)!,
                                           end: TimeOfDay(hour: 14, minute: 0)!)
    static let defaultNight = SessionWindow(start: TimeOfDay(hour: 18, minute: 0)!,
                                            end: TimeOfDay(hour: 20, minute: 0)!)

    static let `default` = SessionSchedule(morning: defaultMorning,
                                           noon: defaultNoon,
                                           night: defaultNight)

    init(morning: SessionWindow, noon: SessionWindow, night: SessionWindow) {
        windows = [.morning: morning, .noon: noon, .night: night]
    }

    /// Builds from the raw strings the profile persists, substituting the
    /// default for anything unparseable or absent.
    init(morningText: String?, noonText: String?, nightText: String?) {
        self.init(morning: morningText.flatMap(SessionWindow.init) ?? Self.defaultMorning,
                  noon: noonText.flatMap(SessionWindow.init) ?? Self.defaultNoon,
                  night: nightText.flatMap(SessionWindow.init) ?? Self.defaultNight)
    }

    subscript(period: SessionPeriod) -> SessionWindow {
        // Every period is populated by both initialisers, so the fallback is
        // unreachable; it exists to keep the subscript non-optional at call sites.
        windows[period] ?? Self.defaultMorning
    }

    /// Periods in the order their windows open, which is the order the Today
    /// screen lists them.
    var orderedPeriods: [SessionPeriod] {
        SessionPeriod.allCases.sorted {
            self[$0].start.minutesFromMidnight < self[$1].start.minutesFromMidnight
        }
    }
}

// MARK: - Tests

/// One row of the session hub. `id` deliberately reuses the identifiers the
/// app already writes to CSV and stores in GamificationManager, so the session
/// layer does not introduce a second vocabulary for the same tests.
struct SessionTest: Identifiable, Equatable {
    let id: String
    let title: String
    let durationHint: String
    let iconName: String
}

extension SessionTest {
    /// The nine tests, in the order the design lists them. Identical for all
    /// three periods (decision D3 in the plan).
    static let dailyBattery: [SessionTest] = [
        SessionTest(id: "trail_making_A", title: "Trail Making",
                    durationHint: "~30 sec · connect the numbers", iconName: "number.circle"),
        SessionTest(id: "spiral_tracing", title: "Spiral Tracing",
                    durationHint: "~20 sec · each hand", iconName: "tornado"),
        SessionTest(id: "finger_tapping", title: "Finger Tapping",
                    durationHint: "~20 sec · each hand", iconName: "hand.point.up"),
        SessionTest(id: "hand_turning", title: "Hand Rotation",
                    durationHint: "~15 sec · each hand", iconName: "arrow.clockwise"),
        SessionTest(id: "voice_test", title: "Voice Acoustic",
                    durationHint: "~15 sec · one long aaah", iconName: "mic.fill"),
        SessionTest(id: "fingers_test", title: "Free-Space Fingers",
                    durationHint: "~10 sec · in front of the camera", iconName: "hand.point.up.left.fill"),
        SessionTest(id: "facial_movement", title: "Facial Movement",
                    durationHint: "~20 sec · follow expressions", iconName: "face.smiling"),
        SessionTest(id: "leg_agility", title: "Leg Agility",
                    durationHint: "~10 sec · each leg", iconName: "figure.walk.motion"),
        SessionTest(id: "voice_recording", title: "Voice Sample",
                    durationHint: "~60 sec · describe a picture", iconName: "waveform.and.mic"),
    ]

    static func test(id: String) -> SessionTest? {
        dailyBattery.first { $0.id == id }
    }
}

// MARK: - Daily tasks

/// The secondary tasks under the session cards on Today. A task leaves the row
/// once it is done for the day, which is why the design's "tasks completed"
/// variant shows only one card.
enum DailyTask: String, CaseIterable, Codable, Identifiable {
    case questionnaire
    case medication

    var id: String { rawValue }

    var title: String {
        switch self {
        case .questionnaire: return "Daily questionnaire"
        case .medication:    return "Log medication"
        }
    }

    var subtitle: String {
        switch self {
        case .questionnaire: return "5 min"
        case .medication:    return "Track intake"
        }
    }

    var iconName: String {
        switch self {
        case .questionnaire: return "list.clipboard"
        case .medication:    return "pills"
        }
    }
}

// MARK: - Results

/// What a finished test contributes to the hub row, e.g. "9.4 seconds".
struct SessionTestResult: Codable, Equatable {
    let testId: String
    let completedAt: Date
    let summary: String
}

// MARK: - State

/// How a session card and hub present themselves at a given moment.
enum SessionState: Equatable {
    /// The window has not opened yet today.
    case locked
    /// The window is open and no test has been completed.
    case available
    /// The window is open and at least one test is done.
    case inProgress
    /// Every test in the battery is done.
    case completed
    /// The window closed before the battery was finished.
    case missed

    var isActionable: Bool { self == .available || self == .inProgress }
}

// MARK: - Progress

/// A single session's persisted progress. Resuming a session after the app is
/// killed restores this verbatim.
struct SessionProgress: Codable, Equatable {
    /// "yyyy-MM-dd" of the day the window started on.
    let day: String
    let period: SessionPeriod
    private(set) var startedAt: Date?
    private(set) var results: [String: SessionTestResult]

    /// A gap longer than this between two finished tests is read as the
    /// participant having put the phone down, and is excluded from the
    /// duration shown on the completion screen.
    static let pauseThreshold: TimeInterval = 5 * 60

    init(day: String, period: SessionPeriod, startedAt: Date? = nil,
         results: [String: SessionTestResult] = [:]) {
        self.day = day
        self.period = period
        self.startedAt = startedAt
        self.results = results
    }

    var battery: [SessionTest] { SessionTest.dailyBattery }

    var completedCount: Int { results.count }

    var totalCount: Int { battery.count }

    var hasStarted: Bool { startedAt != nil || !results.isEmpty }

    var isComplete: Bool { battery.allSatisfy { results[$0.id] != nil } }

    /// The test the hub highlights with a Start button, or nil when finished.
    var nextTest: SessionTest? { battery.first { results[$0.id] == nil } }

    func result(for testId: String) -> SessionTestResult? { results[testId] }

    /// Time actually spent testing, with pauses excluded. Drives the
    /// "4 minutes" chip on the completion screen.
    var activeDuration: TimeInterval {
        let stamps = ([startedAt].compactMap { $0 } + results.values.map(\.completedAt)).sorted()
        guard stamps.count > 1 else { return 0 }
        return zip(stamps, stamps.dropFirst()).reduce(0) { total, pair in
            let gap = pair.1.timeIntervalSince(pair.0)
            return gap <= Self.pauseThreshold ? total + gap : total
        }
    }

    /// Records a finished test. Re-running a test overwrites its previous
    /// result so a repeated attempt cannot inflate the completed count.
    mutating func record(testId: String, summary: String, at date: Date) {
        guard SessionTest.test(id: testId) != nil else { return }
        if startedAt == nil { startedAt = date }
        results[testId] = SessionTestResult(testId: testId, completedAt: date, summary: summary)
    }

    /// Marks the session as begun without completing anything, so a
    /// participant who opens the hub and backs out is still resumable.
    mutating func markStarted(at date: Date) {
        if startedAt == nil { startedAt = date }
    }
}

// MARK: - Day keys

/// "yyyy-MM-dd" keys, matching the format the rest of the app uses for daily
/// data directories.
///
/// Built from date components rather than a shared DateFormatter: the
/// formatter would have to be re-pointed at the caller's timezone on every
/// call, which is not safe to do from more than one thread.
enum SessionDay {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight on `key` in the calendar's timezone.
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }
}
