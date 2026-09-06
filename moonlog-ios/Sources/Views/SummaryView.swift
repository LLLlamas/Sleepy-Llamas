import SwiftUI
import SwiftData
import MoonlogCore

/// The night as the parents will read it.
///
/// This is what the app is for, and it is the first screen to actually call
/// `Totals.compute` — the totals layer was fully tested and completely unreachable
/// until `LogEvent` gained a snapshot projection.
struct SummaryView: View {
    let family: Family
    let shift: Shift?

    /// Closed shifts, newest first. Bounded — a doula accumulates one per night and
    /// nobody scrolls a year back on this screen.
    @Query(filter: #Predicate<Shift> { !$0.isOpen }, sort: \Shift.startedAt, order: .reverse)
    private var closedShifts: [Shift]

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    @State private var copied = false

    var body: some View {
        Group {
            if let shift {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(shift: shift, now: context.date)
                }
            } else if pastNights.isEmpty {
                EmptyStatePlaceholder(
                    emoji: "📋",
                    title: "No shift running",
                    message: "Start a shift and the night's totals appear here.")
            } else {
                ScrollView {
                    PastNightsSection(family: family, shifts: pastNights)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, MoonLayout.tabBarClearance)
                }
            }
        }
        .background(palette.bg)
        .toolbar {
            if let shift {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: HandoffComposer.text(family: family, shift: shift, now: Date())) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = HandoffComposer.text(family: family, shift: shift, now: Date())
                        Haptics.success()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
            }
        }
    }

    /// This family's past nights. Filtering here rather than in the predicate
    /// because a `@Query` cannot capture `family.id` at declaration.
    private var pastNights: [Shift] {
        closedShifts.filter { $0.familyIDRaw == family.id }.prefix(14).map { $0 }
    }

    /// The per-baby cards alone, so a past night renders through exactly this view
    /// rather than a parallel copy that could drift.
    @ViewBuilder
    func summaryCards(now: Date) -> some View {
        if let shift {
            let events = (shift.events ?? []).compactMap(\.snapshot)
            let sessions = (shift.sleepSessions ?? []).compactMap(\.snapshot)
            VStack(spacing: 18) {
                shiftHeader(shift, now: now)
                ForEach(family.activeBabies) { baby in
                    babyCard(
                        baby,
                        totals: Totals.compute(
                            events: events, sessions: sessions, forBaby: baby.id,
                            shift: shift.window, asOf: now),
                        unit: family.volumeUnit, shift: shift)
                }
            }
        }
    }

    private func content(shift: Shift, now: Date) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCards(now: now)
                PastNightsSection(family: family, shifts: pastNights)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, MoonLayout.tabBarClearance)
        }
    }

    private func shiftHeader(_ shift: Shift, now: Date) -> some View {
        let zone = TimeZone(identifier: shift.timeZoneIdentifier) ?? .current
        let end = shift.endedAt ?? now
        return VStack(spacing: 4) {
            Text(family.name)
                .font(.headline)
                .foregroundStyle(palette.ink)
            Text("\(Fmt.clock(shift.startedAt, timeZone: zone)) – \(Fmt.clock(end, timeZone: zone))"
                 + (shift.isOpen ? " · running" : ""))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette.faint)
            if let caregiver = shift.caregiver, !caregiver.isEmpty {
                Text(caregiver).font(.footnote).foregroundStyle(palette.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func babyCard(
        _ baby: Baby, totals: ShiftTotals, unit: VolumeUnit, shift: Shift
    ) -> some View {
        // Pinned to the shift, like Tonight. Reading the optional property here
        // meant a dead fallback that, if it ever fired, would show a different day
        // number for the same baby in the same session.
        let dayOfLife = DayOfLife.calendarDay(
            birthAt: baby.birthAt, forShift: shift.window, calendar: family.calendar)
        return
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BabyChip(name: baby.name, accent: baby.accent)
                Spacer()
                Text("Day \(dayOfLife)")
                    .font(.subheadline)
                    .foregroundStyle(palette.faint)
            }

            statRow([
                ("Feeds", "\(totals.feeds)", palette.ink),
                ("Sleep", Fmt.duration(totals.sleepSeconds), palette.sleep),
                ("Diapers", "\(totals.diapers)", palette.ink),
            ])

            statRow([
                ("Bottle", totals.feedMl > 0 ? Fmt.amount(ml: totals.feedMl, unit: unit) : "—",
                 palette.soft),
                ("At breast", totals.breastSeconds > 0
                    ? Fmt.duration(totals.breastSeconds) : "—", palette.soft),
                ("Longest", totals.longestStretchSeconds > 0
                    ? Fmt.duration(totals.longestStretchSeconds) : "—", palette.soft),
            ])

            detail("Wet / dirty", "\(totals.wet) / \(totals.dirty)")
            if !totals.stoolProgression.isEmpty {
                detail("Stool",
                       totals.stoolProgression.map(Fmt.stool).joined(separator: " → "))
            }
            if totals.stretches > 0 {
                detail("Stretches", "\(totals.stretches)")
            }
            if let temp = totals.highestTempF {
                HStack {
                    Text("Highest temp")
                        .font(.footnote)
                        .foregroundStyle(palette.faint)
                    Spacer()
                    Text(Fmt.temp(temp))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(totals.hasFever ? palette.stop : palette.soft)
                }
                if totals.hasFever { FeverBadge() }
            }
        }
        .padding(16)
        .cardSurface(palette)
    }

    private func statRow(_ stats: [(String, String, Color)]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(stats, id: \.0) { label, value, tint in
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tint)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(palette.faint)
            Spacer()
            Text(value).font(.footnote.monospacedDigit()).foregroundStyle(palette.soft)
        }
    }
}
