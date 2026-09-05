import Foundation

public enum DayOfLife {

    /// Calendar day of life, clinical convention: **the birth day is Day 1**, and
    /// the number rolls over at midnight.
    ///
    /// This differs from the web version, which counts completed 24-hour blocks and
    /// so reports "Day 0" for a baby ten hours old and rolls over at the birth
    /// *minute*. Neither matches how a pediatrician counts, and the minute-rollover
    /// means the same handoff text reports a different Day N depending on when it
    /// is copied.
    ///
    /// Both endpoints are anchored to `startOfDay` before differencing, which is
    /// what makes this immune to 23- and 25-hour days.
    public static func calendarDay(birthAt: Date, asOf: Date, calendar: Calendar) -> Int {
        let birthDay = calendar.startOfDay(for: birthAt)
        let day = calendar.startOfDay(for: asOf)
        let elapsed = calendar.dateComponents([.day], from: birthDay, to: day).day ?? 0
        // Clamped so a timestamp before birth (a mis-set clock, a bad import)
        // reads as Day 1 rather than zero or negative.
        return max(1, elapsed + 1)
    }

    /// Day of life for a shift, pinned to the shift's start.
    ///
    /// Because the doula sets the shift hours, the number shown must stay stable
    /// for the whole shift. Computing it against `now` is why the web version's
    /// header can change mid-shift and why its handoff is self-inconsistent.
    public static func calendarDay(
        birthAt: Date,
        forShift shift: ShiftWindow,
        calendar: Calendar
    ) -> Int {
        calendarDay(birthAt: birthAt, asOf: shift.startedAt, calendar: calendar)
    }

    /// Absolute hours since birth. What actually matters in the first 48 hours, and
    /// DST-immune by construction since both endpoints are absolute instants.
    public static func hours(birthAt: Date, asOf: Date) -> Double {
        max(0, asOf.timeIntervalSince(birthAt)) / 3600
    }
}
