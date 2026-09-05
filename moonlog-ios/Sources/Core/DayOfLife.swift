import Foundation

public enum DayOfLife {

    /// Clinical convention: the birth day is Day 1, rolling at midnight — not
    /// completed 24-hour blocks. See `docs/decisions.md`.
    public static func calendarDay(birthAt: Date, asOf: Date, calendar: Calendar) -> Int {
        let birthDay = calendar.startOfDay(for: birthAt)
        let day = calendar.startOfDay(for: asOf)
        let elapsed = calendar.dateComponents([.day], from: birthDay, to: day).day ?? 0
        // Clamped so a timestamp before birth (a mis-set clock, a bad import)
        // reads as Day 1 rather than zero or negative.
        return max(1, elapsed + 1)
    }

    /// Pinned to the shift's start, so the number cannot change mid-shift and make
    /// a handoff self-inconsistent.
    public static func calendarDay(
        birthAt: Date,
        forShift shift: ShiftWindow,
        calendar: Calendar
    ) -> Int {
        calendarDay(birthAt: birthAt, asOf: shift.startedAt, calendar: calendar)
    }

    /// Absolute hours — what matters in the first 48, and DST-immune by construction.
    public static func hours(birthAt: Date, asOf: Date) -> Double {
        max(0, asOf.timeIntervalSince(birthAt)) / 3600
    }
}
