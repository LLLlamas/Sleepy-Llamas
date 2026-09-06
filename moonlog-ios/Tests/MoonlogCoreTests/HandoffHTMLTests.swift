import XCTest
@testable import MoonlogCore

/// The keepsake handoff — the document the family keeps, rather than the text the
/// doula pastes into Messages at 6am.
///
/// Every assertion here is on a meaningful substring, never on the whole document.
/// A byte-exact golden file would break on every CSS tweak and would teach everyone
/// to re-bless it without reading the diff, which is exactly how an escaping
/// regression or a wrong number gets waved through.
final class HandoffHTMLTests: XCTestCase {

    private let mia = UUID()
    private let leo = UUID()
    private let zone = TimeZone(identifier: Zone.newYork)!

    private var shift: ShiftWindow {
        ShiftWindow(
            startedAt: makeDate("2026-09-04 21:00", Zone.newYork),
            endedAt: makeDate("2026-09-05 06:00", Zone.newYork))
    }

    private func at(_ wall: String) -> Date { makeDate(wall, Zone.newYork) }

    private func html(
        babies: [HandoffBaby],
        shift: ShiftWindow? = nil,
        caregiver: String? = "Cat",
        note: String? = nil,
        events: [EventSnapshot] = [],
        sessions: [SleepSnapshot] = [],
        unit: VolumeUnit = .oz,
        asOf: Date? = nil
    ) -> String {
        HandoffHTML.render(
            babies: babies, shift: shift ?? self.shift, caregiver: caregiver,
            note: note, events: events, sessions: sessions, unit: unit,
            timeZone: zone, asOf: asOf ?? at("2026-09-05 06:00"))
    }

    // MARK: - Escaping

