import SwiftUI
import SwiftData
import MoonlogCore

/// What Settings needs to run the household picker.
///
/// Grouped because the four travel together, and because a view initialiser
/// taking two `[Family]`-shaped things and two closures is where the wrong
/// argument gets passed without the compiler noticing.
struct FamilyRoster {
    let current: Family?
    let all: [Family]
    let select: (UUID) -> Void
    let create: (String, String, Date, VolumeUnit) -> Void
}

struct SettingsView: View {
    let roster: FamilyRoster
    let onError: (String) -> Void

    @AppStorage("moonlog.appearance") private var appearanceRaw = ""
    /// Retired. Read only so the picker opens on what is actually in force; see
    /// `AppearancePreference.stored`.
    @AppStorage("moonlog.deepNight") private var legacyDeepNight = false
    @State private var newTag = ""
    @State private var addingFamily = false
    @State private var addingBaby = false
    /// The baby whose name, colour or birth date is being corrected. Editing one
    /// also lives on Tonight, on her card; it is here as well because a wrong
    /// birth date is a setup mistake, and Tonight has no cards to tap between
    /// shifts.
    @State private var editingBaby: Baby?
    /// Drives the push to `HistoryView`. State rather than a `NavigationLink`'s
    /// own routing so there is exactly one way in — a screenshot run can set it,
    /// which a `NavigationLink` cannot be made to do without a second route.
    @State private var showingHistory = false
    /// The tags a swipe is asking to delete. Deleting a tag has no Undo — it is not a
    /// `CareStore` write with a reversing twin, it goes through `StoreWrite` — so
    /// this is the one place in Settings that can ask first.
    @State private var deletingTags: [NoteTagPreset]?

    @Environment(\.careStore) private var store
    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme
    @Environment(\.confirmations) private var confirmations

    /// Nil before onboarding — Appearance and Data still apply.
    private var family: Family? { roster.current }

    var body: some View {
        Form {
            clientSection

            if let family {
                babiesSection(family)
                historySection(family)
                preferencesSection(family)
                noteTagsSection(family)
            }

            appearanceSection
            confirmSection
            dataSection
        }
        .moonForm(palette)
        // On the Form for the same reason the destination below is: the row that
        // triggered this is the row being deleted, and a modifier declared on a row
        // that is going away has nowhere to be. An `alert` rather than a
        // `confirmationDialog` for the reason spelled out in `ShiftHoursSheet`.
        .alert(
            deletingTags.map { ConfirmableAction.deleteNoteTag.question(tagSubject($0)) } ?? "",
            isPresented: Binding(
                get: { deletingTags != nil },
                set: { if !$0 { deletingTags = nil } }),
            presenting: deletingTags
        ) { tags in
            Button("Delete", role: .destructive) {
                deletingTags = nil
                deleteTags(tags)
            }
            Button("Cancel", role: .cancel) { deletingTags = nil }
        } message: { _ in
            Text("Notes already written keep the tag. It stops being offered as a chip.")
        }
        // On the Form, never inside the Section that triggers it. A
        // `navigationDestination` declared inside a lazy container is only
        // registered once that row has been built, and pushing it before then
        // lands on a blank screen — which is exactly what this did.
        .navigationDestination(isPresented: $showingHistory) {
            if let family {
                HistoryView(family: family)
            } else {
                // The same guard `TonightView.coreSheet` uses: the household went
                // away between the tap and the push. An empty destination is a
                // blank screen whose only exit is the back button.
                Color.clear.onAppear { showingHistory = false }
            }
        }
        .sheet(isPresented: $addingFamily) {
            AddFamilySheet(onAdd: roster.create)
        }
        .sheet(item: $editingBaby) { baby in
            let id = baby.id
            BabyDetailSheet(
                name: baby.name, accent: baby.accent, birthAt: baby.birthAt
            ) { name, accent, birthAt in
                // No Undo here: Settings writes through `StoreWrite.run`, which has
                // no banner to offer one on. Tonight's copy of this sheet does.
                run { try await $0.updateBaby(id, name: name, accent: accent, birthAt: birthAt) }
            } onArchive: {
                run { try await $0.archiveBaby(id) }
            }
        }
        .sheet(isPresented: $addingBaby) {
            if let family {
                AddBabySheet(familyName: family.name) { name, birthAt in
                    run { _ = try await $0.addBaby(to: family.id, name: name, birthAt: birthAt) }
                }
                .presentationDetents([.medium])
            } else {
                Color.clear.onAppear { addingBaby = false }
            }
        }
        #if DEBUG
        // Screenshot affordance, never reachable in a real run — same rationale
        // as the rest of DemoSeed. These two sheets moved here off Tonight, and a
        // launch argument is now the only way to render them without tapping.
        .task {
            switch DemoSeed.requestedSettingsSheet {
            case "family": addingFamily = true
            case "baby": addingBaby = true
            case "history": showingHistory = true
            default: break
            }
        }
        #endif
    }

