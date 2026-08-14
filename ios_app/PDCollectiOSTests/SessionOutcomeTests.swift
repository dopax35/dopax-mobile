import XCTest
@testable import PDCollectiOS

/// End-to-end checks that running sessions drives the helix the way the
/// completion and baseline screens expect.
final class SessionOutcomeTests: XCTestCase {

    private let calendar = SessionFixture.calendar
    private let battery = SessionTest.dailyBattery.map(\.id)

    private func completeSession(_ manager: SessionManager,
                                 _ period: SessionPeriod,
                                 clock: TestClock) -> SessionOutcome? {
        manager.beginSession(period)
        var last: SessionOutcome?
        for id in battery {
            clock.advance(minutes: 1)
            last = manager.recordTestCompleted(id, in: period, summary: "done")
        }
        return last
    }

    func testFinishingTheBatteryReportsCompletionAndGrowsTheHelix() {
        let clock = TestClock(SessionFixture.date(2026, 7, 26, 8, 5))
        let manager = SessionManager(store: InMemorySessionStore(),
                                     calendar: calendar, now: { clock.now })

        let outcome = completeSession(manager, .morning, clock: clock)

        XCTAssertEqual(outcome, SessionOutcome(sessionCompleted: true,
                                               helixGrew: true,
                                               baselineCompleted: false))
        XCTAssertEqual(manager.state(for: .morning), .completed)
        XCTAssertEqual(manager.baseline.currentDay, 1)
    }

    func testIntermediateTestsReportNoCompletion() {
        let clock = TestClock(SessionFixture.date(2026, 7, 26, 8, 5))
        let manager = SessionManager(store: InMemorySessionStore(),
                                     calendar: calendar, now: { clock.now })

        XCTAssertEqual(manager.recordTestCompleted("trail_making_A", in: .morning, summary: "9.4 seconds"),
                       SessionOutcome.none)
        XCTAssertEqual(manager.baseline.currentDay, 0)
    }

    /// The second session of a day still completes, but the helix has already
    /// grown so the completion screen must not claim it again.
    func testSecondSessionOfTheDayCompletesWithoutGrowingTheHelix() {
        let clock = TestClock(SessionFixture.date(2026, 7, 26, 8, 5))
        let manager = SessionManager(store: InMemorySessionStore(),
                                     calendar: calendar, now: { clock.now })

        completeSession(manager, .morning, clock: clock)

        clock.now = SessionFixture.date(2026, 7, 26, 12, 30)
        manager.refresh()
        let outcome = completeSession(manager, .noon, clock: clock)

        XCTAssertEqual(outcome?.sessionCompleted, true)
        XCTAssertEqual(outcome?.helixGrew, false)
        XCTAssertEqual(manager.baseline.currentDay, 1)
    }

    func testFourteenDaysOfSessionsCompletesTheBaselineExactlyOnce() {
        let store = InMemorySessionStore()
        let clock = TestClock(SessionFixture.date(2026, 7, 1, 8, 5))
        let manager = SessionManager(store: store, calendar: calendar, now: { clock.now })

        var completions: [SessionOutcome] = []
        for day in 1...14 {
            clock.now = SessionFixture.date(2026, 7, day, 8, 5)
            manager.refresh()
            if let outcome = completeSession(manager, .morning, clock: clock) {
                completions.append(outcome)
            }
        }

        XCTAssertEqual(completions.count, 14)
        XCTAssertEqual(completions.filter(\.helixGrew).count, 14)
        XCTAssertEqual(completions.filter(\.baselineCompleted).count, 1)
        XCTAssertEqual(completions.last?.baselineCompleted, true)
        XCTAssertTrue(manager.baseline.isComplete)
        XCTAssertTrue(manager.baseline.shouldPresentCompletion)
    }

    /// Day 15 keeps working; it just has nothing left to unlock.
    func testSessionsContinueAfterTheBaselineIsComplete() {
        let store = InMemorySessionStore()
        let clock = TestClock(SessionFixture.date(2026, 7, 1, 8, 5))
        let manager = SessionManager(store: store, calendar: calendar, now: { clock.now })

        for day in 1...15 {
            clock.now = SessionFixture.date(2026, 7, day, 8, 5)
            manager.refresh()
            let outcome = completeSession(manager, .morning, clock: clock)
            if day == 15 {
                XCTAssertEqual(outcome?.sessionCompleted, true)
                XCTAssertEqual(outcome?.baselineCompleted, false)
            }
        }

        XCTAssertEqual(manager.baseline.currentDay, 14)
    }
}
