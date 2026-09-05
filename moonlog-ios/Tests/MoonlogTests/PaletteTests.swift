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

    /// Consecutive babies must default to different accents, and the index wrap
    /// must be safe for negatives — Swift's `%` returns a negative remainder, which
    /// would trap on array subscript.
    func testBabyAccentCyclesAndSurvivesNegativeIndices() {
        let all = BabyAccent.allCases
        XCTAssertEqual(BabyAccent.forIndex(0), all[0])
        XCTAssertEqual(BabyAccent.forIndex(1), all[1])
        XCTAssertEqual(BabyAccent.forIndex(all.count), all[0])

        XCTAssertNotEqual(BabyAccent.forIndex(0), BabyAccent.forIndex(1))
        XCTAssertEqual(BabyAccent.forIndex(-1), all[all.count - 1])
    }

    /// Regression. An earlier version mapped accents onto palette *roles*, so in
    /// the Day theme "gold" resolved to maroon and sat almost on top of "rose" —
    /// twins were distinguishable at night and barely so by day. Every accent must
    /// be visibly distinct from every other, in every theme.
    func testAccentsAreMutuallyDistinctInEveryTheme() {
        for theme in MoonTheme.allCases {
            let pairs = BabyAccent.allCases
            for i in 0..<pairs.count {
                for j in (i + 1)..<pairs.count {
                    let a = components(pairs[i].color(for: theme))
                    let b = components(pairs[j].color(for: theme))
                    let distance = sqrt(
                        pow(a.0 - b.0, 2) + pow(a.1 - b.1, 2) + pow(a.2 - b.2, 2))
                    XCTAssertGreaterThan(
                        distance, 0.20,
                        "\(theme.displayName): \(pairs[i].displayName) and "
                            + "\(pairs[j].displayName) are too close (\(distance))")
                }
            }
        }
    }

    /// Every accent needs enough contrast against the surface it sits on, or the
    /// dot and the timeline name become unreadable in a dark room.
    func testAccentsContrastWithTheirThemeBackground() {
        for theme in MoonTheme.allCases {
            let bg = components(Palette.for(theme).bg)
            let bgLuma = luminance(bg)
            for accent in BabyAccent.allCases {
                let luma = luminance(components(accent.color(for: theme)))
                XCTAssertGreaterThan(
                    abs(luma - bgLuma), 0.15,
                    "\(theme.displayName): \(accent.displayName) is too close in "
                        + "luminance to the background")
            }
        }
    }

    private func components(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
        let c = UIColor(color).cgColor.components ?? [0, 0, 0, 1]
        return (c[0], c[1], c[2])
    }

    private func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
    }
}
