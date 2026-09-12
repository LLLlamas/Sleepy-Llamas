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
        XCTAssertTrue(out.contains("(about 4.0 oz by bottle)"), "total: keeps its precision")
    }

    /// A logged feed rendering as "0 oz" in the parents' handoff is the worst output
    /// this app can produce. Reachable when a family logged in ml then switched.
    func testASmallAmountNeverRoundsAwayToZero() {
        XCTAssertEqual(Fmt.amount(ml: 5, unit: .oz), "0.17 oz")
        XCTAssertEqual(Fmt.amount(ml: 1, unit: .oz), "0.03 oz")
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
        XCTAssertTrue(out.contains("longest 2h 10m"), out)
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

    /// Archiving a baby mid-shift used to delete their whole night from the
    /// parents' document: the records stayed in the store, and the roster the
    /// handoff was composed from stopped naming them.
    func testAnArchivedBabyWithRecordsInTheShiftIsStillWrittenUp() {
        let babies = [
            HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
            HandoffBaby(id: leo, name: "Leo", dayOfLife: 6, isArchived: true),
        ]
        let events = [
            EventSnapshot(babyID: leo, kind: .feed, at: at("2026-09-05 02:00"),
                          feedMethod: .bottleFormula, amountMl: 90),
            EventSnapshot(babyID: leo, kind: .diaper, at: at("2026-09-05 02:30"),
                          diaperContents: .wet),
        ]
        let roster = Handoff.roster(babies, loggedFor: [leo])
        XCTAssertEqual(roster.map(\.name), ["Mia", "Leo"], "order is the caller's")

        let out = text(babies: roster, events: events)
        XCTAssertTrue(out.contains("— Leo · Day 6 —"), out)
        // 90 ml is 3.04 oz. Direct amount entry means the display no longer snaps
        // to the stepper's half-ounce grid, so a typed 2.25 oz reads back unaltered.
        XCTAssertTrue(out.contains("bottle, formula — 3.04 oz"), out)
        XCTAssertFalse(out.contains("Not matched to a baby"),
                       "Leo is on the roster, so nothing of his is orphaned")
    }

    /// The other half of the rule: a discharged baby who was not cared for tonight
    /// would otherwise get a section of zeroes on a page read at 6am.
    func testAnArchivedBabyWithNothingLoggedIsLeftOutEntirely() {
        let babies = [
            HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
            HandoffBaby(id: leo, name: "Leo", dayOfLife: 6, isArchived: true),
        ]
        let roster = Handoff.roster(babies, loggedFor: [mia])
        XCTAssertEqual(roster.map(\.name), ["Mia"])

        let out = text(
            babies: roster,
            events: [EventSnapshot(babyID: mia, kind: .diaper,
                                   at: at("2026-09-05 02:00"), diaperContents: .wet)])
        XCTAssertFalse(out.contains("Leo"), out)
        XCTAssertTrue(out.contains("Mia's night · Day 6"),
                      "one baby again, so the twin headings stay away")
    }

    /// A record whose baby resolves to nobody — deleted out from under its history,
    /// or a relationship still in flight from sync — was invisible: no block in the
    /// document claimed it, so the night silently lost feeds.
    func testRecordsForABabyNobodyCanNameAreStillReported() {
        let ghost = UUID()
        let events = [
            EventSnapshot(babyID: ghost, kind: .diaper, at: at("2026-09-05 02:00"),
                          diaperContents: .wet),
            EventSnapshot(babyID: ghost, kind: .note, at: at("2026-09-05 03:00"),
                          text: "Fussy at the change"),
        ]
        let sessions = [
            SleepSnapshot(babyID: ghost, startAt: at("2026-09-05 04:00"),
                          endAt: at("2026-09-05 05:00")),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events, sessions: sessions)

        XCTAssertTrue(out.contains("Not matched to a baby · 3 records"), out)
        XCTAssertTrue(out.contains("wet diaper"), out)
        XCTAssertTrue(out.contains("Fussy at the change"), out)
        XCTAssertTrue(out.contains("asleep — 1h"), out)
        XCTAssertTrue(out.contains("Diapers · 0"), "and none of it lands on Mia")
    }

    /// A pump carries no baby by design. It is a household total, not a record that
    /// lost its owner, and must never be reported as one.
    func testAPumpIsNeverMistakenForAnUnattributedRecord() {
        let out = text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            events: [EventSnapshot(babyID: EventSnapshot.noBaby, kind: .pump,
                                   at: at("2026-09-05 01:00"), pumpedMl: 120)])
        XCTAssertTrue(out.contains("Pumped · 4.1 oz over 1 session"), out)
        XCTAssertFalse(out.contains("Not matched to a baby"), out)
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

    // MARK: - The letter

    /// The document is a letter, not a table: a header, a line addressed to the
    /// parents, the night in a fixed order, a sign-off. The greeting is the part
    /// that was missing — a page that opens on "🍼 Feeds · 3" is a report.
    func testItOpensWithAGreetingAndClosesWithASignOff() {
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(
            out.contains("Good morning. Here is Mia's night, just as it happened."), out)
        XCTAssertTrue(out.hasSuffix("With care,\nCat 🌙"), out)
    }

    /// "Good morning" is only true of a finished night, and this document can be
    /// sent mid-shift — the doula shares it at 1am so the parents know where things
    /// stand. Greeting them with the wrong time of day is the small wrongness that
    /// makes a letter read as generated.
    func testAnOpenShiftIsNotGreetedAsAMorning() {
        let open = ShiftWindow(startedAt: at("2026-09-04 21:00"))
        let out = Handoff.text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            shift: open, caregiver: "Cat", events: [], sessions: [],
            unit: .oz, timeZone: zone, asOf: at("2026-09-05 01:00"))
        XCTAssertFalse(out.contains("Good morning"), out)
        XCTAssertTrue(out.contains("Here is Mia's night so far"), out)
        XCTAssertTrue(out.contains("summary through"), "and the shift is still open")
        XCTAssertTrue(out.contains("4h 00m so far"), out)
    }

    /// The date is the answer to "which night was this?" — worth whole words on a
    /// document the family keeps, where "Fri, Sep 4" is the register of a list.
    func testTheDateIsWrittenOut() {
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(out.contains(Fmt.longDate(shift.startedAt, timeZone: zone)), out)
        XCTAssertFalse(out.contains(Fmt.nightOf(shift.startedAt, timeZone: zone)),
                       "not the abbreviated form as well")
    }

    /// The order the sections come in is fixed. The parents read one of these every
    /// morning; a document whose sections move has to be re-read rather than
    /// scanned.
    func testTheSectionsComeInAFixedOrder() {
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                          feedMethod: .bottleFormula, amountMl: 60),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:00"),
                          diaperContents: .wet),
            EventSnapshot(babyID: mia, kind: .medication, at: at("2026-09-05 03:00"),
                          medicationName: "Vitamin D"),
            EventSnapshot(babyID: mia, kind: .note, at: at("2026-09-05 04:00"),
                          text: "Settled quickly"),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events,
                       sessions: [SleepSnapshot(babyID: mia,
                                                startAt: at("2026-09-05 04:30"),
                                                endAt: at("2026-09-05 05:30"))])
        let order = ["Feeds ·", "Diapers ·", "Sleep ·", "Medication ·", "Notes"]
        var cursor = out.startIndex
        for marker in order {
            guard let found = out.range(of: marker, range: cursor..<out.endIndex) else {
                return XCTFail("\(marker) missing or out of order in:\n\(out)")
            }
            cursor = found.upperBound
        }
    }

    // MARK: - Feeds

    /// A total is a sum of amounts read off a bottle in the dark. "about" is the
    /// honest register for it, and the PWA had it before the port dropped the word.
    /// Breast time rides alongside rather than folding in: a night of two bottles
    /// and forty minutes at the breast is not four ounces of feeding.
    func testTheFeedTotalIsHedgedAndBreastTimeIsReportedBesideIt() {
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                          feedMethod: .bottleFormula, amountMl: 60),
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 03:00"),
                          feedMethod: .breast, leftSeconds: 1080, rightSeconds: 720),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("about 2.0 oz by bottle · 30m at the breast"), out)
    }

    func testANightWithNoFeedsSaysSoInAWholeSentence() {
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(out.contains("No feeds logged this shift."), out)
    }

    // MARK: - Sleep

    /// Sleep was the one section that gave a total where feeds and notes gave a
    /// sequence, so a parent asking "when did she go down?" had nothing to read.
    func testEachStretchOfSleepIsListedAndClippedToTheShift() {
        let sessions = [
            // Started before the doula arrived: reported from when she was there to
            // watch it, so the rows add up to the total printed above them.
            SleepSnapshot(babyID: mia, startAt: at("2026-09-04 20:30"),
                          endAt: at("2026-09-04 22:00")),
            SleepSnapshot(babyID: mia, startAt: at("2026-09-05 01:00"),
                          endAt: at("2026-09-05 02:45")),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       sessions: sessions)
        XCTAssertTrue(out.contains("9:00p  → 10:00p · 1h"), "clipped to the shift start")
        XCTAssertFalse(out.contains("8:30p"), "the half hour before the shift is not hers")
        XCTAssertTrue(out.contains("1:00a  → 2:45a · 1h 45m"), out)
        XCTAssertTrue(out.contains("Sleep · 2h 45m over 2 stretches"), out)
    }

    /// One stretch is its own longest, and saying so prints the same number twice.
    func testASingleStretchDoesNotReportItselfAsTheLongest() {
        let out = text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            sessions: [SleepSnapshot(babyID: mia, startAt: at("2026-09-05 01:00"),
                                     endAt: at("2026-09-05 02:00"))])
        XCTAssertTrue(out.contains("Sleep · 1h over 1 stretch"), out)
        XCTAssertFalse(out.contains("longest"), out)
    }

    /// An open stretch has no end to print, so it says "so far" — the same honesty
    /// the header applies to an open shift.
    func testAnOpenStretchSaysSoFarRatherThanInventingAnEnd() {
        let out = text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            sessions: [SleepSnapshot(babyID: mia, startAt: at("2026-09-05 05:40"))])
        XCTAssertTrue(out.contains("still asleep · 20m so far"), out)
        XCTAssertTrue(out.contains("still asleep, since"), "and the time they went down")
    }

    // MARK: - Diapers, now that a wet one can carry a colour

    /// The diaper sheet offers the colour swatches for every contents choice, so a
    /// legal record is `contents: .wet` with a colour against it — and
    /// `stoolProgression` collects a colour from any diaper that carries one. A
    /// fixed "Stool" label then reports stool on a night that had none, which is
    /// the one thing this line is read for.
    func testAColourOnAWetDiaperIsNeverReportedAsStool() {
        let events = [
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:00"),
                          diaperContents: .wet, stoolColor: .yellow),
        ]
        let baby = HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)
        let out = text(babies: [baby], events: events)
        XCTAssertTrue(out.contains("(1 wet, 0 dirty)"), out)
        XCTAssertTrue(out.contains("Colour: Yellow"), out)
        XCTAssertFalse(out.contains("Stool"), "no dirty diaper contributed a colour")

        // And the keepsake says it the same way, because both ask one helper.
        let page = HandoffHTML.render(
            babies: [baby], shift: shift, caregiver: "Cat", note: nil,
            events: events, sessions: [], unit: .oz, timeZone: zone,
            asOf: at("2026-09-05 06:00"))
        XCTAssertTrue(page.contains("Colour: Yellow"), page)
        XCTAssertFalse(page.contains("Stool:"), page)
    }

    /// The other half: as soon as a dirty diaper carries one of those colours, the
    /// progression is a stool progression again and is named as one.
    func testAColourOnADirtyDiaperIsStillReportedAsStool() {
        let events = [
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:00"),
                          diaperContents: .wet, stoolColor: .meconium),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 04:00"),
                          diaperContents: .both, stoolColor: .transitional),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("Stool: Meconium → Transitional"), out)
    }

    /// The label is public so the Summary card asks the same question the handoff
    /// asks, rather than hard-coding a word that used to be safe.
    func testTheColourLabelIsTheSameDecisionEverywhere() {
        let wetOnly = [EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:00"),
                                     diaperContents: .wet, stoolColor: .yellow)]
        let dirty = wetOnly + [EventSnapshot(babyID: mia, kind: .diaper,
                                             at: at("2026-09-05 03:00"),
                                             diaperContents: .dirty, stoolColor: .green)]
        XCTAssertEqual(Handoff.diaperColourLabel(in: wetOnly, forBaby: mia), "Colour")
        XCTAssertEqual(Handoff.diaperColourLabel(in: dirty, forBaby: mia), "Stool")
        XCTAssertEqual(Handoff.diaperColourLabel(in: dirty, forBaby: leo), "Colour",
                       "Leo logged nothing, so nothing of Mia's answers for him")
        XCTAssertEqual(Handoff.diaperColourLabel(in: dirty), "Stool",
                       "no baby asked about means the whole household")
    }

    /// A stray record has one line to say what it was, and the colour is the only
    /// detail in it worth the room — the more so now that a wet diaper can carry one.
    func testAStrayDiaperNamesItsColour() {
        let ghost = UUID()
        let out = text(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            events: [EventSnapshot(babyID: ghost, kind: .diaper,
                                   at: at("2026-09-05 02:00"),
                                   diaperContents: .wet, stoolColor: .yellow)])
        XCTAssertTrue(out.contains("wet diaper — yellow"), out)
    }

    // MARK: - The two documents

    /// The anti-drift rule, applied to the words rather than the numbers: the page
    /// the family keeps opens with the same sentence the 6am message did.
    func testBothDocumentsOpenWithTheSameSentence() {
        let babies = [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
                      HandoffBaby(id: leo, name: "Leo", dayOfLife: 6)]
        let greeting = Handoff.greeting(babies: babies, shift: shift)
        let plain = text(babies: babies)
        let page = HandoffHTML.render(
            babies: babies, shift: shift, caregiver: "Cat", note: nil,
            events: [], sessions: [], unit: .oz, timeZone: zone,
            asOf: at("2026-09-05 06:00"))
        XCTAssertTrue(greeting.contains("Mia & Leo's night"), greeting)
        XCTAssertTrue(plain.contains(greeting), plain)
        // The page escapes the apostrophe and the ampersand, so it carries the same
        // sentence in the only form HTML can hold it.
        XCTAssertTrue(page.contains("Mia &amp; Leo&#39;s night, just as it happened."), page)
    }
    // MARK: - Every record carries the time it happened

    /// Diapers were a count and a colour, on the theory that eight rows of "wet" is
    /// not the shape of a night. But this document is the record the family hands to
    /// their pediatrician, and a change with no time on it cannot be placed against
    /// the feed before it.
    func testEveryDiaperChangeIsListedWithItsTime() {
        let events = [
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-04 23:12"),
                          diaperContents: .wet),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:40"),
                          diaperContents: .both, stoolColor: .yellow),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("11:12p  wet diaper"), out)
        XCTAssertTrue(out.contains("2:40a  wet + dirty diaper — yellow"), out)
    }

    /// The rows are clipped like the count above them. A back-dated change is
    /// excluded from both or from neither — never from one of the two.
    func testADiaperOutsideTheShiftIsInNeitherTheCountNorTheRows() {
        let events = [
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-04 19:30"),
                          diaperContents: .wet),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:40"),
                          diaperContents: .wet),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events)
        XCTAssertTrue(out.contains("Diapers · 1"), out)
        XCTAssertFalse(out.contains("7:30p"), out)
    }

    func testANightWithNoDiapersSaysSoInAWholeSentence() {
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(out.contains("No diapers logged this shift."), out)
    }

    /// A stretch says when it began, when the baby woke, and how long that was —
    /// the same three facts the timeline row now carries.
    func testASleepStretchGivesItsStartItsWakeAndItsLength() {
        let sessions = [
            SleepSnapshot(babyID: mia, startAt: at("2026-09-04 22:42"),
                          endAt: at("2026-09-05 01:15")),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       sessions: sessions)
        XCTAssertTrue(out.contains("10:42p  → 1:15a · 2h 33m"), out)
    }

    /// The rows carry the value and its time; the heading counts them. A heading
    /// naming the latest weight was, on a night with one weighing, the row below it
    /// printed twice — once without a time on it.
    func testEachWeighingIsListedWithItsTime() {
        let events = [
            EventSnapshot(babyID: mia, kind: .measurement, at: at("2026-09-04 22:00"),
                          weightGrams: 3200),
            EventSnapshot(babyID: mia, kind: .measurement, at: at("2026-09-05 05:00"),
                          weightGrams: 3260),
            // Saved without a number: a row for it would be a blank line.
            EventSnapshot(babyID: mia, kind: .measurement, at: at("2026-09-05 05:30")),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events, unit: .ml)
        XCTAssertTrue(out.contains("Weight · 2 taken"), out)
        XCTAssertTrue(out.contains("10:00p  3.20 kg"), out)
        XCTAssertTrue(out.contains("5:00a  3.26 kg"), out)
        XCTAssertFalse(out.contains("5:30a"), "a weighing with no number is not a row")
    }

    func testEachPumpSessionIsListedWithItsTime() {
        let events = [
            EventSnapshot(babyID: EventSnapshot.noBaby, kind: .pump,
                          at: at("2026-09-05 00:30"), pumpedMl: 90),
            EventSnapshot(babyID: EventSnapshot.noBaby, kind: .pump,
                          at: at("2026-09-05 03:30"), pumpedMl: 60),
        ]
        let out = text(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       events: events, unit: .ml)
        XCTAssertTrue(out.contains("Pumped · 150 ml over 2 sessions"), out)
        XCTAssertTrue(out.contains("12:30a  90 ml"), out)
        XCTAssertTrue(out.contains("3:30a  60 ml"), out)
    }

}
