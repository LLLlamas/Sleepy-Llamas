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

    /// Repairs a baby's sessions into a non-overlapping sequence. Required, not
    /// defensive: sync can deliver two open sessions for one baby.
    ///
    /// Order-independent — two devices reaching different answers would fight — so
    /// everything is sorted first with a total tie-break on id.
    ///
    /// - Starts within `mergeWindow` are one double-registered tap; collapse into
    ///   the earlier, staying open if either was.
    /// - A session still open when a later one begins is closed at that start.
    /// - An overlapping session is truncated to the next one's start.
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
                // Keep the earlier identity so the merge is stable across devices.
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
