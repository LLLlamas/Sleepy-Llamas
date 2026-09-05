import XCTest
@testable import MoonlogCore

final class DayBucketsTests: XCTestCase {

    private let babyA = UUID()
    private func at(_ wall: String, _ zone: String = Zone.newYork) -> Date {
        makeDate(wall, zone)
    }

    // MARK: - Day interval generation

    func testDaysAreContiguousNonOverlappingAndCoverTheRange() {
        let cal = calendar(Zone.newYork)
        let range = DateInterval(start: at("2026-09-01 08:00"), end: at("2026-09-05 20:00"))
        let days = DayBuckets.days(covering: range, calendar: cal)

        XCTAssertEqual(days.count, 5)
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertEqual(a.end, b.start, "no gaps, no overlaps")
        }
        XCTAssertLessThanOrEqual(days.first!.start, range.start)
        XCTAssertGreaterThanOrEqual(days.last!.end, range.end)
    }

    /// Day length is a calendar fact, not 86,400 seconds. Both DST directions.
    func testDayLengthsAreTwentyThreeAndTwentyFiveHoursAcrossTransitions() {
        let cal = calendar(Zone.newYork)

        let spring = DayBuckets.days(
            covering: DateInterval(start: at("2025-03-09 06:00"), end: at("2025-03-09 20:00")),
            calendar: cal)
        XCTAssertEqual(spring.count, 1)
        XCTAssertEqual(spring[0].duration, 23 * 3600, accuracy: 1)

        let fall = DayBuckets.days(
            covering: DateInterval(start: at("2025-11-02 06:00"), end: at("2025-11-02 20:00")),
            calendar: cal)
        XCTAssertEqual(fall.count, 1)
        XCTAssertEqual(fall[0].duration, 25 * 3600, accuracy: 1)
    }

    /// The 30-minute case: a bucket 24.5 hours long.
    func testThirtyMinuteDSTShiftProducesAHalfHourLongerDay() {
        let cal = calendar(Zone.lordHowe)
        let days = DayBuckets.days(
            covering: DateInterval(
                start: at("2025-04-06 06:00", Zone.lordHowe),
                end: at("2025-04-06 20:00", Zone.lordHowe)),
            calendar: cal)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].duration, 24.5 * 3600, accuracy: 1)
    }

    // MARK: - Half-open containment

    /// `DateInterval.contains` is closed at both ends, so a midnight event would
    /// land in two adjacent buckets. Point events must be half-open.
    func testMidnightBelongsToExactlyOneDay() {
        let cal = calendar(Zone.newYork)
        let days = DayBuckets.days(
            covering: DateInterval(start: at("2026-09-04 12:00"), end: at("2026-09-05 12:00")),
            calendar: cal)
        let midnight = at("2026-09-05 00:00")

        let matches = days.filter { DayBuckets.day($0, contains: midnight) }
        XCTAssertEqual(matches.count, 1, "a midnight event must not be double-counted")
        XCTAssertEqual(matches.first?.start, midnight)

        // And the closed built-in really would have double-counted it.
        XCTAssertEqual(days.filter { $0.contains(midnight) }.count, 2,
                       "documents why the custom half-open check exists")
    }

    // MARK: - Sleep clipping across days — the partition invariant

    /// **The invariant.** A session's per-day contributions must sum to exactly its
    /// total duration, and must be split at the boundary rather than assigned
    /// wholesale to the start day.
    ///
    /// Both assertions are needed. The sum alone does *not* catch clip-vs-assign:
    /// when a session lies entirely inside the bucketed range, dumping all of it on
    /// day one still sums correctly. Only the per-day split exposes that — verified
    /// by mutation.
    func testPerDayContributionsSumToTheTotalDuration() {
        let cal = calendar(Zone.newYork)
        let shift = ShiftWindow(startedAt: at("2026-09-04 20:00"), endedAt: at("2026-09-05 08:00"))
        let session = SleepSnapshot(
            babyID: babyA, startAt: at("2026-09-04 22:00"), endAt: at("2026-09-05 06:00"))

        let days = DayBuckets.days(covering: DateInterval(
            start: shift.startedAt, end: shift.endedAt!), calendar: cal)
        let perDay = days.map {
            DayBuckets.sleepSeconds(of: session, in: $0, clippedTo: shift, asOf: .distantFuture)
        }

        XCTAssertEqual(perDay.reduce(0, +), 8 * 3600, accuracy: 0.5)
        // And it really is split, not assigned wholesale to the start day.
        XCTAssertEqual(perDay[0], 2 * 3600, accuracy: 0.5)
        XCTAssertEqual(perDay[1], 6 * 3600, accuracy: 0.5)
    }

    /// The same invariant holds when the split lands on a DST transition, where
    /// the two days are 23 and 24 hours long.
    func testPartitionInvariantHoldsAcrossADSTTransition() {
        let cal = calendar(Zone.newYork)
        let shift = ShiftWindow(startedAt: at("2025-03-08 20:00"), endedAt: at("2025-03-09 12:00"))
        let session = SleepSnapshot(
            babyID: babyA, startAt: at("2025-03-08 22:00"), endAt: at("2025-03-09 08:00"))

        let days = DayBuckets.days(covering: DateInterval(
            start: shift.startedAt, end: shift.endedAt!), calendar: cal)
        let total = days.reduce(0.0) {
            $0 + DayBuckets.sleepSeconds(of: session, in: $1, clippedTo: shift, asOf: .distantFuture)
        }
        XCTAssertEqual(total, session.endAt!.timeIntervalSince(session.startAt), accuracy: 0.5)
    }

    /// A session left open in a closed shift must not leak into later days.
    func testOpenSessionDoesNotLeakIntoDaysAfterTheShiftEnded() {
        let cal = calendar(Zone.newYork)
        let shift = ShiftWindow(startedAt: at("2026-09-04 22:00"), endedAt: at("2026-09-05 06:00"))
        let stillAsleep = SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 05:40"))

        let laterDays = DayBuckets.days(covering: DateInterval(
            start: at("2026-09-05 00:00"), end: at("2026-09-08 00:00")), calendar: cal)
        let total = laterDays.reduce(0.0) {
            $0 + DayBuckets.sleepSeconds(
                of: stillAsleep, in: $1, clippedTo: shift, asOf: at("2026-09-08 00:00"))
        }
        XCTAssertEqual(total, 20 * 60, accuracy: 0.5)
    }

    func testEventBucketingIsPerBabyAndPerDay() {
        let cal = calendar(Zone.newYork)
        let babyB = UUID()
        let events = [
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-04 23:00")),
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-05 01:00")),
            EventSnapshot(babyID: babyB, kind: .feed, at: at("2026-09-05 02:00")),
        ]
        let days = DayBuckets.days(covering: DateInterval(
            start: at("2026-09-04 20:00"), end: at("2026-09-05 08:00")), calendar: cal)

        XCTAssertEqual(DayBuckets.events(events, in: days[0]).count, 1)
        XCTAssertEqual(DayBuckets.events(events, in: days[1]).count, 2)
        XCTAssertEqual(
            DayBuckets.events(events.filter { $0.babyID == babyA }, in: days[1]).count, 1)
    }
}
