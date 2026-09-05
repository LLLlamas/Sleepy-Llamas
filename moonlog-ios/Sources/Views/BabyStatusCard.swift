import SwiftUI
import MoonlogCore

/// One baby's live state plus their actions.
///
/// With twins these stack, so both babies' state is visible at once and each has
/// its own buttons — there is no "active baby" mode to set wrong, which is the
/// failure this layout exists to prevent. With one baby it renders as the single
/// full-width status block.
struct BabyStatusCard: View {
    let baby: BabyPresentation
    let now: Date
    let dueSoonHours: Double

    var onFeed: () -> Void
    var onDiaper: () -> Void
    var onToggleSleep: () -> Void
    var onEditBaby: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusLine
            actions
        }
        .padding(16)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        Button(action: onEditBaby) {
            headerContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(baby.name), day \(baby.dayOfLife). Edit name and colour.")
    }

    private var headerContent: some View {
        HStack(spacing: 10) {
            // Accent is the THIRD identifying signal, never the only one — the name
            // is always present and card order is fixed. Hue discrimination is poor
            // in a dark room and absent for colourblind users.
            Circle()
                .fill(baby.accent.color(for: theme))
                .frame(width: 10, height: 10)

            Text(baby.name)
                .font(.headline)
                .foregroundStyle(palette.ink)

            Spacer()

            Text("Day \(baby.dayOfLife)")
                .font(.subheadline)
                .foregroundStyle(palette.faint)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.faint)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Status

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: baby.isAsleep ? "moon.zzz.fill" : "sun.max.fill")
                .font(.subheadline)
                .foregroundStyle(baby.isAsleep ? palette.sleep : palette.awake)

            Text(baby.isAsleep ? "Asleep" : "Awake")
                .font(.title3.weight(.semibold))
                .foregroundStyle(baby.isAsleep ? palette.sleep : palette.awake)

            if let since = baby.asleepSince {
                Text(Fmt.duration(max(0, now.timeIntervalSince(since))))
                    // Monospaced digits so the number does not jitter as digit
                    // widths change — this is re-read all night.
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(palette.soft)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            baby.isAsleep
                ? "\(baby.name) asleep\(baby.asleepSince.map { " for " + Fmt.duration(max(0, now.timeIntervalSince($0))) } ?? "")"
                : "\(baby.name) awake")
    }

    // MARK: - Last events

    private var lastRow: some View {
        HStack(spacing: 14) {
            lastChip(
                icon: "drop.fill",
                label: baby.lastFeedAt.map { Fmt.ago($0, now: now) } ?? "no feed yet",
                warn: baby.feedIsDue)
            lastChip(
                icon: "square.on.square",
                label: baby.lastDiaperAt.map { Fmt.ago($0, now: now) } ?? "no change yet",
                warn: false)
            Spacer()
        }
    }

    private func lastChip(icon: String, label: String, warn: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption.monospacedDigit())
        }
        .foregroundStyle(warn ? palette.warn : palette.faint)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            lastRow
            HStack(spacing: 8) {
                actionButton("Feed", systemImage: "drop.fill", action: onFeed)
                actionButton("Diaper", systemImage: "square.on.square", action: onDiaper)
                actionButton(
                    baby.isAsleep ? "Wake" : "Sleep",
                    systemImage: baby.isAsleep ? "sun.max.fill" : "moon.zzz.fill",
                    tint: baby.isAsleep ? palette.awake : palette.sleep,
                    action: onToggleSleep)
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.body)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            // 56pt floor, carried over from the web version's --tap token. One
            // hand, in the dark, holding a baby.
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? palette.ink)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("\(title) for \(baby.name)")
    }
}

/// What the card needs, already computed. Keeps the view free of domain logic and
/// makes it previewable without a store.
struct BabyPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let accent: BabyAccent
    let dayOfLife: Int
    let isAsleep: Bool
    let asleepSince: Date?
    let lastFeedAt: Date?
    let lastDiaperAt: Date?
    /// Whether the feed is overdue. Computed upstream so a future-dated entry
    /// cannot silently suppress the warning the way it does in the web version.
    let feedIsDue: Bool
}
