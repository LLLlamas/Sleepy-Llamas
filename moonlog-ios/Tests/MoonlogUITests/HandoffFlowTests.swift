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
    ///
    /// It deliberately does **not** assert the button flipping to "Copied". That is
    /// a two-second state, and this harness has taken longer than that to answer a
    /// single query on this machine; a test that fails on timing rather than on
    /// behaviour teaches the suite to be ignored.
    func testTheHandoffCanBeReachedDuringTheShift() {
        launch(["-moonlogTab", "summary"])
        let copy = app.buttons["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 15), "no Copy")
        XCTAssertTrue(copy.isHittable, "Copy is there but cannot be tapped")
        copy.tap()
        XCTAssertTrue(
            app.staticTexts["Summary"].waitForExistence(timeout: 5),
            "copying took the screen down with it")
    }

    /// The note to the parents used to be an item inside the share menu, which is
    /// exactly the shape of a control nobody finds — and it edits the handoff rather
    /// than sharing it. It is on Summary itself now, so this asserts the screen, not
    /// the menu: behind the open menu the row underneath still answered the old
    /// query, and the test passed for a whole build without a route existing.
    func testTheParentNoteIsOnSummaryItself() {
        launch(["-moonlogTab", "summary"])
        let note = app.buttons["summary.parentsNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 15), "no way to the parent note")
        XCTAssertTrue(note.isHittable, "the parent note is there but cannot be tapped")
        note.tap()
        XCTAssertTrue(
            app.buttons["Save"].waitForExistence(timeout: 5), "the note sheet did not open")
    }

    /// Past nights was only ever under Settings, a tab away from the screen the
    /// question is asked on.
    func testPastNightsIsReachableFromSummary() {
        launch(["-moonlogTab", "summary"])
        reveal(app.buttons["summary.pastNights"]).tap()
        let aNight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] ' – '")).firstMatch
        XCTAssertTrue(
            aNight.waitForExistence(timeout: 10)
                || app.staticTexts["No finished nights yet"].exists,
            "pushed a blank screen")
    }
}
