import SwiftUI
import MoonlogCore

/// The top of Tonight: whose night this is and what time it is now.
///
/// The clock is the largest thing in the app on purpose. A night doula reads the
/// time constantly — every log is "when did that happen relative to now" — and the
/// PWA answered that in a 19-pixel line in a header bar, next to the wordmark,
/// which is the size you use for something nobody needs.
///
/// The family name is here for a second reason. It used to live in the switcher on
/// this screen's toolbar, and that control was justified partly as a standing
/// answer to "whose night am I logging?" The switcher has moved to Settings, so
/// that answer has to keep being given somewhere, or moving it would have traded a
/// two-tap convenience for the exact mis-logging risk it was guarding against.
struct NightHeader: View {
    let familyName: String
    /// The device's zone, not the family's stored one — see `Tonight.timeZone`.
    let timeZone: TimeZone

    @Environment(\.palette) private var palette

    /// Scaled, not fixed. This is the one number on the screen chosen for people
    /// who cannot read small text at 4am, so opting it out of Dynamic Type would
    /// defeat the point of making it big.
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 52

    var body: some View {
        // `.everyMinute`, not a 30-second period: a periodic schedule starts
        // counting from whenever the view first appeared, so the minute rolled over
        // here up to half a minute after it rolled over in the status bar — the app
        // reading 3:11 with the phone reading 3:12 all night. `.everyMinute` fires
        // on the boundary, so the two change together.
        //
        // Its own tick, like the cards. The screen around it deliberately does not
        // re-render on the clock — see the note in `TonightView.body`.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 2) {
            // The family name alone. It used to carry "on since HH:MM" as well,
            // which answered a question nobody asks mid-shift now that a family's
            // hours are set in advance rather than discovered from when the app
            // was opened.
            Text(familyName.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(palette.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(Fmt.clock(now, timeZone: timeZone))
                // Monospaced digits so the minute rolling over does not shift the
                // whole line — at this size a proportional 1 moves it visibly.
                .font(.system(size: clockSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(Fmt.longDate(now, timeZone: timeZone))
                .font(.subheadline)
                .foregroundStyle(palette.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // The one condition under which a whole night is lost on quit, and it
            // was visible only on the Settings tab — a line reading "In memory"
            // that nobody has a reason to go and read. Silently losing a night is
            // the worst thing this app can do, so it says so on the screen the
            // logging actually happens on, all night, in the stop colour.
            if case .inMemory = ModelContainerFactory.mode {
                Label(
                    "Not saving to this phone — tonight will be lost when the app closes.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.stop)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        // One utterance, not four. VoiceOver reading the family name, then the
        // clock, then the date as separate stops is three swipes to learn what a
        // glance gives.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(familyName). \(Fmt.clock(now, timeZone: timeZone)), "
                + Fmt.longDate(now, timeZone: timeZone)
                + storageWarningForVoiceOver)
    }

    /// Folded into the header's one utterance rather than left as a separate stop,
    /// because `children: .combine` would otherwise drop it entirely.
    private var storageWarningForVoiceOver: String {
        if case .inMemory = ModelContainerFactory.mode {
            return ". Warning: not saving to this phone. Tonight will be lost when "
                + "the app closes."
        }
        return ""
    }
}
