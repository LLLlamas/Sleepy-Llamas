import Foundation

/// One baby, as the handoff needs to name them.
public struct HandoffBaby: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let dayOfLife: Int
    /// Discharged, but their history did not go anywhere. Only `roster` reads this;
    /// once a baby is in the roster the rest of the handoff treats them like any
    /// other. Defaulted, so a caller that has no notion of archiving is unaffected.
    public let isArchived: Bool

    public init(id: UUID, name: String, dayOfLife: Int, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.dayOfLife = dayOfLife
        self.isArchived = isArchived
    }
}

/// The night, written out for the parents.
///
/// Lives in Core, and is a pure function of value types, for two reasons: it is the
/// app's actual output and deserves tests, and it must render the same numbers the
/// Summary screen shows — both go through `Totals.compute`.
///
/// The register is deliberately different from the UI's. The interface uses chips
/// and abbreviations because a tired doula scans it; this is prose because the
/// parents read it over coffee. "left breast", not "Breast L".
public enum Handoff {

    /// Who the night is written about: everyone currently on the family's roster,
    /// plus anyone this shift actually logged something for. Composing from the
    /// active babies alone meant archiving a baby mid-shift silently erased
    /// everything already logged against them from the parents' document.
    ///
    /// An archived baby with nothing logged stays out — an empty section for a
    /// discharged baby is noise on a page read at 6am. Input order is preserved, so
    /// the caller sorts once (by `sortOrder`) and this never reshuffles the cards.
    public static func roster(
        _ babies: [HandoffBaby], loggedFor logged: Set<UUID>
    ) -> [HandoffBaby] {
        babies.filter { !$0.isArchived || logged.contains($0.id) }
    }

