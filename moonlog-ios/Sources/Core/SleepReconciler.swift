import Foundation

public struct ReconcileResult: Sendable, Equatable {
    /// The repaired sessions, ordered by start.
    public let sessions: [SleepSnapshot]
    /// Sessions absorbed into an earlier one as a duplicate tap.
    public let mergedAway: [UUID]
    /// Sessions that were given (or had corrected) an end time.
    public let repairedEnds: [UUID]
}

public enum SleepReconciler {

    /// Repairs a baby's sleep sessions into a consistent, non-overlapping sequence.
    ///
    /// This is not defensive padding — it is required. CloudKit cannot enforce
    /// uniqueness, so two devices can both open a session for the same baby, and
    /// the store will accept both. The UI would then show one while the other
    /// accrued invisibly.
    ///
    /// The output must not depend on arrival order: two devices reconciling the
    /// same set must reach the same answer, or they will fight. Everything is
    /// therefore sorted first, with a total tie-break on id.
    ///
    /// Rules, in order:
    /// - Sessions starting within `mergeWindow` of each other are the same tap
    ///   double-registered. Collapse into the earlier; the result stays open if
    ///   either was open.
    /// - A session still open when a later one begins was never closed. Close it
    ///   where the next begins, rather than letting two run at once.
    /// - A session overlapping the next is truncated to the next one's start.
    public static func reconcile(
        _ sessions: [SleepSnapshot],
        forBaby babyID: UUID,
        mergeWindow: TimeInterval = 120
    ) -> ReconcileResult {
        let ordered = sessions
            .filter { $0.babyID == babyID }
            .sorted {
                $0.startAt == $1.startAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.startAt < $1.startAt
            }

        var result: [SleepSnapshot] = []
        var mergedAway: [UUID] = []
        var repairedEnds: [UUID] = []

        for session in ordered {
            guard let previous = result.last else {
                result.append(session)
                continue
            }

            if session.startAt.timeIntervalSince(previous.startAt) <= mergeWindow {
                // Same tap registered twice. Keep the earlier identity so the merge
                // is stable across devices; stay open if either side was open.
                let end: Date?
                if previous.endAt == nil || session.endAt == nil {
                    end = nil
                } else {
                    end = max(previous.endAt!, session.endAt!)
                }
                result[result.count - 1] = SleepSnapshot(
                    id: previous.id, babyID: previous.babyID,
                    startAt: previous.startAt, endAt: end)
                mergedAway.append(session.id)
                continue
            }

            let needsEnd = previous.endAt == nil
            let overlaps = (previous.endAt ?? .distantPast) > session.startAt
            if needsEnd || overlaps {
                result[result.count - 1] = SleepSnapshot(
                    id: previous.id, babyID: previous.babyID,
                    startAt: previous.startAt, endAt: session.startAt)
                repairedEnds.append(previous.id)
            }
            result.append(session)
        }

        return ReconcileResult(
            sessions: result,
            mergedAway: mergedAway.sorted { $0.uuidString < $1.uuidString },
            repairedEnds: repairedEnds.sorted { $0.uuidString < $1.uuidString })
    }
}
