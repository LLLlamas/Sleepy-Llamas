import Foundation

/// The single source of "now" and of calendar arithmetic. Nothing in `MoonlogCore`
/// touches `Date.now` or `Calendar.current` directly: `now` is injectable so DST can
/// be tested, and the calendar carries the family's home zone, not the device's.
public struct MoonClock: Sendable {
    public let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    public init(
        timeZoneIdentifier: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        var calendar = Calendar(identifier: .gregorian)
        // GMT, not `.current` — an unrecognised identifier is a data problem, and
        // adopting the device zone would hide it.
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        self.calendar = calendar
        self.nowProvider = now
    }

    public var now: Date { nowProvider() }

    public var timeZone: TimeZone { calendar.timeZone }

    /// Start of the calendar day, in this clock's zone. Use instead of zeroing
    /// hour/minute — on a transition day those are not equivalent.
    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Whole calendar days between two dates. Anchoring both endpoints to
    /// `startOfDay` is what makes this immune to 23- and 25-hour days.
    public func calendarDays(from start: Date, to end: Date) -> Int {
        let a = startOfDay(for: start)
        let b = startOfDay(for: end)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