    public static func text(
        babies: [HandoffBaby],
        shift: ShiftWindow,
        caregiver: String?,
        events allEvents: [EventSnapshot],
        sessions: [SleepSnapshot],
        unit: VolumeUnit,
        timeZone: TimeZone,
        asOf now: Date
    ) -> String {
        var lines: [String] = []
        let end = shift.endedAt ?? now
        // Clipped once, here, so every list below agrees with the totals above it.
        // Back-dating outside the shift is allowed by design, and the counts have
        // always excluded it — the lists used not to.
        let events = shift.interval(asOf: now)
            .map { window in allEvents.filter { window.contains($0.at) } } ?? []

        lines.append(
            header(babies: babies, shift: shift, end: end, timeZone: timeZone))
        if let caregiver, !caregiver.isEmpty {
            lines.append("Cared for by \(caregiver)")
        }

        for baby in babies {
            let totals = Totals.compute(
                events: allEvents, sessions: sessions, forBaby: baby.id,
                shift: shift, asOf: now)
            lines.append("")
            if babies.count > 1 {
                lines.append("— \(baby.name) · Day \(baby.dayOfLife) —")
            }
            // A blank line between blocks: pasted into Messages at 6am, an
            // unbroken wall of text is not read.
            lines.append(contentsOf: feedBlock(baby, totals, events, unit, timeZone))
            lines.append("")
            lines.append(contentsOf: diaperBlock(totals))
            lines.append("")
            lines.append(contentsOf: sleepBlock(baby, totals, sessions, shift, now, timeZone))
            let extras = extrasBlock(baby, totals, events, unit, timeZone)
            if !extras.isEmpty {
                lines.append("")
                lines.append(contentsOf: extras)
            }
            let notes = noteBlock(baby, events, timeZone)
            if !notes.isEmpty {
                lines.append("")
                lines.append(contentsOf: notes)
            }
        }

        // Records logged against a baby who is nowhere in the roster — a `Baby`
        // deleted out from under its history, or a relationship that never arrived
        // from sync. They were logged for somebody, so they must not vanish from the
        // parents' page just because the name has. Roster-independent, like the
        // household total below it.
        let stray = unattributedBlock(
            babies, events, sessions, shift, now, unit, timeZone)
        if !stray.isEmpty {
            lines.append("")
            lines.append(contentsOf: stray)
        }

        let household = Totals.household(events: allEvents, shift: shift, asOf: now)
        if !household.isEmpty {
            lines.append("")
            lines.append("🫙  Pumped · \(Fmt.amountTotal(ml: household.pumpedMl, unit: unit)) "
                + "over \(household.pumpSessions) session"
                + (household.pumpSessions == 1 ? "" : "s"))
        }

        lines.append("")
        if let caregiver, !caregiver.isEmpty {
            lines.append("With care,")
            lines.append("\(caregiver) 🌙")
        } else {
            lines.append("🌙 logged with Moonlog")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Blocks

    private static func header(
        babies: [HandoffBaby], shift: ShiftWindow, end: Date, timeZone: TimeZone
    ) -> String {
        var f = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        f.timeZone = timeZone
        let names = babies.map(\.name)
        let title: String
        switch names.count {
        case 0: title = "The night"
        case 1: title = "\(names[0])'s night · Day \(babies[0].dayOfLife)"
        default:
            let head = names.dropLast().joined(separator: ", ")
            title = "\(head) & \(names[names.count - 1])'s night"
        }
        let onWatch = Fmt.paddedDuration(end.timeIntervalSince(shift.startedAt))
        // An open shift must not read as a finished one. The PWA framed this as
        // "summary through <time>" and that honesty was dropped in the port.
        let line = shift.isOpen
            ? "Shift started \(Fmt.clock(shift.startedAt, timeZone: timeZone)) · "
                + "summary through \(Fmt.clock(end, timeZone: timeZone)) · "
                + "\(onWatch) so far"
            : "Shift \(Fmt.clock(shift.startedAt, timeZone: timeZone)) → "
                + "\(Fmt.clock(end, timeZone: timeZone)) · \(onWatch) on watch"
        return """
        🌙 \(title)
        \(shift.startedAt.formatted(f))
        \(line)
        """
    }

    private static func feedBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals,
        _ events: [EventSnapshot], _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        var out = ["🍼  Feeds · \(totals.feeds)"
            + (totals.feedMl > 0
                ? " (\(Fmt.amountTotal(ml: totals.feedMl, unit: unit)) by bottle)" : "")]
        let feeds = events
            .filter { $0.babyID == baby.id && $0.kind == .feed }
            .sorted { $0.at < $1.at }
        for feed in feeds {
            out.append("     \(Fmt.shortClock(feed.at, timeZone: timeZone))  "
                + warmFeed(feed, unit: unit))
        }
        if feeds.isEmpty { out.append("     none logged") }
        return out
    }

    /// Prose, not chips. "left breast — 18 min" reads; "Breast L · 18m" does not.
    private static func warmFeed(_ feed: EventSnapshot, unit: VolumeUnit) -> String {
        var parts: [String] = []
        switch feed.feedMethod {
        case .breast, .none:
            let left = feed.leftSeconds ?? 0
            let right = feed.rightSeconds ?? 0
            if left > 0 && right > 0 {
                parts.append("both sides")
                parts.append("left \(Fmt.duration(TimeInterval(left))), "
                    + "right \(Fmt.duration(TimeInterval(right)))")
            } else if left > 0 {
                parts.append("left breast")
                parts.append(Fmt.duration(TimeInterval(left)))
            } else if right > 0 {
                parts.append("right breast")
                parts.append(Fmt.duration(TimeInterval(right)))
            } else {
                parts.append("breast")
            }
        case .bottleBreastmilk, .bottleFormula:
            parts.append(feed.feedMethod == .bottleFormula
                ? "bottle, formula" : "bottle, breastmilk")
            if let ml = feed.amountMl, ml > 0 {
                parts.append(Fmt.amount(ml: ml, unit: unit))
            }
            if let s = feed.feedDurationSeconds, s > 0 {
                parts.append(Fmt.duration(TimeInterval(s)))
            }
        case .unknown:
            parts.append("feed")
        }
        return parts.joined(separator: " — ")
    }

    private static func diaperBlock(_ totals: ShiftTotals) -> [String] {
        var out = ["🧷  Diapers · \(totals.diapers)"
            + (totals.diapers > 0 ? "  (\(totals.wet) wet, \(totals.dirty) dirty)" : "")]
        if !totals.stoolProgression.isEmpty {
            out.append("     stool: "
                + totals.stoolProgression.map(Fmt.stool).joined(separator: " → "))
        }
        return out
    }

    private static func sleepBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals, _ sessions: [SleepSnapshot],
        _ shift: ShiftWindow, _ now: Date, _ timeZone: TimeZone
    ) -> [String] {
        var out: [String] = []
        if totals.stretches > 0 {
            out.append("😴  Sleep · \(Fmt.spanned(totals.sleepSeconds)) "
                + "over \(totals.stretches) stretch\(totals.stretches == 1 ? "" : "es")")
            if totals.longestStretchSeconds > 0 {
                out.append("     longest was \(Fmt.spanned(totals.longestStretchSeconds))")
            }
        } else {
            out.append("😴  Sleep · none logged")
        }
        // The single fact a parent most wants at 6am.
        if let open = SleepMath.openSession(in: sessions, forBaby: baby.id) {
            out.append("     still asleep, since "
                + "\(Fmt.clock(open.startAt, timeZone: timeZone))")
        }
        return out
    }

