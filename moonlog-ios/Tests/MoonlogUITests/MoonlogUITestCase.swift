import XCTest

/// Shared launch for every reachability test.
///
/// Each test gets its own seeded night: `-moonlogResetStore` empties the store
/// first, because the seed deliberately only fires into an empty one and without
/// the reset the second test in a run would inherit whatever the first logged.
class MoonlogUITestCase: XCTestCase {

    /// The installed app, not a fresh bundle — a UI test target hosted by the app
    /// launches the real thing, which is the entire point of this suite.
    let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    @discardableResult
    func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        // `-moonlogStillGlyphs` freezes the tile's sun and moon. XCUITest waits for
        // the app to report itself idle before the hierarchy snapshot a compound
        // query needs, and an animation in flight is not idle: with the glyphs
        // moving, the one test that asks for a button *containing* "Mia is asleep"
        // took eighteen minutes on its own and the suite took twenty-two. The drift
        // is bounded now, so the worst case is the length of the window rather than
        // forever — but it is decorative and nothing here asserts on it, so the
        // still frame stays.
        app.launchArguments =
            ["-moonlogSeedDemo", "YES", "-moonlogResetStore", "YES",
             "-moonlogStillGlyphs", "YES"] + extraArguments
        app.launch()
        return app
    }

    /// Launch again **without** emptying the store, for the tests that need a
    /// value read back from UserDefaults rather than from a store just rebuilt.
    ///
    /// It exists so those tests do not hand-write `launchArguments` and silently
    /// lose the rest of the list — `-moonlogStillGlyphs` above is the flag whose
    /// absence made one test take eighteen minutes. Dropping the reset is the
    /// only difference, and it is the point.
    @discardableResult
    func relaunch(_ extraArguments: [String] = []) -> XCUIApplication {
        app.launchArguments =
            ["-moonlogSeedDemo", "YES", "-moonlogStillGlyphs", "YES"] + extraArguments
        app.launch()
        return app
    }

    /// Scrolls until the element can actually be tapped.
    ///
    /// `exists` is not `isHittable`: a row below the fold exists, and tapping it
    /// silently does nothing. Both of this app's shipped-unreachable bugs would
    /// have passed an `exists` assertion.
    ///
    /// It scrolls before asserting existence, not after. In a `Form` — which is a
    /// lazy container — a row far enough down the list has not been **built** yet,
    /// so it does not exist to query either. Asserting first failed four tests on
    /// controls that were plainly there.
    @discardableResult
    func reveal(
        _ element: XCUIElement, swipes: Int = 14,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        // A short wait first, so a screen still loading is not read as a missing
        // control and swiped past.
        _ = element.waitForExistence(timeout: 5)
        var remaining = swipes
        while !(element.exists && element.isHittable) && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
        XCTAssertTrue(element.exists, "never appeared", file: file, line: line)
        XCTAssertTrue(element.isHittable, "exists but cannot be tapped", file: file, line: line)
        return element
    }

    /// Scrolls the sheet or page until `element` is clear of `cover`, then returns it.
    ///
    /// `isHittable` is **not** enough on its own. A row resting under the Save bar —
    /// which is a `safeAreaInset`, so it floats above the scrolling content — still
    /// reports `isHittable == true`, and tapping it lands on the bar. That is how a
    /// tap on Delete came back as "Diaper updated": the save ran instead, and every
    /// assertion about the delete failed somewhere unrelated.
    ///
    /// So this asserts the two frames do not intersect before handing the element
    /// back. Measure the frame; do not trust a coordinate tap or a hittable flag.
    ///
    /// It scrolls `app.scrollViews.firstMatch`, not `app.swipeUp()` — swiping the
    /// whole application frame drags near the home indicator and has left the
    /// simulator in a state that failed the *next* test in the class.
    @discardableResult
    func revealClear(
        _ element: XCUIElement, of cover: XCUIElement, swipes: Int = 6,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        _ = element.waitForExistence(timeout: 5)
        var remaining = swipes
        while element.exists && cover.exists
                && element.frame.intersects(cover.frame) && remaining > 0 {
            app.scrollViews.firstMatch.swipeUp()
            remaining -= 1
        }
        XCTAssertTrue(element.exists, "never appeared", file: file, line: line)
        XCTAssertFalse(
            element.frame.intersects(cover.frame),
            "\(element.frame) is still under \(cover.frame) — a tap here hits the wrong control",
            file: file, line: line)
        return element
    }

    /// The card control for one baby. Labelled "\(title) for \(name)" by
    /// `BabyStatusCard.action`, which is what makes a wrong-twin tap detectable
    /// here at all.
    func cardButton(_ title: String, for baby: String) -> XCUIElement {
        app.buttons["\(title) for \(baby)"]
    }
}
