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
}
