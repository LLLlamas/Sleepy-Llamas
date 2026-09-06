import Foundation

/// One baby, as the handoff needs to name them.
public struct HandoffBaby: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let dayOfLife: Int

    public init(id: UUID, name: String, dayOfLife: Int) {
        self.id = id
        self.name = name
        self.dayOfLife = dayOfLife
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
