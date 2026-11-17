import XCTest
@testable import MoonlogCore

/// A reminder offset is a physical duration, so a DST transition falling inside it
/// must not move the fire time. Every zone here is from `docs/testing.md`'s fixture
/// table, and each expectation was checked against tzdata before it was written down.
///
/// The pair that earns its place is Lord Howe: its shift is **30 minutes**, so a
/// "±1 hour" special case gives a different wrong answer there than plain wall-clock
/// arithmetic does — it fails there while New York and London would pass.
final class FeedReminderTests: XCTestCase {

    private let threeHours: TimeInterval = 3 * 3600

    /// Asserts both halves, because neither is sufficient alone: the interval says
    /// nothing about the clock, and the wall clock passes trivially in a zone with no
    /// transition. Same lesson as the bucketing tests — the sum alone does not catch it.
    private func assertThreeHoursLater(
        feed: String, fire: String, _ zoneID: String, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let feedAt = makeDate(feed, zoneID)
        let result = FeedReminder.fireDate(feedAt: feedAt, afterMinutes: 180)
        XCTAssertEqual(
            result.timeIntervalSince(feedAt), threeHours, accuracy: 0.5,
            "three hours must be three physical hours — \(message)", file: file, line: line)
        XCTAssertEqual(result, makeDate(fire, zoneID), message, file: file, line: line)
    }

    // MARK: - fireDate across the DST fixtures

    func testThreeHoursIsThreePhysicalHoursAcrossSpringForward() {
        assertThreeHoursLater(
            feed: "2026-03-08 00:30", fire: "2026-03-08 04:30", Zone.newYork,
            "wall-clock arithmetic would say 03:30 and shorten the gap by an hour")
    }

    func testThreeHoursIsThreePhysicalHoursAcrossFallBack() {
        assertThreeHoursLater(
            feed: "2026-11-01 00:30", fire: "2026-11-01 02:30", Zone.newYork,
            "wall-clock arithmetic would say 03:30 and stretch the gap by an hour")
    }

    /// London transitions at 01:00, not 02:00 — a fixture that catches anything
    /// hard-coding the US transition hour.
    func testLondonTransitionsAtOneNotTwo() {
        assertThreeHoursLater(
            feed: "2026-03-29 00:30", fire: "2026-03-29 04:30", Zone.london,
            "BST starts at 01:00")
        assertThreeHoursLater(
            feed: "2026-10-25 00:30", fire: "2026-10-25 02:30", Zone.london,
            "BST ends at 02:00")
    }

    /// The important one. A ±1 hour special case fires at 04:30 here; wall-clock
    /// arithmetic fires at 03:30. Both are wrong, and only this zone tells them apart.
    func testLordHoweThirtyMinuteShiftForward() {
        assertThreeHoursLater(
            feed: "2026-10-04 00:30", fire: "2026-10-04 04:00", Zone.lordHowe,
            "a 30-minute shift: ±1h would say 04:30, wall-clock would say 03:30")
    }

    func testLordHoweThirtyMinuteShiftBackward() {
        assertThreeHoursLater(
            feed: "2026-04-05 00:30", fire: "2026-04-05 03:00", Zone.lordHowe,
            "a 30-minute shift: ±1h would say 02:30, wall-clock would say 03:30")
    }

    /// The control. Same date as the spring-forward case, in a zone that does not
    /// observe DST — so a mutation that breaks the others must leave this one green,
    /// or the fixtures are measuring something other than the transition.
    func testPhoenixControlHasNoTransitionToSurvive() {
        assertThreeHoursLater(
            feed: "2026-03-08 00:30", fire: "2026-03-08 03:30", Zone.phoenix,
            "no DST — the naive answer and the correct answer coincide here")
    }

    // MARK: - presets

    func testEveryPresetIsStrictlyAfterTheFeed() {
        let feedAt = makeDate("2026-09-04 02:14", Zone.newYork)
        for minutes in FeedReminder.presetMinutes {
            XCTAssertGreaterThan(
                FeedReminder.fireDate(feedAt: feedAt, afterMinutes: minutes), feedAt,
                "preset \(minutes)m must land after the feed")
        }
        XCTAssertEqual(
            FeedReminder.presetMinutes, FeedReminder.presetMinutes.sorted(),
            "the picker renders these in order")
        XCTAssertEqual(
            Set(FeedReminder.presetMinutes).count, FeedReminder.presetMinutes.count,
            "a duplicated preset is two identical rows in the picker")
    }

