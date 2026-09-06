import XCTest
@testable import MoonlogCore

/// The two 12-hour clock formats. They share one hour-12 computation, and this is
/// what stops that sharing from being a refactor nobody checked: `shortClock` is
/// pasted into every handoff the parents read, so its output is not free to move.
///
/// Midnight and noon are the cases worth having tests for. `hour % 12` is 0 at both,
/// and the app runs almost entirely on the wrong side of the first one.
final class FormattersTests: XCTestCase {

    private let zone = TimeZone(identifier: Zone.newYork)!

    private func at(_ wall: String) -> Date { makeDate(wall, Zone.newYork) }

    func testClockAmPmSpellsTheSuffixOut() {
        XCTAssertEqual(Fmt.clockAmPm(at("2026-09-04 03:42"), timeZone: zone), "3:42am")
        XCTAssertEqual(Fmt.clockAmPm(at("2026-09-04 15:42"), timeZone: zone), "3:42pm")
    }

    func testShortClockKeepsItsSingleLetter() {
        XCTAssertEqual(Fmt.shortClock(at("2026-09-04 03:42"), timeZone: zone), "3:42a")
        XCTAssertEqual(Fmt.shortClock(at("2026-09-04 15:42"), timeZone: zone), "3:42p")
    }

    /// Midnight is 12am, not 0am — and it is am, which is the half of the rule that
    /// a `< 12` test gets right only by accident of the hour being 0.
    func testMidnightAndNoonReadAsTwelve() {
        XCTAssertEqual(Fmt.clockAmPm(at("2026-09-04 00:05"), timeZone: zone), "12:05am")
        XCTAssertEqual(Fmt.clockAmPm(at("2026-09-04 12:05"), timeZone: zone), "12:05pm")
        XCTAssertEqual(Fmt.shortClock(at("2026-09-04 00:05"), timeZone: zone), "12:05a")
        XCTAssertEqual(Fmt.shortClock(at("2026-09-04 12:05"), timeZone: zone), "12:05p")
    }

    /// The minute pads, the hour does not. "03:42am" is a receipt, not a sentence.
    func testMinutePadsAndHourDoesNot() {
        XCTAssertEqual(Fmt.clockAmPm(at("2026-09-04 09:00"), timeZone: zone), "9:00am")
        XCTAssertEqual(Fmt.clockAmPm(at("2026-09-04 22:07"), timeZone: zone), "10:07pm")
    }

    /// Both formats take the shift's zone, never the device's. A family two zones
    /// over would otherwise get a status line disagreeing with the timeline beneath.
    func testRenderedInTheZonePassedIn() {
        let instant = at("2026-09-04 23:30")
        XCTAssertEqual(Fmt.clockAmPm(instant, timeZone: zone), "11:30pm")
        XCTAssertEqual(
            Fmt.clockAmPm(instant, timeZone: TimeZone(identifier: Zone.phoenix)!),
            "8:30pm")
    }
}