    // MARK: - Whose night this is

    /// First section, and deliberately the loudest thing on the screen.
    ///
    /// This is the app's one global mode. It used to be a dropdown in Tonight's
    /// toolbar, on the theory that the label doubled as a standing answer to
    /// "whose night am I logging?" — but it also made switching household a
    /// one-tap neighbour of the buttons pressed forty times a night. The standing
    /// answer now comes from `NightHeader`, which states the family name without
    /// offering to change it, and changing it lives here, two taps away, where a
    /// deliberate act belongs.
    ///
    /// An inline picker rather than a menu: with the two or three households a
    /// doula actually carries, every option and the checkmark on the live one are
    /// visible without opening anything. **Keep this at the root of the stack.**
    /// A switcher reachable from a pushed screen could change the family under a
    /// `ShiftDetailView`, which captures its `Family` and would go on rendering
    /// the previous household's night.
    @ViewBuilder
    private var clientSection: some View {
        Section {
            if roster.all.isEmpty {
                Text("No client family yet.")
                    .font(.footnote)
                    .foregroundStyle(palette.faint)
            } else if let current = family {
                Picker("Client family", selection: familyBinding(current)) {
                    ForEach(roster.all) { family in
                        Text(family.name).tag(family.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Button {
                Haptics.tap()
                addingFamily = true
            } label: {
                Label("Add client family", systemImage: "person.2.badge.plus")
            }
        } header: {
            Text("Client family")
        } footer: {
            Text("Everything you log tonight goes to the household ticked here. "
                 + "The name is shown above the clock on Tonight, so you can check "
                 + "it without coming back.")
        }
        .listRowBackground(palette.raised)
    }

    /// Takes the current family rather than reaching for it, so the getter cannot
    /// need a fallback. An earlier version ended `?? UUID()`, which would have
    /// minted a fresh selection on every body pass had it ever been reached.
    /// Selection is only ever written for a family already in the list, so
    /// `FamilySelection.resolve` remains the only thing coping with a stale id.
    private func familyBinding(_ current: Family) -> Binding<UUID> {
        Binding(
            get: { current.id },
            set: { id in
                guard id != current.id else { return }
                Haptics.tap()
                roster.select(id)
            })
    }

    // MARK: - Babies

    /// Adding a twin is a setup act, not a 3am act. It sat first in Tonight's
    /// overflow menu, one slip above "End shift".
    private func babiesSection(_ family: Family) -> some View {
        Section {
            ForEach(family.activeBabies) { baby in
                Button {
                    Haptics.tap()
                    editingBaby = baby
                } label: {
                    HStack {
                        BabyChip(name: baby.name, accent: baby.accent)
                        Spacer()
                        // The birth date, not "Day N". Day-of-life is pinned to a
                        // shift everywhere it appears, precisely so it cannot drift
                        // mid-night; there is no shift in scope here, and computing
                        // one against `Date()` would put a second, differently-derived
                        // day number in the app.
                        Text("Born \(Fmt.nightOf(baby.birthAt, timeZone: family.calendar.timeZone))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(palette.faint)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.faint)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit \(baby.name)")
            }
            Button {
                Haptics.tap()
                addingBaby = true
            } label: {
                Label("Add baby", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Babies")
        } footer: {
            Text("Tap a baby to correct her name, colour or birth date. The birth "
                 + "date is what \"Day 4\" on the handoff counts from.")
        }
        .listRowBackground(palette.raised)
    }

    // MARK: - History

    /// Past nights used to render under tonight's totals on Summary, and — because
    /// that section only appeared in the branch with no open shift — were
    /// unreachable during the shift itself. Here they are reachable all night.
    private func historySection(_ family: Family) -> some View {
        Section {
            Button {
                Haptics.tap()
                showingHistory = true
            } label: {
                HStack {
                    Label("Past nights", systemImage: "calendar")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.faint)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(palette.ink)
        }
        .listRowBackground(palette.raised)
    }

    // MARK: - Per-family preferences

    private func preferencesSection(_ family: Family) -> some View {
        Group {
            Section(family.name) {
                Picker("Bottle measurement", selection: unitBinding(family)) {
                    ForEach(VolumeUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            .listRowBackground(palette.raised)

            Section {
                ForEach(EventKind.optional, id: \.self) { kind in
                    Toggle(label(for: kind), isOn: optionalBinding(kind, family))
                }
            } header: {
                Text("Also log")
            } footer: {
                Text("Off by default. Pumping is recorded for the shift rather than "
                     + "for a baby.")
            }
            .listRowBackground(palette.raised)
        }
    }

    private func noteTagsSection(_ family: Family) -> some View {
        Section {
            let tags = sortedTags(family)
            ForEach(tags) { tag in
                Text(tag.label)
            }
            .onDelete { offsets in
                let doomed = offsets.map { tags[$0] }
                guard confirms(.deleteNoteTag) else { return deleteTags(doomed) }
                deletingTags = doomed
            }
            HStack {
                TextField("Add a tag", text: $newTag)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit { addTag(family) }
                Button("Add") { addTag(family) }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Note tags")
        } footer: {
            Text("Shown as quick chips when writing a note.")
        }
        .listRowBackground(palette.raised)
    }

    // MARK: - App-wide

    /// Three ways, not a toggle. "Follow phone" gives Day on a phone in Light
    /// appearance, which is the wrong screen to be holding over a sleeping baby —
    /// and the only override used to be a switch called Deep Night, whose label
    /// says nothing about the cream page you are actually trying to escape.
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: appearanceRaw)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Follow phone is Night when your phone is in dark mode and Day "
                 + "when it is not. Night and Deep Night stay dark whatever the "
                 + "phone is set to; Deep Night is darker still, for when even "
                 + "Night is too bright.")
        }
        .listRowBackground(palette.raised)
    }

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: {
                AppearancePreference.stored(
                    raw: appearanceRaw, legacyDeepNight: legacyDeepNight)
            },
            set: { appearanceRaw = $0.rawValue })
    }

    /// App-wide, not per family. This is how the doula wants the app to behave, and
    /// it does not change because tonight is a different household.
    private var confirmSection: some View {
        Section {
            ForEach(ConfirmableAction.allCases) { action in
                Toggle(isOn: confirmBinding(action)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label)
                        Text(action.note)
                            .font(.caption)
                            .foregroundStyle(palette.faint)
                    }
                }
                .sensoryFeedback(.selection, trigger: confirms(action))
            }
        } header: {
            Text("Ask before")
        } footer: {
            Text("On, the app asks first. Off, it just does it. Anything undoable "
                 + "leaves an Undo on the banner for six seconds either way — which "
                 + "is why most of these start off.")
        }
        .listRowBackground(palette.raised)
    }

    private var dataSection: some View {
        Section {
            LabeledContent("Storage", value: storageLabel)
            LabeledContent("Sync", value: syncLabel)
        } header: {
            Text("Data")
        } footer: {
            // Previously this was in a code comment claiming Settings surfaced
            // it. There was no Settings, so a fallback to memory was silent.
            Text(storageFooter)
        }
        .listRowBackground(palette.raised)
    }

    // MARK: - Bindings

    /// A swipe deletes one row, but `onDelete` hands over an `IndexSet` and a
    /// multi-select edit can hand over several. Naming them is better than "these".
    private func tagSubject(_ tags: [NoteTagPreset]) -> String {
        tags.count == 1 ? "\(tags[0].label)" : "\(tags.count) note"
    }

    private func deleteTags(_ tags: [NoteTagPreset]) {
        let ids = tags.map(\.id)
        run { store in for id in ids { try await store.deleteNoteTag(id) } }
    }

    private func confirms(_ action: ConfirmableAction) -> Bool {
        confirmations?.confirms(action) ?? action.confirmsByDefault
    }

    /// No `run` and no `StoreWrite`: this one is `UserDefaults`, not the store, so
    /// there is no actor round-trip and nothing that can fail to save.
    private func confirmBinding(_ action: ConfirmableAction) -> Binding<Bool> {
        Binding(
            get: { confirms(action) },
            set: { confirmations?.setConfirms($0, for: action) })
    }

    private func unitBinding(_ family: Family) -> Binding<VolumeUnit> {
        Binding(
            get: { family.volumeUnit },
            set: { unit in run { try await $0.setVolumeUnit(unit, familyID: family.id) } })
    }

    private func optionalBinding(_ kind: EventKind, _ family: Family) -> Binding<Bool> {
        Binding(
            get: { family.enabledKinds.contains(kind) },
            set: { on in
                var kinds = EventKind.optional.filter { family.enabledKinds.contains($0) }
                if on { kinds.append(kind) } else { kinds.removeAll { $0 == kind } }
                run { try await $0.setOptionalKinds(kinds, familyID: family.id) }
            })
    }

    private func sortedTags(_ family: Family) -> [NoteTagPreset] {
        (family.noteTags ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func label(for kind: EventKind) -> String {
        switch kind {
        case .pump: return "Pumping"
        case .medication: return "Medication"
        case .measurement: return "Weight"
        default: return kind.rawValue.capitalized
        }
    }

    private var storageLabel: String {
        switch ModelContainerFactory.mode {
        case .syncing: return "iCloud"
        case .localOnly: return "On this device"
        case .inMemory: return "In memory"
        }
    }

    /// Read from the mode rather than hardcoded. It used to say "Off" flatly, which
    /// would have gone on saying it after the iCloud capability landed — while the
    /// line directly above it said "iCloud".
    private var syncLabel: String {
        switch ModelContainerFactory.mode {
        case .syncing: return "On"
        case .localOnly, .inMemory: return "Off — this device only"
        }
    }

    private var storageFooter: String {
        switch ModelContainerFactory.mode {
        case .inMemory:
            return "⚠︎ The on-disk store failed to open. Anything logged now is lost "
                + "when the app closes. Restart the app before relying on it."
        case .syncing:
            return "Records sync to your iCloud account, so they survive losing this "
                + "phone."
        case .localOnly:
            return "Records stay on this phone, and are carried by the phone's own "
                + "backup. Deleting the app deletes them."
        }
    }

    // MARK: - Writes

    private func addTag(_ family: Family) {
        let label = newTag
        newTag = ""
        Haptics.tap()
        run { try await $0.addNoteTag(label, familyID: family.id) }
    }

    private func run(_ action: @escaping (CareStore) async throws -> Void) {
        StoreWrite.run(store, onError: onError, action)
    }
}
