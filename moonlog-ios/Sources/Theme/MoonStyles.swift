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
            .background(palette.bg)
            .tint(palette.accent)
    }

    /// The raised card treatment: fill plus a hairline border.
    func cardSurface(_ palette: Palette) -> some View {
        let shape = RoundedRectangle(cornerRadius: MoonLayout.cardCorner, style: .continuous)
        return self
            .background(palette.raised, in: shape)
            .overlay(shape.stroke(palette.line, lineWidth: 1))
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
