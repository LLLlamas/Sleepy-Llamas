import SwiftUI

/// Sleepy Llamas maroon identity, ported from `moonlog/src/styles/tokens.css`.
///
/// Call sites refer to *roles* (`.sleep`, `.warn`, `.ink`), never to raw hex,
/// because those roles carry meaning the UI depends on.
///
/// The values were ported from the PWA's `tokens.css` and are **no longer verbatim**.
/// Two things were wrong with treating them as settled:
///
/// 1. The claim that they were contrast-checked did not survive being checked.
///    `PaletteTests` now measures every text role against every surface at WCAG
///    2.1, and the Day theme failed five pairs — `sleep` on `chip` at 3.71:1 was
///    the worst. Those values are corrected here.
/// 2. The maroon read as near-black on a phone. The web ramp leans on a very
///    quiet `bg`→`raised` step, which a monitor flatters and an OLED panel in a
///    dark nursery does not, so the surfaces above `bg` are lifted toward maroon
///    and `bgLift` carries the identity at the top of the page.
///
/// `bg` is unchanged in Night and Deep Night — it is the brand anchor, the PWA's
/// `theme-color`, and the value every screenshot so far was taken against. Day's
/// `bg` moves one step warmer (`fdf6f4` → `fdf4f1`), because a cream page cannot
/// be made more maroon by lifting only what sits on top of it. Anything added
/// here has to pass the contrast test before it can be looked at.
public enum MoonTheme: String, CaseIterable, Sendable {
    /// Default dark. Deep maroon-black for a 3am nursery.
    case night
    /// Darker still, for when even Night is too bright.
    case deepNight
    /// Blush and cream, brand identity at full strength, for daytime reading.
    case day

    public var colorScheme: ColorScheme {
        switch self {
        case .night, .deepNight: return .dark
        case .day: return .light
        }
    }

    public var displayName: String {
        switch self {
        case .night: return "Night"
        case .deepNight: return "Deep Night"
        case .day: return "Day"
        }
    }
}

/// The semantic color roles. One instance per theme; see `Palette.for(_:)`.
public struct Palette: Sendable {
    // Surfaces, back to front
    public let bg: Color
    /// The maroon the page fades *from*, at the top where the clock sits.
    ///
    /// `bg` stays the brand anchor — it is the PWA's `theme-color` and the value
    /// every screenshot of this app has been taken against. The identity was
    /// reading as near-black on a phone, though, because `bg`→`raised` is a
    /// six-thousandths luminance step that a bright monitor flatters and an OLED
    /// panel in a dark room does not. This is the lift, and it is a role rather
    /// than an inline gradient stop so the contrast test covers text drawn on it.
    public let bgLift: Color
    public let raised: Color
    public let raised2: Color
    public let chip: Color

    // Text
    public let ink: Color
    public let soft: Color
    /// Tuned per theme to hold AA against `raised`/`raised2`/`chip` at small sizes.
    /// If a surface changes, re-measure rather than eyeballing an equivalent.
    public let faint: Color

    // Structure
    public let line: Color
    public let lineStrong: Color

    // Brand accent — the warm nightlight glow
    public let accent: Color
    public let accentDeep: Color
    public let accentFaint: Color
    /// Text drawn *on* an accent fill.
    public let accentInk: Color

    // State roles. These are semantic, not decorative.
    public let sleep: Color
    public let sleepFaint: Color
    public let awake: Color
    public let awakeFaint: Color
    /// Due-soon / caution — the overdue-feed state.
    public let warn: Color
    public let warnFaint: Color
    /// Fever flag and destructive actions.
    public let stop: Color
    public let stopFaint: Color

    public let backdrop: Color

    /// Built once each. Previously reconstructed on every view update, and five
    /// times per `RootView` body — each one ~20 hex scans through a fresh `Scanner`.
    public static func `for`(_ theme: MoonTheme) -> Palette {
        switch theme {
        case .night: return cachedNight
        case .deepNight: return cachedDeepNight
        case .day: return cachedDay
        }
    }

    private static let cachedNight = build(.night)
    private static let cachedDeepNight = build(.deepNight)
    private static let cachedDay = build(.day)

    /// The card the status tile sits on. Named separately because `BabyAccent`
    /// blends its wash against it, and the wash's contrast is only meaningful if
    /// that blend uses the same value the card is actually painted with — two
    /// copies of this hex would drift apart and the tests would keep passing.
    static func raisedHex(_ theme: MoonTheme) -> String {
        switch theme {
        case .night: return "2d1219"
        case .deepNight: return "210d14"
        case .day: return "fffaf7"
        }
    }

