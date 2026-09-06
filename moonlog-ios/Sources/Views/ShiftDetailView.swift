import SwiftUI
import SwiftData
import MoonlogCore

/// A past night, read-only.
///
/// Ending a shift used to make that night permanently invisible: the record stayed
/// in the store and no screen could reach it. This is the way back to it — and to
/// the handoff, which is often wanted after the fact rather than at 6am.
struct ShiftDetailView: View {
    let family: Family
    let shift: Shift

    @Environment(\.palette) private var palette
    @State private var copied = false

    private var zone: TimeZone {
        TimeZone(identifier: shift.timeZoneIdentifier) ?? .current
    }

    /// A closed shift is fixed in time, so `asOf` is its own end — nothing here
    /// depends on the current clock, and nothing needs to tick.
    private var asOf: Date { shift.endedAt ?? Date() }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SummaryView(family: family, shift: shift).summaryCards(now: asOf)

                TimelineSection(
                    entries: ShiftTimeline.entries(
                        for: shift, unit: family.volumeUnit, now: asOf, editable: false),
                    timeZone: zone,
                    names: Dictionary(
                        uniqueKeysWithValues: family.activeBabies.map { ($0.id, $0.name) }),
                    accents: Dictionary(
                        uniqueKeysWithValues: family.activeBabies.map { ($0.id, $0.accent) }))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, MoonLayout.tabBarClearance)
        }
        .background(palette.bg)
        .navigationTitle(Fmt.nightOf(shift.startedAt, timeZone: zone))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: HandoffComposer.text(family: family, shift: shift, now: asOf)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    UIPasteboard.general.string =
                        HandoffComposer.text(family: family, shift: shift, now: asOf)
                    Haptics.success()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
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

/// One place that turns a stored shift into handoff text, so the live Summary and a
/// past night cannot produce different documents for the same records.
enum HandoffComposer {
    static func text(family: Family, shift: Shift, now: Date) -> String {
        Handoff.text(
            babies: family.activeBabies.map {
                HandoffBaby(
                    id: $0.id, name: $0.name,
                    dayOfLife: DayOfLife.calendarDay(
                        birthAt: $0.birthAt, forShift: shift.window,
                        calendar: family.calendar))
            },
            shift: shift.window,
            caregiver: shift.caregiver,
            events: (shift.events ?? []).compactMap(\.snapshot),
            sessions: (shift.sleepSessions ?? []).compactMap(\.snapshot),
            unit: family.volumeUnit,
            timeZone: TimeZone(identifier: shift.timeZoneIdentifier) ?? .current,
            asOf: now)
    }
}

/// The list of past nights, shown under the live summary.
struct PastNightsSection: View {
    let family: Family
    let shifts: [Shift]

    @Environment(\.palette) private var palette

    var body: some View {
        if !shifts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Past nights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.faint)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(shifts.enumerated()), id: \.element.id) { index, shift in
                        NavigationLink {
                            ShiftDetailView(family: family, shift: shift)
                        } label: {
                            row(shift)
                        }
                        .buttonStyle(.plain)
                        if index < shifts.count - 1 {
                            Divider().overlay(palette.line).padding(.leading, 16)
                        }
                    }
                }
                .cardSurface(palette)
            }
        }
    }

    private func row(_ shift: Shift) -> some View {
        let zone = TimeZone(identifier: shift.timeZoneIdentifier) ?? .current
        let end = shift.endedAt ?? shift.startedAt
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.nightOf(shift.startedAt, timeZone: zone))
                    .font(.subheadline)
                    .foregroundStyle(palette.ink)
                Text("\(Fmt.clock(shift.startedAt, timeZone: zone)) – "
                     + "\(Fmt.clock(end, timeZone: zone))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.faint)
            }
            Spacer()
            Text(Fmt.duration(end.timeIntervalSince(shift.startedAt)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.soft)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(palette.faint.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: MoonLayout.tapTarget)
        .contentShape(Rectangle())
    }
}
