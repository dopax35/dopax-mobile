import XCTest
@testable import PDCollectiOS

/// Shared fixtures. A UTC calendar keeps the window arithmetic deterministic
/// wherever the tests are run.
enum SessionFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}

/// Mutable clock so a test can advance time without sleeping.
final class TestClock {
    var now: Date
    init(_ start: Date) { now = start }
    func advance(seconds: Int) { now = now.addingTimeInterval(TimeInterval(seconds)) }
    func advance(minutes: Int) { now = now.addingTimeInterval(TimeInterval(minutes) * 60) }
    func advance(days: Int) { now = now.addingTimeInterval(TimeInterval(days) * 86_400) }
}

final class SessionWindowTests: XCTestCase {

    private let calendar = SessionFixture.calendar

    // MARK: - Parsing

    func testParsesStoredRange() {
        let window = SessionWindow("18:00-20:00")
        XCTAssertEqual(window?.start, TimeOfDay(hour: 18, minute: 0))
        XCTAssertEqual(window?.end, TimeOfDay(hour: 20, minute: 0))
    }

    func testParsingToleratesSpacingAndEnDash() {
        XCTAssertEqual(SessionWindow(" 08:00 – 10:00 "),
                       SessionWindow(start: TimeOfDay(hour: 8, minute: 0)!,
                                     end: TimeOfDay(hour: 10, minute: 0)!))
    }

    func testRejectsMalformedRanges() {
        XCTAssertNil(SessionWindow("not a window"))
        XCTAssertNil(SessionWindow("08:00"))
        XCTAssertNil(SessionWindow("25:00-26:00"))
        XCTAssertNil(SessionWindow("08:60-10:00"))
    }

    /// A participant with a corrupted stored value still gets a usable app.
    func testScheduleFallsBackToDefaultsOnGarbage() {
        let schedule = SessionSchedule(morningText: "garbage", noonText: nil, nightText: "21:00-23:00")
        XCTAssertEqual(schedule[.morning], SessionSchedule.defaultMorning)
        XCTAssertEqual(schedule[.noon], SessionSchedule.defaultNoon)
        XCTAssertEqual(schedule[.night], SessionWindow("21:00-23:00"))
    }

    func testOrderedPeriodsFollowWindowStart() {
        XCTAssertEqual(SessionSchedule.default.orderedPeriods, [.morning, .noon, .night])
    }

    // MARK: - Boundaries

    func testWindowBoundariesAreInclusive() {
        let window = SessionWindow("18:00-20:00")!
        let day = SessionFixture.date(2026, 7, 26)

        XCTAssertFalse(window.isOpen(at: SessionFixture.date(2026, 7, 26, 17, 59), onDayOf: day, calendar: calendar))
        XCTAssertTrue(window.isOpen(at: SessionFixture.date(2026, 7, 26, 18, 0), onDayOf: day, calendar: calendar))
        XCTAssertTrue(window.isOpen(at: SessionFixture.date(2026, 7, 26, 20, 0), onDayOf: day, calendar: calendar))
        XCTAssertFalse(window.isOpen(at: SessionFixture.date(2026, 7, 26, 20, 1), onDayOf: day, calendar: calendar))
    }

    func testMinutesRemainingCountsDownAndStopsAtClose() {
        let window = SessionWindow("18:00-20:00")!
        let day = SessionFixture.date(2026, 7, 26)

        XCTAssertEqual(window.minutesRemaining(at: SessionFixture.date(2026, 7, 26, 19, 22),
                                               onDayOf: day, calendar: calendar), 38)
        XCTAssertEqual(window.minutesRemaining(at: SessionFixture.date(2026, 7, 26, 20, 0),
                                               onDayOf: day, calendar: calendar), 0)
        XCTAssertNil(window.minutesRemaining(at: SessionFixture.date(2026, 7, 26, 20, 1),
                                             onDayOf: day, calendar: calendar))
    }

    func testDisplayRangeMatchesDesignChip() {
        XCTAssertEqual(SessionWindow("18:00-20:00")!.displayRange, "18:00 - 20:00")
        XCTAssertEqual(SessionWindow("8:5-10:0")!.displayRange, "08:05 - 10:00")
    }

    // MARK: - Crossing midnight

    func testWindowCrossingMidnightExtendsIntoNextDay() {
        let window = SessionWindow("22:00-01:00")!
        XCTAssertTrue(window.crossesMidnight)

        let day = SessionFixture.date(2026, 7, 26)
        XCTAssertTrue(window.isOpen(at: SessionFixture.date(2026, 7, 26, 23, 30), onDayOf: day, calendar: calendar))
        XCTAssertTrue(window.isOpen(at: SessionFixture.date(2026, 7, 27, 0, 30), onDayOf: day, calendar: calendar))
        XCTAssertFalse(window.isOpen(at: SessionFixture.date(2026, 7, 27, 1, 30), onDayOf: day, calendar: calendar))
    }

    // MARK: - Day keys

    func testDayKeyRoundTrip() {
        let key = SessionDay.key(for: SessionFixture.date(2026, 7, 26, 13, 5), calendar: calendar)
        XCTAssertEqual(key, "2026-07-26")
        XCTAssertEqual(SessionDay.date(from: key, calendar: calendar), SessionFixture.date(2026, 7, 26))
    }

    func testDayKeyRejectsMalformedInput() {
        XCTAssertNil(SessionDay.date(from: "nonsense", calendar: calendar))
    }
}
