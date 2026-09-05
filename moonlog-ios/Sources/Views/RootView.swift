import SwiftUI
import MoonlogCore

/// Scaffold placeholder. Replaced by the Tonight screen once `MoonlogCore` and the
/// SwiftData layer land — this exists so the project builds and runs, and so the
/// palette wiring is verifiable on device from the first commit.
struct RootView: View {
    @Environment(\.moonTheme) private var theme
    @Environment(\.palette) private var palette

    private let clock = MoonClock(timeZoneIdentifier: TimeZone.current.identifier)

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("🌙")
                    .font(.system(size: 44))

                Text("Moonlog")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(palette.ink)

                Text(clock.now, format: .dateTime.hour().minute())
                    // Monospaced digits so a running timer doesn't jitter as
                    // digit widths change — a number that gets re-read all night.
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(palette.accent)

                Text(theme.displayName)
                    .font(.footnote)
                    .foregroundStyle(palette.faint)
            }
        }
        .preferredColorScheme(theme.colorScheme)
    }
}

#Preview("Night") {
    RootView().environment(\.moonTheme, .night)
}

#Preview("Deep Night") {
    RootView().environment(\.moonTheme, .deepNight)
}

#Preview("Day") {
    RootView().environment(\.moonTheme, .day)
}
