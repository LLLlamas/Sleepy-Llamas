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

    /// Which client household is on screen. A raw string because `@AppStorage`
    /// cannot hold a `UUID`; it is resolved against `families` on every render, so
    /// an id left behind by a deleted or archived family falls back rather than
    /// leaving the doula on an empty screen. See `FamilySelection`.
    @AppStorage("moonlog.currentFamilyID") private var currentFamilyIDRaw = ""

    @State private var error: String?
    @State private var tab = "tonight"
    @State private var addingFamily = false

    private var theme: MoonTheme {
        if deepNightEnabled { return .deepNight }
        return systemScheme == .dark ? .night : .day
    }

    private var palette: Palette { Palette.for(theme) }

    /// Never `families.first` directly: that made every household after the first
    /// unreachable. The stored id wins when it still names a family the query can
    /// see; anything else falls back to the oldest active one.
    private var currentFamily: Family? {
        guard let id = FamilySelection.resolve(
            storedID: currentFamilyIDRaw, among: families.map(\.id)) else { return nil }
        return families.first { $0.id == id }
    }

    var body: some View {
        tabs(currentFamily)
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
            // Switching household is deliberate, so the screen starts clean.
            // Without a per-family identity SwiftUI keeps TonightView's `@State`
            // across the change, and a half-filled log sheet would still be
            // holding the previous family's baby id.
            .id(family.id)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { familyMenu(family) }
            }
            .sheet(isPresented: $addingFamily) {
                AddFamilySheet(onAdd: createFamily)
            }
        } else {
            OnboardingView(onCreate: createFamily)
        }
    }

    /// The switcher, on Tonight rather than in Settings: it is the screen the doula
    /// is on all night, and the label doubles as a standing answer to "whose night
    /// am I logging?" — the mistake this guards against is logging a feed against
    /// the wrong household, which Settings, two taps away, would not prevent.
    private func familyMenu(_ current: Family) -> some View {
        Menu {
            // A Picker, so the current household carries a checkmark. Colour is
            // never the only signal.
            Picker("Client family", selection: familyBinding(current)) {
                ForEach(families) { family in
                    Text(family.name).tag(family.id)
                }
            }
            Divider()
            Button("Add client family", systemImage: "person.2.badge.plus") {
                addingFamily = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .accessibilityLabel("Client family, \(current.name)")
    }

    private func familyBinding(_ current: Family) -> Binding<UUID> {
        Binding(
            get: { current.id },
            set: { id in
                guard id != current.id else { return }
                Haptics.tap()
                currentFamilyIDRaw = id.uuidString
            })
    }

    /// Shared by first-run onboarding and the later add-family sheet — the same
    /// three writes, in the same order, so a second household is set up exactly
    /// like the first.
    private func createFamily(
        _ familyName: String, _ babyName: String, _ birthAt: Date, _ unit: VolumeUnit
    ) {
        run { store in
            let familyID = try await store.createFamily(name: familyName)
            try await store.setVolumeUnit(unit, familyID: familyID)
            _ = try await store.addBaby(to: familyID, name: babyName, birthAt: birthAt)
            // Select what was just created. `families` is sorted oldest-first, so
            // without this a newly added household would open behind the one
            // already on screen.
            currentFamilyIDRaw = familyID.uuidString
        }
    }

    @ViewBuilder
    private func summary(_ family: Family?, _ shift: Shift?) -> some View {
        if let family {
            SummaryView(family: family, shift: shift).id(family.id)
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
        StoreWrite.run(store, onError: { error = $0 }, action)
    }
}

/// Resolving the persisted family selection.
///
/// Its own type, not a computed property in the view, so the fallback rule can be
/// tested: it is the difference between a stale id showing the wrong household's
/// night and showing no household at all.
enum FamilySelection {
    /// The family to display, given what was stored and what actually exists.
    ///
    /// Falls back to the first of `ids` — the query's order, oldest active family
    /// first — when nothing is stored, when the stored value is not a UUID, or when
    /// it names a family that has since been archived or deleted. Returns `nil`
    /// only when there are no families at all, which is the onboarding case.
    static func resolve(storedID: String, among ids: [UUID]) -> UUID? {
        guard let stored = UUID(uuidString: storedID), ids.contains(stored) else {
            return ids.first
        }
        return stored
    }
}
