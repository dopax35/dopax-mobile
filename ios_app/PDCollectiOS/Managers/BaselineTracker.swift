import Foundation
import Combine

/// Tracks the 14-day baseline the onboarding promises: "For the next 14 days,
/// every session teaches dopa-X how you move."
///
/// A day counts once the participant completes their first session on it
/// (decision D4 in the plan). Counting *days with a completed session* rather
/// than calendar days elapsed means a skipped day costs no progress — it
/// simply does not advance the helix — which matches the design's framing that
/// sessions, not dates, are what teach the model.
final class BaselineTracker: ObservableObject {

    /// Segments in the day-scale on the completion screen.
    static let totalDays = 14

    /// Days on which at least one session was completed, in the order they
    /// were recorded. Never shrinks and never contains duplicates.
    @Published private(set) var completedDays: [String]

    /// Every session finished, not one per day. The day-14 screen reports
    /// both figures ("14 days, 38 sessions") because they say different
    /// things: how long the participant has been at it, and how much they did.
    @Published private(set) var completedSessions: Int

    private let store: SessionStoring

    init(store: SessionStoring) {
        self.store = store
        self.completedDays = store.loadBaselineDays()
        self.completedSessions = store.completedSessionCount
    }

    /// 0 before the first completed session, otherwise 1...14.
    var currentDay: Int { min(completedDays.count, Self.totalDays) }

    var isComplete: Bool { completedDays.count >= Self.totalDays }

    /// The date the baseline period began, i.e. the day of the first completed
    /// session. Nil until then.
    var startDayKey: String? { completedDays.first }

    /// "Your helix grew today · day 8 of 14"
    var progressCaption: String {
        "Your helix grew today · day \(currentDay) of \(Self.totalDays)"
    }

    /// "Day 8 of 14 · dopa-X is learning you" — the Profile helix card.
    var profileCaption: String {
        "Day \(currentDay) of \(Self.totalDays) · dopa-X is learning you"
    }

    /// Whether the day-14 screen still needs to be shown. It is a one-shot:
    /// once acknowledged it must never appear again.
    var shouldPresentCompletion: Bool { isComplete && !store.hasSeenBaselineCompletion }

    func markCompletionPresented() {
        store.hasSeenBaselineCompletion = true
    }

    /// Records that a session finished on `dayKey`.
    ///
    /// Returns true only when this advanced the helix, so the caller can show
    /// "your helix grew today" for the first session of a day and stay quiet
    /// for the second and third. Calling this repeatedly for the same day is a
    /// no-op.
    @discardableResult
    func recordSessionCompleted(on dayKey: String) -> Bool {
        // The session total counts every session, so it is incremented before
        // the day check that the helix return value depends on.
        completedSessions += 1
        store.completedSessionCount = completedSessions

        guard !completedDays.contains(dayKey) else { return false }
        completedDays.append(dayKey)
        store.saveBaselineDays(completedDays)
        return true
    }

    /// True once `dayKey` has contributed a helix segment.
    func hasCompletedSession(on dayKey: String) -> Bool {
        completedDays.contains(dayKey)
    }
}
