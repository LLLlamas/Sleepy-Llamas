import XCTest
@testable import MoonlogCore

/// Time zones chosen to break different assumptions. `Australia/Lord_Howe` is the
/// important one: its DST shift is **30 minutes**, so any code that quietly assumes
/// "±1 hour" fails there loudly instead of silently.
private enum Zone {
    static let newYork = "America/New_York"      // US spring-forward / fall-back
    static let phoenix = "America/Phoenix"       // no DST — control
    static let lordHowe = "Australia/Lord_Howe"  // 30-minute DST shift
    static let london = "Europe/London"          // transition at 01:00, not 02:00
}

private func date(_ iso: String, _ zoneID: String) -> Date {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: zoneID)
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: iso)!
}

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
        let before = date("2025-03-08 12:00", Zone.newYork)
        let after = date("2025-03-09 12:00", Zone.newYork)

        XCTAssertLessThan(
            after.timeIntervalSince(before), 86_400,
            "precondition: this really is a 23-hour day"
        )
        XCTAssertEqual(clock.calendarDays(from: before, to: after), 1)
    }

    func testCalendarDaysCountsOneAcrossFallBack() {
        let clock = MoonClock(timeZoneIdentifier: Zone.newYork)
        let before = date("2025-11-01 12:00", Zone.newYork)
        let after = date("2025-11-02 12:00", Zone.newYork)

        XCTAssertGreaterThan(
            after.timeIntervalSince(before), 86_400,
            "precondition: this really is a 25-hour day"
        )
        XCTAssertEqual(clock.calendarDays(from: before, to: after), 1)
    }

    /// The 30-minute case. A "±1 hour" special-case passes New York and fails here.
    func testCalendarDaysAcrossThirtyMinuteDSTShift() {
        let clock = MoonClock(timeZoneIdentifier: Zone.lordHowe)
        let before = date("2025-10-04 12:00", Zone.lordHowe)
        let after = date("2025-10-05 12:00", Zone.lordHowe)
        XCTAssertEqual(clock.calendarDays(from: before, to: after), 1)
    }

    /// Times only minutes apart but on opposite sides of midnight are one day
    /// apart, and times 23 hours apart within one day are zero days apart. This
    /// is the distinction the web version's elapsed-milliseconds math cannot make.
    func testCalendarDaysIsAboutCalendarDaysNotElapsedTime() {
        let clock = MoonClock(timeZoneIdentifier: Zone.phoenix)

        let lateNight = date("2026-09-05 23:58", Zone.phoenix)
        let justAfterMidnight = date("2026-09-06 00:03", Zone.phoenix)
        XCTAssertEqual(clock.calendarDays(from: lateNight, to: justAfterMidnight), 1)

        let earlyMorning = date("2026-09-05 00:30", Zone.phoenix)
        let lateEvening = date("2026-09-05 23:30", Zone.phoenix)
        XCTAssertEqual(clock.calendarDays(from: earlyMorning, to: lateEvening), 0)
    }

    func testStartOfDayLandsOnLocalMidnightOnATransitionDay() {
        let clock = MoonClock(timeZoneIdentifier: Zone.newYork)
        let duringTheDay = date("2025-03-09 15:00", Zone.newYork)
        let midnight = clock.startOfDay(for: duringTheDay)

        var comps = clock.calendar.dateComponents([.hour, .minute], from: midnight)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)

        // And on London's 01:00 transition, where the naive approach is worse still.
        let london = MoonClock(timeZoneIdentifier: Zone.london)
        let londonMidnight = london.startOfDay(for: date("2025-03-30 15:00", Zone.london))
        comps = london.calendar.dateComponents([.hour, .minute], from: londonMidnight)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }
}
