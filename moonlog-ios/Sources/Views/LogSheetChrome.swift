import SwiftUI
import MoonlogCore

/// Shared frame for every log sheet: which baby, when, and the save gate.
///
/// Centralised because the validation is the point. In the web version four of the
/// five sheets had **no** time bounds at all, so a mis-tapped AM/PM wrote a
/// timestamp twelve hours in the future and silently suppressed the overdue-feed
/// warning for the rest of the night.
/// A baby this record could be moved to. Deliberately not `BabyPresentation`:
/// the chrome needs a name, and taking the whole thing would tie every sheet to
/// Tonight's derived state.
struct ReassignTarget: Identifiable {
    let id: UUID
    let name: String
}

/// Moving a record to the twin it should have been logged against.
///
/// Before this, the only remedy for a wrong-twin tap was delete-and-re-log, which
/// discarded `createdAt` and the source fields that make a mis-scan traceable.
/// Carried as one value so each sheet forwards a single argument.
struct Reassignment {
    let targets: [ReassignTarget]
    let move: (UUID) -> Void
}

struct LogSheetChrome<Content: View>: View {
    let title: String
    /// Shown prominently — a mis-scan or a mis-tap on the wrong twin should be
    /// obvious before saving, not discovered in the morning handoff.
    let babyName: String?
    let accent: Color
    @Binding var at: Date
    let shift: ShiftWindow
    /// The wrong-twin remedy. Non-nil only when editing an existing record in a
    /// family with somewhere to move it to.
    var reassignment: Reassignment?
    let saveEnabled: Bool
    let onSave: () -> Void
    /// Non-nil puts a Delete row at the bottom, behind a confirmation. Only set
    /// when editing an existing record.
    var onDelete: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.confirmations) private var confirmations

    /// The Save button stays hit-testable during the dismiss animation, and the
    /// write is async, so without this a second tap writes a second record.
    @State private var isSaving = false
    @State private var confirmingDelete = false
    /// The target a "Wrong baby?" choice is waiting on. Raised here rather than by
    /// `TonightView`, for the same reason the delete is: choosing dismisses this
    /// sheet, so a dialog set from here and presented back on Tonight would be
    /// handed across a view that is going away.
    @State private var confirmingMove: ReassignTarget?

    private var isFuture: Bool { at.isMeaningfullyInFuture }

    private func confirms(_ action: ConfirmableAction) -> Bool {
        confirmations?.confirms(action) ?? action.confirmsByDefault
    }

    private var confirmsDelete: Bool { confirms(.deleteRecord) }

    /// Dismisses on choosing: the record now belongs to another baby, so the name
    /// at the top of this sheet — the whole point of the chip — would be a lie.
    @ViewBuilder
    private func reassignMenu(_ reassignment: Reassignment) -> some View {
        Menu {
            ForEach(reassignment.targets) { target in
                Button {
                    guard confirms(.moveRecord) else {
                        Haptics.commit()
                        reassignment.move(target.id)
                        dismiss()
                        return
                    }
                    Haptics.warn()
                    confirmingMove = target
                } label: {
                    Label("Move to \(target.name)", systemImage: "arrow.uturn.right")
                }
            }
        } label: {
            Text("Wrong baby?")
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.accent)
        }
    }

    private var isOutsideShift: Bool {
        guard !isFuture else { return false }
        if at < shift.startedAt { return true }
        if let ended = shift.endedAt, at > ended { return true }
        return false
    }

    private var canSave: Bool { saveEnabled && !isFuture && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                if let babyName {
                    Section {
                        HStack(spacing: 10) {
                            Circle().fill(accent).frame(width: 10, height: 10)
                            Text(babyName).font(.headline).foregroundStyle(palette.ink)
                            // accent is passed in already resolved, so BabyChip does not fit here
                            if let reassignment, !reassignment.targets.isEmpty {
                                Spacer()
                                reassignMenu(reassignment)
                            }
                        }
                    }
                    .listRowBackground(palette.raised)
                }

                Section("When") {
                    DatePicker("Time", selection: $at, displayedComponents: [.date, .hourAndMinute])
                    if isFuture {
                        // Blocking: a future timestamp corrupts every "time since"
                        // reading that depends on it.
                        Label("That's in the future", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.stop)
                            .font(.footnote)
                    } else if isOutsideShift {
                        // Advisory only — back-dating into a previous shift is
                        // occasionally legitimate, and totals clip it anyway.
                        Label("Outside this shift", systemImage: "info.circle")
                            .foregroundStyle(palette.warn)
                            .font(.footnote)
                    }
                }
                .listRowBackground(palette.raised)

                // Applied to the caller's sections, not to the Form — on the Form
                // it does not reach the rows, which then keep the system grouped
                // grey and read as a different app from the cards behind.
                content()
                    .listRowBackground(palette.raised)

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            // The one delete confirmation in the app, and it is
                            // inherited by all five log sheets because they all wrap
                            // this chrome. Off, the delete lands on the first tap and
                            // the banner's Undo is the safety net instead.
                            guard confirmsDelete else {
                                Haptics.commit()
                                onDelete()
                                dismiss()
                                return
                            }
                            Haptics.warn()
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(palette.raised)
                    .confirmationDialog(
                        babyName.map { "Delete this entry for \($0)?" } ?? "Delete this entry?",
                        isPresented: $confirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            Haptics.commit()
                            onDelete()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("It disappears from the timeline and from the night's totals.")
                    }
                }
            }
            // On the Form, not on the `Menu` that sets it — a menu builds its items
            // on its own schedule and closes as one is chosen, and this project has
            // already paid once for a presentation modifier inside a lazy container.
            .confirmationDialog(
                confirmingMove.map { ConfirmableAction.moveRecord.question($0.name) } ?? "",
                isPresented: Binding(
                    get: { confirmingMove != nil },
                    set: { if !$0 { confirmingMove = nil } }),
                titleVisibility: .visible,
                presenting: confirmingMove
            ) { target in
                Button(ConfirmableAction.moveRecord.verb) {
                    confirmingMove = nil
                    reassignment?.move(target.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { confirmingMove = nil }
            } message: { target in
                Text("It leaves \(babyName ?? "this baby")'s night and joins "
                     + "\(target.name)'s. Undoable for six seconds.")
            }
            // `scrollContentBackground` clears the Form's own fill; the rows still
            // default to the system grouped colour, so they need the palette too or
            // the sheet reads as a different app from the cards behind it.
            .scrollContentBackground(.hidden)
            .moonBackground(palette)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        Haptics.commit()
                        onSave()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .tint(palette.accent)
    }
}

