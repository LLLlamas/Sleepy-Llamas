import XCTest
@testable import MoonlogCore

/// The prefill for the shift pickers. Every DST fact asserted here was read out of
/// this machine's tz database with `zdump -v`, and every Foundation behaviour was
/// observed by running it, not taken from the documentation:
///
/// | Fixture | Fact |
/// |---|---|
/// | New York 2026-03-08 | 01:59:59 EST → 03:00:00 EDT; **02:00–02:59 does not exist** |
/// | New York 2026-11-01 | 01:59:59 EDT → 01:00:00 EST; **01:00–01:59 happens twice** |
/// | Lord Howe 2026-10-04 | 01:59:59 +1030 → 02:30:00 +11; **02:00–02:29 does not exist** |
/// | Lord Howe 2026-04-05 | 01:59:59 +11 → 01:30:00 +1030; **01:30–01:59 happens twice** |
/// | New York 2027-03-14 | spring forward |
/// | Phoenix | no transitions — the control |
final class ShiftDefaultsTests: XCTestCase {

    private let nightWindow = ShiftWindowDefault(startMinute: 22 * 60, endMinute: 6 * 60)
    private let dayWindow = ShiftWindowDefault(startMinute: 9 * 60, endMinute: 17 * 60)

    // MARK: - The window itself

    func testCrossingMidnightIsExpressedByEndNotExceedingStart() {
        XCTAssertTrue(nightWindow.crossesMidnight)
        XCTAssertFalse(dayWindow.crossesMidnight)
    }

    func testDurationWrapsForACrossingWindowAndDoesNotForANonCrossingOne() {
        XCTAssertEqual(nightWindow.durationMinutes, 480)
        XCTAssertEqual(dayWindow.durationMinutes, 480)
    }

    /// Start and end on the same minute is a whole day, not nothing. Returning 0 here
    /// would make the plausibility gate in `suggestedStart` accept only an exact hit.
    func testEqualMinutesIsAFullDayNotZero() {
        let window = ShiftWindowDefault(startMinute: 90, endMinute: 90)
        XCTAssertEqual(window.durationMinutes, 1440)
        XCTAssertTrue(window.crossesMidnight)
    }

    /// `%` keeps the sign of its dividend, so an unwrapped -60 stays -60 and names an
    /// hour that does not exist.
    func testInitWrapsMinutesIntoASingleDay() {
        XCTAssertEqual(ShiftWindowDefault(startMinute: -60, endMinute: 1500).startMinute, 1380)
        XCTAssertEqual(ShiftWindowDefault(startMinute: -60, endMinute: 1500).endMinute, 60)
        XCTAssertEqual(ShiftWindowDefault(startMinute: -1441, endMinute: 2880).startMinute, 1439)
        XCTAssertEqual(ShiftWindowDefault(startMinute: -1441, endMinute: 2880).endMinute, 0)
    }

    // MARK: - Start minutes that name a local time which does not exist

    /// New York skips 02:00–02:59 on 2026-03-08, so a 02:00 start has to resolve
    /// forward to 03:00 EDT. Landing on 01:00 would be the classic hour-off bug, and
    /// crashing would be worse.
    func testNonexistentStartResolvesForwardOnSpringForward() throws {
        let cal = calendar(Zone.newYork)
        let window = ShiftWindowDefault(startMinute: 2 * 60, endMinute: 10 * 60)
        let now = makeDate("2026-03-08 03:30", Zone.newYork)

        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(window, now: now, calendar: cal))

