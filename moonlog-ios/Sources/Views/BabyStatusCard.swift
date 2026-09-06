import SwiftUI
import MoonlogCore

/// Already-computed state for one card. Keeps the view free of domain logic and
/// previewable without a store.
struct BabyPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let accent: BabyAccent
    let dayOfLife: Int
    let asleepSince: Date?
    /// When they last woke — the end of their most recent sleep. `nil` when they
    /// have not slept this shift, in which case nothing is claimed about how long
    /// they have been up. Only meaningful while `asleepSince` is `nil`.
    let awakeSince: Date?
    let lastFeedAt: Date?
    let lastDiaperAt: Date?

    var isAsleep: Bool { asleepSince != nil }

    /// The instant the current state began, whichever state that is.
    var stateSince: Date? { asleepSince ?? awakeSince }

    /// Whether the feed is overdue as of `now`. Computed here rather than baked in,
    /// so the value can refresh on the clock without invalidating the whole screen.
    ///
    /// A future-dated feed (reachable only via sync from a device with a skewed
    /// clock) counts as overdue rather than as "just fed" — treating it as recent is
    /// what silently suppressed this warning in the web version.
    func feedIsDue(now: Date, after interval: TimeInterval = 3 * 3600) -> Bool {
        guard let lastFeedAt else { return false }
        let elapsed = now.timeIntervalSince(lastFeedAt)
        return elapsed < 0 || elapsed >= interval
    }
}

/// One baby's live state plus their actions. With twins these stack, so both
/// states are visible at once and neither set of buttons can act on the wrong baby.
struct BabyStatusCard: View {
    let baby: BabyPresentation
    /// The shift's zone, not the device's. Every other clock on this screen is
    /// rendered in it, and a family in another timezone would otherwise get a
    /// status line disagreeing with the timeline row directly beneath it.
    let timeZone: TimeZone

