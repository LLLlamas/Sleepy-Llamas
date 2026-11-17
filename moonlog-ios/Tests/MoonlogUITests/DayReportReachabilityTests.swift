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
}
