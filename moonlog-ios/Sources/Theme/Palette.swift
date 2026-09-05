import SwiftUI

/// Sleepy Llamas maroon identity, ported from `moonlog/src/styles/tokens.css`.
///
/// The hex values are carried over verbatim — they were contrast-checked against
/// real surfaces in the web app, including the `--faint` values which are the
/// tightest. Call sites refer to *roles* (`.sleep`, `.warn`, `.ink`), never to raw
/// hex, because those roles carry meaning the UI depends on.
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

    public static func `for`(_ theme: MoonTheme) -> Palette {
        switch theme {
        case .night:
            return Palette(
                bg: .hex("1a0a0e"), raised: .hex("241016"),
                raised2: .hex("2e151c"), chip: .hex("361a22"),
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
                bg: .hex("100508"), raised: .hex("190a0f"),
                raised2: .hex("221017"), chip: .hex("2a141b"),
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
                bg: .hex("fdf6f4"), raised: .hex("fffaf5"),
                raised2: .hex("f7e6e2"), chip: .hex("f3ddd6"),
                ink: .hex("2a1418"), soft: .hex("6b4a4f"), faint: .hex("7e5c61"),
                line: .hex("3d0f17", opacity: 0.12), lineStrong: .hex("3d0f17", opacity: 0.24),
                accent: .hex("a83246"), accentDeep: .hex("6b1a28"),
                accentFaint: .hex("f7e6e2"), accentInk: .hex("fffaf5"),
                sleep: .hex("3f7d68"), sleepFaint: .hex("e1f0e9"),
                awake: .hex("a83246"), awakeFaint: .hex("f7e6e2"),
                warn: .hex("9c3a54"), warnFaint: .hex("f7e0e6"),
                stop: .hex("b8324a"), stopFaint: .hex("fbe6ea"),
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

    public func color(for theme: MoonTheme) -> Color {
        switch theme {
        case .night, .deepNight:
            // Light enough to carry on #1a0a0e / #100508.
            switch self {
            case .gold: return .hex("d9a96b")
            case .rose: return .hex("e39aa6")
            case .lilac: return .hex("b7a0dd")
            case .sky: return .hex("6aa8dd")
            case .sage: return .hex("8fb8a8")
            }
        case .day:
            // Darkened to hold contrast on the cream/blush surfaces.
            switch self {
            case .gold: return .hex("9a6b1f")
            case .rose: return .hex("b8446a")
            case .lilac: return .hex("6b4d9e")
            case .sky: return .hex("1f5f9e")
            case .sage: return .hex("3f7d68")
            }
        }
    }
}

extension Color {
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