    /// Medication and weight, when the family logs them. Previously computed and
    /// then rendered nowhere, so a dose given at 2am never reached the parents.
    private static func extrasBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals,
        _ events: [EventSnapshot], _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        var out: [String] = []
        let meds = events
            .filter { $0.babyID == baby.id && $0.kind == .medication }
            .sorted { $0.at < $1.at }
        if !meds.isEmpty {
            out.append("💊  Medication · \(meds.count)")
            for med in meds {
                let what = [med.medicationName, med.doseText]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                out.append("     \(Fmt.shortClock(med.at, timeZone: timeZone))  "
                    + (what.isEmpty ? "given" : what))
            }
        }
        if let grams = totals.latestWeightGrams {
            out.append("⚖️  Weight · \(Fmt.weight(grams: grams, unit: unit))")
        }
        return out
    }

    /// The catch-all for records whose baby the roster does not name. Sleep is
    /// clipped to the shift like everywhere else, so a session that contributed no
    /// time inside the window is not announced as a record.
    ///
    /// `EventSnapshot.noBaby` is deliberately not an orphan: a pump carries no baby
    /// by design and is reported as a household total, not as a lost record.
    private static func unattributedBlock(
        _ babies: [HandoffBaby], _ events: [EventSnapshot], _ sessions: [SleepSnapshot],
        _ shift: ShiftWindow, _ now: Date, _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        let named = Set(babies.map(\.id))
        let orphanEvents = events
            .filter { !named.contains($0.babyID) && $0.babyID != EventSnapshot.noBaby }
            .sorted { $0.at < $1.at }
        let orphanSleep = sessions
            .filter { !named.contains($0.babyID) }
            .map { ($0, SleepMath.seconds(of: $0, clippedTo: shift, asOf: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.0.startAt < $1.0.startAt }

        let count = orphanEvents.count + orphanSleep.count
        guard count > 0 else { return [] }

        var out = ["❔  Not matched to a baby · \(count) record"
            + (count == 1 ? "" : "s")]
        for event in orphanEvents {
            out.append("     \(Fmt.shortClock(event.at, timeZone: timeZone))  "
                + strayLine(event, unit: unit))
        }
        for (session, seconds) in orphanSleep {
            out.append("     \(Fmt.shortClock(session.startAt, timeZone: timeZone))  "
                + "asleep — \(Fmt.duration(seconds))")
        }
        return out
    }

    /// Terser than the per-baby blocks on purpose: without a name to head them,
    /// these lines have to say what each record was.
    private static func strayLine(_ event: EventSnapshot, unit: VolumeUnit) -> String {
        switch event.kind {
        case .feed:
            return warmFeed(event, unit: unit)
        case .diaper:
            // `Fmt.diaper(.unknown)` is already the word "Diaper" — appending the
            // noun to it reads "diaper diaper".
            guard let contents = event.diaperContents, contents != .unknown
            else { return "diaper" }
            return Fmt.diaper(contents).lowercased() + " diaper"
        case .note:
            if let text = event.text, !text.isEmpty { return text }
            return event.noteTags.isEmpty ? "note" : event.noteTags.joined(separator: ", ")
        case .medication:
            let what = [event.medicationName, event.doseText]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return what.isEmpty ? "medication given" : "medication — \(what)"
        case .measurement:
            guard let grams = event.weightGrams else { return "measurement" }
            return "weighed \(Fmt.weight(grams: grams, unit: unit))"
        case .pump:
            // Filtered out above; a pump reaching here would carry a real baby id,
            // which no write path produces.
            return "pumped"
        }
    }

    private static func noteBlock(
        _ baby: HandoffBaby, _ events: [EventSnapshot], _ timeZone: TimeZone
    ) -> [String] {
        let notes = events
            .filter { $0.babyID == baby.id && $0.kind == .note }
            .sorted { $0.at < $1.at }
        guard !notes.isEmpty else { return [] }
        var out = ["📝  Notes"]
        for note in notes {
            var line = "     \(Fmt.shortClock(note.at, timeZone: timeZone))  "
            var pieces: [String] = []
            if let text = note.text, !text.isEmpty { pieces.append(text) }
            if !note.noteTags.isEmpty { pieces.append(note.noteTags.joined(separator: ", ")) }
            if let temp = note.tempF {
                pieces.append(String(format: "%.1f°F", temp)
                    + (temp >= ShiftTotals.feverThresholdF ? " — tell the parents" : ""))
            }
            line += pieces.isEmpty ? "note" : pieces.joined(separator: " · ")
            out.append(line)
        }
        return out
    }
}
