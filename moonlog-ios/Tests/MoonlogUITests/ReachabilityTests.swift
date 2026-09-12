import XCTest

/// Can a thumb actually get to it?
///
/// Every test here exists because something in this app was built, tested, and had
/// no route to it: `Totals.compute` with no caller, the Note button and the Copy and
/// Share items rendered nowhere, `reassignEvent` and `archiveBaby` with no call site,
/// History pushing a blank screen. The unit suite was green through all of it.
final class ReachabilityTests: MoonlogUITestCase {

    /// The regression test for the worst of them. `BabyStatusCard` declared
    /// `onNote`, `TonightView` passed it a closure, and the action row rendered
    /// three buttons — so notes, the note tags in Settings, the temperature field
    /// and the fever badge were unreachable through two TestFlight builds.
    func testEveryCardControlIsThere() {
        launch()
        for baby in ["Mia", "Leo"] {
            for control in ["Feed", "Diaper", "Note"] {
                let button = cardButton(control, for: baby)
                XCTAssertTrue(
                    button.waitForExistence(timeout: 15),
                    "\(control) is missing from \(baby)'s card")
                XCTAssertTrue(button.isHittable, "\(control) for \(baby) cannot be tapped")
            }
        }
        // The fourth names the state it moves *to*, so exactly one of the two.
        XCTAssertTrue(
            cardButton("Wake", for: "Mia").exists || cardButton("Sleep", for: "Mia").exists,
            "no sleep control on Mia's card")
    }

    func testNoteButtonOpensTheNoteSheet() {
        launch()
        reveal(cardButton("Note", for: "Mia")).tap()
        XCTAssertTrue(app.navigationBars["Note"].waitForExistence(timeout: 5))
        // The three things that were unreachable with it.
        XCTAssertTrue(app.buttons["Spit-up"].exists, "note tag chips")
        XCTAssertTrue(app.switches["Temperature"].exists, "the temperature field")
        XCTAssertTrue(app.buttons["Cancel"].exists, "a way out")
    }

    /// The night's most repeated action, end to end, counting the taps.
    ///
    /// It used to be unloggable in two: a breast feed refused to save until you had
    /// stepped the minutes up from zero, so the record was lost to save a detail —
    /// and Save was in the navigation bar's far corner, about 800pt from a thumb
    /// holding the phone one-handed.
    func testAFeedCanBeLoggedInTwoTaps() {
        launch()
        reveal(cardButton("Feed", for: "Mia")).tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save")
        XCTAssertTrue(save.isEnabled, "a feed cannot be logged on its time alone")
        // Bottom third of the screen, where a thumb holding the phone can reach it.
        XCTAssertGreaterThan(
            save.frame.midY, app.frame.height * 0.66,
            "Save is stranded out of thumb reach")
        save.tap()

        XCTAssertTrue(
            app.buttons["Undo"].waitForExistence(timeout: 5),
            "the feed did not log, or logged without an Undo")
    }

    func testFeedSheetOpensFromTheCard() {
        launch()
        reveal(cardButton("Feed", for: "Leo")).tap()
        XCTAssertTrue(app.navigationBars["Feed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Leo"].exists, "the sheet says whose feed it is")
    }

