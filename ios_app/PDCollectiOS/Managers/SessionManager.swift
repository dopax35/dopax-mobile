import Foundation
import Combine

/// What changed as a result of finishing a test, so the caller knows which
/// screen to show next.
struct SessionOutcome: Equatable {
    /// The last remaining test in the battery was just finished.
    let sessionCompleted: Bool
    /// This was the first completed session of the day, so the helix advanced.
    let helixGrew: Bool
    /// The 14th baseline day was just reached.
    let baselineCompleted: Bool

    static let none = SessionOutcome(sessionCompleted: false, helixGrew: false, baselineCompleted: false)
}

/// The test the participant launched from a hub.
///
/// Test screens are shared with the Tests tab and know nothing about
/// sessions, so the hub records what it opened and the manager uses that to
/// attribute the completion signal when it arrives. Without it, a test run
/// for practice from the Tests tab would silently count toward the protocol.
struct SessionRun: Equatable {
    let period: SessionPeriod
    let testId: String
}

/// Owns the state of today's three sessions.
///
/// This is the single source of truth for "what is the participant supposed to
/// do right now". The Today screen, the session hub, and the completion screen
/// all read from here rather than deriving window arithmetic of their own.
///
/// The clock and calendar are injected so the state machine is testable, and
/// so a timezone change or a day rollover can be reproduced deterministically.
final class SessionManager: ObservableObject {

    // MARK: - Published state

    /// Progress for each period of its current session day. Rebuilt by
    /// `refresh()` whenever the day may have rolled over.
    @Published private(set) var progressByPeriod: [SessionPeriod: SessionProgress] = [:]

    /// Secondary tasks already done today.
    @Published private(set) var completedTasks: Set<DailyTask> = []

    /// Bumped whenever derived state may have changed, so views observing this
    /// manager re-evaluate window countdowns.
    @Published private(set) var lastRefresh: Date

    /// The test currently open from a hub, or nil when nothing is running
    /// inside a session.
    @Published private(set) var activeRun: SessionRun?

    /// What the most recent completion changed. The hub reads this to decide
    /// between the completion screen and the once-only baseline screen, then
    /// clears it. Nil at rest.
    @Published private(set) var lastOutcome: SessionOutcome?

    let baseline: BaselineTracker

    // MARK: - Configuration

    private(set) var schedule: SessionSchedule
    private let store: SessionStoring
    private let calendar: Calendar
    private let now: () -> Date

    // MARK: - Init

    init(schedule: SessionSchedule = .default,
         store: SessionStoring = UserDefaultsSessionStore(),
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.schedule = schedule
        self.store = store
        self.calendar = calendar
        self.now = now
        self.baseline = BaselineTracker(store: store)
        self.lastRefresh = now()
        refresh()
    }

    /// Applies windows edited in Profile without rebuilding the manager.
    func updateSchedule(_ schedule: SessionSchedule) {
        self.schedule = schedule
        refresh()
    }

    // MARK: - Day resolution