/// Minutes stepper with a readable value. Used for feed durations, where a wheel
/// would be precision nobody has at 3am.
struct MinutesField: View {
    let label: String
    @Binding var minutes: Int
    var step: Int = 1

    @Environment(\.palette) private var palette

    var body: some View {
        Stepper(value: $minutes, in: 0...240, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text(minutes == 0 ? "—" : "\(minutes)m")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(minutes == 0 ? palette.faint : palette.ink)
            }
        }
    }
}

/// Weight in the family's unit. Storage stays canonical grams.
///
/// Typed rather than stepped: a nursery scale reads to the gram, and stepping from
/// zero to a 3.5kg baby would be hundreds of taps. The formatted read-back is what
/// confirms the number landed as intended — 7.25 entered, "7 lb 4.0 oz" shown.
struct WeightField: View {
    let unit: VolumeUnit
    @Binding var grams: Double

    @Environment(\.palette) private var palette

    private var gramsPerUnit: Double { unit == .oz ? 453.59237 : 1 }
    private var label: String { unit == .oz ? "Pounds" : "Grams" }

    private var typed: Binding<Double> {
        Binding(
            get: { grams / gramsPerUnit },
            set: { grams = max(0, $0) * gramsPerUnit })
    }

    var body: some View {
        HStack {
            // Labelled beside the field, not through the placeholder: a placeholder
            // disappears the moment there is a value, and "0" alone does not say
            // whether it means grams or pounds.
            Text(label)
            Spacer()
            TextField(label, value: typed, format: .number.precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 120)
        }
        HStack {
            Text("Reads as")
            Spacer()
            Text(grams == 0 ? "—" : Fmt.weight(grams: grams, unit: unit))
                .font(.body.monospacedDigit())
                .foregroundStyle(grams == 0 ? palette.faint : palette.ink)
        }
    }
}

/// Amount in the family's unit. Storage stays canonical millilitres.
struct AmountField: View {
    let unit: VolumeUnit
    @Binding var ml: Double

    @Environment(\.palette) private var palette

    /// Half an ounce, or 10ml — the granularity a bottle is actually read at.
    private var stepMl: Double { unit == .oz ? 14.7868 : 10 }

    var body: some View {
        Stepper(
            value: Binding(
                get: { ml },
                set: { ml = max(0, $0) }),
            in: 0...1000,
            step: stepMl
        ) {
            HStack {
                Text("Amount")
                Spacer()
                Text(ml == 0 ? "—" : Fmt.amount(ml: ml, unit: unit))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(ml == 0 ? palette.faint : palette.ink)
            }
        }
    }
}


/// Shared empty state. Used wherever a screen has nothing to show yet — which is a
/// normal condition here, not an error: between visits there is no open shift.
struct EmptyStatePlaceholder: View {
    let emoji: String
    let title: String
    let message: String

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 40))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .moonBackground(palette)
    }
}
