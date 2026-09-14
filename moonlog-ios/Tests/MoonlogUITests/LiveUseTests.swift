import XCTest

/// What a tired thumb actually does to a record after logging it: correct it,
/// delete it, move it to the other twin, back out of a screen, send the night on.
///
/// The rest of the suite proves those controls are *reachable*. This drives them
/// to the end — a Save that writes, a Delete that is confirmed and carried out, a
/// pushed screen that pops. Every one of these ends by asserting the app is still
/// on its feet, because the failure being looked for here is a crash or a modal
/// with no way out, not a wrong label.
final class LiveUseTests: MoonlogUITestCase {

    /// `-moonlogEditFirst` opens the newest record's edit sheet — a sleep.
    private func openTheEditSheet() {
        launch(["-moonlogEditFirst", "YES"])
        XCTAssertTrue(
            app.buttons["Wrong baby?"].waitForExistence(timeout: 15),
            "the edit sheet never opened")
    }

    /// Tonight is alive and answering, which is the thing every case here is
    /// really asking about.
    private func assertBackOnTonight(_ why: String) {
        XCTAssertTrue(
            app.buttons.containing(.staticText, identifier: "Mia is asleep").firstMatch
                .waitForExistence(timeout: 15)
                || app.buttons.containing(.staticText, identifier: "Mia is awake").firstMatch
                    .waitForExistence(timeout: 5),
            why)
    }

    // MARK: - Update

    /// Saving an edit is a different write from logging one — `updateSleepSession`,
    /// not a fresh insert — and it is the write that happens after a mis-tap has
    /// already been noticed.
    func testEditingARecordSavesAndComesBack() {
        openTheEditSheet()

        let save = reveal(app.buttons["Save"])
        XCTAssertEqual(save.label, "Save", "Save is not the save button")
        save.tap()

        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'updated'")).firstMatch
                .waitForExistence(timeout: 10),
            "nothing said the record was updated — the save did not complete")
        assertBackOnTonight("the sheet saved but Tonight did not come back")
    }

    // MARK: - Delete

    /// Delete asks first, the question has to have a way out, and the app has to
    /// survive the answer.
    ///
    /// It did not: confirming a delete **crashed**. `TonightView.body` rebuilds
    /// before SwiftData has taken the deleted object out of `shift.events`, and
    /// reading `babyIDRaw` on a deleted model traps. `Shift.liveEvents` is the fix.
    ///
    /// Note `revealClear` rather than `reveal`. The Delete row rests under the Save
    /// bar, and a covered row still reports `isHittable == true` — the first version
    /// of this test tapped "Delete" and got back "Diaper updated".
    func testDeletingARecordCanBeCancelledAndThenCarriedOut() {
        openTheEditSheet()

        revealClear(app.buttons["Delete"], of: app.buttons["Save"]).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "delete did not ask")
        XCTAssertTrue(app.alerts.buttons["Cancel"].exists, "a delete confirmation with no way out")
        app.alerts.buttons["Cancel"].tap()

        // Cancel means cancel: the sheet is still up and the record is still there.
        XCTAssertTrue(
            app.buttons["Wrong baby?"].waitForExistence(timeout: 5),
            "Cancel closed the sheet anyway")

        revealClear(app.buttons["Delete"], of: app.buttons["Save"]).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "delete did not ask again")
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'deleted'")).firstMatch
                .waitForExistence(timeout: 10),
            "nothing said the record was deleted — the app died on the delete")
        assertBackOnTonight("the app did not come back after a delete")
    }

    // MARK: - Move

    /// The wrong-twin remedy, carried through rather than merely offered.
    /// `testWrongBabyIsOnTheEditSheet` stops at the open menu; this taps the item,
    /// answers the confirmation and checks the app survives the reassignment.
    func testMovingARecordToTheOtherBabyCompletes() {
        openTheEditSheet()

        app.buttons["Wrong baby?"].tap()
        let moveItem = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Move to '")).firstMatch
        XCTAssertTrue(moveItem.waitForExistence(timeout: 5), "nowhere to move it")
        moveItem.tap()

        // Move confirms by default; if that default ever changes, the write just
        // happens and this still passes.
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            let confirm = app.alerts.buttons.matching(
                NSPredicate(format: "label != 'Cancel'")).firstMatch
            XCTAssertTrue(confirm.exists, "a move confirmation with nothing to confirm")
            confirm.tap()
        }

        assertBackOnTonight("the app did not survive moving a record to the other baby")
    }

    // MARK: - Back

    /// Every pushed screen has to come back. `.navigationDestination(isPresented:)`
    /// has landed on a blank screen in this app twice, and a route that pushes but
    /// will not pop strands a user mid-night just as completely.
    func testPushedScreensComeBack() {
        launch(["-moonlogTab", "summary"])

        reveal(app.buttons["summary.pastNights"]).tap()
        XCTAssertTrue(
            app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10),
            "Past nights pushed nothing with a way back")
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(
            app.buttons["summary.pastNights"].waitForExistence(timeout: 10),
            "back from Past nights did not return to Summary")

        // The other push in the app: a client family, from the root of Settings.
        app.buttons["Settings"].firstMatch.tap()
        reveal(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Rename or remove '")).firstMatch).tap()
        XCTAssertTrue(
            app.navigationBars["Client family"].waitForExistence(timeout: 10),
            "the family detail never pushed")
        app.navigationBars["Client family"].buttons.firstMatch.tap()

        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Rename or remove '")).firstMatch
                .waitForExistence(timeout: 10),
            "back from the family detail did not return to Settings")
    }

    // MARK: - Copy and Share

    /// Share is a `Menu` of two `ShareLink`s behind a bare SF Symbol, so until it
    /// was given an accessibility label nothing could name it — which is why Copy
    /// has been driven since the suite existed and Share never had.
    ///
    /// It opens the menu and closes it again rather than tapping a `ShareLink`:
    /// that hands off to `UIActivityViewController`, a system sheet this suite
    /// cannot dismiss reliably, and a test that can wedge the simulator is worse
    /// than no test. Opening proves both routes are composed and hittable.
    func testShareMenuOffersBothDocumentsAndCloses() {
        launch(["-moonlogTab", "summary"])

        let share = app.buttons["summary.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "no Share control on Summary")
        XCTAssertTrue(share.isHittable, "Share is there but cannot be tapped")
        share.tap()

        XCTAssertTrue(
            app.buttons["Send the page"].waitForExistence(timeout: 5),
            "the keepsake page is not on the share menu")
        XCTAssertTrue(
            app.buttons["Send as plain text"].exists,
            "the plain-text handoff is not on the share menu")

        // Dismiss without choosing. A menu left open over Summary is a screen with
        // nothing working on it.
        app.tap()
        XCTAssertTrue(
            app.buttons["Copy"].waitForExistence(timeout: 10),
            "Summary did not come back after the share menu closed")
    }
}