    // MARK: - scheduleDate

    /// A feed remembered and logged four hours late. Three hours after it is already
    /// an hour ago, and iOS drops a past trigger silently.
    func testNilWhenTheFireDateHasAlreadyPassed() {
        XCTAssertNil(FeedReminder.scheduleDate(
            feedAt: makeDate("2026-09-04 02:14", Zone.newYork),
            afterMinutes: 180,
            now: makeDate("2026-09-04 06:14", Zone.newYork)))
    }

    func testNilAtTheExactBoundary() {
        let feedAt = makeDate("2026-09-04 02:14", Zone.newYork)
        let fire = FeedReminder.fireDate(feedAt: feedAt, afterMinutes: 180)
        XCTAssertNil(
            FeedReminder.scheduleDate(feedAt: feedAt, afterMinutes: 180, now: fire),
            "a trigger landing on the current instant is already past on arrival")
    }

    func testNonNilOneSecondBeforeTheBoundary() {
        let feedAt = makeDate("2026-09-04 02:14", Zone.newYork)
        let fire = FeedReminder.fireDate(feedAt: feedAt, afterMinutes: 180)
        XCTAssertEqual(
            FeedReminder.scheduleDate(
                feedAt: feedAt, afterMinutes: 180, now: fire.addingTimeInterval(-1)),
            fire)
    }

    /// The two entry points must not drift, across a transition least of all.
    func testScheduleDateAgreesWithFireDate() {
        XCTAssertEqual(
            FeedReminder.scheduleDate(
                feedAt: makeDate("2026-03-08 00:30", Zone.newYork),
                afterMinutes: 180,
                now: makeDate("2026-03-08 00:31", Zone.newYork)),
            makeDate("2026-03-08 04:30", Zone.newYork))
    }

    // MARK: - body

    /// The wording is ours and is pinned. The clock rendering is `Fmt.clock`'s job and
    /// is locale- and ICU-dependent — recent OS versions emit U+202F before "AM" — so
    /// it is asserted by hour and minute rather than by the whole string. Pinning the
    /// full string would fail on an OS update for something that is not a bug.
    func testBodyStatesTheLastFeedTime() {
        let body = FeedReminder.body(
            lastFedAt: makeDate("2026-09-04 02:14", Zone.newYork),
            timeZone: TimeZone(identifier: Zone.newYork)!)

        XCTAssertTrue(body.hasPrefix("Feed reminder · last fed "), body)
        XCTAssertTrue(body.contains("2:14"), body)
        XCTAssertEqual(
            body.components(separatedBy: " · ").count, 2,
            "two segments only — the baby's name belongs to the notification title, "
                + "and repeating it here prints it twice on one lock screen")
    }

    /// The family's zone, never the device's. A doula working a household two zones
    /// over must not be told the client's night in her own clock.
    func testBodyUsesTheFamilysZoneNotTheDevices() {
        let instant = makeDate("2026-09-04 02:14", Zone.newYork)
        let newYork = FeedReminder.body(
            lastFedAt: instant, timeZone: TimeZone(identifier: Zone.newYork)!)
        let phoenix = FeedReminder.body(
            lastFedAt: instant, timeZone: TimeZone(identifier: Zone.phoenix)!)

        XCTAssertTrue(newYork.contains("2:14"), newYork)
        XCTAssertTrue(phoenix.contains("11:14"), phoenix)
        XCTAssertNotEqual(newYork, phoenix)
    }
    func testMalformedOffsetsAndDatesDoNotProduceASchedule() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        for minutes in [Int.min, -1, 0, 1441, Int.max] {
            XCTAssertNil(FeedReminder.scheduleDate(feedAt: now, afterMinutes: minutes, now: now))
        }
        XCTAssertNil(FeedReminder.scheduleDate(feedAt: Date(timeIntervalSince1970: .infinity), afterMinutes: 90, now: now))
    }

}
