import XCTest
@testable import MoonlogCore

final class MoonClockTests: XCTestCase {

    func testNowIsInjectable() {
        let pinned = Date(timeIntervalSince1970: 1_788_625_413)
        let clock = MoonClock(timeZoneIdentifier: Zone.newYork, now: { pinned })
        XCTAssertEqual(clock.now, pinned)
    }

    func testUnknownTimeZoneFallsBackToGMTNotDeviceZone() {
        // Deliberate: an unrecognised identifier must not silently inherit the
        // device zone, which would hide the data problem and skew the charts.
        let clock = MoonClock(timeZoneIdentifier: "Not/AZone")
        XCTAssertEqual(clock.timeZone, .gmt)
    }

    /// The web version divided elapsed milliseconds by 86,400,000. On a
    /// spring-forward day that day is only 23 hours long, so the quotient is
    /// ~0.958 and floors to 0 — a whole day disappears.
    func testCalendarDaysCountsOneAcrossSpringForward() {
        let clock = MoonClock(timeZoneIdentifier: Zone.newYork)
        let before = makeDate("2025-03-08 12:00", Zone.newYork)
        let after = makeDate("2025-03-09 12:00", Zone.newYork)

        XCTAssertLessThan(
            after.timeIntervalSince(before), 86_400,
            "precondition: this really is a 23-hour day"
        )
        XCTAssertEqual(clock.calendarDays(from: before, to: after), 1)
    }

    func testCalendarDaysCountsOneAcrossFallBack() {
        let clock = MoonClock(timeZoneIdentifier: Zone.newYork)
        let before = makeDate("2025-11-01 12:00", Zone.newYork)
        let after = makeDate("2025-11-02 12:00", Zone.newYork)

        XCTAssertGreaterThan(
            after.timeIntervalSince(before), 86_400,
            "precondition: this really is a 25-hour day"
        )
        XCTAssertEqual(clock.calendarDays(from: before, to: after), 1)
    }

    /// The 30-minute case. A "±1 hour" special-case passes New York and fails here.
    func testCalendarDaysAcrossThirtyMinuteDSTShift() {
        let clock = MoonClock(timeZoneIdentifier: Zone.lordHowe)
        let before = makeDate("2025-10-04 12:00", Zone.lordHowe)
        let after = makeDate("2025-10-05 12:00", Zone.lordHowe)
        XCTAssertEqual(clock.calendarDays(from: before, to: after), 1)
    }

    /// Times only minutes apart but on opposite sides of midnight are one day
    /// apart, and times 23 hours apart within one day are zero days apart. This
    /// is the distinction the web version's elapsed-milliseconds math cannot make.
    func testCalendarDaysIsAboutCalendarDaysNotElapsedTime() {
        let clock = MoonClock(timeZoneIdentifier: Zone.phoenix)

        let lateNight = makeDate("2026-09-05 23:58", Zone.phoenix)
        let justAfterMidnight = makeDate("2026-09-06 00:03", Zone.phoenix)
        XCTAssertEqual(clock.calendarDays(from: lateNight, to: justAfterMidnight), 1)

        let earlyMorning = makeDate("2026-09-05 00:30", Zone.phoenix)
        let lateEvening = makeDate("2026-09-05 23:30", Zone.phoenix)
        XCTAssertEqual(clock.calendarDays(from: earlyMorning, to: lateEvening), 0)
    }

    func testStartOfDayLandsOnLocalMidnightOnATransitionDay() {
        let clock = MoonClock(timeZoneIdentifier: Zone.newYork)
        let duringTheDay = makeDate("2025-03-09 15:00", Zone.newYork)
        let midnight = clock.startOfDay(for: duringTheDay)

        var comps = clock.calendar.dateComponents([.hour, .minute], from: midnight)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)

        // And on London's 01:00 transition, where the naive approach is worse still.
        let london = MoonClock(timeZoneIdentifier: Zone.london)
        let londonMidnight = london.startOfDay(for: makeDate("2025-03-30 15:00", Zone.london))
        comps = london.calendar.dateComponents([.hour, .minute], from: londonMidnight)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }
}