    /// `archiveBaby` existed in `CareStore` with no call site anywhere, so a baby
    /// added by mistake rode every future handoff forever.
    func testBabyEditorCarriesBirthDateAndRemove() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons.containing(.staticText, identifier: "Mia").firstMatch).tap()

        XCTAssertTrue(app.navigationBars["Baby"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Born"].exists, "the birth date is editable")
        XCTAssertTrue(app.buttons["Remove Mia"].exists, "a baby can be removed")
    }

    /// History pushed a **blank screen** when its `.navigationDestination` sat
    /// inside a `Section`: nothing failed, nothing logged, the suite stayed green,
    /// and only a screenshot caught it. This asserts the destination has content.
    func testPastNightsPushesAScreenWithSomethingOnIt() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Past nights"]).tap()

        // Asserted on the destination's own **content**, not on its navigation bar.
        // A bar can render over a screen with nothing on it, which is exactly the
        // bug this test exists for; and querying the bar once hung XCUITest for
        // twenty-five minutes, which is indistinguishable from a slow suite.
        //
        // The seed carries finished nights as well as tonight's running one, so the
        // list has rows. Either those or the empty state is a screen; neither is.
        let aNight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] ' – '")).firstMatch
        XCTAssertTrue(
            aNight.waitForExistence(timeout: 10)
                || app.staticTexts["No finished nights yet"].exists,
            "pushed a blank screen")
    }

    /// The night's most repeated action, made repeatable. A routine bottle meant
    /// choosing the method and setting the amount again every time, and this app
    /// has shipped a control that was declared, passed a closure, and rendered
    /// nowhere — so the assertion is that a thumb can reach it, not that it exists.
    ///
    /// Leo, because the seed gives him bottles with amounts; Mia's feeds are breast,
    /// where there is less to repeat. The row's own text is not asserted: it is in
    /// the household's volume unit and would pin this test to the seed's choice.
    func testAFeedCanRepeatTheLastOne() {
        launch()
        reveal(cardButton("Feed", for: "Leo")).tap()

        let repeatRow = app.buttons["feed.sameAsLast"]
        XCTAssertTrue(repeatRow.waitForExistence(timeout: 5), "no way to repeat the last feed")
        XCTAssertTrue(repeatRow.isHittable, "the row is there but cannot be tapped")
        repeatRow.tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save")
        save.tap()
        XCTAssertTrue(
            app.buttons["Undo"].waitForExistence(timeout: 10),
            "the repeated feed did not log")
    }

    /// A sleep that ended while both hands were full had no route: the tile toggles
    /// at the moment it is tapped, so recording one meant logging a state that was
    /// not true and then correcting it from the timeline. `recordCompletedSleep`
    /// landed in `CareStore` with no call site, which is how the last three of these
    /// started.
    func testAnEarlierSleepCanBeLoggedFromTheShiftMenu() {
        launch()
        reveal(app.buttons["More"]).tap()

        // Flat per baby, because the seed carries twins.
        let entry = app.buttons["Log earlier sleep — Mia"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "no route to a missed sleep")
        entry.tap()

        XCTAssertTrue(
            app.navigationBars["Earlier sleep"].waitForExistence(timeout: 5),
            "the menu entry opened nothing")
        // Never open-ended: this route must not create the session she is in now.
        XCTAssertFalse(app.switches["Still asleep"].exists, "an earlier sleep cannot be running")

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save")
        XCTAssertTrue(save.isEnabled, "the defaulted hour does not save")
        save.tap()

        XCTAssertTrue(
            app.buttons["Undo"].waitForExistence(timeout: 10),
            "the sleep did not log, or logged without an Undo")
    }

    /// The client-family picker had never been driven. It is the app's one global
    /// mode, and the seed carries a second household precisely so it has somewhere
    /// to switch to.
    func testSwitchingClientFamilyChangesWhoseNightItIs() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Okafor"]).tap()

        app.buttons["Tonight"].firstMatch.tap()
        // Okafor is between visits, so switching to it must leave the running
        // Nguyen shift behind rather than carrying the cards over.
        XCTAssertTrue(
            app.buttons["Start shift"].waitForExistence(timeout: 10),
            "still showing the previous household's shift")
        XCTAssertFalse(cardButton("Feed", for: "Mia").exists, "Nguyen's cards followed")
    }
    /// Save looked like a bar the width of the sheet and answered like the word
    /// printed on it. `.plain` hit-tests a button's *contents*, and the contents
    /// were an `HStack` holding one `Text`, so the width the `.infinity` frame
    /// bought was layout and nothing else: **measured at 38×20pt inside a 370×56pt
    /// bar**. Every log of the night ends on this control.
    ///
    /// The frame is asserted as well as the tap, because a normalised coordinate is
    /// taken against the element's *own* frame — a tap "at the edge of Save" lands
    /// on the word again when the frame has collapsed to it, and passes.
    func testSaveIsAsBigAsTheBarItLooksLike() {
        launch()
        reveal(cardButton("Feed", for: "Mia")).tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save")
        XCTAssertGreaterThan(
            save.frame.width, app.frame.width * 0.7,
            "Save answers on the word, not on the bar")
        XCTAssertGreaterThanOrEqual(save.frame.height, 44, "under the minimum target")
        // Bottom third of the screen, where a thumb holding the phone can reach it.
        XCTAssertGreaterThan(
            save.frame.midY, app.frame.height * 0.66,
            "Save is stranded out of thumb reach")

        // Well clear of the word, still inside the bar — where a thumb lands.
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(
            app.buttons["Undo"].waitForExistence(timeout: 5),
            "the edge of the Save bar does not save")
    }

}
