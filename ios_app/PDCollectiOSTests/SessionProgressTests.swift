import XCTest
@testable import PDCollectiOS

final class SessionProgressTests: XCTestCase {

    private let start = SessionFixture.date(2026, 7, 26, 18, 0)

    private func makeProgress() -> SessionProgress {
        SessionProgress(day: "2026-07-26", period: .night)
    }

    // MARK: - Ordering

    func testBatteryHasNineTestsInDesignOrder() {
        XCTAssertEqual(SessionTest.dailyBattery.map(\.id), [
            "trail_making_A", "spiral_tracing", "finger_tapping", "hand_turning",
            "voice_test", "fingers_test", "facial_movement", "leg_agility", "voice_recording",
        ])
    }

    /// The identifiers are the ones GamificationManager and the CSV layer
    /// already use, so the session layer does not fork the vocabulary.
    func testBatteryIdentifiersAreUnique() {
        let ids = SessionTest.dailyBattery.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testNextTestFollowsBatteryOrderRegardlessOfCompletionOrder() {
        var progress = makeProgress()
        progress.record(testId: "finger_tapping", summary: "x", at: start)
        XCTAssertEqual(progress.nextTest?.id, "trail_making_A")

        progress.record(testId: "trail_making_A", summary: "9.4 seconds", at: start)
        XCTAssertEqual(progress.nextTest?.id, "spiral_tracing")
    }

    func testSessionIsCompleteOnlyWhenEveryTestIsDone() {
        var progress = makeProgress()
        for test in SessionTest.dailyBattery.dropLast() {
            progress.record(testId: test.id, summary: "x", at: start)
        }
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.completedCount, 8)

        progress.record(testId: "voice_recording", summary: "x", at: start)
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.nextTest)
    }

    func testUnknownTestIsNotRecorded() {
        var progress = makeProgress()
        progress.record(testId: "not_a_test", summary: "x", at: start)
        XCTAssertEqual(progress.completedCount, 0)
        XCTAssertFalse(progress.hasStarted)
    }

    // MARK: - Started

    func testMarkStartedMakesAnEmptySessionResumable() {
        var progress = makeProgress()
        XCTAssertFalse(progress.hasStarted)

        progress.markStarted(at: start)
        XCTAssertTrue(progress.hasStarted)
        XCTAssertEqual(progress.startedAt, start)
    }

    func testMarkStartedDoesNotMoveAnExistingStart() {
        var progress = makeProgress()
        progress.markStarted(at: start)
        progress.markStarted(at: start.addingTimeInterval(600))
        XCTAssertEqual(progress.startedAt, start)
    }

    // MARK: - Duration

    func testActiveDurationSumsTheGapsBetweenTests() {
        var progress = makeProgress()
        progress.markStarted(at: start)
        progress.record(testId: "trail_making_A", summary: "x", at: start.addingTimeInterval(30))
        progress.record(testId: "spiral_tracing", summary: "x", at: start.addingTimeInterval(60))

        XCTAssertEqual(progress.activeDuration, 60, accuracy: 0.001)
    }

    /// "Pause anytime — your progress is saved automatically." A long gap is
    /// the participant putting the phone down, not time spent testing.
    func testActiveDurationExcludesLongPauses() {
        var progress = makeProgress()
        progress.markStarted(at: start)
        progress.record(testId: "trail_making_A", summary: "x", at: start.addingTimeInterval(30))
        progress.record(testId: "spiral_tracing", summary: "x", at: start.addingTimeInterval(30 + 3600))

        XCTAssertEqual(progress.activeDuration, 30, accuracy: 0.001)
    }

    func testActiveDurationIsZeroBeforeAnythingHappens() {
        XCTAssertEqual(makeProgress().activeDuration, 0, accuracy: 0.001)
    }

    // MARK: - Encoding

    /// Resume depends on a clean round trip through the store.
    func testProgressRoundTripsThroughJSON() throws {
        var progress = makeProgress()
        progress.markStarted(at: start)
        progress.record(testId: "trail_making_A", summary: "9.4 seconds", at: start.addingTimeInterval(30))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(SessionProgress.self, from: encoder.encode(progress))

        XCTAssertEqual(decoded, progress)
        XCTAssertEqual(decoded.result(for: "trail_making_A")?.summary, "9.4 seconds")
        XCTAssertEqual(decoded.nextTest?.id, "spiral_tracing")
    }
}
