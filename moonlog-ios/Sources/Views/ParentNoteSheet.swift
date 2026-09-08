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
    let onSave: (String) async throws -> Void

    @State private var text: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmingDiscard = false
    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(babyNames: String, existing: String, onSave: @escaping (String) async throws -> Void) {
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
                        .disabled(isSaving)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text(babyNames.isEmpty ? "Note" : "For \(babyNames)'s parents")
                } footer: {
                    Text("Goes at the top of the page you send them. Leave it empty "
                         + "and the page simply has no note.")
                }
                .listRowBackground(palette.raised)
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(palette.stop)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .moonBackground(palette)
            .navigationTitle("Note to parents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trimmed != existing.trimmingCharacters(in: .whitespacesAndNewlines) {
                            confirmingDiscard = true
                        } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(isSaving ? "Saving…" : (saveError == nil ? "Save" : "Retry save")) {
                    guard !isSaving else { return }
                    isSaving = true
                    saveError = nil
                    Haptics.commit()
                    Task {
                        do {
                            try await onSave(trimmed)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                            Haptics.warn()
                        }
                        isSaving = false
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: MoonLayout.tapTarget)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || trimmed == existing.trimmingCharacters(in: .whitespacesAndNewlines))
                .padding()
                .background(.bar)
            }
            .alert("Discard this note?", isPresented: $confirmingDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Your changes have not been saved.")
            }
            // Straight into typing: this sheet exists for one field.
            .task { focused = true }
        }
        .interactiveDismissDisabled(isSaving || trimmed != existing.trimmingCharacters(in: .whitespacesAndNewlines))
        .tint(palette.accent)
    }
}
