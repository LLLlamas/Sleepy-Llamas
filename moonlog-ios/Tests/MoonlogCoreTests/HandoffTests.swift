import XCTest
@testable import MoonlogCore

/// The handoff is the app's actual output — what the parents read over coffee.
final class HandoffTests: XCTestCase {

    private let mia = UUID()
    private let leo = UUID()
    private let zone = TimeZone(identifier: Zone.newYork)!

    private var shift: ShiftWindow {
        ShiftWindow(
            startedAt: makeDate("2026-09-04 21:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork))
    }

    private func at(_ wall: String) -> Date { makeDate(wall, Zone.newYork) }

    private func text(
        babies: [HandoffBaby],
        caregiver: String? = "Cat",
        events: [EventSnapshot] = [],
        sessions: [SleepSnapshot] = [],
        unit: VolumeUnit = .oz
    ) -> String {
        Handoff.text(
            babies: babies, shift: shift, caregiver: caregiver,
            events: events, sessions: sessions, unit: unit,
            timeZone: zone, asOf: at("2026-09-05 06:00"))
    }

    func testHeaderNamesTheBabyTheDayAndTheHoursOnWatch() {
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(out.contains("Mia's night · Day 6"), out)
        // Not a literal "9:00 PM": Date.FormatStyle separates the meridiem with a
        // narrow no-break space (U+202F), so an ASCII-space literal never matches.
        XCTAssertTrue(out.contains("9:00"), out)
        XCTAssertTrue(out.contains("PM"), out)
        XCTAssertTrue(out.contains("9h 00m on watch"), "padded register for documents")
    }

    /// Prose, not chips. The parents read this; the doula reads the UI.
    func testFeedsAreWrittenAsProse() {
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-04 22:40"),
                          feedMethod: .breast, leftSeconds: 1080),
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:15"),
                          feedMethod: .bottleFormula, amountMl: 74),
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 04:00"),
                          feedMethod: .breast, leftSeconds: 480, rightSeconds: 360),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)

        XCTAssertTrue(out.contains("left breast — 18m"), out)
        XCTAssertTrue(out.contains("bottle, formula — 2.5 oz"), out)
        XCTAssertTrue(out.contains("both sides"), out)
        XCTAssertTrue(out.contains("Feeds · 3"), out)
    }

    /// Two registers, deliberately. An individual bottle is entered on a
    /// half-ounce grid, so "2 oz" is exact and "2.0 oz" is just noise. A TOTAL is a
    /// sum that does not sit on that grid, so rounding it to the nearest half
    /// misstates the figure a parent is most likely to write down.
    func testIndividualFeedsRoundToHalvesAndTotalsKeepADecimal() {
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                          feedMethod: .bottleFormula, amountMl: 59.15),
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 04:00"),
                          feedMethod: .bottleFormula, amountMl: 60),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("bottle, formula — 2 oz"), "per feed: no bare .0")
        XCTAssertTrue(out.contains("(4.0 oz by bottle)"), "total: keeps its precision")
    }

    /// A logged feed rendering as "0 oz" in the parents' handoff is the worst output
    /// this app can produce. Reachable when a family logged in ml then switched.
    func testASmallAmountNeverRoundsAwayToZero() {
        XCTAssertEqual(Fmt.amount(ml: 5, unit: .oz), "0.2 oz")
        XCTAssertEqual(Fmt.amount(ml: 1, unit: .oz), "0.1 oz")
        XCTAssertFalse(Fmt.amount(ml: 5, unit: .oz).hasPrefix("0 oz"))
    }

    func testDiapersAndStoolProgression() {
        let events = [
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-04 23:00"),
                          diaperContents: .both, stoolColor: .meconium),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:00"),
                          diaperContents: .wet),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 04:00"),
                          diaperContents: .dirty, stoolColor: .transitional),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("Diapers · 3"), out)
        XCTAssertTrue(out.contains("(2 wet, 2 dirty)"), "both counts as each")
        XCTAssertTrue(out.contains("Meconium → Transitional"),
                      "same casing as the Summary card")
    }

    func testSleepReportsTotalStretchesAndLongest() {
        let sessions = [
            SleepSnapshot(babyID: mia, startAt: at("2026-09-04 22:00"),
                          endAt: at("2026-09-05 00:10")),
            SleepSnapshot(babyID: mia, startAt: at("2026-09-05 01:00"),
                          endAt: at("2026-09-05 02:00")),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       sessions: sessions)
        XCTAssertTrue(out.contains("over 2 stretches"), out)
        XCTAssertTrue(out.contains("longest was 2h 10m"), out)
    }

    /// A note that says nothing is useless to the parents — the body must appear.
    func testNoteBodyAndFeverEscalationAppear() {
        let events = [
            EventSnapshot(babyID: mia, kind: .note, at: at("2026-09-05 02:05"),
                          text: "Spat up after the bottle", noteTags: ["Spit-up"]),
            EventSnapshot(babyID: mia, kind: .note, at: at("2026-09-05 03:00"),
                          tempF: 100.6),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("Spat up after the bottle"), out)
        XCTAssertTrue(out.contains("Spit-up"), out)
        XCTAssertTrue(out.contains("100.6°F"), out)
        XCTAssertTrue(out.contains("tell the parents"), "the app observes, it does not diagnose")
    }

    func testTwinsGetSeparateSectionsAndNeitherIsMixedIn() {
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                          feedMethod: .bottleFormula, amountMl: 60),
            EventSnapshot(babyID: leo, kind: .feed, at: at("2026-09-05 02:00"),
                          feedMethod: .bottleFormula, amountMl: 90),
            EventSnapshot(babyID: leo, kind: .diaper, at: at("2026-09-05 02:30"),
                          diaperContents: .wet),
        ]
        let out = text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
                     HandoffBaby(id: leo, name: "Leo", dayOfLife: 6)],
            events: events)

        XCTAssertTrue(out.contains("Mia & Leo's night"), out)
        XCTAssertTrue(out.contains("— Mia · Day 6 —"), out)
        XCTAssertTrue(out.contains("— Leo · Day 6 —"), out)

        let miaBlock = out.components(separatedBy: "— Leo").first ?? ""
        XCTAssertTrue(miaBlock.contains("Feeds · 1"), "Mia has one feed, not both")
        XCTAssertFalse(miaBlock.contains("Diapers · 1"), "Leo's diaper is not Mia's")
    }

    func testSignedOffByTheCaregiver() {
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(out.hasSuffix("With care,\nCat 🌙"), out)

        let anon = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                        caregiver: nil)
        XCTAssertTrue(anon.hasSuffix("🌙 logged with Moonlog"), anon)
    }

    /// An open session at the end of the shift is clipped, not run to `now`.
    func testStillAsleepIsCountedOnlyToTheShiftEnd() {
        let sessions = [SleepSnapshot(babyID: mia, startAt: at("2026-09-05 05:40"))]
        let out = Handoff.text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            shift: shift, caregiver: "Cat", events: [], sessions: sessions,
            unit: .oz, timeZone: zone, asOf: at("2026-09-12 06:00"))
        XCTAssertTrue(out.contains("Sleep · 20m"), out)
    }
}
