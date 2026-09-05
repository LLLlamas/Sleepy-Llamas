import SwiftUI
import MoonlogCore

/// Shared frame for every log sheet: which baby, when, and the save gate.
///
/// Centralised because the validation is the point. In the web version four of the
/// five sheets had **no** time bounds at all, so a mis-tapped AM/PM wrote a
/// timestamp twelve hours in the future and silently suppressed the overdue-feed
/// warning for the rest of the night.
struct LogSheetChrome<Content: View>: View {
    let title: String
    /// Shown prominently — a mis-scan or a mis-tap on the wrong twin should be
    /// obvious before saving, not discovered in the morning handoff.
    let babyName: String?
    let accent: Color
    @Binding var at: Date
    let shift: ShiftWindow
    let saveEnabled: Bool
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// A minute of slack, so setting "now" by hand is never rejected by a race.
    private var isFuture: Bool { at > Date().addingTimeInterval(60) }

    private var isOutsideShift: Bool {
        guard !isFuture else { return false }
        if at < shift.startedAt { return true }
        if let ended = shift.endedAt, at > ended { return true }
        return false
    }

    private var canSave: Bool { saveEnabled && !isFuture }

    var body: some View {
        NavigationStack {
            Form {
                if let babyName {
                    Section {
                        HStack(spacing: 10) {
                            Circle().fill(accent).frame(width: 10, height: 10)
                            Text(babyName).font(.headline).foregroundStyle(palette.ink)
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
            }
            // `scrollContentBackground` clears the Form's own fill; the rows still
            // default to the system grouped colour, so they need the palette too or
            // the sheet reads as a different app from the cards behind it.
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }.disabled(!canSave)
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


extension View {
    /// Ending a shift is the one irreversible-feeling action in a night, so it names
    /// who is still asleep — that is what the parents are about to be handed.
    func confirmDialogEndShift(
        isPresented: Binding<Bool>,
        asleep: [String],
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog("End shift?", isPresented: isPresented, titleVisibility: .visible) {
            Button("End shift", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            if asleep.isEmpty {
                Text("Logging stops until you start the next one.")
            } else {
                Text("\(asleep.joined(separator: " and ")) still asleep — that stays in "
                     + "the record. Logging stops until you start the next shift.")
            }
        }
    }
}
