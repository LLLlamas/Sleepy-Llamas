import SwiftUI
import MoonlogCore

/// The shift's own hours, which belong to the doula rather than to the clock.
///
/// `startShift` and `endShift` both take the time they are given precisely so this
/// screen can exist. Tapping "End shift" half an hour after actually leaving used
/// to widen the window by half an hour and credit the parents with sleep nobody
/// watched — the totals and the handoff clip to this window.
struct ShiftHoursSheet: View {

    enum Purpose: Identifiable {
        /// Correcting a running shift's start.
        case correct
        /// Ending it, which is also the last chance to fix the start.
        case end

        var id: Self { self }
    }

    let purpose: Purpose
    let window: ShiftWindow
    /// Named rather than counted, so ending while someone is asleep is a decision
    /// rather than a surprise. Their sleep stays in the record either way.
    let asleep: [String]
    /// `nil` for the end means "leave it running".
    let onSave: (Date, Date?) -> Void

    @State private var startedAt: Date
    @State private var endedAt: Date
    /// The confirm button stays hit-testable through the dismiss animation, and the
    /// write is async — the same guard the log sheets need.
    @State private var isSaving = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(
        purpose: Purpose,
        window: ShiftWindow,
        asleep: [String] = [],
        onSave: @escaping (Date, Date?) -> Void
    ) {
        self.purpose = purpose
        self.window = window
        self.asleep = asleep
        self.onSave = onSave
        _startedAt = State(initialValue: window.startedAt)
        // Now is the suggestion, never the record. It is pre-filled because it is
        // right most nights, and editable because the night it is wrong is the
        // night it matters.
        _endedAt = State(initialValue: window.endedAt ?? Date())
    }

    private var isEnding: Bool { purpose == .end }
    private var startsInFuture: Bool { startedAt.isMeaningfullyInFuture }
    private var endsInFuture: Bool { isEnding && endedAt.isMeaningfullyInFuture }
    private var endsBeforeStart: Bool { isEnding && endedAt < startedAt }

    private var canSave: Bool {
        !isSaving && !startsInFuture && !endsInFuture && !endsBeforeStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Started") {
                    DatePicker(
                        "Start", selection: $startedAt,
                        displayedComponents: [.date, .hourAndMinute])
                    if startsInFuture {
                        advisory("That hasn't happened yet", blocking: true)
                    }
                }
                .listRowBackground(palette.raised)

                if isEnding {
                    Section("Ended") {
                        DatePicker(
                            "End", selection: $endedAt,
                            displayedComponents: [.date, .hourAndMinute])
                        if endsInFuture {
                            advisory("That hasn't happened yet", blocking: true)
                        } else if endsBeforeStart {
                            advisory("That's before the shift started", blocking: true)
                        }
                    }
                    .listRowBackground(palette.raised)

                    if !asleep.isEmpty {
                        Section {
                            Text("\(asleep.joined(separator: " and ")) still asleep — "
                                 + "that stays in the record. Logging stops until you "
                                 + "start the next shift.")
                                .font(.footnote)
                                .foregroundStyle(palette.soft)
                        }
                        .listRowBackground(palette.raised)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle(isEnding ? "End shift" : "Shift times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // "End", not "End shift": the title already says which shift,
                    // and the pair read as a stutter side by side.
                    Button(isEnding ? "End" : "Save") {
                        guard canSave else { return }
                        isSaving = true
                        Haptics.commit()
                        onSave(startedAt, isEnding ? endedAt : nil)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .tint(palette.accent)
    }

    /// Icon as well as colour, so the warning survives a colour-blind reader and a
    /// dark nursery. See `docs/design.md`.
    @ViewBuilder
    private func advisory(_ text: String, blocking: Bool) -> some View {
        Label(
            text,
            systemImage: blocking ? "exclamationmark.triangle.fill" : "info.circle"
        )
        .foregroundStyle(blocking ? palette.stop : palette.warn)
        .font(.footnote)
    }
}