    /// A write is in flight for this baby; actions are inert until it lands.
    var isBusy: Bool
    var onFeed: () -> Void
    var onDiaper: () -> Void
    var onToggleSleep: () -> Void
    var onNote: () -> Void
    var onEditBaby: () -> Void
    var onAdjustSleep: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    private var accentColor: Color { baby.accent.color(for: theme) }
    private var stateColor: Color { baby.isAsleep ? palette.sleep : palette.awake }
    /// The wash the state tint is legible on. These pairs were ported together and
    /// are pinned to 4.5:1 by `PaletteTests` — do not substitute an opacity.
    private var stateWash: Color { baby.isAsleep ? palette.sleepFaint : palette.awakeFaint }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // Only these two labels depend on the clock. Ticking here rather than
            // around the whole screen means the timeline — every row, every
            // formatted time — re-renders on writes, not every 30 seconds.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    status(now: context.date)
                    lastSeen(now: context.date)
                }
            }
            actions
        }
        .padding(16)
        .cardSurface(palette)
    }

    // A visible chevron, not a long-press — see `docs/design.md`.
    private var header: some View {
        Button(action: { Haptics.tap(); onEditBaby() }) {
            HStack {
                BabyChip(name: baby.name, accent: baby.accent)
                Spacer()
                Text("Day \(baby.dayOfLife)").font(.subheadline).foregroundStyle(palette.faint)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(baby.name), day \(baby.dayOfLife). Edit name and colour.")
    }

    // The Wake/Sleep button toggles instantly — that is the 3am path. This tile
    // opens the sheet for a back-dated or corrected time, visibly rather than
    // behind a long-press.
    //
    // Ported from the PWA's sleep tile, which is the one piece of that design
    // worth keeping literally: a bordered, state-tinted block reading "Mia is
    // asleep" is legible across a dark room in a way a coloured word in a row is
    // not. What is deliberately NOT ported is its copy — the web tile said "tap
    // when Mia wakes" because tapping it toggled. Tapping this one opens the
    // adjust sheet, so it says so.
    private func status(now: Date) -> some View {
        Button(action: { Haptics.tap(); onAdjustSleep() }) {
            statusContent(now: now)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibleStatus(now: now))
        .accessibilityHint("Adjust the time")
    }

    private func statusContent(now: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: baby.isAsleep ? "moon.zzz.fill" : "sun.max.fill")
                .font(.title3)
                .foregroundStyle(stateColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(baby.name) is \(baby.isAsleep ? "asleep" : "awake")")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.faint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            if let since = baby.asleepSince {
                // Monospaced so the number doesn't jitter as digit widths change.
                Text(Fmt.ago(since, now: now))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stateWash, in: shape)
        // Two points, not one: the tint is the third signal here, behind the name
        // in the copy and the icon, and a hairline would disappear against the
        // wash it sits on.
        .overlay(shape.stroke(stateColor, lineWidth: 2))
        .contentShape(shape)
    }

    /// "Since 3:42am · tap to adjust" — when this state began, then what the tap does.
    ///
    /// The time sits on this line rather than trailing the state sentence above it,
    /// which is where it was first put. Appended there it wrapped, and it wrapped
    /// *inside* the parenthetical — "(since" ending one line and "10:12am)" alone on
    /// the next — because the asleep tile also carries the elapsed badge on its
    /// trailing edge. That is the state where the line is tightest and the only one
    /// where the badge exists, and any name longer than "Mia" makes it worse. The
    /// state stays one short bold line; the clock time is the supporting fact.
    ///
    /// Both states carry it now. Awake used to say nothing about when it started,
    /// which was the more useful of the two — "she has been up since 4:20" is what
    /// decides whether to try a feed.
    private var subtitle: String {
        let hint = baby.isAsleep ? "tap to adjust" : "tap to log a sleep you missed"
        guard let since = baby.stateSince else {
            // Before this baby has slept, there is no honest answer. Say nothing
            // rather than name the shift's start as though it were a wake.
            return hint.prefix(1).uppercased() + hint.dropFirst()
        }
        return "Since \(Fmt.clockAmPm(since, timeZone: timeZone)) · \(hint)"
    }

    /// VoiceOver gets the elapsed time rather than the clock time. The visible tile
    /// shows both — the counter on the right is only rendered while asleep — and a
    /// spoken "asleep for 40m" answers the question the doula is actually asking
    /// faster than a spoken "asleep since 3:42am" does.
    private func accessibleStatus(now: Date) -> String {
        if let since = baby.asleepSince {
            return "\(baby.name) asleep for \(Fmt.ago(since, now: now))"
        }
        guard let woke = baby.awakeSince else { return "\(baby.name) awake" }
        return "\(baby.name) awake for \(Fmt.ago(woke, now: now))"
    }

    private func lastSeen(now: Date) -> some View {
        HStack(spacing: 14) {
            chip("drop.fill", baby.lastFeedAt, now: now,
                 empty: "no feed yet", warn: baby.feedIsDue(now: now))
            chip("square.on.square", baby.lastDiaperAt, now: now,
                 empty: "no change yet", warn: false)
            Spacer()
        }
    }

    private func chip(
        _ icon: String, _ at: Date?, now: Date, empty: String, warn: Bool
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(at.map { Fmt.ago($0, now: now) } ?? empty).font(.caption.monospacedDigit())
        }
        .foregroundStyle(warn ? palette.warn : palette.faint)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            action("Feed", "drop.fill", onFeed)
            action("Diaper", "square.on.square", onDiaper)
            // Tinted by the state the button moves *to*, matching its label —
            // "Wake" is gold, "Sleep" is sage, whichever state you are in now.
            action(
                baby.isAsleep ? "Wake" : "Sleep",
                baby.isAsleep ? "sun.max.fill" : "moon.zzz.fill",
                onToggleSleep, tint: baby.isAsleep ? palette.awake : palette.sleep)
        }
    }

    private func action(
        _ title: String, _ icon: String, _ run: @escaping () -> Void, tint: Color? = nil
    ) -> some View {
        Button(action: {
            guard !isBusy else { return }
            Haptics.tap()
            run()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: MoonLayout.tapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle((tint ?? palette.ink).opacity(isBusy ? 0.4 : 1))
        .background(palette.chip, in: RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous))
        .accessibilityLabel("\(title) for \(baby.name)")
    }
}
