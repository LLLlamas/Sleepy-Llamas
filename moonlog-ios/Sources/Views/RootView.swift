import SwiftUI
import SwiftData
import MoonlogCore

struct RootView: View {
    /// Theme follows the system light/dark appearance, with Deep Night as an
    /// explicit override. Deliberately *not* switched automatically by shift hours:
    /// changing the screen under a tired user at 3am is when predictability matters
    /// most.
    @AppStorage("moonlog.deepNight") private var deepNightEnabled = false

    /// Read here, in a View. An `App` struct does not receive a live system
    /// `colorScheme`, and — more importantly — deriving the theme from this value
    /// and then applying `.preferredColorScheme` from that same derivation is
    /// circular: the forced scheme becomes the value we read next, so the theme
    /// latches on whatever it resolved first and never changes again. That is why
    /// `preferredColorScheme` below is only applied for the explicit Deep Night
    /// override, never for the system-following case.
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Family.createdAt) private var families: [Family]

    private var theme: MoonTheme {
        if deepNightEnabled { return .deepNight }
        return systemScheme == .dark ? .night : .day
    }

    private var palette: Palette { Palette.for(theme) }

    var body: some View {
        NavigationStack {
            content
                .background(palette.bg)
                .navigationTitle("Moonlog")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(palette.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(palette.accent)
        .environment(\.moonTheme, theme)
        // Only forced for the explicit override. Applying it in the
        // system-following case would create the latch described above.
        .preferredColorScheme(deepNightEnabled ? .dark : nil)
    }

    @ViewBuilder
    private var content: some View {
        if let family = families.first {
            if let shift = openShift(for: family) {
                TonightView(family: family, shift: shift)
            } else {
                StartShiftPlaceholder(familyName: family.name)
            }
        } else {
            EmptyStatePlaceholder(
                emoji: "🌙",
                title: "No family yet",
                message: "Onboarding lands next.")
        }
    }

    /// The doula sets shift times explicitly, so between visits there is genuinely
    /// no open shift — that is a normal state, not an error.
    private func openShift(for family: Family) -> Shift? {
        (family.shifts ?? [])
            .filter(\.isOpen)
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }
}

struct StartShiftPlaceholder: View {
    let familyName: String
    @Environment(\.palette) private var palette

    var body: some View {
        EmptyStatePlaceholder(
            emoji: "🌙",
            title: "No shift running",
            message: "\(familyName) · start a shift to begin logging.")
    }
}

struct EmptyStatePlaceholder: View {
    let emoji: String
    let title: String
    let message: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 40))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(palette.bg)
    }
}
