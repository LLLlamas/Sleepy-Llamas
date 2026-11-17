import SwiftUI
import MoonlogCore

struct ReminderField: View {
    let label: String
    @Binding var minutes: Int

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    /// True once the system has said yes in this sheet, so stepping 90 → 120 → 150
    /// does not re-ask on every tap.
    @State private var authorized = false
    /// Set when the request came back no. Blocking, and it deliberately outlives the
    /// reset to Off below — see `requestIfNeeded`.
    @State private var denied = false
    @State private var isRequesting = false

    private var presets: [Int] { FeedReminder.presetMinutes }

    private var isOn: Bool { minutes > 0 }

    /// 0 is Off; 1...`presets.count` select a preset.
    private var index: Binding<Int> {
        Binding(
            get: {
                guard minutes > 0 else { return 0 }
                // A stored value that is not a preset — written by an older build, or
                // by a future one with a longer list — reads back honestly (the label
                // renders `minutes`, not the preset) and steps to its nearest
                // neighbour, rather than being snapped the moment the sheet opens.
                let nearest = presets.enumerated().min {
                    abs($0.element - minutes) < abs($1.element - minutes)
                }
                return (nearest?.offset ?? 0) + 1
            },
            set: { minutes = $0 <= 0 ? 0 : presets[min($0, presets.count) - 1] })
    }

    var body: some View {
        Stepper(value: index, in: 0...presets.count) {
            HStack {
                Text(label)
                Spacer()
                // The bell as well as the tint — colour is never the only signal, and
                // this row's whole state is "an alarm is set or it is not".
                //
                // `palette.accent` for that pending state, never `palette.warn`: warn
                // is the overdue-feed colour the status chip already flips to, and two
                // chips in one colour meaning opposite things is the contradiction
                // this palette exists to prevent.
                if isOn {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
                // "Off", not "—". A dash is what an unfilled field looks like; an
                // alarm is either set or it is not, and the honest word for not is
                // Off. And `Fmt.duration`, so 150 reads "2h 30m" — the doula thinks
                // in hours between feeds, not in minutes.
                Text(isOn ? Fmt.duration(TimeInterval(minutes) * 60) : "Off")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(isOn ? palette.accent : palette.faint)
            }
        }
        .accessibilityIdentifier("feed.reminder")
        .onChange(of: minutes) { _, new in requestIfNeeded(for: new) }

        if denied {
            // Blocking idiom, matching the future-timestamp advisory above: triangle
            // and `palette.stop`, because nothing set here can fire until this is
            // fixed and the fix is not on this screen.
            Label("Notifications are off for Moonlog", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.stop)
                .font(.footnote)
            Button {
                Haptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: "arrow.up.forward.app")
                    .font(.footnote)
            }
        }
    }

    /// Asked here and nowhere else in the app.
    ///
    /// The system prompt can be shown **once, ever**, so it is spent on the gesture
    /// that means "I want an alarm" — never at launch, never in `.onAppear`, where the
    /// answer would be a guess about a feature she has not reached yet.
    @MainActor
    private func requestIfNeeded(for newValue: Int) {
        // Reaching Off — by hand, or by the reset below — promises nothing, so there
        // is nothing to ask for. `denied` is *not* cleared here: it is still true, and
        // clearing it would also wipe the advisory a tenth of a second after the reset
        // set it, leaving the value back at Off with no reason given.
        guard newValue > 0 else { return }
        guard !authorized, !isRequesting else { return }
        isRequesting = true
        Task {
            // `requestAuthorization` is the whole check, not merely the ask: already
            // authorized returns true without prompting, already denied returns false
            // without prompting. Reading the status first would mean naming
            // `UNAuthorizationStatus` in this file, and `FeedReminders` is meant to be
            // the only file in the project that imports `UserNotifications`.
            let granted = await FeedReminders.requestAuthorization()
            isRequesting = false
            if granted {
                authorized = true
                denied = false
            } else {
                // Reset, not merely warn. A sheet that saves a reminder it knows
                // cannot fire is a silent drop — she would put the phone down
                // believing a baby will be woken for.
                Haptics.warn()
                denied = true
                minutes = 0
            }
        }
    }
}

