import Foundation

/// One stretch of sleep as it counts toward a shift: when it began, when it ended,
/// and how long that was.
///
/// Dates rather than formatted strings, because the timeline writes "1:15 AM" and
/// the documents "1:15a" — and the thing that must not exist twice is the *clipping*
/// rule, not the clock format. Before this the timeline showed a duration alone, so
/// a row said a baby slept 2h 33m without saying until when.
public struct SleepStretch: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let start: Date
    /// Where the stretch stops counting. On an open session this is where the clip
    /// fell — the shift's end, or now — so `isOpen` guards printing it as a waking.
    public let end: Date
    public let isOpen: Bool

    public var seconds: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID, start: Date, end: Date, isOpen: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.isOpen = isOpen
    }
}

public enum SleepMath {

    /// The clipped stretch, or `nil` when the session contributed no time to the
    /// shift. Every caller that wants to *describe* a sleep goes through this;
    /// `interval` and `seconds` remain for the ones that only need to add it up.
    public static func stretch(
        of session: SleepSnapshot,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> SleepStretch? {
        guard let span = interval(of: session, clippedTo: shift, asOf: now),
              span.duration > 0 else { return nil }
        return SleepStretch(
            id: session.id, start: span.start, end: span.end, isOpen: session.isOpen)
    }

    /// Every stretch one baby slept during the shift, oldest first.
    public static func stretches(
        of sessions: [SleepSnapshot],
        forBaby babyID: UUID,
        clippedTo shift: ShiftWindow,
        asOf now: Date
    ) -> [SleepStretch] {
        sessions
            .filter { $0.babyID == babyID }
            .compactMap { stretch(of: $0, clippedTo: shift, asOf: now) }
            .sorted { $0.start < $1.start }
    }

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
        lastCompleted(in: sessions, forBaby: babyID)?.endAt
    }

    /// The whole of this baby's most recently finished sleep, not just its end.
    ///
    /// The card names both ends of it once the baby is awake again — "3:42a–4:22a"
    /// is the fact a doula reads off to the parents, and it was previously only
    /// recoverable by scrolling the timeline. Ties on `endAt` break on id, for the
    /// same reason `openSession` does.
    public static func lastCompleted(
        in sessions: [SleepSnapshot],
        forBaby babyID: UUID
    ) -> SleepSnapshot? {
        sessions
            .filter { $0.babyID == babyID && $0.endAt != nil }
            .max { lhs, rhs in
                lhs.endAt == rhs.endAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : (lhs.endAt ?? .distantPast) < (rhs.endAt ?? .distantPast)
            }
    }
}