    private static func build(_ theme: MoonTheme) -> Palette {
        switch theme {
        case .night:
            return Palette(
                bg: .hex("1a0a0e"), bgLift: .hex("2e1019"), raised: .hex(raisedHex(.night)),
                raised2: .hex("3a1822"), chip: .hex("43202b"),
                ink: .hex("f7ece9"), soft: .hex("d9bcbd"), faint: .hex("bb979c"),
                line: .hex("3f2129"), lineStrong: .hex("532a34"),
                accent: .hex("d9a96b"), accentDeep: .hex("bd8748"),
                accentFaint: .hex("3a2a1d"), accentInk: .hex("1a0a0e"),
                sleep: .hex("8fb8a8"), sleepFaint: .hex("23362f"),
                awake: .hex("d9a96b"), awakeFaint: .hex("3a2a1d"),
                warn: .hex("db8893"), warnFaint: .hex("38202a"),
                stop: .hex("e36d6d"), stopFaint: .hex("3a181c"),
                backdrop: Color(red: 8 / 255, green: 3 / 255, blue: 5 / 255).opacity(0.62)
            )
        case .deepNight:
            return Palette(
                bg: .hex("100508"), bgLift: .hex("220b12"), raised: .hex(raisedHex(.deepNight)),
                raised2: .hex("2c121b"), chip: .hex("351822"),
                ink: .hex("efdedb"), soft: .hex("c8a9ab"), faint: .hex("ab8c91"),
                line: .hex("341a21"), lineStrong: .hex("46232c"),
                accent: .hex("cc9a5e"), accentDeep: .hex("ab7740"),
                accentFaint: .hex("2f2218"), accentInk: .hex("100508"),
                sleep: .hex("84ab9c"), sleepFaint: .hex("1c3029"),
                awake: .hex("cc9a5e"), awakeFaint: .hex("2f2218"),
                warn: .hex("cf7d88"), warnFaint: .hex("2e1a22"),
                stop: .hex("d96363"), stopFaint: .hex("301317"),
                backdrop: Color(red: 4 / 255, green: 1 / 255, blue: 2 / 255).opacity(0.72)
            )
        case .day:
            return Palette(
                bg: .hex("fdf4f1"), bgLift: .hex("f6e4df"), raised: .hex(raisedHex(.day)),
                raised2: .hex("f9ebe7"), chip: .hex("f5e2dc"),
                ink: .hex("2a1418"), soft: .hex("6b4a4f"), faint: .hex("6f5056"),
                line: .hex("3d0f17", opacity: 0.12), lineStrong: .hex("3d0f17", opacity: 0.24),
                accent: .hex("a83246"), accentDeep: .hex("6b1a28"),
                accentFaint: .hex("f7e6e2"), accentInk: .hex("fffaf5"),
                sleep: .hex("2f6753"), sleepFaint: .hex("e4f1eb"),
                awake: .hex("a83246"), awakeFaint: .hex("f7e6e2"),
                warn: .hex("9c3a54"), warnFaint: .hex("f7e0e6"),
                stop: .hex("a82a42"), stopFaint: .hex("fbe6ea"),
                backdrop: .hex("3d0f17", opacity: 0.32)
            )
        }
    }
}

/// A baby's accent colour, chosen by the user.
///
/// These are **not** palette roles. An earlier version reused `--accent`, `--sleep`
/// and `--warn`, which meant "gold" resolved to maroon in the Day theme and sat far
/// too close to "rose" — twins were distinguishable at night and barely so by day.
/// Each accent now carries its own value per theme, spaced around the hue wheel and
/// tuned separately for dark maroon and light blush surfaces.
///
/// There are five, not six. A "clay" terracotta was tried and removed: in a warm
/// maroon palette it sits inescapably close to gold, and a contrast test caught it
/// in every theme. Five well-separated options beat six that crowd — nobody needs a
/// sixth, and two colours a tired person can confuse are worse than one fewer.
///
/// Colour is still only ever the **third** identifying signal. The baby's name is
/// always visible and card order is fixed, because hue discrimination degrades in a
/// dark room and is absent for colourblind users — and mis-logging to the wrong twin
/// is the failure this whole layout is built to prevent.
public enum BabyAccent: String, CaseIterable, Sendable, Identifiable {
    case gold, rose, lilac, sky, sage

    public var id: String { rawValue }

