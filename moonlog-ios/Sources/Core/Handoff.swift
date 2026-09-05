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
        events: [EventSnapshot],
        sessions: [SleepSnapshot],
        unit: VolumeUnit,
        timeZone: TimeZone,
        asOf now: Date
    ) -> String {
        var lines: [String] = []
        let end = shift.endedAt ?? now

        lines.append(header(babies: babies, shift: shift, end: end, timeZone: timeZone))
        if let caregiver, !caregiver.isEmpty {
            lines.append("Cared for by \(caregiver)")
        }

        for baby in babies {
            let totals = Totals.compute(
                events: events, sessions: sessions, forBaby: baby.id,
                shift: shift, asOf: now)
            lines.append("")
            if babies.count > 1 {
                lines.append("— \(baby.name) · Day \(baby.dayOfLife) —")
            }
            lines.append(contentsOf: feedBlock(baby, totals, events, unit, timeZone))
            lines.append(contentsOf: diaperBlock(totals))
            lines.append(contentsOf: sleepBlock(totals))
            lines.append(contentsOf: noteBlock(baby, events, timeZone))
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
        default: title = "\(names.joined(separator: " & "))'s night"
        }
        let window = "\(Fmt.clock(shift.startedAt, timeZone: timeZone)) → "
            + "\(Fmt.clock(end, timeZone: timeZone))"
        let onWatch = Fmt.paddedDuration(end.timeIntervalSince(shift.startedAt))
        return """
        🌙 \(title)
        \(shift.startedAt.formatted(f))
        Shift \(window) · \(onWatch) on watch
        """
    }

    private static func feedBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals,
        _ events: [EventSnapshot], _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        var out = ["🍼  Feeds · \(totals.feeds)"
            + (totals.feedMl > 0 ? " (about \(Fmt.amount(ml: totals.feedMl, unit: unit)))" : "")]
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
                + totals.stoolProgression.map(\.rawValue).joined(separator: " → "))
        }
        return out
    }

    private static func sleepBlock(_ totals: ShiftTotals) -> [String] {
        guard totals.stretches > 0 else { return ["😴  Sleep · none logged"] }
        var out = ["😴  Sleep · \(Fmt.duration(totals.sleepSeconds)) "
            + "over \(totals.stretches) stretch\(totals.stretches == 1 ? "" : "es")"]
        if totals.longestStretchSeconds > 0 {
            out.append("     longest was \(Fmt.duration(totals.longestStretchSeconds))")
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
            line += pieces.joined(separator: " · ")
            out.append(line)
        }
        return out
    }
}
