import Foundation

public enum SleepMath {

    /// The portion of `session` that counts toward `shift`.
    ///
    /// The rule that matters: **an open session inside a closed shift runs only to
    /// the shift's end, never to `now`.** In the web version an open session kept
    /// accruing against the current time forever, so reopening a week-old handoff
    /// claimed the baby had slept 168 hours.
    ///
    /// Clipping rather than closing the session is deliberate. A doula finishes by
    /// leaving the baby with the parents, often still asleep — so "asleep since
    /// 5:40, still asleep when I left" is the honest record, and the shift should
    /// account for the minutes she was actually there and no more.
    ///
    /// Clipping also absorbs back-dated entries that stray outside the shift: they
    /// contribute their overlap and nothing more, instead of silently crediting one
    /// shift with another's hours.
    public static func interval(
        of session: SleepSnapshot,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> DateInterval? {
        guard let window = shift.interval(asOf: now) else { return nil }

        // An open session is bounded by the window, not by `now`.
        let rawEnd = session.endAt ?? window.end
        // A malformed record (end before start) contributes nothing rather than
        // trapping in DateInterval's initialiser.
        guard rawEnd >= session.startAt else { return nil }

        return DateInterval(start: session.startAt, end: rawEnd)
            .intersection(with: window)
    }

    public static func seconds(
        of session: SleepSnapshot,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> TimeInterval {
        interval(of: session, clippedTo: shift, asOf: now)?.duration ?? 0
    }

    /// Total sleep across a shift.
    ///
    /// Sums seconds and leaves rounding to the display layer. The web version
    /// rounded each session to whole minutes and *then* summed, which drifts a
    /// night's total by several minutes across eight stretches.
    public static func totalSeconds(
        of sessions: [SleepSnapshot],
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> TimeInterval {
        sessions.reduce(0) { $0 + seconds(of: $1, clippedTo: shift, asOf: now) }
    }

    /// Sleep for one baby only. With twins, "is she asleep" and "how long has she
    /// slept" are per-baby questions — the web version could only ask them per
    /// shift, which is what multi-baby support invalidates.
    public static func totalSeconds(
        of sessions: [SleepSnapshot],
        forBaby babyID: UUID,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> TimeInterval {
        totalSeconds(
            of: sessions.filter { $0.babyID == babyID },
            clippedTo: shift,
            asOf: now
        )
    }

    /// The open session for a baby, if any. Deterministic when the data is briefly
    /// inconsistent — CloudKit can deliver two open sessions for one baby and no
    /// schema constraint can prevent it, so pick the earliest start rather than
    /// whichever arrived first.
    public static func openSession(
        in sessions: [SleepSnapshot],
        forBaby babyID: UUID
    ) -> SleepSnapshot? {
        sessions
            .filter { $0.babyID == babyID && $0.isOpen }
            .min { lhs, rhs in
                lhs.startAt == rhs.startAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.startAt < rhs.startAt
            }
    }
}
