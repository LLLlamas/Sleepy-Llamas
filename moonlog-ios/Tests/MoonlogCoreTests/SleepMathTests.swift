import XCTest
@testable import MoonlogCore

final class SleepMathTests: XCTestCase {

    private let babyA = UUID()
    private let babyB = UUID()

    // MARK: - The regression that motivated the whole rewrite

    /// **The bug.** In the web version an open sleep session left behind by a closed
    /// shift keeps accruing against `now`, so the shift's total grows by a minute
    /// per minute forever — reopen a week-old handoff and it claims 168 hours.
    ///
    /// Here: the doula ends her shift at 06:00 with the baby asleep since 05:40.
    /// The shift must report 20 minutes, and must still report 20 minutes when the
    /// same record is read hours or weeks later.
    func testOpenSessionInAClosedShiftDoesNotGrowWithNow() {
        let shift = ShiftWindow(
            startedAt: makeDate("2026-09-04 22:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork)
        )
        let stillAsleep = SleepSnapshot(
            babyID: babyA,
            startAt: makeDate("2026-09-05 05:40", Zone.newYork),
            endAt: nil
        )

        let atHandoff = makeDate("2026-09-05 06:00", Zone.newYork)
        let hoursLater = makeDate("2026-09-05 14:00", Zone.newYork)
        let aWeekLater = makeDate("2026-09-12 06:00", Zone.newYork)

        for now in [atHandoff, hoursLater, aWeekLater] {
            XCTAssertEqual(
                SleepMath.seconds(of: stillAsleep, clippedTo: shift, asOf: now),
                20 * 60,
                accuracy: 0.5,
                "an open session in a CLOSED shift must stop at the shift end"
            )
        }
    }

    /// The counterpart: while the shift is still running, an open session *should*
    /// track `now`. Clipping must not freeze a live timer.
    func testOpenSessionInAnOpenShiftDoesTrackNow() {
        let shift = ShiftWindow(startedAt: makeDate("2026-09-04 22:00", Zone.newYork))
        let asleep = SleepSnapshot(
            babyID: babyA,
            startAt: makeDate("2026-09-05 01:00", Zone.newYork)
        )

        let at0130 = SleepMath.seconds(
            of: asleep, clippedTo: shift, asOf: makeDate("2026-09-05 01:30", Zone.newYork))
        let at0230 = SleepMath.seconds(
            of: asleep, clippedTo: shift, asOf: makeDate("2026-09-05 02:30", Zone.newYork))

        XCTAssertEqual(at0130, 30 * 60, accuracy: 0.5)
        XCTAssertEqual(at0230, 90 * 60, accuracy: 0.5)
    }

    // MARK: - Clipping absorbs strays

    /// A session back-dated to before the shift began contributes only its overlap.
    /// The web version credited the whole thing, silently attributing another
    /// caregiver's hours to this shift.
    func testSessionStartingBeforeTheShiftContributesOnlyItsOverlap() {
        let shift = ShiftWindow(
            startedAt: makeDate("2026-09-04 22:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork)
        )
        let straddling = SleepSnapshot(
            babyID: babyA,
            startAt: makeDate("2026-09-04 21:00", Zone.newYork),   // an hour early
            endAt: makeDate("2026-09-04 22:30", Zone.newYork)
        )
        XCTAssertEqual(
            SleepMath.seconds(of: straddling, clippedTo: shift, asOf: .distantFuture),
            30 * 60, accuracy: 0.5
        )
    }

    func testSessionEntirelyOutsideTheShiftContributesNothing() {
        let shift = ShiftWindow(
            startedAt: makeDate("2026-09-04 22:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork)
        )
        let yesterday = SleepSnapshot(
            babyID: babyA,
            startAt: makeDate("2026-09-03 22:00", Zone.newYork),
            endAt: makeDate("2026-09-03 23:00", Zone.newYork)
        )
        XCTAssertEqual(
            SleepMath.seconds(of: yesterday, clippedTo: shift, asOf: .distantFuture), 0)
    }

    /// A malformed record must contribute zero, not trap. `DateInterval`'s
    /// initialiser crashes when end precedes start, and CloudKit can deliver a
    /// half-synced record.
    func testMalformedSessionContributesZeroWithoutCrashing() {
        let shift = ShiftWindow(
            startedAt: makeDate("2026-09-04 22:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork)
        )
        let backwards = SleepSnapshot(
            babyID: babyA,
            startAt: makeDate("2026-09-05 03:00", Zone.newYork),
            endAt: makeDate("2026-09-05 02:00", Zone.newYork)
        )
        XCTAssertEqual(
            SleepMath.seconds(of: backwards, clippedTo: shift, asOf: .distantFuture), 0)
    }

    func testZeroLengthShiftCountsNothingRatherThanCrashing() {
        let instant = makeDate("2026-09-05 06:00", Zone.newYork)
        let shift = ShiftWindow(startedAt: instant, endedAt: instant)
        let session = SleepSnapshot(babyID: babyA, startAt: instant)
        XCTAssertEqual(SleepMath.seconds(of: session, clippedTo: shift, asOf: instant), 0)
    }

    // MARK: - Totals

    /// Sum seconds, round once. The web version rounded each session to whole
    /// minutes and then summed; eight stretches at x.5 minutes drift the night's
    /// total by several minutes.
    func testTotalSumsSecondsRatherThanRoundedMinutes() {
        let base = makeDate("2026-09-04 22:00", Zone.newYork)
        let shift = ShiftWindow(startedAt: base, endedAt: base.addingTimeInterval(8 * 3600))

        // Eight 90-second sessions = 12 minutes exactly.
        // Rounding each to whole minutes first would give 8 or 16, not 12.
        var sessions: [SleepSnapshot] = []
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i) * 600)
            sessions.append(
                SleepSnapshot(babyID: babyA, startAt: start, endAt: start.addingTimeInterval(90)))
        }

        let total = SleepMath.totalSeconds(of: sessions, clippedTo: shift, asOf: .distantFuture)
        XCTAssertEqual(total, 8 * 90, accuracy: 0.5)
        XCTAssertEqual(total / 60, 12, accuracy: 0.01)
    }

    // MARK: - Twins

    /// Baby A being asleep must not affect any question about Baby B. This is the
    /// case the web version structurally cannot express, since its open-sleep query
    /// is scoped to the shift rather than the baby.
    func testPerBabySleepIsIndependent() {
        let base = makeDate("2026-09-04 22:00", Zone.newYork)
        let shift = ShiftWindow(startedAt: base, endedAt: base.addingTimeInterval(8 * 3600))

        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: base, endAt: base.addingTimeInterval(3600)),
            SleepSnapshot(babyID: babyB, startAt: base, endAt: base.addingTimeInterval(1800)),
        ]

