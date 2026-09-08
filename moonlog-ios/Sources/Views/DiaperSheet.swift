import SwiftUI
import MoonlogCore

struct DiaperSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    let editing: DiaperEntry?
    let onSave: (DiaperEntry) async throws -> Void
    var onDelete: (() -> Void)?
    /// Forwarded to the chrome; set only when editing.
    var reassignment: Reassignment?

    @State private var at: Date
    @State private var contents: DiaperContents
    @State private var stool: StoolColor?

    init(
        baby: BabyPresentation,
        shift: ShiftWindow,
        editing: DiaperEntry? = nil,
        reassignment: Reassignment? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (DiaperEntry) async throws -> Void
    ) {
        self.baby = baby
        self.shift = shift
        self.editing = editing
        self.onDelete = onDelete
        self.reassignment = reassignment
        self.onSave = onSave
        _at = State(initialValue: editing?.at ?? Date())
        _contents = State(initialValue: editing?.contents ?? .wet)
        _stool = State(initialValue: editing?.stool)
    }

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        LogSheetChrome(
            title: editing == nil ? "Diaper" : "Edit diaper",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $at,
            shift: shift,
            reassignment: reassignment,
            saveEnabled: true,
            // Saved exactly as the swatches show it, cleared included. The colour used
            // to be dropped whenever the contents were not dirty, because the section
            // was dropped with them: a colour picked on "dirty" and then corrected to
            // "wet" stayed in state unseen and put meconium in the parents' handoff.
            // Nothing can be stranded now that the section stands on every contents
            // choice — the only way to abandon a colour is to tap the chosen swatch
            // again, and that has to reach the record as nil rather than leave the
            // previous colour standing.
            onSave: {
                try await onSave(DiaperEntry(at: at, contents: contents, stool: stool))
            },
            onDelete: onDelete
        ) {
            Section("What") {
                Picker("Contents", selection: $contents) {
                    Text("Wet").tag(DiaperContents.wet)
                    Text("Dirty").tag(DiaperContents.dirty)
                    Text("Both").tag(DiaperContents.both)
                }
                .pickerStyle(.segmented)
            }

            // On every contents choice, not just the dirty ones: a wet diaper can carry
            // something worth reporting too, and a picker that comes and goes with the
            // segmented control is what stranded a colour in the first place.
            Section {
                StoolPicker(selection: $stool)
            } header: {
                Text("Colour")
            } footer: {
                Text("Whether meconium has cleared is what the parents and the "
                     + "pediatrician are watching for. Tap a chosen colour again to "
                     + "clear it.")
            }
        }
    }
}

/// Labelled swatches in clinical progression order — never colour alone. Tapping the
/// selected one clears it: the field is optional, and with the picker on every diaper a
/// mis-tap needs a way back that is not "delete the record and log it again".
private struct StoolPicker: View {
    @Binding var selection: StoolColor?
    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(StoolColor.allCases, id: \.self) { colour in
                Button {
                    selection = selection == colour ? nil : colour
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(swatch(colour))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle().stroke(
                                    selection == colour ? palette.ink : palette.line,
                                    lineWidth: selection == colour ? 2 : 1))
                        Text(colour.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(selection == colour ? palette.ink : palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colour.rawValue.capitalized)
                .accessibilityAddTraits(selection == colour ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }

    /// Approximations of the real thing, kept muted so the sheet stays calm.
    private func swatch(_ colour: StoolColor) -> Color {
        switch colour {
        case .meconium: return .hex("2f2a2e")
        case .transitional: return .hex("6b5a3a")
        case .green: return .hex("6f8f5a")
        case .brown: return .hex("8a6440")
        case .yellow: return .hex("d9b45c")
        }
    }
}

struct DiaperEntry: Sendable {
    let at: Date
    let contents: DiaperContents
    let stool: StoolColor?
}
