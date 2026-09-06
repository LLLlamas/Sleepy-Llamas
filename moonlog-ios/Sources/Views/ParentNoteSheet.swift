import SwiftUI

/// The sentences the doula writes to the parents, which sit at the top of the
/// keepsake page above everything the app recorded automatically.
///
/// Editable for as long as the shift exists, and deliberately not required: a night
/// with nothing to add should not manufacture something. When it is empty the page
/// simply has no note section.
struct ParentNoteSheet: View {
    let babyNames: String
    let existing: String
    let onSave: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(babyNames: String, existing: String, onSave: @escaping (String) -> Void) {
        self.babyNames = babyNames
        self.existing = existing
        self.onSave = onSave
        _text = State(initialValue: existing)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text(babyNames.isEmpty ? "Note" : "For \(babyNames)'s parents")
                } footer: {
                    Text("Goes at the top of the page you send them. Leave it empty "
                         + "and the page simply has no note.")
                }
                .listRowBackground(palette.raised)
            }
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle("Note to parents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.commit()
                        onSave(trimmed)
                        dismiss()
                    }
                    // Enabled even when empty — clearing a note is an edit too.
                    .disabled(trimmed == existing.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            // Straight into typing: this sheet exists for one field.
            .task { focused = true }
        }
        .tint(palette.accent)
    }
}
