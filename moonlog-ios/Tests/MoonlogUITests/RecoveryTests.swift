import XCTest

/// The mistakes a tired thumb makes, and whether the app lets them be taken back.
///
/// A wrong-twin tap is the failure this app is shaped around, and Undo is the six
/// seconds it gets to be caught in. None of it had ever been driven.
final class RecoveryTests: MoonlogUITestCase {

    /// The tile toggles wake/sleep on tap, with no confirmation by default —
    /// `ConfirmPreferences` leans on Undo for everything that has one.
    func testTappingTheTileOffersUndoAndUndoingPutsItBack() {
        launch()
        let mia = app.buttons.containing(.staticText, identifier: "Mia is asleep").firstMatch
        XCTAssertTrue(mia.waitForExistence(timeout: 15), "Mia's status tile")
        mia.tap()

        // The banner names the baby, which is what makes a mis-tap catchable.
        let banner = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Mia'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "no confirmation banner")

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo offered")
        XCTAssertTrue(undo.isHittable, "Undo exists but is not a tappable target")
        undo.tap()

        XCTAssertTrue(
            app.buttons.containing(.staticText, identifier: "Mia is asleep")
                .firstMatch.waitForExistence(timeout: 10),
            "Undo did not put Mia back to sleep")
    }

    /// The confirmation preferences are the one setting that changes behaviour on
    /// another screen, and it has to survive a relaunch to be worth anything.
    func testTurningOnAskBeforeMakesTheTileConfirm() {
        launch(["-moonlogTab", "settings"])
        // Matched on the contained text, not the switch's own label: each row is a
        // title plus an explanatory second line, and the accessibility label is
        // both of them joined.
        // Tapped at the row's trailing edge, where the switch actually is.
        //
        // Neither the row's centre nor its label toggles it — both were tried and
        // both left the value at "0". A `contentShape` on the label does not change
        // that. So the target for this control really is the switch and not the
        // row, which is a wart rather than a bug and is recorded as one; the test
        // taps where a thumb would rather than pretending otherwise.
        let row = reveal(
            app.switches.containing(.staticText, identifier: "Wake and sleep").firstMatch)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(row.value as? String, "1", "the switch did not turn on")

        app.buttons["Tonight"].firstMatch.tap()
        let mia = app.buttons.containing(.staticText, identifier: "Mia is asleep").firstMatch
        XCTAssertTrue(mia.waitForExistence(timeout: 10))
        mia.tap()

        // An alert, never a confirmationDialog — inside a sheet the latter presents
        // as a popover and drops the cancel action, which is how a delete shipped
        // with no way out. Asserting Cancel exists is asserting that rule holds.
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "no confirmation")
        XCTAssertTrue(app.alerts.buttons["Cancel"].exists, "a confirmation with no way out")
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(
            app.buttons.containing(.staticText, identifier: "Mia is asleep")
                .firstMatch.waitForExistence(timeout: 5),
            "Cancel changed something anyway")
    }

    /// The wrong-twin remedy. It was unreachable once already, and then reachable
    /// but rendered as a caption with nothing saying it could be tapped.
    func testWrongBabyIsOnTheEditSheet() {
        launch(["-moonlogEditFirst", "YES"])
        let wrongBaby = app.buttons["Wrong baby?"]
        XCTAssertTrue(wrongBaby.waitForExistence(timeout: 15), "no way to move a record")
        XCTAssertTrue(wrongBaby.isHittable)
        wrongBaby.tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Move to '")).firstMatch
                .waitForExistence(timeout: 5),
            "the menu offers nowhere to move it")
    }
}
