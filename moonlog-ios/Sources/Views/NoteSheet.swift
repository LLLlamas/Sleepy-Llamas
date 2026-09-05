import SwiftUI
import MoonlogCore

struct NoteSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    let presetTags: [String]
    let editing: NoteEntry?
    let onSave: (NoteEntry) -> Void
    var onDelete: (() -> Void)?

    @State private var at: Date
    @State private var text: String
    @State private var selected: Set<String>
    @State private var recordTemp: Bool
    @State private var tempF: Double

    init(
        baby: BabyPresentation,
        shift: ShiftWindow,
        presetTags: [String],
        editing: NoteEntry? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (NoteEntry) -> Void
    ) {
        self.baby = baby
        self.shift = shift
        self.presetTags = presetTags
        self.editing = editing
        self.onDelete = onDelete
        self.onSave = onSave
        _at = State(initialValue: editing?.at ?? Date())
        _text = State(initialValue: editing?.text ?? "")
        _selected = State(initialValue: Set(editing?.tags ?? []))
        _recordTemp = State(initialValue: editing?.tempF != nil)
        _tempF = State(initialValue: editing?.tempF ?? 98.6)
    }

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    private var isFever: Bool { tempF >= ShiftTotals.feverThresholdF }

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selected.isEmpty || recordTemp
    }

    var body: some View {
        LogSheetChrome(
            title: editing == nil ? "Note" : "Edit note",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $at,
            shift: shift,
            saveEnabled: hasContent,
            onSave: {
                onSave(
                    NoteEntry(
                        at: at,
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        tags: Array(selected).sorted(),
                        tempF: recordTemp ? tempF : nil))
            },
            onDelete: onDelete
        ) {
            if !presetTags.isEmpty {
                Section("Tags") {
                    TagChips(tags: presetTags, selected: $selected)
                }
            }

            Section("What happened") {
                TextField("Optional", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Toggle("Temperature", isOn: $recordTemp.animation())
                if recordTemp {
                    Stepper(value: $tempF, in: 93...107, step: 0.1) {
                        HStack {
                            Text("Reading")
                            Spacer()
                            Text(String(format: "%.1f °F", tempF))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(isFever ? palette.stop : palette.ink)
                        }
                    }
                    if isFever {
                        Label("At or above \(String(format: "%.1f", ShiftTotals.feverThresholdF))°F",
                              systemImage: "thermometer.high")
                            .foregroundStyle(palette.stop)
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

/// Wrapping chips. Tags are user-defined, so this renders whatever exists rather
/// than a fixed set.
private struct TagChips: View {
    let tags: [String]
    @Binding var selected: Set<String>
    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let isOn = selected.contains(tag)
                Button {
                    if isOn { selected.remove(tag) } else { selected.insert(tag) }
                } label: {
                    Text(tag)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(isOn ? palette.accentInk : palette.ink)
                        .background(
                            isOn ? palette.accent : palette.chip,
                            in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct NoteEntry {
    let at: Date
    let text: String
    let tags: [String]
    let tempF: Double?
}
