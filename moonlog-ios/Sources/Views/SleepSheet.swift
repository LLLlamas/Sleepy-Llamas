import SwiftUI
import MoonlogCore

/// Manual sleep entry, and the correction path when a toggle was mistimed.
struct SleepSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    /// The session already running, if any — the sheet then edits it rather than
    /// opening a second one.
    let openSince: Date?
    let onSave: (SleepEntry) -> Void

    @State private var startAt: Date
    @State private var endAt: Date
    @State private var stillAsleep: Bool

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    init(
        baby: BabyPresentation,
        shift: ShiftWindow,
        openSince: Date?,
        onSave: @escaping (SleepEntry) -> Void
    ) {
        self.baby = baby
        self.shift = shift
        self.openSince = openSince
        self.onSave = onSave
        let now = Date()
        _startAt = State(initialValue: openSince ?? now.addingTimeInterval(-30 * 60))
        _endAt = State(initialValue: now)
        _stillAsleep = State(initialValue: openSince != nil)
    }

    /// End must be strictly after start. The web version added 24 hours instead of
    /// refusing, so nudging "woke" back past "asleep" silently recorded a 23-hour
    /// sleep — and its own error message was unreachable.
    private var endIsBeforeStart: Bool { !stillAsleep && endAt <= startAt }

    private var duration: TimeInterval? {
        stillAsleep ? nil : max(0, endAt.timeIntervalSince(startAt))
    }

    var body: some View {
        LogSheetChrome(
            title: openSince == nil ? "Sleep" : "Edit sleep",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $startAt,
            shift: shift,
            saveEnabled: !endIsBeforeStart,
            onSave: {
                onSave(SleepEntry(startAt: startAt, endAt: stillAsleep ? nil : endAt))
            }
        ) {
            Section("Woke") {
                Toggle("Still asleep", isOn: $stillAsleep.animation())
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
                } else if let duration {
                    HStack {
                        Text("Slept")
                        Spacer()
                        Text(Fmt.duration(duration))
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
