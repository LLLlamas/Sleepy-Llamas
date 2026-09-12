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
enum EntrySaveError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The data store is unavailable. Your entry has not been saved." }
}

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
    var saveDisabledReason: String? = nil
    let onSave: () async throws -> Void
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
    @State private var saveError: String?
    @State private var numericValidation = NumericValidation()
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
            // A `Label` with a chevron, not bare text: this is the app's named
            // wrong-twin remedy and it rendered as a caption — no border, no
            // indicator, nothing saying it could be tapped at all.
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                Text("Wrong baby?")
                Image(systemName: "chevron.down")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.accent)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(palette.chip, in: Capsule())
        }
    }

    private var isOutsideShift: Bool {
        guard !isFuture else { return false }
        if at < shift.startedAt { return true }
        if let ended = shift.endedAt, at > ended { return true }
        return false
    }

    private var canSave: Bool { saveEnabled && !isFuture && !isSaving && numericValidation.firstError == nil }

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
                    // Was a `confirmationDialog` and had the popover bug the whole
                    // time: inside a sheet it presented as a popover, and a popover
                    // drops the cancel action — so the app's one "are you sure?"
                    // offered a red Delete and no way out but tapping beside it.
                    // Shipped that way; found while adding the others.
                    .alert(
                        babyName.map { "Delete this entry for \($0)?" } ?? "Delete this entry?",
                        isPresented: $confirmingDelete
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
            .disabled(isSaving)
            // On the Form, not on the `Menu` that sets it — a menu builds its items
            // on its own schedule and closes as one is chosen, and this project has
            // already paid once for a presentation modifier inside a lazy container.
            // An `alert` rather than a `confirmationDialog` for the reason spelled
            // out in `ShiftHoursSheet`: inside a sheet the dialog presents as a
            // popover, and a popover has no cancel button.
            .alert(
                confirmingMove.map { ConfirmableAction.moveRecord.question($0.name) } ?? "",
                isPresented: Binding(
                    get: { confirmingMove != nil },
                    set: { if !$0 { confirmingMove = nil } }),
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
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .tint(palette.accent)
        .environment(numericValidation)
        .interactiveDismissDisabled(isSaving)
    }

    /// Save, at the bottom, full width.
    ///
    /// It was in the navigation bar's trailing corner, which on a 6.3" phone is
    /// about 800pt from a thumb holding the phone — for the action that ends every
    /// log of the night, performed one-handed with a baby in the other arm. The
    /// *destructive* Delete in the same sheet was already a comfortable full-width
    /// row at the bottom, so the easy control was the dangerous one.
    ///
    /// A `safeAreaInset` rather than a last `Section`: it stays put while the form
    /// scrolls, rises with the keyboard, and cannot end up below the fold in a
    /// sheet whose content is longer than the screen. Cancel stays in the bar,
    /// where a control you rarely want belongs.
    private var saveBar: some View {
        VStack(spacing: 8) {
            if let reason = saveError ?? numericValidation.firstError ?? (!saveEnabled ? saveDisabledReason : nil) {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(palette.stop)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("saveFeedback")
            }
            Button {
                guard canSave else { return }
                isSaving = true
                saveError = nil
                Haptics.commit()
                Task {
                    do {
                        try await onSave()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                        Haptics.warn()
                    }
                    isSaving = false
                }
            } label: {
                HStack {
                    if isSaving { ProgressView() }
                    Text(isSaving ? "Saving…" : (saveError == nil ? "Save" : "Retry save"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: MoonLayout.tapTarget)
                // The whole bar, not just the word on it. `.plain` hit-tests the
                // label's *contents*, and the contents are an `HStack` holding one
                // `Text` — so the width the `.infinity` frame bought was layout and
                // nothing else. Measured: **38×20pt inside a 370×56pt bar**, on the
                // one control every log of the night ends with.
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: MoonLayout.controlCorner, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSave ? palette.accentInk : palette.faint)
            .background(
                canSave ? palette.accent : palette.chip,
                in: RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous))
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

/// A sheet keeps invalid text visible and blocks Save instead of silently saving
/// the last valid number from a value-backed TextField.
@Observable
final class NumericValidation {
    var errors: [UUID: String] = [:]
    var firstError: String? { errors.sorted { $0.key.uuidString < $1.key.uuidString }.first?.value }
}

struct ValidatedNumberField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var fractionDigits = 2
    var allowsEmpty = true

    @Environment(NumericValidation.self) private var validation
    @Environment(\.locale) private var locale
    @State private var text = ""
    @State private var fieldID = UUID()
    @State private var initialText: String?

    private var parsed: Double? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return allowsEmpty ? 0 : nil }
        let separator = locale.decimalSeparator ?? "."
        let parts = raw.components(separatedBy: separator)
        guard parts.count <= 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              raw.contains(where: \.isNumber),
              fractionDigits > 0 || parts.count == 1 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        guard let number = formatter.number(from: raw)?.doubleValue,
              number.isFinite, range.contains(number) else { return nil }
        return number
    }

    private func display(_ number: Double) -> String {
        if number == 0 && allowsEmpty { return "" }
        return number.formatted(.number.locale(locale).grouping(.never)
            .precision(.fractionLength(0...fractionDigits)))
    }

    private func validate() {
        if let parsed {
            validation.errors[fieldID] = nil
            value = parsed
        } else {
            let lower = range.lowerBound.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
            let upper = range.upperBound.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
            validation.errors[fieldID] = "Enter \(label.lowercased()) between \(lower) and \(upper)."
        }
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(allowsEmpty ? "Optional" : label, text: $text)
                .keyboardType(fractionDigits == 0 ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
                .accessibilityLabel(label)
                .accessibilityIdentifier("number.\(label)")
                .onChange(of: text) { _, newText in
                    if initialText == newText { initialText = nil; return }
                    initialText = nil
                    validate()
                }
                .onChange(of: value) { _, newValue in
                    // A stepper can change the same value. Do not rewrite the text
                    // after each keystroke when this field itself caused the change.
                    if parsed != newValue { text = display(newValue) }
                }
                .onAppear {
                    let displayed = display(value)
                    if text != displayed { initialText = displayed; text = displayed }
                }
                .onDisappear { validation.errors[fieldID] = nil }
        }
    }
}

/// Direct entry avoids repeated taps; the familiar five-minute adjustment remains.
struct MinutesField: View {
    let label: String
    @Binding var minutes: Int
    var step: Int = 1

    var body: some View {
        ValidatedNumberField(
            label: "\(label) minutes",
            value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }),
            range: 0...240, fractionDigits: 0)
        Stepper("Adjust \(label.lowercased()) by \(step) min", value: $minutes, in: 0...240, step: step)
    }
}

