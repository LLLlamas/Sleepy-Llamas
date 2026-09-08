import SwiftUI
import SwiftData
import MoonlogCore

/// Tonight, as the parents will read it.
///
/// This is what the app is for, and it is the first screen to actually call
/// `Totals.compute` — the totals layer was fully tested and completely unreachable
/// until `LogEvent` gained a snapshot projection.
///
/// Scoped to the running shift only. Past nights moved to `HistoryView`, reached
/// from Settings: they were rendered here in the no-open-shift branch, which meant
/// history was visible exactly when it was least wanted and hidden all night.
struct SummaryView: View {
    let family: Family
    let shift: Shift?

    /// Closed shifts, newest first — the same query `HistoryView` runs, for the
    /// same reason it cannot capture `family.id` in the predicate.
    @Query(filter: #Predicate<Shift> { !$0.isOpen }, sort: \Shift.startedAt, order: .reverse)
    private var closedShifts: [Shift]

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme
    @Environment(\.careStore) private var store

    @State private var copied = false
    @State private var editingNote = false

    /// The night this screen is about: the running shift, or — the moment it ends —
    /// the one just finished.
    ///
    /// Ending a shift used to empty this screen and take Copy and Share away with
    /// it, at the exact moment the handoff was finished and wanted. Getting it back
    /// was four taps through Settings › Past nights, on a different tab, described
    /// in prose rather than offered as a route.
    private var shown: Shift? {
        shift ?? closedShifts.first { $0.familyIDRaw == family.id }
    }

    var body: some View {
        Group {
            if let shift {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(shift: shift, now: context.date)
                }
            } else if let last = shown {
                // No `TimelineView`: a finished night's totals do not move.
                content(shift: last, now: last.endedAt ?? Date())
            } else {
                EmptyStatePlaceholder(
                    emoji: "📋",
                    title: "No shift running",
                    message: "Start a shift and the night's totals appear here. "
                        + "Finished nights are under Settings › Past nights.")
            }
        }
        .moonBackground(palette)
        .toolbar {
            if let shift = shown {
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
            if let shift = shown {
                ParentNoteSheet(
                    babyNames: family.activeBabies.map(\.name).joined(separator: " & "),
                    existing: shift.parentNote ?? ""
                ) { text in
                    guard let store else { throw EntrySaveError.unavailable }
                    try await store.setShiftNote(shift.id, text: text)
                }
                .presentationDetents([.medium, .large])
            }
        }
        #if DEBUG
        // A screenshot affordance, never reachable in a real run — same rationale
        // as the rest of DemoSeed.
        .task {
            guard DemoSeed.wantsHandoffDump, let shift = shown else { return }
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
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    private func content(shift: Shift, now: Date) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        editingNote = true
                    } label: {
                        Label(
                            (shift.parentNote?.isEmpty ?? true)
                                ? "Add a note to the parents" : "Edit the note to the parents",
                            systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: MoonLayout.tapTarget, alignment: .leading)
                    }
                    .accessibilityIdentifier("summary.parentsNote")
                    if let note = shift.parentNote, !note.isEmpty {
                        Text(note).font(.body).foregroundStyle(palette.ink)
                    }
                    NavigationLink {
                        HistoryView(family: family)
                    } label: {
                        Label("Past nights", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: MoonLayout.tapTarget, alignment: .leading)
                    }
                    .accessibilityIdentifier("summary.pastNights")
                }
                .padding(.horizontal, 16)
                .cardSurface(palette)
                SummaryCards(family: family, shift: shift, now: now)
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
            // `shift.roster(of:)`, not `activeBabies`: a baby archived mid-shift
            // keeps her card for the night she was actually here, and the cards
            // agree with the handoff because both apply `Handoff.roster`.
            ForEach(shift.roster(of: family)) { baby in
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
            // "ended", not blank: Summary now keeps the night just finished, and
            // a closed shift that says nothing reads exactly like a running one.
            Text("\(Fmt.clock(shift.startedAt, timeZone: zone)) – \(Fmt.clock(end, timeZone: zone))"
                 + (shift.isOpen ? " · running" : " · ended"))
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
        return VStack(alignment: .leading, spacing: 14) {
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
