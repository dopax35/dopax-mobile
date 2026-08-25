import XCTest
@testable import PDCollectiOS

/// The bridge between a test screen finishing and a session advancing.
///
/// This is the seam where a practice run from the Tests tab could quietly
/// count toward the protocol, which would corrupt what a "completed session"
/// means in the study data. Most of what follows is about that not happening.
final class SessionRunTests: XCTestCase {

    private let calendar = SessionFixture.calendar

    private func makeManager(at date: Date,
                             store: SessionStoring = InMemorySessionStore())
        -> (SessionManager, TestClock, SessionStoring) {
        let clock = TestClock(date)
        let manager = SessionManager(schedule: .default,
                                     store: store,
                                     calendar: calendar,
                                     now: { clock.now })
        return (manager, clock, store)
    }

    /// Noon, so exactly one window is open.
    private func noon() -> (SessionManager, TestClock, SessionStoring) {
        makeManager(at: SessionFixture.date(2026, 7, 26, 13, 30))
    }

    // MARK: - Attribution

    func testCompletionCountsOnlyForTheTestTheHubLaunched() {
        let (manager, _, _) = noon()
        manager.beginTest("trail_making_A", in: .noon)

        XCTAssertNotNil(manager.testDidComplete(testId: "trail_making_A", score: 9.4))
        XCTAssertEqual(manager.progress(for: .noon).completedCount, 1)
    }

    func testACompletionFromADifferentTestIsIgnored() {
        let (manager, _, _) = noon()
        manager.beginTest("trail_making_A", in: .noon)

        XCTAssertNil(manager.testDidComplete(testId: "finger_tapping", score: 12))
        XCTAssertEqual(manager.progress(for: .noon).completedCount, 0)
    }

    func testAPracticeRunOutsideASessionDoesNotAdvanceAnything() {
        let (manager, _, _) = noon()

        XCTAssertNil(manager.testDidComplete(testId: "spiral_tracing", score: 1))
        XCTAssertEqual(manager.progress(for: .noon).completedCount, 0)
    }

    func testEndingTheRunStopsLaterCompletionsFromCounting() {
        let (manager, _, _) = noon()
        manager.beginTest("voice_test", in: .noon)
        manager.endTestRun()

        XCTAssertNil(manager.testDidComplete(testId: "voice_test", score: 3))
        XCTAssertEqual(manager.progress(for: .noon).completedCount, 0)
    }

    func testALockedPeriodCannotBeginATest() {
        // 06:00 — before any window opens.
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        manager.beginTest("trail_making_A", in: .morning)

        XCTAssertNil(manager.testDidComplete(testId: "trail_making_A", score: 9.4))
    }

    func testAnUnknownTestIdIsRefused() {
        let (manager, _, _) = noon()
        manager.beginTest("not_a_test", in: .noon)

        XCTAssertNil(manager.testDidComplete(testId: "not_a_test", score: 1))
    }

    // MARK: - Summaries

    func testTrailMakingReportsItsDurationAndOthersConfirmCompletion() {
        let trail = SessionTest.test(id: "trail_making_A")!
        XCTAssertEqual(trail.completedSummary(score: 9.42), "9.4 seconds")

        XCTAssertEqual(SessionTest.test(id: "finger_tapping")!.completedSummary(score: 88),
                       "Both hands done")
        XCTAssertEqual(SessionTest.test(id: "leg_agility")!.completedSummary(score: 42),
                       "Both legs done")
        XCTAssertEqual(SessionTest.test(id: "voice_recording")!.completedSummary(score: 60),
                       "Recorded")
    }

    func testTheHubRunsNineTestsAndTheTestsTabBrowsesTheSameNine() {
        XCTAssertEqual(SessionTest.dailyBattery.count, 9)
        XCTAssertEqual(Set(SessionTest.browseOrder.map(\.id)),
                       Set(SessionTest.dailyBattery.map(\.id)))
    }

    func testOnlyTheCameraAndMicrophoneTestsDeclareACapability() {
        let needing = SessionTest.dailyBattery.filter { $0.capability != nil }.map(\.id)
        XCTAssertEqual(Set(needing),
                       ["voice_test", "voice_recording", "fingers_test", "facial_movement"])
    }

    // MARK: - Outcome plumbing

    func testFinishingTheBatterySurfacesAnOutcomeUntilItIsCleared() {
        let (manager, clock, _) = noon()
        for test in SessionTest.dailyBattery {
            manager.beginTest(test.id, in: .noon)
            manager.testDidComplete(testId: test.id, score: 1)
            manager.endTestRun()
            clock.advance(minutes: 1)
        }

        XCTAssertEqual(manager.lastOutcome?.sessionCompleted, true)
        manager.clearOutcome()
        XCTAssertNil(manager.lastOutcome)
    }

    // MARK: - Session counter

    func testTheSessionCounterCountsEverySessionNotEveryDay() {
        let store = InMemorySessionStore()
        let baseline = BaselineTracker(store: store)

        XCTAssertTrue(baseline.recordSessionCompleted(on: "2026-07-26"))
        XCTAssertFalse(baseline.recordSessionCompleted(on: "2026-07-26"))
        XCTAssertTrue(baseline.recordSessionCompleted(on: "2026-07-27"))

        XCTAssertEqual(baseline.completedDays.count, 2)
        XCTAssertEqual(baseline.completedSessions, 3)
    }

    func testTheSessionCounterSurvivesARelaunch() {
        let store = InMemorySessionStore()
        let first = BaselineTracker(store: store)
        first.recordSessionCompleted(on: "2026-07-26")
        first.recordSessionCompleted(on: "2026-07-26")

        let second = BaselineTracker(store: store)
        XCTAssertEqual(second.completedSessions, 2)
        XCTAssertEqual(second.completedDays, ["2026-07-26"])
    }
}
