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

    @MainActor
    private static let store = CareStore(modelContainer: sharedContainer)

    /// One instance for the whole app. Settings writes it and three screens read it,
    /// and they must be looking at the same object or a toggle only takes effect on
    /// the next launch.
    @MainActor
    private static let confirmations = ConfirmPreferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.careStore, Self.store)
                .environment(\.confirmations, Self.confirmations)
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

private struct CareStoreKey: EnvironmentKey {
    static let defaultValue: CareStore? = nil
}

extension EnvironmentValues {
    var careStore: CareStore? {
        get { self[CareStoreKey.self] }
        set { self[CareStoreKey.self] = newValue }
    }
}

/// Optional for the same reason `careStore` is: a `nil` default keeps this key free
/// of a shared mutable instance the compiler would have to be told to trust. Readers
/// go through `Environment.confirms(_:)`, which falls back to the action's own
/// default, so a preview without the injection still behaves like a fresh install.
private struct ConfirmationsKey: EnvironmentKey {
    static let defaultValue: ConfirmPreferences? = nil
}

extension EnvironmentValues {
    var confirmations: ConfirmPreferences? {
        get { self[ConfirmationsKey.self] }
        set { self[ConfirmationsKey.self] = newValue }
    }
}
