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

    @Query(filter: #Predicate<Family> { !$0.isArchived }, sort: \Family.createdAt)
    private var families: [Family]

    /// Only the open shifts — at most one per family — rather than every shift the
    /// family has ever had. The previous version walked `family.shifts` and sorted
    /// it on every body pass, so the work grew by one element per night, forever.
    @Query(filter: #Predicate<Shift> { $0.isOpen }, sort: \Shift.startedAt, order: .reverse)
    private var openShifts: [Shift]

    @State private var error: String?
    @State private var tab = "tonight"

    private var theme: MoonTheme {
        if deepNightEnabled { return .deepNight }
        return systemScheme == .dark ? .night : .day
    }

    private var palette: Palette { Palette.for(theme) }

    var body: some View {
        tabs(families.first)
            .tint(palette.accent)
            .environment(\.moonTheme, theme)
            // Only forced for the explicit override. Applying it in the
            // system-following case would latch the theme on its first value.
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

    /// Bottom tabs, following the retired PWA's shape. Present from the very first
    /// screen — seeing the app's shape while setting it up is reassuring, and it
    /// keeps Settings reachable before a family exists.
    @ViewBuilder
    private func tabs(_ family: Family?) -> some View {
        let shift = family.flatMap(openShift(for:))

        TabView(selection: $tab) {
            stack("Moonlog") { tonight(family, shift) }
                .tabItem { Label("Tonight", systemImage: "moon.stars.fill") }
                .tag("tonight")

            stack("Summary") { summary(family, shift) }
                .tabItem { Label("Summary", systemImage: "list.bullet.rectangle") }
                .tag("summary")

            stack("Settings") { SettingsView(family: family) { error = $0 } }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        // Softened during onboarding: the bar stays visible so the app's shape is
        // legible from the first screen, but muted because two of its three
        // destinations have nothing in them yet.
        .toolbarBackground(palette.bg.opacity(families.isEmpty ? 0.55 : 1), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: tab)
        #if DEBUG
        .task { tab = DemoSeed.requestedTab ?? tab }
        #endif
    }

    /// One `NavigationStack` per tab, which is the standard iOS shape. A single
    /// stack wrapping the whole `TabView` does not surface the selected tab's
    /// toolbar items — that silently made Summary's Copy and Share unreachable.
    private func stack<Content: View>(
        _ title: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .background(palette.bg)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(palette.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func tonight(_ family: Family?, _ shift: Shift?) -> some View {
        if let family {
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

    @ViewBuilder
    private func summary(_ family: Family?, _ shift: Shift?) -> some View {
        if let family {
            SummaryView(family: family, shift: shift)
        } else {
            EmptyStatePlaceholder(
                emoji: "📋",
                title: "Nothing yet",
                message: "Set up a family first — the night's totals appear here.")
        }
    }

    /// Between visits there is genuinely no open shift — a normal state.
    private func openShift(for family: Family) -> Shift? {
        openShifts.first { $0.familyIDRaw == family.id }
    }

    private func run(_ action: @escaping (CareStore) async throws -> Void) {
        guard let store else {
            error = "The data store is unavailable."
            return
        }
        Task {
            do { try await action(store) } catch { self.error = "\(error)" }
        }
    }
}