        let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        XCTAssertEqual(parts.day, 8)
        XCTAssertEqual(parts.hour, 3, "02:00 does not exist; the gap resolves forward to 03:00")
        XCTAssertEqual(parts.minute, 0)
        XCTAssertNotEqual(parts.hour, 1, "resolving backward would be the hour-off bug")
    }

    /// Lord Howe skips only 02:00–02:29, and this is where Foundation stops doing what
    /// you would guess. `matchingPolicy: .nextTime` does **not** land on 02:30: it
    /// resolves 02:00 to the *next day*, so the nearest occurrence is a day away and
    /// the plausibility gate refuses it. That is the intended outcome — the picker
    /// falls back to `now`, and no prefill beats a wrong one.
    ///
    /// This is also the case that kills any "±1 hour" special case: a hardcoded +1h
    /// would answer 03:00 here and still pass the New York test above.
    func testNonexistentStartOnAHalfHourTransitionYieldsNoPrefillRatherThanAWrongOne() {
        let cal = calendar(Zone.lordHowe)
        let window = ShiftWindowDefault(startMinute: 2 * 60, endMinute: 10 * 60)
        let now = makeDate("2026-10-04 04:00", Zone.lordHowe)

        XCTAssertNil(
            ShiftDefaults.suggestedStart(window, now: now, calendar: cal),
            "the only occurrences near 2026-10-04 02:00 are a day away")
    }

    /// The same zone and the same window one day later, to show the zone itself is
    /// fine and it really is the transition doing it.
    func testTheSameLordHoweWindowPrefillsNormallyOffTheTransitionDay() throws {
        let cal = calendar(Zone.lordHowe)
        let window = ShiftWindowDefault(startMinute: 2 * 60, endMinute: 10 * 60)
        let now = makeDate("2026-10-05 04:00", Zone.lordHowe)

        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(window, now: now, calendar: cal))
        XCTAssertEqual(start, makeDate("2026-10-05 02:00", Zone.lordHowe))
    }

    // MARK: - Start minutes that are ambiguous

    /// 01:30 happens twice on 2026-11-01 in New York. Which one is picked barely
    /// matters; that both devices pick the *same* one is the whole point, so the
    /// expected instant is built physically from an unambiguous midnight rather than
    /// parsed from an ambiguous wall clock.
    func testAmbiguousStartIsDeterministicOnFallBack() throws {
        let cal = calendar(Zone.newYork)
        let window = ShiftWindowDefault(startMinute: 90, endMinute: 9 * 60 + 30)
        let midnight = makeDate("2026-11-01 00:00", Zone.newYork)
        let firstOccurrence = midnight.addingTimeInterval(90 * 60)      // 01:30 EDT
        let secondOccurrence = midnight.addingTimeInterval(150 * 60)    // 01:30 EST
        XCTAssertNotEqual(firstOccurrence, secondOccurrence, "precondition: really ambiguous")

        let now = midnight.addingTimeInterval(180 * 60)                 // 02:00 EST
        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(window, now: now, calendar: cal))

        XCTAssertEqual(start, firstOccurrence, "repeatedTimePolicy .first, and it must stick")
        XCTAssertEqual(
            start, ShiftDefaults.suggestedStart(window, now: now, calendar: cal),
            "two calls must agree, or two devices will not")
    }

    /// Lord Howe repeats 01:30–01:59 on 2026-04-05, so 01:40 is ambiguous in the tz
    /// database. Foundation, however, does **not** treat it as ambiguous here:
    /// `date(bySettingHour:)` returns the +11 occurrence for `repeatedTimePolicy`
    /// `.first` *and* `.last`, which was checked directly rather than assumed. So this
    /// test pins the instant, and the New York case above is the one that pins the
    /// policy. Kept because the instant is what the picker shows, and a change that
    /// moved it by thirty minutes should fail something.
    func testAmbiguousStartIsDeterministicOnAHalfHourFallBack() throws {
        let cal = calendar(Zone.lordHowe)
        let window = ShiftWindowDefault(startMinute: 100, endMinute: 9 * 60 + 40)
        let midnight = makeDate("2026-04-05 00:00", Zone.lordHowe)
        let firstOccurrence = midnight.addingTimeInterval(100 * 60)     // 01:40 +11
        let secondOccurrence = midnight.addingTimeInterval(130 * 60)    // 01:40 +1030
        XCTAssertNotEqual(firstOccurrence, secondOccurrence, "precondition: really ambiguous")

        let now = midnight.addingTimeInterval(180 * 60)
        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(window, now: now, calendar: cal))

        XCTAssertEqual(start, firstOccurrence)
    }

    // MARK: - The control

    func testPhoenixHasNoTransitionToTripOver() throws {
        let cal = calendar(Zone.phoenix)
        let now = makeDate("2026-03-08 22:30", Zone.phoenix)

        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(nightWindow, now: now, calendar: cal))
        XCTAssertEqual(start, makeDate("2026-03-08 22:00", Zone.phoenix))

        let end = ShiftDefaults.suggestedEnd(nightWindow, after: start, calendar: cal)
        XCTAssertEqual(end, makeDate("2026-03-09 06:00", Zone.phoenix))
        XCTAssertEqual(
            end.timeIntervalSince(start), 8 * 3600, accuracy: 0.5,
            "no DST here, so the clock span and the physical span coincide")
    }

    // MARK: - suggestedEnd across a transition

    /// **The one that matters.** 22:00→06:00 is eight hours *on the clock*. On the
    /// night the clocks go forward it is seven *physical* hours, so asserting
    /// `end.timeIntervalSince(start) == 8 * 3600` would be asserting the bug. The
    /// wall-clock components are the contract; the physical span is recorded second,
    /// as the thing that is allowed to vary.
    func testEndKeepsItsWallClockTimeAcrossSpringForward() {
        let cal = calendar(Zone.newYork)
        let start = makeDate("2027-03-13 22:00", Zone.newYork)

        let end = ShiftDefaults.suggestedEnd(nightWindow, after: start, calendar: cal)

        let parts = cal.dateComponents([.day, .hour, .minute], from: end)
        XCTAssertEqual(parts.day, 14)
        XCTAssertEqual(parts.hour, 6)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(
            end.timeIntervalSince(start), 7 * 3600, accuracy: 0.5,
            "eight hours on the clock is seven in the world on this night")
    }

    func testEndKeepsItsWallClockTimeAcrossFallBack() {
        let cal = calendar(Zone.newYork)
        let start = makeDate("2026-10-31 22:00", Zone.newYork)

        let end = ShiftDefaults.suggestedEnd(nightWindow, after: start, calendar: cal)

        let parts = cal.dateComponents([.day, .hour, .minute], from: end)
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(parts.hour, 6)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(
            end.timeIntervalSince(start), 9 * 3600, accuracy: 0.5,
            "and nine on this one")
    }

    /// Lord Howe again, because a half-hour transition is the case a "the night is
    /// either 7 or 9 hours" assumption gets wrong: here it is 7.5 and 8.5.
    func testEndKeepsItsWallClockTimeAcrossAHalfHourTransition() {
        let cal = calendar(Zone.lordHowe)

        let springStart = makeDate("2026-10-03 22:00", Zone.lordHowe)
        let springEnd = ShiftDefaults.suggestedEnd(nightWindow, after: springStart, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.hour], from: springEnd).hour, 6)
        XCTAssertEqual(
            springEnd.timeIntervalSince(springStart), 7.5 * 3600, accuracy: 0.5,
            "thirty minutes, not sixty")

        let autumnStart = makeDate("2026-04-04 22:00", Zone.lordHowe)
        let autumnEnd = ShiftDefaults.suggestedEnd(nightWindow, after: autumnStart, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.hour], from: autumnEnd).hour, 6)
        XCTAssertEqual(
            autumnEnd.timeIntervalSince(autumnStart), 8.5 * 3600, accuracy: 0.5)
    }

    // MARK: - Plausibility

    /// The bug this whole file exists to prevent: arriving at 04:00 must not prefill
    /// 22:00 and credit the parents six hours nobody watched.
    func testArrivingLateInTheWindowPrefillsNothingRatherThanTheWindowStart() {
        let cal = calendar(Zone.newYork)
        let now = makeDate("2026-06-11 04:00", Zone.newYork)

        XCTAssertNil(ShiftDefaults.suggestedStart(nightWindow, now: now, calendar: cal))
    }

    func testArrivingJustAfterTheHourPrefillsTheHour() throws {
        let cal = calendar(Zone.newYork)
        let now = makeDate("2026-06-10 22:05", Zone.newYork)

        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(nightWindow, now: now, calendar: cal))
        XCTAssertEqual(start, makeDate("2026-06-10 22:00", Zone.newYork))
    }

    /// Arriving exactly on the hour must prefill *this* occurrence, not yesterday's.
    /// A backward `nextDate(after:)` search is strictly before its anchor and gets
    /// this wrong by 24 hours.
    func testArrivingExactlyOnTheHourPrefillsThisOccurrence() throws {
        let cal = calendar(Zone.newYork)
        let now = makeDate("2026-06-10 22:00", Zone.newYork)

        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(nightWindow, now: now, calendar: cal))
        XCTAssertEqual(start, now)
    }

    /// Arriving ten minutes early yields nothing, deliberately: 22:00 is further ahead
    /// than `CareStore.rejectFuture` tolerates, so offering it would put a Start button
    /// on screen that cannot succeed. The caller falls back to `now`, which records
    /// when she actually started.
    func testArrivingBeforeTheWindowPrefillsNothingBecauseTheActorWouldRefuseIt() {
        let cal = calendar(Zone.newYork)
        let now = makeDate("2026-06-10 21:50", Zone.newYork)

        XCTAssertNil(ShiftDefaults.suggestedStart(nightWindow, now: now, calendar: cal))
    }

    // MARK: - The invariant that links this to the writer

    /// Whatever `suggestedStart` returns, `CareStore.rejectFuture` must accept it.
    /// Swept across every fixture zone, every transition day and every hour, because
    /// the one combination that violates it is the one that ships a dead button.
    ///
    /// `now` is built by adding whole hours to an unambiguous midnight rather than by
    /// parsing a wall clock: 02:15 does not exist in New York on 2026-03-08, and the
    /// fixture helper would rather fail than guess.
    func testANonNilPrefillIsNeverOneTheActorWouldRefuse() {
        let windows = [
            nightWindow,
            dayWindow,
            ShiftWindowDefault(startMinute: 2 * 60, endMinute: 10 * 60),
            ShiftWindowDefault(startMinute: 90, endMinute: 90),
        ]
        let days = ["2026-03-08", "2026-11-01", "2026-10-04", "2026-04-05", "2026-06-10"]

        for zone in [Zone.newYork, Zone.phoenix, Zone.lordHowe, Zone.london] {
            let cal = calendar(zone)
            for day in days {
                let midnight = makeDate("\(day) 00:00", zone)
                for hour in 0..<24 {
                    let now = midnight.addingTimeInterval(Double(hour) * 3600)
                    for window in windows {
                        guard let start = ShiftDefaults.suggestedStart(
                            window, now: now, calendar: cal) else { continue }
                        XCTAssertFalse(
                            start.isMeaningfullyInFuture(asOf: now),
                            "\(zone) \(day) +\(hour)h, window "
                                + "\(window.startMinute)-\(window.endMinute): "
                                + "prefill \(start) would be refused by rejectFuture")
                    }
                }
            }
        }
    }

    /// The same invariant against the real clock, which is the one
    /// `Date.isMeaningfullyInFuture` — and therefore `CareStore.rejectFuture` — will
    /// actually consult. A window starting this very minute must prefill, and the
    /// prefill must survive the actor.
    func testAPrefillForTheCurrentMinuteSurvivesTheRealClockCheck() throws {
        let cal = calendar(Zone.newYork)
        let now = Date()
        let parts = cal.dateComponents([.hour, .minute], from: now)
        let minute = try XCTUnwrap(parts.hour) * 60 + XCTUnwrap(parts.minute)
        let window = ShiftWindowDefault(startMinute: minute, endMinute: minute + 480)

        let start = try XCTUnwrap(
            ShiftDefaults.suggestedStart(window, now: now, calendar: cal),
            "a window starting this minute must prefill")
        XCTAssertFalse(
            start.isMeaningfullyInFuture,
            "CareStore.rejectFuture would refuse this prefill")
        XCTAssertLessThanOrEqual(start, now, "the current minute began at or before now")
    }
}
