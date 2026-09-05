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
            if let shift = openShift(for: family) {
                TonightView(family: family, shift: shift)
            } else {
                StartShiftView(familyName: family.name) { startedAt, caregiver in
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
