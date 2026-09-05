import SwiftUI
import MoonlogCore

/// Name and accent colour for one baby.
///
/// Reached by tapping the card header rather than by a long-press: a hidden
/// gesture is the wrong way to expose the only route to editing, and the web
/// version's undiscoverable long-press for manual sleep entry is the cautionary
/// example.
struct BabyDetailSheet: View {
    let babyID: UUID
    @State private var name: String
    @State private var accent: BabyAccent
    let onSave: (String, BabyAccent) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    init(
        babyID: UUID,
        name: String,
        accent: BabyAccent,
        onSave: @escaping (String, BabyAccent) -> Void
    ) {
        self.babyID = babyID
        self._name = State(initialValue: name)
        self._accent = State(initialValue: accent)
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section {
                    AccentPicker(selection: $accent, theme: theme)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Used on this baby's card and timeline rows. The name is "
                         + "always shown too, so a colour is never the only way to "
                         + "tell them apart.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle("Baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName, accent)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .tint(palette.accent)
    }
}

/// Swatch grid. Every swatch is labelled, and the selected one carries a checkmark
/// as well as a ring — so the current choice is legible without relying on colour.
struct AccentPicker: View {
    @Binding var selection: BabyAccent
    let theme: MoonTheme

    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(BabyAccent.allCases) { option in
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(option.color(for: theme))
                                .frame(width: 40, height: 40)
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.bg)
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(
                                    option == selection ? palette.ink : .clear,
                                    lineWidth: 2)
                                .padding(-4)
                        )
                        Text(option.displayName)
                            .font(.caption2)
                            .foregroundStyle(
                                option == selection ? palette.ink : palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(option == selection ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}
