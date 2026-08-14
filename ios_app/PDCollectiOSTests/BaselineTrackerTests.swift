import XCTest
@testable import PDCollectiOS

final class BaselineTrackerTests: XCTestCase {

    private func makeTracker() -> (BaselineTracker, SessionStoring) {
        let store = InMemorySessionStore()
        return (BaselineTracker(store: store), store)
    }

    private func dayKeys(_ count: Int) -> [String] {
        (1...count).map { String(format: "2026-07-%02d", $0) }
    }

    // MARK: - Advancement

    func testHelixStartsAtZero() {
        let (tracker, _) = makeTracker()
        XCTAssertEqual(tracker.currentDay, 0)
        XCTAssertNil(tracker.startDayKey)
        XCTAssertFalse(tracker.isComplete)
    }

    func testFirstSessionOfADayAdvancesTheHelix() {
        let (tracker, _) = makeTracker()
        XCTAssertTrue(tracker.recordSessionCompleted(on: "2026-07-26"))
        XCTAssertEqual(tracker.currentDay, 1)
    }

    /// Decision D4: the second and third sessions of a day add data but not a
    /// helix segment.
    func testLaterSessionsOnTheSameDayDoNotAdvanceTheHelix() {
        let (tracker, _) = makeTracker()
        tracker.recordSessionCompleted(on: "2026-07-26")

        XCTAssertFalse(tracker.recordSessionCompleted(on: "2026-07-26"))
        XCTAssertFalse(tracker.recordSessionCompleted(on: "2026-07-26"))
        XCTAssertEqual(tracker.currentDay, 1)
    }

    /// A skipped day costs no progress; it simply does not advance the helix.
    func testSkippedDaysDoNotConsumeSegments() {
        let (tracker, _) = makeTracker()
        tracker.recordSessionCompleted(on: "2026-07-01")
        tracker.recordSessionCompleted(on: "2026-07-09")

        XCTAssertEqual(tracker.currentDay, 2)
        XCTAssertEqual(tracker.startDayKey, "2026-07-01")
    }

    func testHelixNeverExceedsFourteen() {
        let (tracker, _) = makeTracker()
        dayKeys(20).forEach { tracker.recordSessionCompleted(on: $0) }

        XCTAssertEqual(tracker.currentDay, 14)
        XCTAssertTrue(tracker.isComplete)
    }

    func testCompletesOnTheFourteenthDay() {
        let (tracker, _) = makeTracker()
        dayKeys(13).forEach { tracker.recordSessionCompleted(on: $0) }
        XCTAssertFalse(tracker.isComplete)

        tracker.recordSessionCompleted(on: "2026-07-14")
        XCTAssertTrue(tracker.isComplete)
        XCTAssertEqual(tracker.currentDay, 14)
    }

    // MARK: - Persistence

    func testProgressSurvivesARebuild() {
        let store = InMemorySessionStore()
        let tracker = BaselineTracker(store: store)
        dayKeys(3).forEach { tracker.recordSessionCompleted(on: $0) }

        let revived = BaselineTracker(store: store)
        XCTAssertEqual(revived.currentDay, 3)
        XCTAssertEqual(revived.startDayKey, "2026-07-01")
    }

    // MARK: - Completion screen

    func testCompletionScreenIsShownOnceAndOnlyOnce() {
        let (tracker, _) = makeTracker()
        dayKeys(14).forEach { tracker.recordSessionCompleted(on: $0) }

        XCTAssertTrue(tracker.shouldPresentCompletion)
        tracker.markCompletionPresented()
        XCTAssertFalse(tracker.shouldPresentCompletion)
    }

    func testCompletionScreenStaysDismissedAcrossRebuilds() {
        let store = InMemorySessionStore()
        let tracker = BaselineTracker(store: store)
        dayKeys(14).forEach { tracker.recordSessionCompleted(on: $0) }
        tracker.markCompletionPresented()

        XCTAssertFalse(BaselineTracker(store: store).shouldPresentCompletion)
    }

    func testCompletionScreenIsNotOfferedEarly() {
        let (tracker, _) = makeTracker()
        dayKeys(13).forEach { tracker.recordSessionCompleted(on: $0) }
        XCTAssertFalse(tracker.shouldPresentCompletion)
    }

    // MARK: - Copy

    func testCaptionsMatchTheDesign() {
        let (tracker, _) = makeTracker()
        dayKeys(8).forEach { tracker.recordSessionCompleted(on: $0) }

        XCTAssertEqual(tracker.progressCaption, "Your helix grew today · day 8 of 14")
        XCTAssertEqual(tracker.profileCaption, "Day 8 of 14 · dopa-X is learning you")
    }
}
