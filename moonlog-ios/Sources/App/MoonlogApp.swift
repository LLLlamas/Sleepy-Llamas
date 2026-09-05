import SwiftUI
import SwiftData

@main
struct MoonlogApp: App {
    /// Built once, on the main actor. The factory degrades to a local store rather
    /// than crashing, so a CloudKit problem never costs the night's logs.
    @MainActor
    private static let sharedContainer: ModelContainer = {
        let container = ModelContainerFactory.make()
        #if DEBUG
        DemoSeed.seedIfNeeded(container)
        #endif
        return container
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Self.sharedContainer)
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
