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
        app.launchArguments =
            ["-moonlogSeedDemo", "YES", "-moonlogResetStore", "YES"] + extraArguments
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

    /// The card control for one baby. Labelled "\(title) for \(name)" by
    /// `BabyStatusCard.action`, which is what makes a wrong-twin tap detectable
    /// here at all.
    func cardButton(_ title: String, for baby: String) -> XCUIElement {
        app.buttons["\(title) for \(baby)"]
    }
}
