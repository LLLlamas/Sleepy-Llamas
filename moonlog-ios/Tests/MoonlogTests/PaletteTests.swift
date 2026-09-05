import XCTest
import SwiftUI
@testable import Moonlog

final class PaletteTests: XCTestCase {

    func testEveryThemeResolves() {
        for theme in MoonTheme.allCases {
            _ = Palette.for(theme)
            XCTAssertFalse(theme.displayName.isEmpty)
        }
    }

    func testDarkThemesReportDarkColorScheme() {
        XCTAssertEqual(MoonTheme.night.colorScheme, .dark)
        XCTAssertEqual(MoonTheme.deepNight.colorScheme, .dark)
        XCTAssertEqual(MoonTheme.day.colorScheme, .light)
    }

    /// Guards the hex parser against a silent all-black failure, which is the
    /// failure mode that would be hardest to notice in a Night theme.
    func testHexParsingProducesExpectedComponents() {
        let accent = Color.hex("d9a96b")
        let components = UIColor(accent).cgColor.components ?? []
        XCTAssertEqual(components.count, 4)
        XCTAssertEqual(components[0], 0xd9 / 255, accuracy: 0.001)
        XCTAssertEqual(components[1], 0xa9 / 255, accuracy: 0.001)
        XCTAssertEqual(components[2], 0x6b / 255, accuracy: 0.001)
    }

    /// Twins must never resolve to the same accent, and the index wrap must be
    /// safe for negatives — Swift's `%` returns a negative remainder, which would
    /// trap on array subscript.
    func testBabyAccentCyclesAndSurvivesNegativeIndices() {
        XCTAssertEqual(BabyAccent.forIndex(0), .gold)
        XCTAssertEqual(BabyAccent.forIndex(1), .sage)
        XCTAssertEqual(BabyAccent.forIndex(2), .rose)
        XCTAssertEqual(BabyAccent.forIndex(3), .gold)

        XCTAssertNotEqual(BabyAccent.forIndex(0), BabyAccent.forIndex(1))
        XCTAssertEqual(BabyAccent.forIndex(-1), .rose)
        XCTAssertEqual(BabyAccent.forIndex(-3), .gold)
    }
}