    /// Spoken by VoiceOver and shown under each swatch, so the choice is never
    /// communicated by colour alone.
    public var displayName: String {
        switch self {
        case .gold: return "Gold"
        case .rose: return "Rose"
        case .lilac: return "Lilac"
        case .sky: return "Sky"
        case .sage: return "Sage"
        }
    }

    /// Default for the nth baby in a family — distinct without the user choosing.
    public static func forIndex(_ index: Int) -> BabyAccent {
        let all = BabyAccent.allCases
        return all[((index % all.count) + all.count) % all.count]
    }

    public func color(for theme: MoonTheme) -> Color { .hex(hex(for: theme)) }

    /// The hex behind `color(for:)`. Exposed as a string because the status tile's
    /// wash is a *blend* of it with the card underneath, and blending needs numbers.
    func hex(for theme: MoonTheme) -> String {
        switch theme {
        case .night, .deepNight:
            // Light enough to carry on #1a0a0e / #100508.
            switch self {
            case .gold: return "d9a96b"
            case .rose: return "e39aa6"
            case .lilac: return "b7a0dd"
            case .sky: return "6aa8dd"
            case .sage: return "8fb8a8"
            }
        case .day:
            // Darkened to hold contrast on the cream/blush surfaces.
            switch self {
            case .gold: return "9a6b1f"
            case .rose: return "b8446a"
            case .lilac: return "6b4d9e"
            case .sky: return "1f5f9e"
            case .sage: return "3f7d68"
            }
        }
    }

    /// The fill behind the status tile: this baby's colour, most of the way back to
    /// the card it sits on.
    ///
    /// **Asleep is the same colour faded further.** Which reads as *darker* on the
    /// two night themes and as *more transparent* by day, because both are "closer
    /// to the card" — the card is near-black at night and near-white by day. One
    /// rule, and it is the one the tile is meant to express: awake is the baby's
    /// colour at full, asleep is that colour quietened.
    ///
    /// **Computed opaque, never `.opacity()`.** An alpha value composites against
    /// whatever happens to be behind it at render time, which no contrast test can
    /// measure — `PaletteTests` reads the components and would score a translucent
    /// wash as if it were solid, passing a pair the eye fails. See the note on
    /// `Palette.raisedHex`.
    ///
    /// **The factors differ per theme, and that is not a rounding artefact.** How
    /// deep the awake fill can go is set by how much room the theme's own text roles
    /// have on it, and the three cards are nothing like each other: Day's is
    /// near-white and takes a fill at 0.74, Deep Night's is near-black and gives out
    /// at 0.85. Each number is the deepest that still keeps `ink` and `faint` at
    /// 4.5:1 and the accent outline at 3:1, for all five accents. They were measured,
    /// not chosen — change one and `PaletteTests` will tell you.
    ///
    /// The asleep fill sits at 0.95 everywhere: far enough back to read as quietened,
    /// not so far that the baby's colour disappears into the card.
    ///
    /// The honest limit of this: on Deep Night the two fills are only 1.17:1 apart,
    /// because a near-black card flattens everything blended into it. The fill is a
    /// supporting signal there, not the one carrying the state — the moon or sun
    /// glyph, the words "is asleep", and the elapsed counter that appears only while
    /// asleep all say it outright.
    public func wash(for theme: MoonTheme, asleep: Bool) -> Color {
        let awake: Double
        switch theme {
        case .night: awake = 0.82
        case .deepNight: awake = 0.85
        case .day: awake = 0.74
        }
        return .blend(
            hex(for: theme), toward: Palette.raisedHex(theme), by: asleep ? 0.95 : awake)
    }
}

extension Color {
    /// Two hex colours mixed, `by` of the way from the first to the second, as a
    /// fully opaque colour.
    ///
    /// Takes hex strings rather than `Color`s because SwiftUI will not give a
    /// `Color`'s components back without bridging to UIKit, and nothing in `Sources`
    /// imports UIKit for colour. Component-wise in sRGB, which is what "mix" means
    /// everywhere else these values are authored.
    static func blend(_ from: String, toward to: String, by amount: Double) -> Color {
        let a = rgb(from), b = rgb(to)
        let t = min(max(amount, 0), 1)
        return Color(
            .sRGB,
            red: a.0 + (b.0 - a.0) * t,
            green: a.1 + (b.1 - a.1) * t,
            blue: a.2 + (b.2 - a.2) * t,
            opacity: 1)
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    /// Six-digit hex, matching how the values are written in `tokens.css` so the
    /// two files can be diffed by eye.
    static func hex(_ hex: String, opacity: Double = 1) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }
}
