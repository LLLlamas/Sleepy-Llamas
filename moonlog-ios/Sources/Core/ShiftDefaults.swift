import Foundation

/// A family's usual shift hours, held as minutes from local midnight.
///
/// Minutes rather than a stored `Date` because the window is a *wall-clock* fact:
/// 22:00 is 22:00 in both halves of the year, and an absolute instant would drift by
/// an hour — or by thirty minutes on Lord Howe — every time the zone transitions.
public struct ShiftWindowDefault: Sendable, Hashable {
    /// Minutes from local midnight, wrapped into `0..<1440`.
    public let startMinute: Int
    public let endMinute: Int

    public static let minutesPerDay = 1440

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = Self.wrapped(startMinute)
        self.endMinute = Self.wrapped(endMinute)
    }

    /// `%` keeps the sign of its dividend, so a bare `minute % 1440` leaves `-60` at
    /// `-60` and names an hour that does not exist. Wrapped once here, at the only
    /// door in, so nothing downstream has to re-check.
    public static func wrapped(_ minute: Int) -> Int {
        let remainder = minute % minutesPerDay
        return remainder < 0 ? remainder + minutesPerDay : remainder
    }

    /// Crossing midnight is expressed by `end <= start` rather than a flag — a flag
    /// is a field that can contradict the two it describes.
    public var crossesMidnight: Bool { endMinute <= startMinute }

    /// Wraps. 1440 when the two are equal: a window that starts and ends on the same
    /// minute is a whole day, not nothing.
    ///
    /// **Wall-clock minutes, deliberately.** This is what the window is *called*, not
    /// how long it physically lasts — on a transition night 22:00→06:00 runs seven or
    /// nine hours. Never add this to a `Date` to find an end; that is what
    /// `suggestedEnd` is for.
    public var durationMinutes: Int {
        let span = endMinute - startMinute
        return span > 0 ? span : span + Self.minutesPerDay
    }
}

/// Prefills for the shift pickers, and nothing else. Nothing here is ever written to a
/// record on its own: start and end stay values the doula sets or confirms, which is
/// why `CareStore.startShift` still takes the time it is given. See
/// `docs/architecture.md`, "The shift lifecycle".
public enum ShiftDefaults {

    /// The occurrence of the window's start nearest to `now`, or `nil` when no nearby
    /// occurrence is plausible — in which case the caller should prefill `now` itself.
    ///
    /// Two ways to be implausible, and both matter:
    ///
    /// * **More than half the window in the past.** Arriving at 04:00 must not prefill
    ///   22:00 and credit the parents six hours nobody watched. That is the bug
    ///   `ShiftHoursSheet`'s docstring exists to prevent, reaching the same window
    ///   through the front door instead of the back.
    /// * **Meaningfully in the future.** `CareStore.rejectFuture` judges this exact
    ///   value against this exact threshold, so a prefill past it would put a Start
    ///   button on screen that cannot succeed.
    ///
    /// The second rule is why arriving at 21:50 also yields `nil` rather than 22:00,
    /// which is intended and should not be "fixed" by widening the slack: falling back
    /// to `now` prefills 21:50, recording when she actually started rather than
    /// crediting ten minutes she was not there for. She can scroll to 22:00 if the
    /// billing window is what she wants — the point is that the app never picks it for
    /// her.
    public static func suggestedStart(
        _ window: ShiftWindowDefault,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let nearest = nearestOccurrence(of: window.startMinute, to: now, calendar: calendar)
        else { return nil }

        let secondsBefore = now.timeIntervalSince(nearest)
        guard secondsBefore <= Double(window.durationMinutes) * 60 / 2 else { return nil }
        guard !nearest.isMeaningfullyInFuture(asOf: now) else { return nil }

        return nearest
    }

    /// The first occurrence of `endMinute` strictly after `start`.
    ///
    /// Resolved by calendar, never by adding `durationMinutes`: 22:00→06:00 is eight
    /// hours *on the clock*, which is seven physical hours on a spring-forward night
    /// and nine on a fall-back one. Adding `8 * 3600` would land 05:00 or 07:00 — the
    /// wrong wall-clock time, on the one night of the year anybody would notice.
    public static func suggestedEnd(
        _ window: ShiftWindowDefault,
        after start: Date,
        calendar: Calendar
    ) -> Date {
        let resolved = calendar.nextDate(
            after: start,
            matching: DateComponents(hour: window.endMinute / 60, minute: window.endMinute % 60),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward)

        // Unreachable in practice — an hour and minute recur within two days in every
        // zone — and therefore untested. It exists because the signature promises a
        // Date, not because a case is known that reaches it.
        return resolved
            ?? calendar.date(byAdding: .minute, value: window.durationMinutes, to: start)
            ?? start
    }

    /// The occurrence of `minute` nearest `now`, searched across yesterday, today and
    /// tomorrow in the calendar's own zone.
    ///
    /// Day-stepping plus `date(bySettingHour:)` rather than a backward
    /// `nextDate(after:direction:)`, for two behaviours **observed on this machine**
    /// rather than assumed:
    ///
    /// * A backward `nextDate` is strictly *before* its anchor, so asked at exactly
    ///   22:00 it answers yesterday's 22:00. Stepping days includes today's occurrence
    ///   without needing a nudge on the anchor.
    /// * `repeatedTimePolicy: .first` follows the *search direction*. On 2026-11-01 in
    ///   New York, where 01:30 happens twice, a forward search returns 01:30 EDT and a
    ///   backward search returns 01:30 EST — so a prev/next pair would disagree about
    ///   which instant "the first" names. `date(bySettingHour:)` returns the EDT one
    ///   either way, which is what pinning the policy was for: two devices agreeing.
    ///
    /// `matchingPolicy: .nextTime` resolves a start minute that names a local time
    /// which does not exist. **It does not always resolve it within the same day**, and
    /// that too is observed: on 2026-03-08 in New York, where 02:00–02:59 is missing,
    /// 02:00 resolves forward to 03:00 EDT as you would hope — but on 2026-10-04 on
    /// Lord Howe, where only 02:00–02:29 is missing, 02:00 resolves to *the next day*
    /// rather than to 02:30. The nearest occurrence is then a day away, the plausibility
    /// rules in `suggestedStart` reject it, and the picker prefills `now`. No prefill
    /// beats a wrong one, so this is left as it is rather than hand-rolling gap-end
    /// arithmetic for one minute of one night a year.
    private static func nearestOccurrence(
        of minute: Int,
        to now: Date,
        calendar: Calendar
    ) -> Date? {
        let candidates = (-1...1).compactMap { dayOffset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now)
            else { return nil }
            return calendar.date(
                bySettingHour: minute / 60,
                minute: minute % 60,
                second: 0,
                of: day,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward)
        }
        return candidates.min {
            abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now))
        }
    }
}
