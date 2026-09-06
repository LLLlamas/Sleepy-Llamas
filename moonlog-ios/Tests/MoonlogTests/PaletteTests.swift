import XCTest
import SwiftUI
@testable import Moonlog

final class PaletteTests: XCTestCase {

    /// Caching maps each theme to a `static let`. A transposed pair would be
    /// invisible to a test that only checks the call does not trap — and
    /// night/deepNight are the two easiest to swap.
    func testEachThemeResolvesToItsOwnPalette() {
        XCTAssertNotEqual(Palette.for(.night).bg, Palette.for(.deepNight).bg)
        XCTAssertNotEqual(Palette.for(.night).bg, Palette.for(.day).bg)
        XCTAssertNotEqual(Palette.for(.deepNight).bg, Palette.for(.day).bg)
        XCTAssertEqual(Palette.for(.night).bg, Color.hex("1a0a0e"))
        XCTAssertEqual(Palette.for(.deepNight).bg, Color.hex("100508"))
        // Moved one step warmer from the PWA's `fdf6f4` when the maroon was
        // pushed forward; the dark themes' anchors did not move.
        XCTAssertEqual(Palette.for(.day).bg, Color.hex("fdf4f1"))
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

    /// The palette's whole claim is that it was contrast-checked against real
    /// surfaces. Nothing enforced that, so a surface could be darkened — or the
    /// maroon pushed forward — and the `faint` values, which are the tightest,
    /// would fail silently in the one room this app is used in.
    ///
    /// WCAG 2.1 relative luminance, not the crude weighted sum the accent tests
    /// use: that one compares two accents to each other, where a rough distance is
    /// enough. Text against a surface is a legibility threshold and needs the real
    /// curve. AA is 4.5:1 for body text and 3:1 for large; every role here is read
    /// at footnote size or above, so `faint` is held to 4.5 like the rest.
    func testTextRolesHoldAAAgainstEverySurfaceTheySitOn() {
        for theme in MoonTheme.allCases {
            let p = Palette.for(theme)
            let surfaces = [("bg", p.bg), ("bgLift", p.bgLift), ("raised", p.raised),
                            ("raised2", p.raised2), ("chip", p.chip)]
            let text = [("ink", p.ink), ("soft", p.soft), ("faint", p.faint),
                        ("sleep", p.sleep), ("awake", p.awake), ("warn", p.warn),
                        ("stop", p.stop)]
            for (surfaceName, surface) in surfaces {
                for (textName, colour) in text {
                    let ratio = contrast(colour, surface)
                    XCTAssertGreaterThanOrEqual(
                        ratio, 4.5,
                        "\(theme.displayName): \(textName) on \(surfaceName) is "
                            + String(format: "%.2f:1", ratio))
                }
            }
        }
    }

    /// A state tint on its own faint wash — the pill treatment. These pairs exist
    /// precisely to be used together, so they are the pair most likely to be
    /// reached for without checking.
    func testStateTintsHoldAAOnTheirOwnFaintWash() {
        for theme in MoonTheme.allCases {
            let p = Palette.for(theme)
            let pairs = [("sleep", p.sleep, p.sleepFaint), ("awake", p.awake, p.awakeFaint),
                         ("warn", p.warn, p.warnFaint), ("stop", p.stop, p.stopFaint),
                         ("accent", p.accent, p.accentFaint)]
            for (name, tint, wash) in pairs {
                let ratio = contrast(tint, wash)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(theme.displayName): \(name) on \(name)Faint is "
                        + String(format: "%.2f:1", ratio))
            }
        }
    }

