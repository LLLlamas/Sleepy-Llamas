import Foundation

/// The single source of "now" and of calendar arithmetic for the domain layer.
///
/// Nothing in `MoonlogCore` may touch `Date.now` or `Calendar.current` directly.
/// Two reasons, both learned from the web version:
///
/// 1. `now` is injectable, so a test can pin an instant and walk minute-by-minute
///    across a DST transition. The PWA's time bugs were untestable largely because
///    `new Date()` was called inline everywhere.
/// 2. The calendar carries the **family's home** time zone, not the device's. A
///    doula whose phone is in another zone must not retroactively rebucket months
///    of a client's charts.
public struct MoonClock: Sendable {
    public let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    public init(
        timeZoneIdentifier: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        var calendar = Calendar(identifier: .gregorian)
        // Falling back to GMT rather than `.current` is deliberate. An unrecognised
        // identifier is a data problem; silently adopting the device zone would
        // hide it and make the charts quietly wrong instead of visibly wrong.
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        self.calendar = calendar
        self.nowProvider = now
    }

    public var now: Date { nowProvider() }

    public var timeZone: TimeZone { calendar.timeZone }

    /// Start of the calendar day containing `date`, in this clock's zone.
    ///
    /// Use this instead of zeroing out hour/minute components. On a DST
    /// transition day local midnight is not always "the instant minus the
    /// wall-clock time", which is precisely the bug in the web version's
    /// `setHours(0, 0, 0, 0)` day-difference math.
    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Whole calendar days from `start`'s day to `end`'s day.
    ///
    /// Both endpoints are anchored to `startOfDay` first — that anchoring is what
    /// makes the result immune to 23- and 25-hour days. Never compute this by
    /// dividing a time interval by 86,400.
    public func calendarDays(from start: Date, to end: Date) -> Int {
        let a = startOfDay(for: start)
        let b = startOfDay(for: end)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
