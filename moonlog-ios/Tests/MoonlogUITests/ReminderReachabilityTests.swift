import XCTest

final class ReminderReachabilityTests: MoonlogUITestCase {
    private func chooseReminder() {
        reveal(cardButton("Feed", for: "Mia")).tap()
        let stepper = app.steppers["feed.reminder"]
        reveal(stepper)
        stepper.buttons["feed.reminder-Increment"].tap()
    }

    func testDeniedReminderKeepsTheFeedReachableAndSavable() {
        launch(["-moonlogReminderDenied"])
        chooseReminder()
        XCTAssertTrue(app.staticTexts["Notifications are off for Moonlog"].waitForExistence(timeout: 5))
        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }

    func testFailureAfterSavingShowsPersistentNoticeAfterSheetDismisses() {
        launch(["-moonlogReminderSaveFailure"])
        chooseReminder()
        app.buttons["Save"].tap()
        let warning = app.staticTexts["reminder.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 8), "feed saved but reminder failure was lost during dismissal")
        XCTAssertTrue(warning.label.contains("The feed was saved"))
        XCTAssertFalse(app.navigationBars["Feed"].exists)
        reveal(app.buttons["Dismiss reminder notice"]).tap()
        XCTAssertFalse(warning.exists)
    }
}