    /// Text drawn *on* the accent fill — the confirmation banner, which carries the
    /// Undo button and is the only feedback that a write landed.
    /// The status tile, which is now tinted by the baby rather than by the state:
    /// five accents x three themes x two states, and three pairs inside each tile.
    ///
    /// Two thresholds, because two different things are being measured. `ink` and
    /// `faint` are text and are held to AA's 4.5:1 like every other text role here.
    /// The accent is the 2pt border and the moon/sun glyph — non-text UI components,
    /// which WCAG 1.4.11 holds to 3:1. Holding the border to 4.5 as well was tried
    /// and forced the accent 44% of the way to `ink` to satisfy it, which bleached
    /// out the one thing the tile's colour now exists to say.
    ///
    /// The subtitle uses `soft` rather than `faint` precisely because of this test:
    /// `faint` was what capped how deep either fill could go, and the fills need
    /// depth to stay recognisable as the baby's colour. Text on a wash is a pair
    /// nothing checked before this — not for the old `sleepFaint`/`awakeFaint` either.
    func testTheBabyTintedTileHoldsUpInEveryAccentAndState() {
        for theme in MoonTheme.allCases {
            let p = Palette.for(theme)
            for accent in BabyAccent.allCases {
                for asleep in [true, false] {
                    let wash = accent.wash(for: theme, asleep: asleep)
                    let state = asleep ? "asleep" : "awake"
                    let where_ = "\(theme.displayName)/\(accent.displayName)/\(state)"

                    for (name, text) in [("ink", p.ink), ("soft", p.soft)] {
                        let ratio = contrast(text, wash)
                        XCTAssertGreaterThanOrEqual(
                            ratio, 4.5,
                            "\(where_): \(name) on the tile is "
                                + String(format: "%.2f:1", ratio))
                    }

                    let outline = contrast(accent.color(for: theme), wash)
                    XCTAssertGreaterThanOrEqual(
                        outline, 3.0,
                        "\(where_): the border and icon are "
                            + String(format: "%.2f:1", outline))
                }
            }
        }
    }

    /// The fill has two jobs, and this asserts both — because asserting only the
    /// second is how the first was shipped broken.
    ///
    /// **Identity:** each fill must stand off the card enough to read as this baby's
    /// colour. **Separation:** the two states must not paint the same. They pull
    /// against each other; 1.20 is what every theme clears on both.
    ///
    /// The first version of this test checked separation alone. The factors then in
    /// place put the asleep fill 1.06:1 from the card — invisible, an outline with
    /// nothing inside — and the suite passed, because an invisible fill is still
    /// different from a visible one. It took a screenshot to catch. Neither
    /// assertion below is redundant.
    func testBothFillsStayVisibleAndTellTheStatesApart() {
        for theme in MoonTheme.allCases {
            let card = Palette.for(theme).raised
            for accent in BabyAccent.allCases {
                let awake = accent.wash(for: theme, asleep: false)
                let asleep = accent.wash(for: theme, asleep: true)
                let where_ = "\(theme.displayName)/\(accent.displayName)"

                for (state, fill) in [("awake", awake), ("asleep", asleep)] {
                    let ratio = contrast(fill, card)
                    XCTAssertGreaterThan(
                        ratio, 1.18,
                        "\(where_): the \(state) fill is \(String(format: "%.3f:1", ratio)) "
                            + "against the card — too close to read as a colour at all")
                }

                let apart = contrast(awake, asleep)
                XCTAssertGreaterThan(
                    apart, 1.18,
                    "\(where_): the two fills are only "
                        + String(format: "%.3f:1", apart) + " apart")
            }
        }
    }

    /// `blend` must return four opaque sRGB components. `components(_:)` reads three
    /// and ignores alpha, so a translucent wash would be measured as solid and score
    /// a ratio the eye never gets — and a monochrome colour space returns two
    /// components and traps outright.
    func testBlendProducesOpaqueSRGBComponents() {
        let midpoint = Color.blend("000000", toward: "ffffff", by: 0.5)
        let parts = UIColor(midpoint).cgColor.components ?? []
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[3], 1.0, accuracy: 0.001, "the wash must be opaque")
        for channel in 0..<3 {
            XCTAssertEqual(parts[channel], 0.5, accuracy: 0.01)
        }
        XCTAssertEqual(Color.blend("aabbcc", toward: "ffffff", by: 0), Color.hex("aabbcc"))
    }

    func testAccentInkHoldsAAOnTheAccentFill() {
        for theme in MoonTheme.allCases {
            let p = Palette.for(theme)
            let ratio = contrast(p.accentInk, p.accent)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "\(theme.displayName): accentInk on accent is "
                    + String(format: "%.2f:1", ratio))
        }
    }

    /// WCAG 2.1: `(lighter + 0.05) / (darker + 0.05)`, on linearised sRGB.
    private func contrast(_ a: Color, _ b: Color) -> CGFloat {
        let la = relativeLuminance(components(a))
        let lb = relativeLuminance(components(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func relativeLuminance(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        func channel(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private func components(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
        let c = UIColor(color).cgColor.components ?? [0, 0, 0, 1]
        return (c[0], c[1], c[2])
    }

    private func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
    }
}
