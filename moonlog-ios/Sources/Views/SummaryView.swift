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
    @Environment(\.careStore) private var store

    @State private var copied = false
    @State private var editingNote = false
    @State private var saveError: String?

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
                    // Inside a menu, so each document is composed when it is chosen
                    // rather than on every body evaluation — which also keeps a
                    // screen left open for an hour from sharing an hour-stale one.
                    shareMenu(shift)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = HandoffComposer.text(
                            family: family, shift: shift, now: shift.endedAt ?? Date())
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
        .sheet(isPresented: $editingNote) {
            if let shift {
                ParentNoteSheet(
                    babyNames: family.activeBabies.map(\.name).joined(separator: " & "),
                    existing: shift.parentNote ?? ""
                ) { text in
                    StoreWrite.run(store, onError: { saveError = $0 }) {
                        try await $0.setShiftNote(shift.id, text: text)
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        #if DEBUG
        // A screenshot affordance, never reachable in a real run — same rationale
        // as the rest of DemoSeed.
        .task {
            guard DemoSeed.wantsHandoffDump, let shift else { return }
            let html = HandoffComposer.html(
                family: family, shift: shift, now: shift.endedAt ?? Date())
            let url = URL.documentsDirectory.appending(path: "handoff.html")
            try? Data(html.utf8).write(to: url)
        }
        #endif
    }

    @ViewBuilder
    private func shareMenu(_ shift: Shift) -> some View {
        let asOf = shift.endedAt ?? Date()
        Menu {
            ShareLink(
                item: HandoffPage(
                    filename: HandoffComposer.filename(family: family, shift: shift),
                    html: HandoffComposer.html(family: family, shift: shift, now: asOf)),
                preview: SharePreview(HandoffComposer.filename(family: family, shift: shift))
            ) {
                Label("Send the page", systemImage: "doc.richtext")
            }
            ShareLink(item: HandoffComposer.text(family: family, shift: shift, now: asOf)) {
                Label("Send as plain text", systemImage: "text.alignleft")
            }
            Divider()
            Button {
                editingNote = true
            } label: {
                Label(
                    (shift.parentNote?.isEmpty ?? true)
                        ? "Add a note to the parents" : "Edit the note to the parents",
                    systemImage: "square.and.pencil")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    /// This family's past nights. Filtering here rather than in the predicate
    /// because a `@Query` cannot capture `family.id` at declaration.
    private var pastNights: [Shift] {
        closedShifts.filter { $0.familyIDRaw == family.id }.prefix(14).map { $0 }
    }

    private func content(shift: Shift, now: Date) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                SummaryCards(family: family, shift: shift, now: now)
                PastNightsSection(family: family, shifts: pastNights)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, MoonLayout.tabBarClearance)
        }
    }

}

/// The per-baby cards for one shift.
///
/// A real `View`, not a method on `SummaryView`. It used to be the latter, and a
/// past night's detail called it on a `SummaryView` value that was never installed
/// in the hierarchy — so its `@Environment` reads returned DEFAULTS and every card
/// rendered in the Night palette regardless of theme. In Day that is dark maroon
/// cards on a cream page.
struct SummaryCards: View {
    let family: Family
    let shift: Shift
    let now: Date

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
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
                ("Sleep", Fmt.spanned(totals.sleepSeconds), palette.sleep),
                ("Diapers", "\(totals.diapers)", palette.ink),
            ])

            statRow([
                ("Bottle", totals.feedMl > 0 ? Fmt.amountTotal(ml: totals.feedMl, unit: unit) : "—",
                 palette.soft),
                ("At breast", Fmt.spanned(totals.breastSeconds), palette.soft),
                ("Longest", Fmt.spanned(totals.longestStretchSeconds), palette.soft),
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
