import Foundation
import MoonlogCore

enum Fmt {

    /// "1h 23m" / "48m" / "just now".
    ///
    /// Rounds once, at the point of display — everything upstream carries seconds.
    static func duration(_ seconds: TimeInterval) -> String {
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
    static func ago(_ date: Date, now: Date) -> String {
        duration(max(0, now.timeIntervalSince(date)))
    }

    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Millilitres are canonical in storage; ounces are a display choice.
    static func amount(ml: Double, unit: VolumeUnit) -> String {
        switch unit {
        case .ml:
            return "\(Int(ml.rounded())) ml"
        case .oz:
            let oz = ml / 29.5735
            return String(format: "%.1f oz", oz)
        }
    }

    static func feedMethod(_ method: FeedMethod) -> String {
        switch method {
        case .breastLeft: return "Left breast"
        case .breastRight: return "Right breast"
        case .bottleBreastmilk: return "Bottle · breastmilk"
        case .bottleFormula: return "Bottle · formula"
        case .unknown: return "Feed"
        }
    }

    static func diaper(_ contents: DiaperContents) -> String {
        switch contents {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Wet + dirty"
        case .unknown: return "Diaper"
        }
    }
}

enum VolumeUnit: String, CaseIterable, Sendable {
    case ml, oz
}