    /// The one that matters most. Names, the doula's note and medication names are
    /// free text typed by a person on a phone at 3am. An unescaped `<` silently
    /// swallows the rest of the page — the parents open the keepsake months later
    /// and half the night is simply not there, with nothing to say it went missing.
    func testFreeTextIsEscapedSoNothingCanSwallowTheRestOfThePage() {
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia & \"Leo\" <3", dayOfLife: 6)],
            note: "<script>alert(1)</script>",
            events: [
                EventSnapshot(babyID: mia, kind: .medication, at: at("2026-09-05 02:00"),
                              medicationName: "Vitamin D & Iron", doseText: "0.5 ml"),
            ])

        // The escaped forms are present…
        XCTAssertTrue(out.contains("Mia &amp; &quot;Leo&quot; &lt;3"), out)
        XCTAssertTrue(out.contains("&lt;script&gt;alert(1)&lt;/script&gt;"), out)
        XCTAssertTrue(out.contains("Vitamin D &amp; Iron"), out)

        // …and the raw forms are nowhere, in the note, the title or the heading.
        XCTAssertFalse(out.contains("<script"), "a note must never become markup")
        XCTAssertFalse(out.contains("alert(1)</script>"), out)
        XCTAssertFalse(out.contains("Mia & "), "a bare & starts an entity in HTML")
        XCTAssertFalse(out.contains("\"Leo\""), "raw quotes would break an attribute")
        XCTAssertFalse(out.contains("<3"), "a bare < opens a tag and eats what follows")

        // And nothing anywhere in the document leaves a bare ampersand behind —
        // including the ` & ` the twins joiner and the "Medication & weight"
        // heading are built from.
        XCTAssertEqual(unescapedAmpersands(in: out), [], "bare & found")
    }

    /// The joiner between twin names and the built-in headings are literals, not
    /// user text, and were easy to forget: they go through the same escaper.
    func testTheAppsOwnAmpersandsAreEscapedToo() {
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
                     HandoffBaby(id: leo, name: "Leo", dayOfLife: 6)],
            events: [
                EventSnapshot(babyID: mia, kind: .medication, at: at("2026-09-05 02:00"),
                              medicationName: "Vitamin D"),
            ])
        XCTAssertTrue(out.contains("Mia &amp; Leo"), "the title joins names with &")
        XCTAssertTrue(out.contains("Vitamin D"), out)
        XCTAssertEqual(unescapedAmpersands(in: out), [], "bare & found")
    }

    // MARK: - Self-contained

    /// The page is forwarded, saved to Files and opened offline months later. Any
    /// stylesheet, font, script or image fetched over the network would be missing
    /// by then — or would tell a third party the moment the parents opened it.
    func testTheDocumentFetchesNothingOverTheNetwork() {
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
                     HandoffBaby(id: leo, name: "Leo", dayOfLife: 6)],
            note: "Lovely night.\n\nBoth settled by 1am.",
            events: [
                EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                              feedMethod: .bottleFormula, amountMl: 60),
                EventSnapshot(babyID: leo, kind: .diaper, at: at("2026-09-05 02:00"),
                              diaperContents: .both, stoolColor: .transitional),
                EventSnapshot(babyID: EventSnapshot.noBaby, kind: .pump,
                              at: at("2026-09-05 03:00"), pumpedMl: 120),
            ],
            sessions: [SleepSnapshot(babyID: mia, startAt: at("2026-09-04 22:00"),
                                     endAt: at("2026-09-05 00:10"))])

        XCTAssertFalse(out.contains("http://"), "nothing may be fetched")
        XCTAssertFalse(out.contains("https://"), "nothing may be fetched")
        XCTAssertFalse(out.contains("<script"), "no script, inline or otherwise")
        XCTAssertFalse(out.contains("src="), "no image, iframe or embed source")
        XCTAssertFalse(out.contains("<link"), "no external stylesheet")
        XCTAssertTrue(out.contains("<style>"), "the stylesheet is inline instead")
    }

    // MARK: - A complete, responsive document

    /// It is opened on a phone, straight from Messages. Without the viewport tag
    /// mobile Safari renders it at 980px and zooms out, and the keepsake arrives as
    /// unreadable grey lines.
    func testItIsACompleteResponsiveDocument() {
        let out = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)])
        XCTAssertTrue(out.hasPrefix("<!DOCTYPE html>"), String(out.prefix(80)))
        XCTAssertTrue(out.contains("<meta name=\"viewport\""), out)
        XCTAssertTrue(out.contains("width=device-width"), out)
        XCTAssertTrue(out.contains("charset"), "or the emoji and the · arrive as mojibake")
        XCTAssertTrue(out.hasSuffix("</html>"), String(out.suffix(80)))
        XCTAssertTrue(out.contains("<title>"), "it is saved to Files under this name")
    }

    // MARK: - Agreement with the plain-text handoff

    /// The anti-drift test, and the reason both documents derive from
    /// `Totals.compute`. The family is sent the text at 6am and the keepsake later;
    /// if the two ever disagree they have two accounts of the same night and no way
    /// to tell which one is the record.
    func testTheHeadlineNumbersAgreeWithThePlainTextHandoff() {
        let baby = HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-04 22:40"),
                          feedMethod: .bottleFormula, amountMl: 59.15),
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:15"),
                          feedMethod: .bottleFormula, amountMl: 60),
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 04:00"),
                          feedMethod: .breast, leftSeconds: 480, rightSeconds: 360),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-04 23:00"),
                          diaperContents: .both, stoolColor: .meconium),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 02:00"),
                          diaperContents: .wet),
            EventSnapshot(babyID: mia, kind: .diaper, at: at("2026-09-05 04:30"),
                          diaperContents: .dirty, stoolColor: .transitional),
        ]
        let sessions = [
            SleepSnapshot(babyID: mia, startAt: at("2026-09-04 22:00"),
                          endAt: at("2026-09-05 00:10")),
            SleepSnapshot(babyID: mia, startAt: at("2026-09-05 01:30"),
                          endAt: at("2026-09-05 02:30")),
        ]
        let now = at("2026-09-05 06:00")

        let plain = Handoff.text(
            babies: [baby], shift: shift, caregiver: "Cat", events: events,
            sessions: sessions, unit: .oz, timeZone: zone, asOf: now)
        let page = html(babies: [baby], events: events, sessions: sessions)

        // Derived from the same source the two documents claim to share, so this
        // catches a divergence rather than restating one side's answer.
        let totals = Totals.compute(
            events: events, sessions: sessions, forBaby: mia, shift: shift, asOf: now)
        let volume = Fmt.amountTotal(ml: totals.feedMl, unit: .oz)
        let sleep = Fmt.spanned(totals.sleepSeconds)

        XCTAssertEqual(totals.feeds, 3)
        XCTAssertEqual(totals.diapers, 3)

        // Feed count.
        XCTAssertEqual(tileValue("Feeds", in: page), "\(totals.feeds)", page)
        XCTAssertTrue(plain.contains("Feeds · \(totals.feeds)"), plain)

        // Total volume — the figure a parent is most likely to write down.
        XCTAssertEqual(volume, "4.0 oz", "the total keeps its decimal")
        XCTAssertTrue(page.contains("\(volume) by bottle"), page)
        XCTAssertTrue(plain.contains("\(volume) by bottle"), plain)

        // Diaper count, and the wet/dirty split under it.
        XCTAssertEqual(tileValue("Diapers", in: page), "\(totals.diapers)", page)
        XCTAssertTrue(plain.contains("Diapers · \(totals.diapers)"), plain)
        XCTAssertTrue(page.contains("\(totals.wet) wet, \(totals.dirty) dirty"), page)
        XCTAssertTrue(plain.contains("\(totals.wet) wet, \(totals.dirty) dirty"), plain)

        // Sleep total, and the stretch count beside it.
        XCTAssertEqual(sleep, "3h 10m")
        XCTAssertEqual(tileValue("Sleep", in: page), sleep, page)
        XCTAssertTrue(plain.contains("Sleep · \(sleep)"), plain)
        XCTAssertTrue(page.contains("\(totals.stretches) stretches"), page)
        XCTAssertTrue(plain.contains("over \(totals.stretches) stretches"), plain)

        // Stool progression is the marker the doula is actually reporting on.
        XCTAssertTrue(page.contains("Meconium → Transitional"), page)
        XCTAssertTrue(plain.contains("Meconium → Transitional"), plain)
    }

    /// Feeds are described with the same words in both documents, on purpose —
    /// `Handoff.warmFeed` is shared. Two phrasings of one feed is how the parents
    /// end up asking which document is right.
    func testAFeedIsPhrasedIdenticallyInBothDocuments() {
        let baby = HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 04:00"),
                          feedMethod: .breast, leftSeconds: 1080),
        ]
        let plain = Handoff.text(
            babies: [baby], shift: shift, caregiver: "Cat", events: events,
            sessions: [], unit: .oz, timeZone: zone, asOf: at("2026-09-05 06:00"))
        let page = html(babies: [baby], events: events)

        XCTAssertTrue(plain.contains("left breast — 18m"), plain)
        XCTAssertTrue(page.contains("left breast — 18m"), page)
    }

    // MARK: - The doula's note

    func testNoNoteMeansNoNoteSectionAtAll() {
        for absent in [nil, "", "   ", "\n\n  \t "] as [String?] {
            let out = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                           note: absent)
            XCTAssertFalse(out.contains("<section class=\"note\">"),
                           "empty note rendered a section for \(absent ?? "nil")")
            XCTAssertFalse(out.contains("class=\"signoff\""),
                           "and no orphan sign-off under nothing")
        }
    }

    func testANoteIsShownWithTheCaregiversSignOff() {
        let out = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       note: "She took the 2am bottle beautifully.")
        XCTAssertTrue(out.contains("She took the 2am bottle beautifully."), out)
        XCTAssertTrue(out.contains("<section class=\"note\">"), out)
        XCTAssertTrue(out.contains("— Cat"), "signed by whoever kept the night")
    }

    /// The doula typed it into a text field, so the shape they gave it is part of
    /// what they said: a blank line is a new thought, a single newline is a line
    /// break inside one. Collapsing both into a wall of text loses the difference.
    func testNoteBlocksBecomeParagraphsAndSingleNewlinesBecomeBreaks() {
        let twoBlocks = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                             note: "First thought.\n\nSecond thought.")
        let section = noteSection(of: twoBlocks)
        XCTAssertEqual(occurrences(of: "<p>", in: section), 2, section)
        XCTAssertTrue(section.contains("<p>First thought.</p>"), section)
        XCTAssertTrue(section.contains("<p>Second thought.</p>"), section)
        XCTAssertFalse(section.contains("<br>"), "a blank line is not a line break")

        let oneBlock = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                            note: "Bottles are in the fridge.\nTop shelf.")
        let single = noteSection(of: oneBlock)
        XCTAssertEqual(occurrences(of: "<p>", in: single), 1, single)
        XCTAssertTrue(single.contains("fridge.<br>Top shelf."), single)
    }

    // MARK: - An open shift

    /// This page can legitimately be shared mid-shift. An open shift printed as a
    /// time range would either show a dash where the end time goes or claim the
    /// night finished at a time nobody logged.
    func testAnOpenShiftReadsAsStillInProgressRatherThanABrokenRange() {
        let open = ShiftWindow(startedAt: at("2026-09-04 21:00"))
        let out = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       shift: open, asOf: at("2026-09-05 03:00"))
        XCTAssertTrue(out.contains("still in progress"), out)
        XCTAssertFalse(out.contains(" – "), "no en-dash range without an end time")
    }

    /// The single fact a parent most wants at 6am.
    func testABabyStillAsleepIsSaidSoWithTheTimeTheyWentDown() {
        let sessions = [SleepSnapshot(babyID: mia, startAt: at("2026-09-05 05:40"))]
        let out = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                       sessions: sessions)
        XCTAssertTrue(out.contains("Still asleep, since"), out)
        // Not a literal "5:40 AM": Date.FormatStyle separates the meridiem with a
        // narrow no-break space (U+202F), so an ASCII-space literal never matches.
        XCTAssertTrue(out.contains("5:40"), out)

        let awake = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                         sessions: [SleepSnapshot(babyID: mia,
                                                  startAt: at("2026-09-05 01:00"),
                                                  endAt: at("2026-09-05 02:00"))])
        XCTAssertFalse(awake.contains("Still asleep"), awake)
    }

    // MARK: - One baby versus twins

    /// `namesBaby` is `babies.count > 1`. With twins each card has to say whose it
    /// is; with one baby the name is already the page's `<h1>`, and repeating it as
    /// a card heading reads like there is a second child somewhere below.
    func testTwinsNameEachCardAndASingleBabyDoesNotRepeatItsOwnName() {
        let events = [
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                          feedMethod: .bottleFormula, amountMl: 60),
            EventSnapshot(babyID: leo, kind: .diaper, at: at("2026-09-05 02:30"),
                          diaperContents: .wet),
        ]
        let twins = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6),
                     HandoffBaby(id: leo, name: "Leo", dayOfLife: 4)],
            events: events)
        XCTAssertTrue(twins.contains("<h2>Mia</h2>"), twins)
        XCTAssertTrue(twins.contains("<h2>Leo</h2>"), twins)
        XCTAssertTrue(twins.contains("Day 6"), twins)
        XCTAssertTrue(twins.contains("Day 4"), "each twin keeps their own day of life")

        // Neither twin's records land on the other.
        let miaCard = twins.components(separatedBy: "<h2>Leo</h2>").first ?? ""
        XCTAssertEqual(tileValue("Feeds", in: miaCard), "1", miaCard)
        XCTAssertEqual(tileValue("Diapers", in: miaCard), "0", "Leo's diaper is not Mia's")

        let single = html(babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
                          events: events)
        XCTAssertTrue(single.contains("<h1>Mia</h1>"), single)
        XCTAssertFalse(single.contains("<h2>Mia</h2>"),
                       "one baby gets no redundant name heading")
        XCTAssertTrue(single.contains("Day 6"),
                      "but still their day of life, which the parents track")
    }

    // MARK: - Clipping

    /// Back-dating outside the shift is allowed by design, and the totals have
    /// always excluded it. The text handoff's lists were once inconsistent with its
    /// own counts; the keepsake must not reintroduce that — a night that lists a
    /// feed it did not count is a document nobody can reconcile.
    func testARecordBackDatedOutsideTheShiftIsInNeitherTheListsNorTheCounts() {
        let baby = HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)
        let events = [
            // Before the shift started: logged tonight, but about this afternoon.
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-04 17:30"),
                          feedMethod: .bottleFormula, amountMl: 120),
            EventSnapshot(babyID: mia, kind: .note, at: at("2026-09-04 18:00"),
                          text: "Back-dated from the afternoon"),
            // Inside the shift.
            EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-05 01:00"),
                          feedMethod: .bottleFormula, amountMl: 60),
        ]
        let page = html(babies: [baby], events: events)
        let plain = Handoff.text(
            babies: [baby], shift: shift, caregiver: "Cat", events: events,
            sessions: [], unit: .oz, timeZone: zone, asOf: at("2026-09-05 06:00"))

        XCTAssertFalse(page.contains("Back-dated from the afternoon"), page)
        XCTAssertFalse(plain.contains("Back-dated from the afternoon"), plain)
        XCTAssertEqual(tileValue("Feeds", in: page), "1", "one feed, not two")
        XCTAssertTrue(plain.contains("Feeds · 1"), plain)
        XCTAssertTrue(page.contains("2.0 oz by bottle"), "60ml, not 180ml")
        XCTAssertTrue(plain.contains("2.0 oz by bottle"), plain)
    }

    // MARK: - Helpers
    //
    // These read one fragment out of the document rather than comparing the whole
    // thing, so a CSS change cannot fail a test about a number.

    /// The text inside the `.tile-value` of the tile carrying `label`.
    private func tileValue(_ label: String, in page: String) -> String? {
        let opener = "<p class=\"tile-label\">\(label)</p><p class=\"tile-value\">"
        guard let start = page.range(of: opener),
              let end = page.range(of: "</p>", range: start.upperBound..<page.endIndex)
        else { return nil }
        return String(page[start.upperBound..<end.lowerBound])
    }

    private func noteSection(of page: String) -> String {
        guard let start = page.range(of: "<section class=\"note\">"),
              let end = page.range(of: "</section>", range: start.upperBound..<page.endIndex)
        else { return "" }
        return String(page[start.lowerBound..<end.upperBound])
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var index = haystack.startIndex
        while let found = haystack.range(of: needle, range: index..<haystack.endIndex) {
            count += 1
            index = found.upperBound
        }
        return count
    }

    /// Every `&` in a well-formed page starts a character reference. Anything else
    /// is a name or a note that escaped the escaper, so this returns the offending
    /// snippets rather than a bare false — the failure has to say what leaked.
    private func unescapedAmpersands(in page: String) -> [String] {
        let entities = ["&amp;", "&lt;", "&gt;", "&quot;", "&#39;", "&nbsp;"]
        var offenders: [String] = []
        var index = page.startIndex
        while let found = page.range(of: "&", range: index..<page.endIndex) {
            let tail = page[found.lowerBound...]
            if !entities.contains(where: { tail.hasPrefix($0) }) {
                offenders.append(String(tail.prefix(24)))
            }
            index = found.upperBound
        }
        return offenders
    }

    // MARK: - Records with nobody to attach to

    /// The keepsake used to loop the roster and stop. A record logged against a baby
    /// the roster cannot name — a `Baby` deleted out from under its history, or a
    /// relationship still in flight from sync — vanished from the document the
    /// family keeps, while the plain text reported it. It was logged for somebody.
    func testRecordsForABabyNobodyCanNameStillReachThePage() {
        let ghost = UUID()
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            events: [
                EventSnapshot(babyID: mia, kind: .feed, at: at("2026-09-04 22:00"),
                              feedMethod: .breast, leftSeconds: 600),
                EventSnapshot(babyID: ghost, kind: .diaper, at: at("2026-09-05 01:00"),
                              diaperContents: .wet),
            ],
            sessions: [
                SleepSnapshot(babyID: ghost, startAt: at("2026-09-05 02:00"),
                             endAt: at("2026-09-05 03:00")),
            ])

        XCTAssertTrue(out.contains("Not matched to a baby"), out)
        XCTAssertTrue(out.contains("wet diaper"), "the stray record itself is described")
        XCTAssertTrue(out.contains("asleep 1h"), "and stray sleep, clipped like everywhere")
        XCTAssertTrue(out.contains("2 records"), out)
    }

    /// A pump carries no baby by design and is a household total, not a lost record.
    /// Reporting it as unattributed would tell the parents something went wrong.
    func testAPumpIsNeverReportedAsAStrayRecord() {
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            events: [
                EventSnapshot(babyID: EventSnapshot.noBaby, kind: .pump,
                              at: at("2026-09-05 01:00"), pumpedMl: 90),
            ])

        XCTAssertFalse(out.contains("Not matched to a baby"), out)
        XCTAssertTrue(out.contains("Pumping"), "it belongs in the household total")
    }

    /// A session that contributed no time inside the window is not a record to
    /// announce — the same rule the totals apply.
    func testStraySleepOutsideTheWindowIsNotAnnounced() {
        let ghost = UUID()
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            sessions: [
                SleepSnapshot(babyID: ghost, startAt: at("2026-09-04 18:00"),
                             endAt: at("2026-09-04 19:00")),
            ])

        XCTAssertFalse(out.contains("Not matched to a baby"), out)
    }

    /// Note tags are the whole content of a note logged without any typed text, and
    /// the keepsake used to read `text` alone — so such a note arrived as a bare
    /// timestamp with nothing beside it.
    func testANoteLoggedAsTagsAloneStillSaysSomething() {
        let out = html(
            babies: [HandoffBaby(id: mia, name: "Mia", dayOfLife: 6)],
            events: [
                EventSnapshot(babyID: mia, kind: .note, at: at("2026-09-05 01:00"),
                              noteTags: ["Spit-up", "Fussy"]),
            ])

        XCTAssertTrue(out.contains("Spit-up, Fussy"), out)
    }
}
