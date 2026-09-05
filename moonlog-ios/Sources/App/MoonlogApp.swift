import SwiftUI

@main
struct MoonlogApp: App {
    /// Theme follows the system light/dark appearance, with Deep Night as an
    /// explicit override. Deliberately *not* switched automatically by shift
    /// hours: changing the screen under a tired user at 3am is exactly when
    /// predictability matters most.
    @AppStorage("moonlog.deepNight") private var deepNightEnabled = false
    @Environment(\.colorScheme) private var systemScheme

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.moonTheme, resolvedTheme)
        }
    }

    private var resolvedTheme: MoonTheme {
        if deepNightEnabled { return .deepNight }
        return systemScheme == .dark ? .night : .day
    }
}

private struct MoonThemeKey: EnvironmentKey {
    static let defaultValue: MoonTheme = .night
}

extension EnvironmentValues {
    var moonTheme: MoonTheme {
        get { self[MoonThemeKey.self] }
        set { self[MoonThemeKey.self] = newValue }
    }

    /// Convenience so views read roles rather than resolving a theme themselves.
    var palette: Palette { Palette.for(moonTheme) }
}
