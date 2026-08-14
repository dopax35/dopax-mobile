import XCTest
@testable import PDCollectiOS

/// Covers what the Today screen reads off `SessionManager`: the second line of
/// each card, and the daily task row.
final class TodayPresentationTests: XCTestCase {

    private let calendar = SessionFixture.calendar
    private let battery = SessionTest.dailyBattery.map(\.id)

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

    // MARK: - Card subtitle

    func testLockedCardShowsItsWindow() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 6, 0))
        XCTAssertEqual(manager.cardSubtitle(for: .night), "18:00 - 20:00")
    }

    func testAvailableCardShowsBatterySizeAndTimeLeft() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 9, 0))
        XCTAssertEqual(manager.cardSubtitle(for: .morning),
                       "\(SessionTest.dailyBattery.count) tests · 60 min left")
    }

    func testInProgressCardCountsDownRemainingTests() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        manager.recordTestCompleted(battery[0], in: .morning, summary: "done")

        let remaining = battery.count - 1
        XCTAssertEqual(manager.cardSubtitle(for: .morning), "\(remaining) tests remaining")
    }

    func testLastRemainingTestIsSingular() {
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30))
        for id in battery.dropLast() {
            manager.recordTestCompleted(id, in: .morning, summary: "done")
            clock.advance(minutes: 1)
        }
        XCTAssertEqual(manager.cardSubtitle(for: .morning), "1 test remaining")
    }

    func testCompletedCardReportsActiveDuration() {
        let (manager, clock, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 0))
        let secondsPerTest = 180 / battery.count

        manager.beginSession(.morning)
        for id in battery {
            clock.advance(seconds: secondsPerTest)
            manager.recordTestCompleted(id, in: .morning, summary: "done")
        }

        XCTAssertEqual(manager.state(for: .morning), .completed)
        // Three minutes of testing end to end, with no gap long enough to count
        // as a pause.
        XCTAssertEqual(manager.cardSubtitle(for: .morning), "Completed in 3 minutes")
    }

    func testMissedCardReportsHowFarTheParticipantGot() {
        let store = InMemorySessionStore()
        let (morning, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 8, 30), store: store)
        morning.recordTestCompleted(battery[0], in: .morning, summary: "done")
        morning.recordTestCompleted(battery[1], in: .morning, summary: "done")

        let (later, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 11, 0), store: store)
        XCTAssertEqual(later.state(for: .morning), .missed)
        XCTAssertEqual(later.cardSubtitle(for: .morning), "Missed · 2 of \(battery.count) done")
    }

    // MARK: - Duration copy

    func testDurationStaysInSecondsUpToAMinuteAndAHalf() {
        XCTAssertEqual(SessionManager.durationText(1), "1 second")
        XCTAssertEqual(SessionManager.durationText(60), "60 seconds")
        XCTAssertEqual(SessionManager.durationText(89), "89 seconds")
        XCTAssertEqual(SessionManager.durationText(90), "2 minutes")
        XCTAssertEqual(SessionManager.durationText(240), "4 minutes")
    }

    // MARK: - Daily tasks

    func testTasksStartOutstandingAndDropOutWhenDone() {
        let (manager, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 9, 0))
        XCTAssertEqual(manager.outstandingTasks, DailyTask.allCases)

        manager.markTask(.questionnaire)
        XCTAssertTrue(manager.isTaskComplete(.questionnaire))
        XCTAssertEqual(manager.outstandingTasks, [.medication])

        manager.markTask(.medication)
        XCTAssertTrue(manager.outstandingTasks.isEmpty)
    }

    func testMarkingTheSameTaskTwiceIsIdempotent() {
        let (manager, _, store) = makeManager(at: SessionFixture.date(2026, 7, 26, 9, 0))
        manager.markTask(.medication)
        manager.markTask(.medication)

        XCTAssertEqual(store.loadCompletedTasks(day: manager.todayKey), ["medication"])
    }

    func testCompletedTasksSurviveARelaunchOnTheSameDay() {
        let store = InMemorySessionStore()
        let (first, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 9, 0), store: store)
        first.markTask(.questionnaire)

        let (relaunched, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 19, 0), store: store)
        XCTAssertEqual(relaunched.outstandingTasks, [.medication])
    }

    func testTasksResetTheNextDay() {
        let store = InMemorySessionStore()
        let (today, _, _) = makeManager(at: SessionFixture.date(2026, 7, 26, 9, 0), store: store)
        today.markTask(.questionnaire)
        today.markTask(.medication)

        let (tomorrow, _, _) = makeManager(at: SessionFixture.date(2026, 7, 27, 9, 0), store: store)
        XCTAssertEqual(tomorrow.outstandingTasks, DailyTask.allCases)
    }
}
