import SwiftUI
import MoonlogCore

/// Two routes, both real. `.correct` edits an existing session from the sleep row
/// in tonight's timeline; `.earlier` records a sleep that was missed at the time,
/// from the shift menu.
///
/// The second personality was deleted once already, because nothing reached it —
/// the status tile toggles rather than opening this. It is back only because the
/// menu entry and its reachability test landed with it.
struct SleepSheet: View {
    enum Purpose {
        /// Correcting a session that exists. Its wake time may still be open.
        case correct
        /// A finished sleep nobody was free to log. Never open-ended: the baby is
        /// awake now, or asleep in a *later* session this one must not touch.
        case earlier
    }

    let baby: BabyPresentation
    let shift: ShiftWindow
    let purpose: Purpose
    let onSave: (SleepEntry) async throws -> Void
    var onDelete: (() -> Void)?

    @State private var startAt: Date
    @State private var endAt: Date
    @State private var stillAsleep: Bool

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    init(
        baby: BabyPresentation,
        shift: ShiftWindow,
        editing: SleepEntry,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (SleepEntry) async throws -> Void
    ) {
        self.baby = baby
        self.shift = shift
        self.purpose = .correct
        self.onDelete = onDelete
        self.onSave = onSave
        _startAt = State(initialValue: editing.startAt)
        // A running session has no end yet; the picker still needs a value, and now
        // is the only defensible one to show behind a disabled control.
        _endAt = State(initialValue: editing.endAt ?? Date())
        _stillAsleep = State(initialValue: editing.endAt == nil)
    }

    /// Manual entry for a sleep that was missed. Both ends are supplied by the
    /// caller, because only Tonight knows whether a later session is already
    /// running and where this one therefore has to finish.
    init(
        baby: BabyPresentation,
        shift: ShiftWindow,
        earlier startAt: Date,
        until endAt: Date,
        onSave: @escaping (SleepEntry) async throws -> Void
    ) {
        self.baby = baby
        self.shift = shift
        self.purpose = .earlier
        self.onDelete = nil
        self.onSave = onSave
        _startAt = State(initialValue: startAt)
        _endAt = State(initialValue: endAt)
        _stillAsleep = State(initialValue: false)
    }

    /// End must be strictly after start. The web version added 24 hours instead of
    /// refusing, so nudging "woke" back past "asleep" silently recorded a 23-hour
    /// sleep — and its own error message was unreachable.
    private var endIsBeforeStart: Bool { !stillAsleep && endAt <= startAt }

    /// `LogSheetChrome` bounds only the start. Nothing bounded the wake time, so a
    /// mis-nudged date wheel could save a wake 24 hours ahead — and because totals
    /// clip to the shift window, that absorbed the entire rest of the shift as sleep.
    private var endIsInFuture: Bool { !stillAsleep && endAt.isMeaningfullyInFuture }

    private var duration: TimeInterval? {
        stillAsleep ? nil : max(0, endAt.timeIntervalSince(startAt))
    }

    var body: some View {
        LogSheetChrome(
            title: purpose == .correct ? "Edit sleep" : "Earlier sleep",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $startAt,
            shift: shift,
            saveEnabled: !endIsBeforeStart && !endIsInFuture,
            onSave: {
                try await onSave(SleepEntry(startAt: startAt, endAt: stillAsleep ? nil : endAt))
            },
            onDelete: onDelete
        ) {
            Section("Woke") {
                // Not offered for an earlier sleep: an open-ended one would be the
                // session the baby is in now, which this route must never replace.
                if purpose == .correct {
                    Toggle("Still asleep", isOn: $stillAsleep.animation())
                }
                if !stillAsleep {
                    DatePicker("Woke at", selection: $endAt,
                               displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section {
                if endIsBeforeStart {
                    Label("Wake time must be after the sleep time",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.stop)
                        .font(.footnote)
                } else if endIsInFuture {
                    Label("That wake time is in the future",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.stop)
                        .font(.footnote)
                } else if let duration {
                    HStack {
                        Text("Slept")
                        Spacer()
                        Text(Fmt.spanned(duration))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(palette.sleep)
                    }
                } else {
                    Text("Still asleep — the shift's total counts only the time you were here.")
                        .font(.footnote)
                        .foregroundStyle(palette.faint)
                }
            }
        }
    }
}

struct SleepEntry {
    let startAt: Date
    let endAt: Date?
}
