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

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        Group {
            if let shift {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(shift: shift, now: context.date)
                }
            } else {
                EmptyStatePlaceholder(
                    emoji: "📋",
                    title: "No shift running",
                    message: "Start a shift and the night's totals appear here.")
            }
        }
        .background(palette.bg)
    }

    private func content(shift: Shift, now: Date) -> some View {
        let events = (shift.events ?? []).compactMap(\.snapshot)
        let sessions = (shift.sleepSessions ?? []).compactMap(\.snapshot)
        let unit = family.volumeUnit

        return ScrollView {
            VStack(spacing: 18) {
                shiftHeader(shift, now: now)

                ForEach(family.activeBabies) { baby in
                    let totals = Totals.compute(
                        events: events, sessions: sessions, forBaby: baby.id,
                        shift: shift.window, asOf: now)
                    babyCard(baby, totals: totals, unit: unit, now: now)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 88)
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
        _ baby: Baby, totals: ShiftTotals, unit: VolumeUnit, now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(baby.accent.color(for: theme))
                    .frame(width: 10, height: 10)
                Text(baby.name).font(.headline).foregroundStyle(palette.ink)
                Spacer()
                Text("Day \(DayOfLife.calendarDay(birthAt: baby.birthAt, forShift: shift?.window ?? ShiftWindow(startedAt: now), calendar: family.calendar))")
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
                       totals.stoolProgression.map { $0.rawValue.capitalized }
                        .joined(separator: " → "))
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
                    Text(String(format: "%.1f °F", temp))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(totals.hasFever ? palette.stop : palette.soft)
                }
                if totals.hasFever {
                    Label("At or above \(String(format: "%.1f", ShiftTotals.feverThresholdF))°F",
                          systemImage: "thermometer.high")
                        .font(.footnote)
                        .foregroundStyle(palette.stop)
                }
            }
        }
        .padding(16)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.line, lineWidth: 1))
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
