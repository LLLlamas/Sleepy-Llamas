import Foundation

/// Display formatting. Lives in Core so the handoff text and the UI cannot drift
/// apart — both render the same night and must agree.
public enum Fmt {

    /// Stored data may predate input validation. Never let a malformed value trap
    /// while opening the timeline or composing a handoff.
    private static func roundedNonnegative(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0 else { return nil }
        return Int(exactly: value.rounded())
    }

    /// "1h 23m" / "48m" / "just now".
    ///
    /// Rounds once, at the point of display — everything upstream carries seconds.
    /// Zero-padded register for documents: "9h 09m". Used by the handoff header.
    public static func paddedDuration(_ seconds: TimeInterval) -> String {
        guard let total = roundedNonnegative(seconds) else { return "—" }
        let minutes = total / 60
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Compact clock for dense rows: "3:12a".
    public static func shortClock(_ date: Date, timeZone: TimeZone) -> String {
        let (hour12, minute, isAM) = twelveHour(date, timeZone: timeZone)
        return String(format: "%d:%02d%@", hour12, minute, isAM ? "a" : "p")
    }

    /// The same clock spelled out: "3:12am". For the one place a time is read at a
    /// glance across a dark room rather than scanned in a column — the status tile's
    /// "since". `shortClock`'s single letter is a column-width economy that buys
    /// nothing there, and `clock` follows the locale, which puts a space and capitals
    /// in the middle of a sentence.
    public static func clockAmPm(_ date: Date, timeZone: TimeZone) -> String {
        let (hour12, minute, isAM) = twelveHour(date, timeZone: timeZone)
        return String(format: "%d:%02d%@", hour12, minute, isAM ? "am" : "pm")
    }

    /// Hand-rolled rather than via `DateFormatter` so the two clock formats above
    /// cannot drift on the hour-12 rollover, which is the part that gets it wrong.
    private static func twelveHour(
        _ date: Date, timeZone: TimeZone
    ) -> (hour12: Int, minute: Int, isAM: Bool) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return (h % 12 == 0 ? 12 : h % 12, m, h < 12)
    }

    /// A span, for slots that describe a length of time rather than an age.
    /// `duration` returns "just now" under a minute, which reads as nonsense under
    /// a label like "Sleep" — this returns a dash for nothing and minutes otherwise.
    public static func spanned(_ seconds: TimeInterval) -> String {
        guard let total = roundedNonnegative(seconds) else { return "—" }
        if total <= 0 { return "—" }
        if total < 60 { return "under a minute" }
        return duration(seconds)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        guard let total = roundedNonnegative(seconds) else { return "—" }
        guard total >= 60 else { return "just now" }
        let minutes = total / 60
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Elapsed since an instant, clamped at zero.
    ///
    /// A future timestamp reads "just now" rather than a negative. The web version
    /// clamped the same way but then let the *warning* logic see the negative,
    /// which suppressed the overdue-feed alert for the rest of the night — so
    /// callers must check for the future explicitly, not rely on this.
    public static func ago(_ date: Date, now: Date) -> String {
        duration(max(0, now.timeIntervalSince(date)))
    }

    /// "Thu, 4 Sep" — how a past night is named in a list.
    public static func nightOf(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "Saturday, September 6" — the date under the header clock.
    ///
    /// Written out rather than abbreviated. The PWA used "Sat, Sep 6" in an
    /// 11-pixel line nobody read; this one is the answer to "what night is this?",
    /// which is a question worth a whole word at 4am when two nights have run
    /// together.
    public static func longDate(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Millilitres are canonical in storage; ounces are a display choice.
    public static func amount(ml: Double, unit: VolumeUnit) -> String {
        guard let rounded = roundedNonnegative(ml) else { return "—" }
        switch unit {
        case .ml: return "\(rounded) ml"
        case .oz:
            // Direct entry need not sit on the stepper's half-ounce grid.
            if ml > 0 && ml / 29.5735 < 0.005 { return "<0.01 oz" }
            let value = (ml / 29.5735).formatted(
                .number.locale(Locale(identifier: "en_US_POSIX"))
                    .grouping(.never).precision(.fractionLength(0...2)))
            return "\(value) oz"
        }
    }

    /// A summed volume, rounded once at display.
    public static func amountTotal(ml: Double, unit: VolumeUnit) -> String {
        guard let rounded = roundedNonnegative(ml) else { return "—" }
        switch unit {
        case .ml: return "\(rounded) ml"
        case .oz: return String(format: "%.1f oz", ml / 29.5735)
        }
    }

    public static func feedMethod(_ method: FeedMethod) -> String {
        switch method {
        case .breast: return "Breast"
        case .bottleBreastmilk: return "Bottle · breastmilk"
        case .bottleFormula: return "Bottle · formula"
        case .unknown: return "Feed"
        }
    }

    /// "L 8m, R 6m" — or one side alone when only one was used.
    public static func sides(left: Int?, right: Int?) -> String? {
        var parts: [String] = []
        if let l = left, l > 0 { parts.append("L \(duration(TimeInterval(l)))") }
        if let r = right, r > 0 { parts.append("R \(duration(TimeInterval(r)))") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Weight in the unit system implied by the family's volume unit — a household
    /// working in ounces expects pounds and ounces, not grams.
    public static func weight(grams: Double, unit: VolumeUnit) -> String {
        guard let rounded = roundedNonnegative(grams) else { return "—" }
        switch unit {
        case .ml:
            return grams >= 1000
                ? String(format: "%.2f kg", grams / 1000)
                : "\(rounded) g"
        case .oz:
            let totalOz = grams / 28.3495
            let pounds = Int(totalOz / 16)
            let ounces = totalOz - Double(pounds) * 16
            return pounds > 0
                ? "\(pounds) lb " + String(format: "%.1f oz", ounces)
                : String(format: "%.1f oz", ounces)
        }
    }

    public static func temp(_ f: Double) -> String {
        guard f.isFinite else { return "—" }
        return String(format: "%.1f°F", f)
    }

    public static func stool(_ colour: StoolColor) -> String {
        colour.rawValue.capitalized
    }

    public static func diaper(_ contents: DiaperContents) -> String {
        switch contents {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Wet + dirty"
        case .unknown: return "Diaper"
        }
    }

    /// The same contents, named as a thing rather than as an adjective — for a
    /// timeline row, where "Wet" on its own is a word with no subject and reads as
    /// a state of the baby rather than a record of a change.
    ///
    /// Kept separate from `diaper(_:)` rather than folded into it: the handoff
    /// already builds "wet diaper" by lowercasing that one and appending the noun,
    /// and a noun baked in at the source would give the parents "wet diaper diaper".
    public static func diaperRecord(_ contents: DiaperContents) -> String {
        contents == .unknown ? "Diaper" : diaper(contents) + " diaper"
    }
}
