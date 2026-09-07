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

        // Asserted on the destination's own content, not on `navigationBars`.
        // Querying the pushed navigation bar hung XCUITest for twenty-five minutes
        // against a screen that was rendering nothing, and a timeout that long is
        // indistinguishable from a suite that is simply slow.
        //
        // The seeded night is still running, so this household has no finished ones
        // — the empty state is the correct content here, and a blank screen is not.
        XCTAssertTrue(
            app.staticTexts["No finished nights yet"].waitForExistence(timeout: 10),
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
