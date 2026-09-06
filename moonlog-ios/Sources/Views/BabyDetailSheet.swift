import SwiftUI
import MoonlogCore

/// Name, birth date and accent colour for one baby.
struct BabyDetailSheet: View {
    @State private var name: String
    @State private var accent: BabyAccent
    @State private var birthAt: Date
    let onSave: (String, BabyAccent, Date) -> Void
    /// Nil on Tonight. Removing a baby is a setup act like adding one, so it is
    /// offered in Settings and not next to the buttons pressed forty times a
    /// night. `CareStore.archiveBaby` existed with no call site at all until this
    /// — the same unreachable-remedy shape `reassignEvent` had.
    var onArchive: (() -> Void)?

    @State private var confirmingArchive = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    init(
        name: String,
        accent: BabyAccent,
        birthAt: Date,
        onSave: @escaping (String, BabyAccent, Date) -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self._name = State(initialValue: name)
        self._accent = State(initialValue: accent)
        self._birthAt = State(initialValue: birthAt)
        self.onSave = onSave
        self.onArchive = onArchive
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    // Editable, not fixed at creation: it is typed once at 2am and
                    // sets the day of life on every handoff from then on.
                    DatePicker("Born", selection: $birthAt, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Name and birth")
                } footer: {
                    Text("The birth date sets the day of life on the handoff and "
                         + "the parents' page, for this night and every past one.")
                }
                .listRowBackground(palette.raised)

                Section {
                    AccentPicker(selection: $accent, theme: theme)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Used on this baby's card and timeline rows. The name is "
                         + "always shown too, so a colour is never the only way to "
                         + "tell them apart.")
                }
                .listRowBackground(palette.raised)

                if onArchive != nil {
                    Section {
                        Button(role: .destructive) {
                            Haptics.tap()
                            confirmingArchive = true
                        } label: {
                            Text("Remove \(trimmedName.isEmpty ? "this baby" : trimmedName)")
                                .frame(maxWidth: .infinity)
                        }
                    } footer: {
                        Text("She comes off Tonight and off future handoffs. Every "
                             + "night already logged keeps her name and her records.")
                    }
                    .listRowBackground(palette.raised)
                }
            }
            .scrollContentBackground(.hidden)
            .moonBackground(palette)
            .navigationTitle("Baby")
            .navigationBarTitleDisplayMode(.inline)
            // An `.alert`, never a `.confirmationDialog`: inside a sheet the latter
            // presents as a popover and drops the cancel action. See `CLAUDE.md`.
            .alert(
                "Remove \(trimmedName)?", isPresented: $confirmingArchive
            ) {
                Button("Remove", role: .destructive) {
                    onArchive?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Past nights keep her. There is no undo for this.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName, accent, birthAt)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .tint(palette.accent)
    }
}

/// Labelled swatches; the selection carries a checkmark as well as a ring, so it
/// is never communicated by colour alone.
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
