import XCTest

/// The end of the night, which is what the app is for.
final class HandoffFlowTests: MoonlogUITestCase {

    /// Ending the shift used to empty Summary and take Copy and Share with it, at
    /// the exact moment the parents' document was finished and wanted.
    func testTheNightStaysOnSummaryAfterTheShiftEnds() {
        launch(["-moonlogShiftHours", "end"])

        // "End", not "End shift" — the sheet's title already says which shift.
        // The alert's confirming button is the one that reads "End shift".
        let end = app.buttons["End"]
        XCTAssertTrue(end.waitForExistence(timeout: 15), "the end-shift sheet")
        end.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            app.alerts.buttons["End shift"].tap()
        }

        app.buttons["Summary"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Copy"].waitForExistence(timeout: 10),
            "Copy vanished with the shift")
        XCTAssertFalse(
            app.staticTexts["No shift running"].exists,
            "Summary emptied itself at the moment the handoff was wanted")
        // Said, not implied: a closed night that shows only its times reads exactly
        // like a running one.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'ended'")).firstMatch.exists,
            "nothing says the night is over")
    }

    /// Copy and Share both shipped built-but-unreachable once. This asserts the
    /// route, not the document — `HandoffTests` covers what the text says.
    func testTheHandoffCanBeReachedDuringTheShift() {
        launch(["-moonlogTab", "summary"])
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 15), "no Copy")
        reveal(app.buttons["Copy"]).tap()
        XCTAssertTrue(
            app.buttons["Copied"].waitForExistence(timeout: 5),
            "Copy did not report doing anything")
    }

    /// A note to the parents is written at the end of the night and is reached only
    /// through the share menu, which is exactly the shape of a control nobody finds.
    func testTheParentNoteIsReachableFromTheShareMenu() {
        launch(["-moonlogTab", "summary"])
        let share = app.buttons["Share"].exists
            ? app.buttons["Share"] : app.navigationBars.buttons.element(boundBy: 1)
        XCTAssertTrue(share.waitForExistence(timeout: 15), "no share menu")
        share.tap()
        let note = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'note to the parents'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "no way to the parent note")
    }
}
