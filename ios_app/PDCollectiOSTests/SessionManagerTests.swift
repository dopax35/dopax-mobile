import XCTest
@testable import PDCollectiOS

final class SessionManagerTests: XCTestCase {

    private let calendar = SessionFixture.calendar
    private let battery = SessionTest.dailyBattery.map(\.id)

    private func makeManager(at date: Date,
                             store: SessionStoring = InMemorySessionStore(),
                             schedule: SessionSchedule = .default) -> (SessionManager, TestClock, SessionStoring) {
        let clock = TestClock(date)
        let manager = SessionManager(schedule: schedule,
                                     store: store,
                                     calendar: calendar,
                                     now: { clock.now })
        return (manager, clock, store)
    }

    /// Runs the whole battery for one period.
    @discardableResult
    private func completeSession(_ manager: SessionManager,
                                 _ period: SessionPeriod,
                                 clock: TestClock) -> SessionOutcome? {
        var last: SessionOutcome?
        for id in battery {
            last = manager.recordTestCompleted(id, in: period, summary: "done")
            clock.advance(minutes: 1)
        }
        return last
    }

    // MARK: - State machine

    func testPeriodIsLockedBeforeItsWindowOpens() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        XCTAssertEqual(manager.state(for: .morning), .locked)
        XCTAssertEqual(manager.state(for: .noon), .locked)
        XCTAssertEqual(manager.state(for: .night), .locked)
    }

    func testOnlyTheOpenWindowIsActionable() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 12, 30))
        XCTAssertEqual(manager.state(for: .morning), .missed)
        XCTAssertEqual(manager.state(for: .noon), .available)
        XCTAssertEqual(manager.state(for: .night), .locked)
        XCTAssertEqual(manager.actionablePeriod, .noon)
    }

    func testSessionBecomesInProgressAfterFirstTest() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        XCTAssertEqual(manager.state(for: .morning), .available)

        manager.recordTestCompleted("trail_making_A", in: .morning, summary: "9.4 seconds")
        XCTAssertEqual(manager.state(for: .morning), .inProgress)
        XCTAssertEqual(manager.progress(for: .morning).completedCount, 1)
    }

    func testWindowClosingWithoutCompletionMarksMissed() {
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        manager.recordTestCompleted("trail_making_A", in: .morning, summary: "9.4 seconds")

        clock.advance(minutes: 120)
        XCTAssertEqual(manager.state(for: .morning), .missed)
    }

    /// A missed window must not break the run: the next window still opens.
    func testMissedWindowDoesNotBlockLaterSessions() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 19, 0))
        XCTAssertEqual(manager.state(for: .morning), .missed)
        XCTAssertEqual(manager.state(for: .noon), .missed)
        XCTAssertEqual(manager.state(for: .night), .available)
    }

    func testCompletedSessionStaysCompletedAfterWindowCloses() {
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 5))
        completeSession(manager, .morning, clock: clock)
        XCTAssertEqual(manager.state(for: .morning), .completed)

        clock.advance(minutes: 600)
        XCTAssertEqual(manager.state(for: .morning), .completed)
    }

    func testFocusedPeriodFallsBackToNextUpcomingWindow() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        XCTAssertNil(manager.actionablePeriod)
        XCTAssertEqual(manager.focusedPeriod, .morning)
    }

    func testFocusedPeriodIsNilWhenNothingIsLeftToday() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 23, 0))
        XCTAssertNil(manager.actionablePeriod)
        XCTAssertNil(manager.focusedPeriod)
    }

    // MARK: - Window caption

    func testWindowCaptionMatchesTheDesignChip() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 19, 22))
        XCTAssertEqual(manager.windowCaption(for: .night), "18:00 - 20:00 · 38 min left")
    }

    func testWindowCaptionDropsCountdownWhenClosed() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        XCTAssertEqual(manager.windowCaption(for: .night), "18:00 - 20:00")
    }

    // MARK: - Guards

    /// A test run from the Tests tab outside a window must not count toward a
    /// session (decision D5).
    func testRecordingOutsideTheWindowIsRejected() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        XCTAssertNil(manager.recordTestCompleted("finger_tapping", in: .morning, summary: "x"))
        XCTAssertEqual(manager.progress(for: .morning).completedCount, 0)
    }

    func testUnknownTestIdIsIgnored() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        XCTAssertNil(manager.recordTestCompleted("not_a_test", in: .morning, summary: "x"))
        XCTAssertEqual(manager.progress(for: .morning).completedCount, 0)
    }

    func testRepeatingATestDoesNotInflateProgress() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        manager.recordTestCompleted("finger_tapping", in: .morning, summary: "first")
        manager.recordTestCompleted("finger_tapping", in: .morning, summary: "second")

        XCTAssertEqual(manager.progress(for: .morning).completedCount, 1)
        XCTAssertEqual(manager.progress(for: .morning).result(for: "finger_tapping")?.summary, "second")
    }

    func testBeginSessionOnlyAppliesInsideTheWindow() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        XCTAssertFalse(manager.beginSession(.morning))

        let (open, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        XCTAssertTrue(open.beginSession(.morning))
        XCTAssertEqual(open.state(for: .morning), .inProgress)
    }

    // MARK: - Resume

    /// Killing the app mid-session must restore the hub exactly.
    func testProgressSurvivesAManagerRebuild() {
        let store = InMemorySessionStore()
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 10), store: store)

        manager.recordTestCompleted("trail_making_A", in: .morning, summary: "9.4 seconds")
        manager.recordTestCompleted("spiral_tracing", in: .morning, summary: "Both hands done")

        let revived = SessionManager(schedule: .default, store: store,
                                     calendar: calendar, now: { clock.now })

        XCTAssertEqual(revived.state(for: .morning), .inProgress)
        XCTAssertEqual(revived.progress(for: .morning).completedCount, 2)
        XCTAssertEqual(revived.progress(for: .morning).nextTest?.id, "finger_tapping")
        XCTAssertEqual(revived.progress(for: .morning).result(for: "trail_making_A")?.summary, "9.4 seconds")
    }

    func testDayRolloverStartsAFreshSession() {
        let store = InMemorySessionStore()
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 10), store: store)
        manager.recordTestCompleted("trail_making_A", in: .morning, summary: "9.4 seconds")

        clock.advance(days: 1)
        manager.refresh()

        XCTAssertEqual(manager.progress(for: .morning).day, "2026-07-27")
        XCTAssertEqual(manager.progress(for: .morning).completedCount, 0)
        XCTAssertEqual(manager.state(for: .morning), .available)
    }

    /// Yesterday's data is still on disk after the rollover, not overwritten.
    func testPreviousDayProgressIsRetained() {
        let store = InMemorySessionStore()
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 10), store: store)
        manager.recordTestCompleted("trail_making_A", in: .morning, summary: "9.4 seconds")

        clock.advance(days: 1)
        manager.refresh()

        XCTAssertEqual(store.loadProgress(day: "2026-07-26", period: .morning)?.completedCount, 1)
    }

    // MARK: - Crossing midnight

    /// With a 22:00-01:00 night window, 00:30 belongs to the session that
    /// started yesterday, not to a new one.
    func testAfterMidnightTheNightSessionStillBelongsToYesterday() {
        let schedule = SessionSchedule(morningText: "08:00-10:00",
                                       noonText: "12:00-14:00",
                                       nightText: "22:00-01:00")
        let store = InMemorySessionStore()
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 22, 30),
                                              store: store, schedule: schedule)

        manager.recordTestCompleted("trail_making_A", in: .night, summary: "9.4 seconds")
        XCTAssertEqual(manager.progress(for: .night).day, "2026-07-26")

        clock.advance(minutes: 120)      // 00:30 the next day
        manager.refresh()

        XCTAssertEqual(manager.progress(for: .night).day, "2026-07-26")
        XCTAssertEqual(manager.state(for: .night), .inProgress)
        XCTAssertEqual(manager.progress(for: .night).completedCount, 1)
    }

    func testOnceTheCrossingWindowClosesTheDayMovesOn() {
        let schedule = SessionSchedule(morningText: "08:00-10:00",
                                       noonText: "12:00-14:00",
                                       nightText: "22:00-01:00")
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 22, 30),
                                              schedule: schedule)
        clock.advance(minutes: 180)      // 01:30 the next day
        manager.refresh()

        XCTAssertEqual(manager.progress(for: .night).day, "2026-07-27")
        XCTAssertEqual(manager.state(for: .night), .locked)
    }
}
