import Foundation

/// Display formatting. Lives in Core so the handoff text and the UI cannot drift
/// apart — both render the same night and must agree.
public enum Fmt {

    /// "1h 23m" / "48m" / "just now".
    ///
    /// Rounds once, at the point of display — everything upstream carries seconds.
    /// Zero-padded register for documents: "9h 09m". Used by the handoff header.
    public static func paddedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds).rounded()) / 60
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Compact clock for dense rows: "3:12a".
    public static func shortClock(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d%@", hour12, m, h < 12 ? "a" : "p")
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
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

    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Millilitres are canonical in storage; ounces are a display choice.
    public static func amount(ml: Double, unit: VolumeUnit) -> String {
        switch unit {
        case .ml:
            return "\(Int(ml.rounded())) ml"
        case .oz:
            // Nearest half, trailing .0 trimmed — a 2oz bottle reads "2 oz", not
            // "2.0 oz". This appears in the parents' handoff.
            let oz = (ml / 29.5735 * 2).rounded() / 2
            return oz == oz.rounded()
                ? "\(Int(oz)) oz"
                : String(format: "%.1f oz", oz)
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
        switch unit {
        case .ml:
            return grams >= 1000
                ? String(format: "%.2f kg", grams / 1000)
                : "\(Int(grams.rounded())) g"
        case .oz:
            let totalOz = grams / 28.3495
            let pounds = Int(totalOz / 16)
            let ounces = totalOz - Double(pounds) * 16
            return pounds > 0
                ? String(format: "%d lb %.1f oz", pounds, ounces)
                : String(format: "%.1f oz", ounces)
        }
    }

    public static func diaper(_ contents: DiaperContents) -> String {
        switch contents {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Wet + dirty"
        case .unknown: return "Diaper"
        }
    }
}
