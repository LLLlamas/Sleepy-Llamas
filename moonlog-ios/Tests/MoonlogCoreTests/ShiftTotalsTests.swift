import XCTest
@testable import MoonlogCore

final class ShiftTotalsTests: XCTestCase {

    private let babyA = UUID()
    private let babyB = UUID()

    private var shift: ShiftWindow {
        ShiftWindow(
            startedAt: makeDate("2026-09-04 22:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork)
        )
    }

    private func at(_ wall: String) -> Date { makeDate(wall, Zone.newYork) }

    // MARK: - Events

    func testCountsFeedsDiapersAndNotesWithAmounts() {
        let events = [
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-04 23:00"),
                          feedMethod: .bottleFormula, amountMl: 60, feedDurationSeconds: 900),
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-05 02:00"),
                          feedMethod: .breastLeft, feedDurationSeconds: 840),
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 02:10"),
                          diaperContents: .both, stoolColor: .transitional),
            EventSnapshot(babyID: babyA, kind: .note, at: at("2026-09-05 03:00"),
                          noteTags: ["spit-up"]),
        ]

        let t = Totals.compute(events: events, sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)

        XCTAssertEqual(t.feeds, 2)
        XCTAssertEqual(t.feedMl, 60)
        XCTAssertEqual(t.feedSeconds, 1740)
        XCTAssertEqual(t.diapers, 1)
        XCTAssertEqual(t.notes, 1)
    }

    /// "Both" counts toward wet *and* dirty — the PWA's behavior, and the one a
    /// pediatrician's wet-nappy count depends on.
    func testBothCountsAsWetAndDirty() {
        let events = [
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 00:10"),
                          diaperContents: .wet),
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 01:10"),
                          diaperContents: .dirty),
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 02:10"),
                          diaperContents: .both),
        ]
        let t = Totals.compute(events: events, sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.diapers, 3)
        XCTAssertEqual(t.wet, 2)
        XCTAssertEqual(t.dirty, 2)
    }

    /// Stool progression is first-seen order and de-duplicated, because whether
    /// meconium has cleared is what the report is actually communicating.
    func testStoolProgressionIsFirstSeenOrderAndDeduplicated() {
        let events = [
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 03:00"),
                          diaperContents: .dirty, stoolColor: .transitional),
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 00:30"),
                          diaperContents: .dirty, stoolColor: .meconium),
            EventSnapshot(babyID: babyA, kind: .diaper, at: at("2026-09-05 04:00"),
                          diaperContents: .dirty, stoolColor: .transitional),
        ]
        // Deliberately passed out of chronological order.
        let t = Totals.compute(events: events, sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.stoolProgression, [.meconium, .transitional])
    }

    func testHighestTemperatureAndFeverFlag() {
        var events = [
            EventSnapshot(babyID: babyA, kind: .note, at: at("2026-09-05 01:00"), tempF: 99.1),
            EventSnapshot(babyID: babyA, kind: .note, at: at("2026-09-05 02:00"), tempF: 98.6),
        ]
        var t = Totals.compute(events: events, sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.highestTempF, 99.1)
        XCTAssertFalse(t.hasFever)

        events.append(
            EventSnapshot(babyID: babyA, kind: .note, at: at("2026-09-05 03:00"), tempF: 100.4))
        t = Totals.compute(events: events, sessions: [], forBaby: babyA,
                           shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.highestTempF, 100.4)
        XCTAssertTrue(t.hasFever, "the threshold is inclusive")
    }

    // MARK: - Clipping

    func testEventsOutsideTheShiftAreExcluded() {
        let events = [
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-04 21:00")),  // before
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-05 00:00")),  // inside
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-05 09:00")),  // after
        ]
        let t = Totals.compute(events: events, sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.feeds, 1)
    }

    /// `stretches` counts sessions that actually contributed. The web version
    /// counted every session it was handed, so a stray from another night inflated
    /// the count even when it added no time.
    func testStretchesCountsOnlyContributingSessions() {
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 00:00"),
                          endAt: at("2026-09-05 01:00")),
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-03 00:00"),   // another night
                          endAt: at("2026-09-03 02:00")),
        ]
        let t = Totals.compute(events: [], sessions: sessions, forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.stretches, 1)
        XCTAssertEqual(t.sleepSeconds, 3600, accuracy: 0.5)
        XCTAssertEqual(t.longestStretchSeconds, 3600, accuracy: 0.5)
    }

    /// The runaway bug again, this time through the totals path that the handoff
    /// actually renders.
    func testTotalsAreStableAfterTheShiftEnds() {
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 05:40"), endAt: nil)
        ]
        let atEnd = Totals.compute(events: [], sessions: sessions, forBaby: babyA,
                                   shift: shift, asOf: at("2026-09-05 06:00"))
        let muchLater = Totals.compute(events: [], sessions: sessions, forBaby: babyA,
                                       shift: shift, asOf: at("2026-09-12 06:00"))
        XCTAssertEqual(atEnd, muchLater)
        XCTAssertEqual(atEnd.sleepSeconds, 20 * 60, accuracy: 0.5)
    }

    func testLongestStretchUsesClippedNotRawDuration() {
        // Six hours long, but only the last two fall inside the shift.
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-04 18:00"),
                          endAt: at("2026-09-05 00:00")),
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 01:00"),
                          endAt: at("2026-09-05 04:00")),
        ]
        let t = Totals.compute(events: [], sessions: sessions, forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t.longestStretchSeconds, 3 * 3600, accuracy: 0.5,
                       "the 3h stretch inside the shift beats the clipped 2h remnant")
        XCTAssertEqual(t.sleepSeconds, 5 * 3600, accuracy: 0.5)
    }

    // MARK: - Twins

    func testTotalsAreScopedToOneBaby() {
        let events = [
            EventSnapshot(babyID: babyA, kind: .feed, at: at("2026-09-05 00:00"), amountMl: 60),
            EventSnapshot(babyID: babyB, kind: .feed, at: at("2026-09-05 00:30"), amountMl: 90),
            EventSnapshot(babyID: babyB, kind: .diaper, at: at("2026-09-05 01:00"),
                          diaperContents: .wet),
        ]
        let a = Totals.compute(events: events, sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        let b = Totals.compute(events: events, sessions: [], forBaby: babyB,
                               shift: shift, asOf: .distantFuture)

        XCTAssertEqual(a.feeds, 1)
        XCTAssertEqual(a.feedMl, 60)
        XCTAssertEqual(a.diapers, 0)

        XCTAssertEqual(b.feeds, 1)
        XCTAssertEqual(b.feedMl, 90)
        XCTAssertEqual(b.diapers, 1)
    }

    func testEmptyShiftProducesZeroTotals() {
        let t = Totals.compute(events: [], sessions: [], forBaby: babyA,
                               shift: shift, asOf: .distantFuture)
        XCTAssertEqual(t, ShiftTotals())
    }
}
