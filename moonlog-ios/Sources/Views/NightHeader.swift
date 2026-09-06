import SwiftUI
import MoonlogCore

/// The top of Tonight: whose night this is, what time it is now, and how long the
/// doula has been on.
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
    let startedAt: Date
    let timeZone: TimeZone

    @Environment(\.palette) private var palette

    /// Scaled, not fixed. This is the one number on the screen chosen for people
    /// who cannot read small text at 4am, so opting it out of Dynamic Type would
    /// defeat the point of making it big.
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 52

    var body: some View {
        // Its own tick, like the cards. The screen around it deliberately does not
        // re-render on the clock — see the note in `TonightView.body`.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 2) {
            Text("\(familyName) · on since \(Fmt.clock(startedAt, timeZone: timeZone))"
                    .uppercased())
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        // One utterance, not four. VoiceOver reading the family name, then the
        // clock, then the date as separate stops is three swipes to learn what a
        // glance gives.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(familyName). \(Fmt.clock(now, timeZone: timeZone)), "
                + "\(Fmt.longDate(now, timeZone: timeZone)). On since "
                + Fmt.clock(startedAt, timeZone: timeZone))
    }
}
