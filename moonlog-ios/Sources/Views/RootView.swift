import SwiftUI
import SwiftData
import MoonlogCore

struct RootView: View {
    /// Theme follows the system appearance, with Deep Night as an explicit override.
    @AppStorage("moonlog.deepNight") private var deepNightEnabled = false

    /// Read here, in a View. Deriving the theme from this and then applying
    /// `.preferredColorScheme` from that derivation is circular — the forced scheme
    /// becomes the value read next, so it latches on whatever resolved first. Hence
    /// `preferredColorScheme` below covers only the explicit override.
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.careStore) private var store

    @Query(sort: \Family.createdAt) private var families: [Family]

    @State private var error: String?
    @State private var tab = "tonight"

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
        .preferredColorScheme(deepNightEnabled ? .dark : nil)
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let family = families.first {
            tabs(family)
        } else {
            OnboardingView { familyName, babyName, birthAt, unit in
                run { store in
                    let familyID = try await store.createFamily(name: familyName)
                    try await store.setVolumeUnit(unit, familyID: familyID)
                    _ = try await store.addBaby(to: familyID, name: babyName, birthAt: birthAt)
                }
            }
        }
    }

    /// Bottom tabs, following the retired PWA's shape: Tonight, Summary, Settings.
    /// Summary and Settings are reachable with no shift running, because that is a
    /// normal state and both still have something to say.
    @ViewBuilder
    private func tabs(_ family: Family) -> some View {
        let shift = openShift(for: family)
        TabView(selection: $tab) {
            Group {
                if let shift {
                    TonightView(family: family, shift: shift)
                } else {
                    StartShiftView(familyName: family.name) { startedAt, caregiver in
                        Haptics.commit()
                        run {
                            _ = try await $0.startShift(
                                familyID: family.id, startedAt: startedAt, caregiver: caregiver)
                        }
                    }
                }
            }
            .tabItem { Label("Tonight", systemImage: "moon.stars.fill") }
            .tag("tonight")

            SummaryView(family: family, shift: shift)
                .tabItem { Label("Summary", systemImage: "list.bullet.rectangle") }
                .tag("summary")

            SettingsView(family: family) { error = $0 }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        .toolbarBackground(palette.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: tab)
        #if DEBUG
        .task { tab = DemoSeed.requestedTab ?? tab }
        #endif
    }

    /// Between visits there is genuinely no open shift — a normal state.
    private func openShift(for family: Family) -> Shift? {
        (family.shifts ?? [])
            .filter(\.isOpen)
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private func run(_ action: @escaping (CareStore) async throws -> Void) {
        guard let store else { return }
        Task {
            do { try await action(store) } catch { self.error = "\(error)" }
        }
    }
}
