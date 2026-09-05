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

    /// Only the open shifts, which is at most one per family — not every shift the
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

    // `Palette.for` is cached per theme, so this is a lookup rather than the five
    // full palette constructions per body it used to be.
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

    /// The tabs are always present, including during onboarding. Seeing the shape
    /// of the app while setting it up is reassuring, and it keeps Settings reachable
    /// — Deep Night in particular, which someone may want before logging anything.
    private var content: some View {
        tabs(families.first)
    }

    /// Bottom tabs, following the retired PWA's shape: Tonight, Summary, Settings.
    /// Summary and Settings are reachable with no shift running, because that is a
    /// normal state and both still have something to say.
    @ViewBuilder
    private func tabs(_ family: Family?) -> some View {
        let shift = family.flatMap(openShift(for:))
        TabView(selection: $tab) {
            Group {
                if let family {
                    if let shift {
                        TonightView(family: family, shift: shift)
                    } else {
                        StartShiftView(familyName: family.name) { startedAt, caregiver in
                            Haptics.commit()
                            run {
                                _ = try await $0.startShift(
                                    familyID: family.id, startedAt: startedAt,
                                    caregiver: caregiver)
                            }
                        }
                    }
                } else {
                    OnboardingView { familyName, babyName, birthAt, unit in
                        run { store in
                            let familyID = try await store.createFamily(name: familyName)
                            try await store.setVolumeUnit(unit, familyID: familyID)
                            _ = try await store.addBaby(
                                to: familyID, name: babyName, birthAt: birthAt)
                        }
                    }
                }
            }
            .tabItem { Label("Tonight", systemImage: "moon.stars.fill") }
            .tag("tonight")

            Group {
                if let family {
                    SummaryView(family: family, shift: shift)
                } else {
                    EmptyStatePlaceholder(
                        emoji: "📋",
                        title: "Nothing yet",
                        message: "Set up a family first — the night's totals appear here.")
                }
            }
            .tabItem { Label("Summary", systemImage: "list.bullet.rectangle") }
            .tag("summary")

            SettingsView(family: family) { error = $0 }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        // Softened during onboarding: the bar is visible so the app's shape is
        // legible from the first screen, but muted because two of its three
        // destinations have nothing in them yet.
        .toolbarBackground(
            palette.bg.opacity(families.isEmpty ? 0.55 : 1), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: tab)
        #if DEBUG
        .task { tab = DemoSeed.requestedTab ?? tab }
        #endif
    }

    /// Between visits there is genuinely no open shift — a normal state.
    private func openShift(for family: Family) -> Shift? {
        openShifts.first { $0.familyIDRaw == family.id }
    }

    private func run(_ action: @escaping (CareStore) async throws -> Void) {
        guard let store else { return }
        Task {
            do { try await action(store) } catch { self.error = "\(error)" }
        }
    }
}