/// Weight stays canonical grams; the read-back confirms the household's unit.
struct WeightField: View {
    let unit: VolumeUnit
    @Binding var grams: Double
    @Environment(\.palette) private var palette
    private var gramsPerUnit: Double { unit == .oz ? 453.59237 : 1 }
    private var label: String { unit == .oz ? "Pounds" : "Grams" }
    /// A stated bound, not `greatestFiniteMagnitude`: the out-of-range message
    /// reads the bound back, and "between 0 and 39614081257132168000000000000000000000"
    /// is not a sentence. 30kg covers any baby a night doula weighs.
    private var maxGrams: Double { 30_000 }

    var body: some View {
        ValidatedNumberField(
            label: label,
            value: Binding(get: { grams / gramsPerUnit }, set: { grams = $0 * gramsPerUnit }),
            range: 0...(maxGrams / gramsPerUnit))
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
    private var mlPerUnit: Double { unit == .oz ? 29.5735 : 1 }
    private var stepMl: Double { unit == .oz ? 29.5735 / 2 : 10 }

    var body: some View {
        ValidatedNumberField(
            label: unit == .oz ? "Amount (oz)" : "Amount (ml)",
            value: Binding(get: { ml / mlPerUnit }, set: { ml = $0 * mlPerUnit }),
            range: 0...(1000 / mlPerUnit), fractionDigits: unit == .oz ? 2 : 0)
        Stepper(
            unit == .oz ? "Adjust by ½ oz" : "Adjust by 10 ml",
            value: $ml, in: 0...1000, step: stepMl)
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
