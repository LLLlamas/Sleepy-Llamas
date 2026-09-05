import SwiftUI
import SwiftData
import MoonlogCore

struct SettingsView: View {
    /// Nil before onboarding — Appearance and Data still apply.
    let family: Family?
    let onError: (String) -> Void

    @AppStorage("moonlog.deepNight") private var deepNightEnabled = false
    @State private var newTag = ""

    @Environment(\.careStore) private var store
    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        Form {
            Section {
                // The one control that makes Deep Night reachable at all. It was
                // read in three places and written nowhere.
                Toggle("Deep Night", isOn: $deepNightEnabled)
                    .sensoryFeedback(.selection, trigger: deepNightEnabled)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Night and Day follow the system setting. Deep Night is darker "
                     + "still, for when even Night is too bright — it stays on until "
                     + "you turn it off.")
            }
            .listRowBackground(palette.raised)

            if let family {
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

                Section {
                    let tags = sortedTags(family)
                    ForEach(tags) { tag in
                        Text(tag.label)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { tags[$0].id }
                        run { store in for id in ids { try await store.deleteNoteTag(id) } }
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

            Section {
                LabeledContent("Storage", value: storageLabel)
                LabeledContent("Sync", value: "Off — this device only")
            } header: {
                Text("Data")
            } footer: {
                // Previously this was in a code comment claiming Settings surfaced
                // it. There was no Settings, so a fallback to memory was silent.
                Text(storageFooter)
            }
            .listRowBackground(palette.raised)
        }
        .scrollContentBackground(.hidden)
        // A Form needs the same clearance as the scroll views — the floating tab
        // bar overlays its last rows otherwise.
        .contentMargins(.bottom, MoonLayout.tabBarClearance, for: .scrollContent)
        .background(palette.bg)
    }

    // MARK: - Bindings

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

    private var storageFooter: String {
        switch ModelContainerFactory.mode {
        case .inMemory:
            return "⚠︎ The on-disk store failed to open. Anything logged now is lost "
                + "when the app closes. Restart the app before relying on it."
        default:
            return "Records stay on this phone. There is no backup yet — deleting the "
                + "app deletes the records."
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
        guard let store else { onError("The data store is unavailable."); return }
        Task {
            do { try await action(store) } catch { onError("\(error)") }
        }
    }
}