        XCTAssertEqual(
            SleepMath.totalSeconds(of: sessions, forBaby: babyA, clippedTo: shift, asOf: .distantFuture),
            3600, accuracy: 0.5)
        XCTAssertEqual(
            SleepMath.totalSeconds(of: sessions, forBaby: babyB, clippedTo: shift, asOf: .distantFuture),
            1800, accuracy: 0.5)
    }

    func testOpenSessionLookupIsPerBaby() {
        let base = makeDate("2026-09-04 22:00", Zone.newYork)
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: base),                                  // open
            SleepSnapshot(babyID: babyB, startAt: base, endAt: base.addingTimeInterval(60)),
        ]
        XCTAssertNotNil(SleepMath.openSession(in: sessions, forBaby: babyA))
        XCTAssertNil(SleepMath.openSession(in: sessions, forBaby: babyB))
    }

    /// CloudKit can deliver two open sessions for one baby and no schema constraint
    /// can prevent it. Which one we surface must not depend on arrival order.
    func testOpenSessionLookupIsDeterministicWhenDataIsInconsistent() {
        let base = makeDate("2026-09-04 22:00", Zone.newYork)
        let earlier = SleepSnapshot(babyID: babyA, startAt: base)
        let later = SleepSnapshot(babyID: babyA, startAt: base.addingTimeInterval(300))

        for ordering in [[earlier, later], [later, earlier]] {
            XCTAssertEqual(
                SleepMath.openSession(in: ordering, forBaby: babyA)?.id,
                earlier.id,
                "must pick the earliest start regardless of arrival order")
        }
    }

    // MARK: - DST

    /// Duration is physical time, so a stretch spanning "fall back" really is three
    /// hours even though the wall clock advances only two.
    func testSleepAcrossFallBackReportsTrueElapsedTime() {
        let shift = ShiftWindow(
            startedAt: makeDate("2025-11-02 00:00", Zone.newYork),
            endedAt: makeDate("2025-11-02 08:00", Zone.newYork)
        )
        // 01:00 EDT through 03:00 EST — the 1am hour happens twice.
        let start = makeDate("2025-11-02 00:30", Zone.newYork)
        let session = SleepSnapshot(
            babyID: babyA, startAt: start, endAt: start.addingTimeInterval(3 * 3600))

        XCTAssertEqual(
            SleepMath.seconds(of: session, clippedTo: shift, asOf: .distantFuture),
            3 * 3600, accuracy: 0.5)
    }
}
