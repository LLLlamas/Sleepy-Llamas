import Foundation

public enum DayBuckets {

    /// Day intervals covering `range`. Lengths are genuinely 23/24/24.5/25 hours as
    /// the zone dictates — never assume 86,400.
    public static func days(covering range: DateInterval, calendar: Calendar) -> [DateInterval] {
        guard range.duration >= 0 else { return [] }
        var result: [DateInterval] = []
        var cursor = calendar.startOfDay(for: range.start)

        while cursor < range.end {
            guard let day = calendar.dateInterval(of: .day, for: cursor) else { break }
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day.start),
                  next > cursor else { break }   // guards a non-advancing cursor
            cursor = next
        }
        // A zero-length range still belongs to the day containing it.
        if result.isEmpty, let day = calendar.dateInterval(of: .day, for: range.start) {
            result.append(day)
        }
        return result
    }

    /// Half-open: `DateInterval.contains` is closed at both ends, so a midnight
    /// event would land in two adjacent buckets.
    public static func day(_ day: DateInterval, contains date: Date) -> Bool {
        date >= day.start && date < day.end
    }

    public static func events(
        _ events: [EventSnapshot],
        in day: DateInterval
    ) -> [EventSnapshot] {
        events.filter { self.day(day, contains: $0.at) }
    }

    /// **Clipped, not assigned** — a 22:00–06:00 stretch gives two hours to one day
    /// and six to the next. The shift bounds it first, so an open session cannot
    /// leak past the shift's end.
    public static func sleepSeconds(
        of session: SleepSnapshot,
        in day: DateInterval,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> TimeInterval {
        guard let withinShift = SleepMath.interval(of: session, clippedTo: shift, asOf: now)
        else { return 0 }
        return withinShift.intersection(with: day)?.duration ?? 0
    }

    public static func sleepSeconds(
        of sessions: [SleepSnapshot],
        forBaby babyID: UUID,
        in day: DateInterval,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> TimeInterval {
        sessions
            .filter { $0.babyID == babyID }
            .reduce(0) { $0 + sleepSeconds(of: $1, in: day, clippedTo: shift, asOf: now) }
    }
}
