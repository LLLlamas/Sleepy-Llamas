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
    /// The hour this shift was booked until, set when it was started. Only a
    /// suggestion for the field below — what gets written is whatever is confirmed
    /// here. See `Shift.plannedEndAt`.
    let plannedEnd: Date?
    /// `nil` for the end means "leave it running".
    let onSave: (Date, Date?) -> Void

    @State private var startedAt: Date
    @State private var endedAt: Date
    /// The confirm button stays hit-testable through the dismiss animation, and the
    /// write is async — the same guard the log sheets need.
    @State private var isSaving = false
    /// The end-shift "are you sure", raised here rather than by `TonightView`.
    /// Ending is the only action in the app with no Undo, and the confirmation has
    /// to live on the same screen as the button that commits it — set from here and
    /// presented back on Tonight, it would be a dialog handed across a sheet that is
    /// dismissing, and an end-shift that silently does nothing.
    @State private var confirmingEnd = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.confirmations) private var confirmations

    init(
        purpose: Purpose,
        window: ShiftWindow,
        asleep: [String] = [],
        plannedEnd: Date? = nil,
        onSave: @escaping (Date, Date?) -> Void
    ) {
        self.purpose = purpose
        self.window = window
        self.asleep = asleep
        self.plannedEnd = plannedEnd
        self.onSave = onSave
        _startedAt = State(initialValue: window.startedAt)
        // A suggestion, never the record. It is pre-filled because it is right most
        // nights, and editable because the night it is wrong is the night it matters.
        _endedAt = State(
            initialValue: window.endedAt ?? Self.suggestedEnd(planned: plannedEnd, now: Date()))
    }

    /// The booked hour when it has arrived, otherwise now.
    ///
    /// Leaving on time is the common night, and "6:00" is what the doula means where
    /// the clock says 6:03 — the totals and the parents' document both clip to this
    /// window, so those three minutes are sleep nobody watched. A booked end still in
    /// the future means she is leaving early, and then the clock is the honest answer;
    /// offering the plan there would also be a time the sheet refuses to save.
    static func suggestedEnd(planned: Date?, now: Date) -> Date {
        guard let planned, planned <= now else { return now }
        return planned
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
                        Advisory("That hasn't happened yet")
                    }
                }
                .listRowBackground(palette.raised)

                if isEnding {
                    Section("Ended") {
                        DatePicker(
                            "End", selection: $endedAt,
                            displayedComponents: [.date, .hourAndMinute])
                        if endsInFuture {
                            Advisory("That hasn't happened yet")
                        } else if endsBeforeStart {
                            Advisory("That's before the shift started")
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
            .moonBackground(palette)
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
                        // Only the ending asks. This same button also just corrects
                        // the start of a running shift, which is undoable and not
                        // what anyone means by "are you sure".
                        guard isEnding, confirmsEnd else { return commit() }
                        Haptics.warn()
                        confirmingEnd = true
                    }
                    .disabled(!canSave)
                }
            }
            // An `alert`, not a `confirmationDialog`. Attached to content inside a
            // sheet, a confirmation dialog presented as a *popover* — and in that
            // presentation iOS drops the cancel action, so the only way out of "this
            // cannot be undone" was tapping outside it. It also anchored its tail to
            // the sheet's grabber and floated over Tonight. An alert is centred,
            // modal, and always renders both buttons. Verified by screenshot.
            .alert(
                ConfirmableAction.endShift.question(""),
                isPresented: $confirmingEnd
            ) {
                Button(ConfirmableAction.endShift.verb, role: .destructive, action: commit)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(endWarning)
            }
        }
        .tint(palette.accent)
    }

    private var confirmsEnd: Bool {
        confirmations?.confirms(.endShift) ?? ConfirmableAction.endShift.confirmsByDefault
    }

    /// Names who is still asleep, because that is the fact most likely to change the
    /// answer — the totals clip to the window, so ending now stops counting them.
    private var endWarning: String {
        // Says where the handoff goes as well as what is lost. Ending the shift
        // is the moment the parents' document is wanted, and the alert used to
        // describe only the irreversible half.
        let base = "The shift closes for good. This cannot be undone. "
            + "The night stays on Summary, with Copy and Share."
        guard !asleep.isEmpty else { return base }
        return "\(asleep.joined(separator: " and ")) "
            + (asleep.count == 1 ? "is" : "are") + " still asleep. " + base
    }

    private func commit() {
        isSaving = true
        Haptics.commit()
        onSave(startedAt, isEnding ? endedAt : nil)
        dismiss()
    }
}
