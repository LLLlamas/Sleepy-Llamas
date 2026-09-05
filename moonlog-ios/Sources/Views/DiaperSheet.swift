import SwiftUI
import MoonlogCore

struct DiaperSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    let onSave: (DiaperEntry) -> Void

    @State private var at = Date()
    @State private var contents: DiaperContents = .wet
    @State private var stool: StoolColor?

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        LogSheetChrome(
            title: "Diaper",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $at,
            shift: shift,
            saveEnabled: true,
            onSave: { onSave(DiaperEntry(at: at, contents: contents, stool: stool)) }
        ) {
            Section("What") {
                Picker("Contents", selection: $contents) {
                    Text("Wet").tag(DiaperContents.wet)
                    Text("Dirty").tag(DiaperContents.dirty)
                    Text("Both").tag(DiaperContents.both)
                }
                .pickerStyle(.segmented)
            }

            if contents.countsAsDirty {
                Section {
                    StoolPicker(selection: $stool)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Whether meconium has cleared is what the parents and the "
                         + "pediatrician are watching for.")
                }
            }
        }
    }
}

/// Labelled swatches in clinical progression order — never colour alone.
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

struct DiaperEntry {
    let at: Date
    let contents: DiaperContents
    let stool: StoolColor?
}
