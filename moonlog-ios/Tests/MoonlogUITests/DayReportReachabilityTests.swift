import XCTest

/// Real routes through the daytime handoff, using only the local demo household.
/// Share menus are inspected; no share action, message or receipt is sent.
final class DayReportReachabilityTests: MoonlogUITestCase {
    private let summaryText = "A calm day with floor play after lunch."
    private let notesText = "The quiet room helped with the afternoon nap."

    private func dayArguments(ended: Bool, summaryTab: Bool = true) -> [String] {
        var result = ["-moonlogCareContext", "day"]
        if ended { result += ["-moonlogDayShiftEnded", "YES"] }
        if summaryTab { result += ["-moonlogTab", "summary"] }
        return result
    }

    private func reportField(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openReport() {
        reveal(app.buttons["summary.dayReport"]).tap()
        XCTAssertTrue(reportField("report.summary").waitForExistence(timeout: 10),
                      "the report route opened without its editable observations")
    }

    private func enter(_ text: String, into identifier: String) {
        let field = reveal(reportField(identifier))
        field.tap()
        field.typeText(text)
        let done = app.buttons["report.doneEditing"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the editor has no keyboard dismissal control")
        done.tap()
    }

    private func waitForSavedDraft() {
        let save = reveal(app.buttons["report.saveDraft"])
        if save.isEnabled { save.tap() }
        let saved = app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Draft saved on this phone.")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "no durable draft confirmation")
    }

    private func check(_ identifier: String) {
        let control = reveal(app.switches[identifier])
        // SwiftUI's Form switch row reports its whole label as the frame. The
        // trailing switch is the hit target, as in the existing Recovery tests.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "1", "the actual switch did not turn on")
    }

    private func waitUntilEnabled(_ element: XCUIElement, _ message: String) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, message)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testActiveDayHasTodayAndKeepsPublishingDisabled() {
        launch(dayArguments(ended: false, summaryTab: false))
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(cardButton("Feed", for: "Mia").waitForExistence(timeout: 10))
        capture("Nanny Log — Today with both children")

        app.buttons["Summary"].firstMatch.tap()
        openReport()
        check("report.reviewed")
        let publish = reveal(app.buttons["report.publish"])
        XCTAssertFalse(publish.isEnabled, "an active coverage window must not publish a final report")
    }

    func testEditableSummaryAndNotesSurviveRelaunch() {
        launch(dayArguments(ended: true))
        openReport()
        enter(summaryText, into: "report.summary")
        enter(notesText, into: "report.notes")
        waitForSavedDraft()
        app.terminate()

        relaunch(dayArguments(ended: true))
        openReport()
        XCTAssertTrue((reportField("report.summary").value as? String)?.contains(summaryText) == true)
        let notes = reveal(reportField("report.notes"))
        XCTAssertTrue((notes.value as? String)?.contains(notesText) == true)
    }

    func testReviewPublishesImmutableCopyAndReceiptCanBeSkipped() {
        launch(dayArguments(ended: true))
        openReport()
        enter(summaryText, into: "report.summary")
        enter(notesText, into: "report.notes")
        waitForSavedDraft()

        let publish = reveal(app.buttons["report.publish"])
        XCTAssertFalse(publish.isEnabled, "saving a draft is not a review")
        check("report.reviewed")
        waitUntilEnabled(publish, "explicit review did not enable publication of an ended shift")
        // A review belongs to the draft that was read, not later edits.
        // Return toward the editable observations above the review section.
        app.swipeDown()
        enter("Please bring a spare outfit tomorrow.", into: "report.questions")
        waitForSavedDraft()
        XCTAssertFalse(reveal(publish).isEnabled, "editing after review left Publish enabled")
        check("report.reviewed")
        waitUntilEnabled(publish, "the edited draft cannot be reviewed again")
        reveal(publish).tap()

        let status = app.staticTexts["report.publishedStatus"]
        reveal(status)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("revision 1"))
        reveal(app.buttons["report.optionalReceipt"]).tap()
        XCTAssertTrue(reportField("report.parentName").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["report.saveReceipt"].isEnabled)
        app.buttons["Cancel"].tap()

        // Receipt is optional: cancelling it leaves sharing reachable.
        XCTAssertTrue(reveal(app.buttons["report.openPublished"]).isHittable)
        reveal(app.buttons["report.optionalReceipt"]).tap()
        let parent = reveal(reportField("report.parentName"))
        parent.tap(); parent.typeText("Test Parent")
        app.buttons["report.receiptDoneEditing"].tap()
        let parentNote = reveal(reportField("report.parentNote"))
        parentNote.tap(); parentNote.typeText("Please pack extra diapers.")
        app.buttons["report.receiptDoneEditing"].tap()
        check("report.received")
        reveal(app.buttons["report.saveReceipt"]).tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 optional in-person receipt")).firstMatch.waitForExistence(timeout: 8))
        reveal(app.buttons["report.openPublished"]).tap()
        let revision = app.staticTexts["report.revisionTitle"]
        XCTAssertTrue(revision.waitForExistence(timeout: 5))
        XCTAssertEqual(revision.label, "Revision 1")
        XCTAssertFalse(reportField("report.summary").exists, "the published snapshot is an editor")
        XCTAssertFalse(reportField("report.notes").exists, "the published snapshot is an editor")
        capture("Nanny Log — reviewed immutable revision")

        let share = app.buttons["report.share"]
        XCTAssertTrue(share.isHittable, "optional receipt blocks access to Share")
        share.tap()
        XCTAssertTrue(app.buttons["Share text copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share designed page"].exists)
        XCTAssertTrue(app.buttons["Copy report"].exists)
        // Deliberately stop at the menu; selecting a destination is a user action.
    }
    private func openClosedCorrections() {
        // The editor's review section is above any current published copy.
        app.swipeDown(); app.swipeDown()
        reveal(app.buttons["report.correctFacts"]).tap()
        XCTAssertTrue(app.navigationBars["Correct care log"].waitForExistence(timeout: 8))
        XCTAssertFalse(cardButton("Feed", for: "Mia").exists,
                       "the historical editor offers new care instead of corrections")
    }

