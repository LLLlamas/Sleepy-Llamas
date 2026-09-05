import XCTest
@testable import MoonlogCore

final class DayOfLifeTests: XCTestCase {

    /// Clinical convention: the birth day is Day 1. The web version reports Day 0
    /// for a baby ten hours old, which is not how a pediatrician counts.
    func testBirthDayIsDayOne() {
        let cal = calendar(Zone.newYork)
        let birth = makeDate("2026-09-04 23:40", Zone.newYork)

        XCTAssertEqual(
            DayOfLife.calendarDay(birthAt: birth, asOf: birth, calendar: cal), 1)
        XCTAssertEqual(
            DayOfLife.calendarDay(
                birthAt: birth,
                asOf: makeDate("2026-09-04 23:59", Zone.newYork),
                calendar: cal),
            1)
    }

    /// And it rolls at midnight, not at the birth *time*. A baby born at 23:40 is
    /// on Day 2 the next morning, only eight hours old.
    func testRollsOverAtMidnightNotAtTheBirthTime() {
        let cal = calendar(Zone.newYork)
        let birth = makeDate("2026-09-04 23:40", Zone.newYork)

        XCTAssertEqual(
            DayOfLife.calendarDay(
                birthAt: birth,
                asOf: makeDate("2026-09-05 08:00", Zone.newYork),
                calendar: cal),
            2)
        XCTAssertEqual(
            DayOfLife.hours(birthAt: birth, asOf: makeDate("2026-09-05 08:00", Zone.newYork)),
            8.33, accuracy: 0.02,
            "still only eight hours old — hours and Day N answer different questions")
    }

    /// The reason the shift-pinned overload exists: the number must not change
    /// under the doula mid-shift, or the same handoff text reports a different
    /// Day N depending on which minute it is copied.
    func testDayOfLifeIsStableAcrossAnEntireShift() {
        let cal = calendar(Zone.newYork)
        let birth = makeDate("2026-09-01 20:15", Zone.newYork)
        let shift = ShiftWindow(
            startedAt: makeDate("2026-09-04 22:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork)
        )

        let pinned = DayOfLife.calendarDay(birthAt: birth, forShift: shift, calendar: cal)

        // Every instant in the shift, including after midnight and after the
        // birth-time boundary, reports the same pinned value.
        for wall in ["2026-09-04 22:00", "2026-09-04 23:59",
                     "2026-09-05 00:01", "2026-09-05 05:59"] {
            let shiftAtThatMoment = ShiftWindow(
                startedAt: shift.startedAt, endedAt: makeDate(wall, Zone.newYork))
            XCTAssertEqual(
                DayOfLife.calendarDay(birthAt: birth, forShift: shiftAtThatMoment, calendar: cal),
                pinned)
        }

        // Whereas the live value genuinely does tick over at midnight — which is
        // correct behavior for a live header, and wrong for a handoff document.
        XCTAssertNotEqual(
            DayOfLife.calendarDay(
                birthAt: birth, asOf: makeDate("2026-09-05 00:01", Zone.newYork), calendar: cal),
            pinned)
    }

    func testIncrementsExactlyOncePerCalendarDayAcrossDST() {
        for zone in [Zone.newYork, Zone.lordHowe, Zone.london, Zone.phoenix] {
            let cal = calendar(zone)
            let birth = makeDate("2025-03-01 12:00", zone)

            var previous = DayOfLife.calendarDay(birthAt: birth, asOf: birth, calendar: cal)
            var cursor = cal.startOfDay(for: birth)

            // Walk 60 days, crossing whatever transition this zone has.
            for _ in 0..<60 {
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
                let day = DayOfLife.calendarDay(birthAt: birth, asOf: cursor, calendar: cal)
                XCTAssertEqual(
                    day, previous + 1,
                    "\(zone): day of life must advance by exactly 1 per calendar day")
                previous = day
            }
        }
    }

    /// A timestamp before birth — a mis-set clock or a bad import — must clamp to
    /// Day 1 rather than reading zero or negative in a client-facing document.
    func testClampsToDayOneBeforeBirth() {
        let cal = calendar(Zone.newYork)
        let birth = makeDate("2026-09-04 12:00", Zone.newYork)
        XCTAssertEqual(
            DayOfLife.calendarDay(
                birthAt: birth,
                asOf: makeDate("2026-09-01 12:00", Zone.newYork),
                calendar: cal),
            1)
        XCTAssertEqual(
            DayOfLife.hours(
                birthAt: birth, asOf: makeDate("2026-09-01 12:00", Zone.newYork)),
            0)
    }
}
