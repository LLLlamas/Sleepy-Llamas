import XCTest

/// Setting the app up, and taking it apart again.
///
/// All three of these were things the store could do and the app could not reach:
/// a family could be created and never renamed or removed, a baby could be added
/// and never reordered or put back, and there was no way to a first run except
/// deleting the app.
final class HouseholdTests: MoonlogUITestCase {

    func testAFamilyCanBeRenamedAndRemoved() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Rename or remove Nguyen"]).tap()

        XCTAssertTrue(app.navigationBars["Client family"].waitForExistence(timeout: 5))
        // Nguyen has tonight's shift open, so removing it must be refused here
        // rather than by an alert after the tap.
        XCTAssertFalse(
            app.buttons["Remove Nguyen"].isEnabled,
            "offered to remove a household with a night still running")
        XCTAssertTrue(app.buttons["Save"].exists, "no way to rename")
    }

    /// Okafor is between visits and has no shift, so it is the one that can go.
    func testAHouseholdWithNoOpenShiftCanBeRemoved() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Okafor"]).tap()
        reveal(app.buttons["Rename or remove Okafor"]).tap()

        let remove = app.buttons["Remove Okafor"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(remove.isEnabled, "a household between visits should be removable")
        remove.tap()

        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "no confirmation")
        XCTAssertTrue(app.alerts.buttons["Cancel"].exists, "a delete with no way out")
        app.alerts.buttons["Remove"].tap()

        XCTAssertTrue(
            app.staticTexts["Nguyen"].firstMatch.waitForExistence(timeout: 10),
            "did not fall back to the remaining household")
        XCTAssertFalse(app.buttons["Okafor"].exists, "Okafor is still listed")
    }

    /// Card position on Tonight is muscle memory, so it is worth being able to set.
    func testBabiesCanBeReordered() {
        launch(["-moonlogTab", "settings"])
        XCTAssertTrue(
            reveal(app.buttons["Edit"]).isHittable,
            "no way into edit mode, so `onMove` can never fire")
    }

    /// Ships in Release: the only other way back to a first run on a real phone is
    /// deleting the app.
    func testEraseAsksBeforeItDoesAnything() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Erase everything and start over"]).tap()

        XCTAssertTrue(
            app.alerts["Erase everything?"].waitForExistence(timeout: 5),
            "erased with no confirmation at all")
        app.alerts.buttons["Cancel"].tap()

        app.buttons["Tonight"].firstMatch.tap()
        XCTAssertTrue(
            cardButton("Feed", for: "Mia").waitForExistence(timeout: 10),
            "cancelling erased anyway")
    }

    func testEraseReturnsTheAppToItsFirstRun() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Erase everything and start over"]).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Erase everything"].tap()

        // Onboarding is what a first run looks like, and it is the screen that is
        // otherwise unreachable once a family exists.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'family you'")).firstMatch
                .waitForExistence(timeout: 15),
            "did not land back on onboarding")
    }
}
