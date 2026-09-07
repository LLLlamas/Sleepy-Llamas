import XCTest

/// Deep Night is the one theme a screenshot run can never reach by switching the
/// simulator's appearance, because it is a setting rather than an OS mode — so its
/// tile fills were the only two of the eight asserted but never seen.
final class AppearanceTests: MoonlogUITestCase {

    /// A phone in Light appearance used to mean the cream Day theme in a dark
    /// nursery, with no way to say "always dark": the one override was a toggle
    /// labelled Deep Night, which says nothing about the page you are escaping.
    func testPickingNightHoldsAcrossTabsAndRelaunches() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Night"]).tap()

        app.buttons["Tonight"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons.containing(.staticText, identifier: "Mia is asleep")
                .firstMatch.waitForExistence(timeout: 10),
            "Tonight did not survive the theme change")

        // Relaunched **without** the reset, so the choice is read back from
        // UserDefaults rather than from a store that was just rebuilt.
        app.terminate()
        app.launchArguments = ["-moonlogSeedDemo", "YES", "-moonlogTab", "settings"]
        app.launch()

        XCTAssertTrue(
            reveal(app.buttons["Night"]).isSelected,
            "the appearance choice did not survive a launch")
    }

    /// Deep Night has to be selectable, not merely present: it is the darkest
    /// surface the app has and the one a real 3am shift is most likely to want.
    func testDeepNightIsSelectable() {
        launch(["-moonlogTab", "settings"])
        reveal(app.buttons["Deep Night"]).tap()

        app.buttons["Tonight"].firstMatch.tap()
        XCTAssertTrue(
            cardButton("Note", for: "Mia").waitForExistence(timeout: 10),
            "the cards did not render in Deep Night")
    }

    /// "Follow phone" must not force a scheme. Forcing it latches the theme on its
    /// first value and it never follows the phone again.
    func testFollowPhoneIsTheDefault() {
        launch(["-moonlogTab", "settings"])
        XCTAssertTrue(
            reveal(app.buttons["Follow phone"]).isSelected,
            "a fresh install should follow the phone")
    }
}
