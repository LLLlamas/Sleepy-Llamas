import SwiftUI
import MoonlogCore

/// Shared surfaces. Each of these was written out verbatim in three or more places,
/// which meant a palette change to a form or a card was that many edits.
extension View {
    /// Page chrome for a `Form`: palette background, tab-bar clearance, brand tint.
    func moonForm(_ palette: Palette) -> some View {
        self
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, MoonLayout.tabBarClearance, for: .scrollContent)
            .moonBackground(palette)
            .tint(palette.accent)
    }

    /// The page base. One call site per screen, so the identity cannot drift the
    /// way `tabBarClearance` did before it was a constant.
    ///
    /// A wash rather than a flat fill: the maroon is strongest at the top, under
    /// the clock, and settles to `bg` by the time it reaches the timeline. Flat
    /// `bg` on an OLED panel in a dark room reads as black, which is how the brand
    /// went missing from a screen named after it.
    func moonBackground(_ palette: Palette) -> some View {
        background(MoonBackground(palette: palette))
    }

    /// The raised card treatment: fill plus a hairline border.
    func cardSurface(_ palette: Palette) -> some View {
        let shape = RoundedRectangle(cornerRadius: MoonLayout.cardCorner, style: .continuous)
        return self
            .background(palette.raised, in: shape)
            .overlay(shape.stroke(palette.line, lineWidth: 1))
    }
}

/// The page wash. Its own `View` so the gradient is described once and every
/// screen gets the same one — and so `.ignoresSafeArea()` sits here rather than
/// being remembered at each call site.
struct MoonBackground: View {
    let palette: Palette

    var body: some View {
        LinearGradient(
            // Three stops, not two: a straight two-stop ramp puts the midpoint
            // halfway down the screen, which tints the timeline rows and makes the
            // cards behind them look inconsistently lit. This lands on `bg` at
            // 45% and holds it.
            stops: [
                .init(color: palette.bgLift, location: 0),
                .init(color: palette.bg, location: 0.45),
                .init(color: palette.bg, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// A baby's dot and name. Written out three times before this existed, and it is
/// the app's primary identity signal — the name is never omitted, and the colour is
/// only ever the third cue behind name and card position.
struct BabyChip: View {
    let name: String
    let accent: BabyAccent
    var font: Font = .headline

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent.color(for: theme))
                .frame(width: 10, height: 10)
            Text(name).font(font).foregroundStyle(palette.ink)
        }
    }
}

/// The fever flag. The wording matters: the app observes, it does not diagnose, so
/// this states the reading and defers to the parents.
struct FeverBadge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Label(
            "At or above \(Fmt.temp(ShiftTotals.feverThresholdF)) — tell the parents",
            systemImage: "thermometer.high")
            .font(.footnote)
            .foregroundStyle(palette.stop)
    }
}
