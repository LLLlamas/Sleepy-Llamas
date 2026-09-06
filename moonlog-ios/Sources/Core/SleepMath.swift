import Foundation

public enum SleepMath {

    /// The portion of `session` counting toward `shift`.
    ///
    /// **An open session inside a closed shift runs only to the shift's end, never
    /// to `now`** — otherwise an archived shift's total grows forever. Clipping
    /// rather than closing keeps "still asleep when I left" honest, and absorbs
    /// back-dated strays. See `docs/architecture.md`.
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

    /// Sums seconds; rounding belongs to the display layer. Rounding each session
    /// first drifts a night's total by minutes.
    public static func totalSeconds(
        of sessions: [SleepSnapshot],
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> TimeInterval {
        sessions.reduce(0) { $0 + seconds(of: $1, clippedTo: shift, asOf: now) }
    }

    /// Per baby: with twins these are per-baby questions, not per-shift.
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

    /// Earliest start wins, so a duplicate delivered by sync resolves identically
    /// on every device.
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

    /// When this baby last woke: the latest `endAt` across their closed sessions.
    ///
    /// There is no awake session to read — awake is the absence of an open sleep —
    /// so the only honest answer is the end of the last sleep. `nil` when they have
    /// not slept in `sessions` at all, which is the ordinary state at the start of a
    /// shift. The caller shows nothing rather than naming a time it is guessing:
    /// the doula arrives mid-evening and has no idea when this baby last woke.
    ///
    /// An open session is skipped rather than treated as ending now. If one is open
    /// the baby is asleep, and `openSession` is the question being asked.
    public static func lastWake(
        in sessions: [SleepSnapshot],
        forBaby babyID: UUID
    ) -> Date? {
        sessions
            .filter { $0.babyID == babyID }
            .compactMap(\.endAt)
            .max()
    }
}