    /// The calendar day whose session window is relevant for `period` right now.
    ///
    /// Normally today. A window configured to cross midnight (say 22:00-01:00)
    /// belongs to the day it started, so shortly after midnight the still-open
    /// session is yesterday's.
    func activeDayKey(for period: SessionPeriod) -> String {
        let current = now()
        let window = schedule[period]
        if window.crossesMidnight {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: current) ?? current
            if window.isOpen(at: current, onDayOf: yesterday, calendar: calendar) {
                return SessionDay.key(for: yesterday, calendar: calendar)
            }
        }
        return SessionDay.key(for: current, calendar: calendar)
    }

    /// Today's key, used for helix accounting.
    var todayKey: String { SessionDay.key(for: now(), calendar: calendar) }

    // MARK: - Reading state

    /// Reloads every period's progress from the store. Safe to call often —
    /// on foreground, on appear, and on a minute tick.
    func refresh() {
        var rebuilt: [SessionPeriod: SessionProgress] = [:]
        for period in SessionPeriod.allCases {
            let day = activeDayKey(for: period)
            rebuilt[period] = store.loadProgress(day: day, period: period)
                ?? SessionProgress(day: day, period: period)
        }
        progressByPeriod = rebuilt
        completedTasks = Set(store.loadCompletedTasks(day: todayKey).compactMap(DailyTask.init))
        lastRefresh = now()
    }

    // MARK: - Daily tasks

    func isTaskComplete(_ task: DailyTask) -> Bool { completedTasks.contains(task) }

    /// Tasks still to do today, in declaration order. A finished task leaves
    /// the Today row entirely rather than showing a done state.
    var outstandingTasks: [DailyTask] {
        DailyTask.allCases.filter { !completedTasks.contains($0) }
    }

    /// Called from the questionnaire and medication flows once they save.
    func markTask(_ task: DailyTask) {
        guard !completedTasks.contains(task) else { return }
        completedTasks.insert(task)
        store.saveCompletedTasks(completedTasks.map(\.rawValue), day: todayKey)
        lastRefresh = now()
    }

    func progress(for period: SessionPeriod) -> SessionProgress {
        progressByPeriod[period] ?? SessionProgress(day: activeDayKey(for: period), period: period)
    }

    func state(for period: SessionPeriod) -> SessionState {
        let progress = progress(for: period)
        if progress.isComplete { return .completed }

        let window = schedule[period]
        guard let day = SessionDay.date(from: progress.day, calendar: calendar) else { return .locked }
        let current = now()

        if window.isOpen(at: current, onDayOf: day, calendar: calendar) {
            return progress.hasStarted ? .inProgress : .available
        }
        if window.hasClosed(at: current, onDayOf: day, calendar: calendar) {
            return .missed
        }
        return .locked
    }

    /// Minutes before the current window closes, or nil when it is not open.
    func minutesRemaining(for period: SessionPeriod) -> Int? {
        guard state(for: period).isActionable else { return nil }
        guard let day = SessionDay.date(from: progress(for: period).day, calendar: calendar) else { return nil }
        return schedule[period].minutesRemaining(at: now(), onDayOf: day, calendar: calendar)
    }

    /// "18:00 - 20:00 · 38 min left" for the hub's window chip, dropping the
    /// countdown once the window is not open.
    func windowCaption(for period: SessionPeriod) -> String {
        let range = schedule[period].displayRange
        guard let minutes = minutesRemaining(for: period) else { return range }
        return "\(range) · \(minutes) min left"
    }

    /// The second line of a Today card. Each state answers a different
    /// question: when it opens, how much is left, how long it took.
    func cardSubtitle(for period: SessionPeriod) -> String {
        let progress = progress(for: period)
        switch state(for: period) {
        case .locked:
            return schedule[period].displayRange

        case .available:
            guard let minutes = minutesRemaining(for: period) else {
                return schedule[period].displayRange
            }
            return "\(progress.totalCount) tests · \(minutes) min left"

        case .inProgress:
            let remaining = progress.totalCount - progress.completedCount
            return remaining == 1 ? "1 test remaining" : "\(remaining) tests remaining"

        case .completed:
            let duration = progress.activeDuration
            guard duration > 0 else { return "Completed" }
            return "Completed in \(Self.durationText(duration))"

        case .missed:
            return "Missed · \(progress.completedCount) of \(progress.totalCount) done"
        }
    }

    /// "60 seconds" / "4 minutes". Seconds up to a minute and a half, so a
    /// quick session reads honestly instead of rounding to "1 minute".
    static func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 90 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
        let minutes = Int((Double(seconds) / 60).rounded())
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    /// The period the participant can act on now, in window order.
    var actionablePeriod: SessionPeriod? {
        schedule.orderedPeriods.first { state(for: $0).isActionable }
    }

    /// The card the Today screen expands: whatever is actionable, otherwise
    /// the next window due to open. Nil once the day holds nothing to do.
    var focusedPeriod: SessionPeriod? {
        actionablePeriod ?? schedule.orderedPeriods.first { state(for: $0) == .locked }
    }

    // MARK: - Mutating

    /// Marks a session as begun so backing out of the hub still resumes.
    /// Ignored unless the window is open.
    @discardableResult
    func beginSession(_ period: SessionPeriod) -> Bool {
        guard state(for: period).isActionable else { return false }
        var progress = progress(for: period)
        progress.markStarted(at: now())
        persist(progress)
        return true
    }

    /// Records a finished test against an open session.
    ///
    /// Returns nil when `period` is not actionable, which is what keeps a test
    /// run from the Tests tab outside its window from counting toward a
    /// session (decision D5).
    @discardableResult
    func recordTestCompleted(_ testId: String,
                             in period: SessionPeriod,
                             summary: String) -> SessionOutcome? {
        guard state(for: period).isActionable else { return nil }
        guard SessionTest.test(id: testId) != nil else { return nil }

        var progress = progress(for: period)
        let wasComplete = progress.isComplete
        progress.record(testId: testId, summary: summary, at: now())
        persist(progress)

        guard progress.isComplete, !wasComplete else { return SessionOutcome.none }

        let wasBaselineComplete = baseline.isComplete
        let helixGrew = baseline.recordSessionCompleted(on: todayKey)
        let outcome = SessionOutcome(sessionCompleted: true,
                                     helixGrew: helixGrew,
                                     baselineCompleted: baseline.isComplete && !wasBaselineComplete)
        lastOutcome = outcome
        return outcome
    }

    /// Called once the hub has shown whatever `lastOutcome` called for.
    func clearOutcome() {
        lastOutcome = nil
    }

    // MARK: - Running a test from the hub

    /// Opens `testId` as part of `period`, so the completion signal the test
    /// screen emits later can be attributed to this session.
    func beginTest(_ testId: String, in period: SessionPeriod) {
        guard state(for: period).isActionable, SessionTest.test(id: testId) != nil else { return }
        activeRun = SessionRun(period: period, testId: testId)
    }

    /// Clears the attribution when the test screen closes. Safe to call twice
    /// — closing after a completion has already been recorded is the normal
    /// path, not an error.
    func endTestRun() {
        activeRun = nil
    }

    /// Bridges `GamificationManager`, which every test screen already calls
    /// when it saves, into the session layer.
    ///
    /// Returns nil unless the finished test is the one this session opened,
    /// which is what keeps practice runs from the Tests tab out of the
    /// protocol (decision D5).
    @discardableResult
    func testDidComplete(testId: String, score: Double) -> SessionOutcome? {
        guard let run = activeRun, run.testId == testId else { return nil }
        guard let test = SessionTest.test(id: testId) else { return nil }
        return recordTestCompleted(testId,
                                   in: run.period,
                                   summary: test.completedSummary(score: score))
    }

    private func persist(_ progress: SessionProgress) {
        store.save(progress)
        progressByPeriod[progress.period] = progress
        lastRefresh = now()
    }
}
