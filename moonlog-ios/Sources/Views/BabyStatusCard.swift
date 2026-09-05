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
    let lastFeedAt: Date?
    let lastDiaperAt: Date?

    var isAsleep: Bool { asleepSince != nil }

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
        .background(palette.raised, in: card)
        .overlay(card.stroke(palette.line, lineWidth: 1))
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: MoonLayout.cardCorner, style: .continuous)
    }

    // A visible chevron, not a long-press — see `docs/design.md`.
    private var header: some View {
        Button(action: { Haptics.tap(); onEditBaby() }) {
            HStack(spacing: 10) {
                Circle().fill(accentColor).frame(width: 10, height: 10)
                Text(baby.name).font(.headline).foregroundStyle(palette.ink)
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

    // The button toggles instantly — that is the 3am path. This opens the sheet
    // for a back-dated or corrected time, visibly rather than behind a long-press.
    private func status(now: Date) -> some View {
        Button(action: { Haptics.tap(); onAdjustSleep() }) {
            statusContent(now: now)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibleStatus(now: now))
        .accessibilityHint("Adjust the time")
    }

    private func statusContent(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: baby.isAsleep ? "moon.zzz.fill" : "sun.max.fill")
                .font(.subheadline)
            Text(baby.isAsleep ? "Asleep" : "Awake").font(.title3.weight(.semibold))
            if let since = baby.asleepSince {
                // Monospaced so the number doesn't jitter as digit widths change.
                Text(Fmt.ago(since, now: now))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(palette.soft)
            }
            Image(systemName: "slider.horizontal.3")
                .font(.caption2)
                .foregroundStyle(palette.faint)
            Spacer()
        }
        .foregroundStyle(stateColor)
        .contentShape(Rectangle())
    }

    private func accessibleStatus(now: Date) -> String {
        guard let since = baby.asleepSince else { return "\(baby.name) awake" }
        return "\(baby.name) asleep for \(Fmt.ago(since, now: now))"
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
