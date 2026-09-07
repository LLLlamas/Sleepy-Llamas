import SwiftUI
import MoonlogCore

/// Rename a client family, or remove it entirely.
///
/// Removing a household is the app's **only real delete** — a baby is archived so
/// her name survives in past handoffs, but a whole family is how you undo adding
/// the wrong one, or drop a client whose work is finished and whose records you
/// have no business keeping. It takes everything with it, so it says so plainly and
/// asks once, and the store refuses outright while a shift is running.
struct FamilyDetailSheet: View {
    @State private var name: String
    let babyCount: Int
    let hasOpenShift: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(
        name: String,
        babyCount: Int,
        hasOpenShift: Bool,
        onSave: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self._name = State(initialValue: name)
        self.babyCount = babyCount
        self.hasOpenShift = hasOpenShift
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Named, not counted: "Everything for the Nguyens" is a sentence you can
    /// picture, and this is the one control in the app that cannot be undone.
    private var deleteWarning: String {
        let babies = babyCount == 1 ? "one baby" : "\(babyCount) babies"
        return "Every night, every record and \(babies) go with it. This cannot be undone."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                } footer: {
                    Text("Heads the parents' handoff, and sits above the clock all "
                         + "night so you can check whose night it is.")
                }
                .listRowBackground(palette.raised)

                Section {
                    Button(role: .destructive) {
                        Haptics.tap()
                        confirmingDelete = true
                    } label: {
                        Text("Remove \(trimmedName.isEmpty ? "this family" : trimmedName)")
                            .frame(maxWidth: .infinity)
                    }
                    // Said before the tap, not after the store refuses it.
                    .disabled(hasOpenShift)
                } footer: {
                    Text(hasOpenShift
                         ? "End tonight's shift first. A household cannot be removed "
                           + "while a night is still running."
                         : deleteWarning)
                }
                .listRowBackground(palette.raised)
            }
            .scrollContentBackground(.hidden)
            .moonBackground(palette)
            .navigationTitle("Client family")
            .navigationBarTitleDisplayMode(.inline)
            // An `.alert`, never a `.confirmationDialog`: inside a sheet the latter
            // presents as a popover and drops the cancel action. See `CLAUDE.md`.
            .alert("Remove \(trimmedName)?", isPresented: $confirmingDelete) {
                Button("Remove", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteWarning)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .tint(palette.accent)
    }
}