    private func publishReviewedRevision(_ expected: Int) {
        check("report.reviewed")
        let button = reveal(app.buttons["report.publish"])
        waitUntilEnabled(button, "reviewed ended shift cannot publish")
        button.tap()
        let status = reveal(app.staticTexts["report.publishedStatus"])
        XCTAssertTrue(status.label.contains("revision \(expected)"))
    }

    func testEndedFactsCanBeCorrectedUndoneAndPublishedAsANewRevision() {
        launch(dayArguments(ended: true))
        openReport()
        publishReviewedRevision(1)
        reveal(app.buttons["report.optionalReceipt"]).tap()
        let parent = reveal(reportField("report.parentName"))
        parent.tap(); parent.typeText("Audit Parent")
        app.buttons["report.receiptDoneEditing"].tap()
        check("report.received")
        reveal(app.buttons["report.saveReceipt"]).tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 optional in-person receipt")).firstMatch.waitForExistence(timeout: 8))

        openClosedCorrections()
        let latest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.record.")).firstMatch
        XCTAssertTrue(reveal(latest).label.localizedCaseInsensitiveContains("diaper"), "fixture newest row changed")
        latest.tap()
        XCTAssertTrue(app.navigationBars["Edit diaper"].waitForExistence(timeout: 5))
        app.buttons["Wet"].tap()
        app.buttons["Save"].tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8), "closed-shift correction did not expose Undo")
        undo.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "undone")).firstMatch.waitForExistence(timeout: 5))

        // Apply a real factual change after proving the reverse path works.
        reveal(latest).tap()
        XCTAssertTrue(app.navigationBars["Edit diaper"].waitForExistence(timeout: 5))
        app.buttons["Wet"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["End-of-day report"].waitForExistence(timeout: 5))
        let changed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Draft or care log changed" )).firstMatch
        reveal(changed)
        XCTAssertFalse(app.buttons["report.optionalReceipt"].exists, "old receipt was carried onto changed facts")
        app.swipeDown()
        publishReviewedRevision(2)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 optional in-person receipt")).firstMatch.exists,
                       "revision 1 receipt became a receipt of revision 2")

        let old = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Revision 1 ·")).firstMatch
        reveal(old).tap()
        XCTAssertEqual(app.staticTexts["report.revisionTitle"].label, "Revision 1")
        reveal(app.staticTexts["Optional in-person receipt · Audit Parent"])
    }

    func testClosedCorrectionsKeepCoverageEditableWithoutNewLogsOrReminders() {
        launch(dayArguments(ended: true))
        openReport(); openClosedCorrections()
        app.buttons["More"].tap()
        XCTAssertFalse(app.buttons["End shift"].exists, "closed shift can be ended a second time")
        app.buttons["Shift times"].tap()
        XCTAssertTrue(app.navigationBars["Shift times"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start"].exists)
        XCTAssertTrue(app.staticTexts["End"].exists, "ended coverage has no end correction")
        app.buttons["Cancel"].tap()
        let feed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "timeline.record.", "bottle")).firstMatch
        reveal(feed)
        revealClear(feed, of: app.tabBars.firstMatch).tap()
        let opened = app.navigationBars["Edit feed"].waitForExistence(timeout: 5)
        if !opened { print("CLOSED FEED ROUTE HIERARCHY\n" + app.debugDescription) }
        XCTAssertTrue(opened)
        XCTAssertFalse(app.steppers["feed.reminder"].exists, "past correction can create a new reminder")
        app.buttons["Cancel"].tap()
    }

    func testErasingWhileAClosedCorrectionIsOpenDoesNotReadDeletedModels() {
        launch(dayArguments(ended: true))
        openReport(); openClosedCorrections()
        app.buttons["Settings"].firstMatch.tap()
        reveal(app.buttons["Erase everything and start over"]).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Erase everything"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "family you")).firstMatch.waitForExistence(timeout: 15),
                      "a retained closed editor crashed or kept the erased family alive")
    }

}
