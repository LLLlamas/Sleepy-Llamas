import Foundation

/// The numbers on the Summary screen and in the parents' handoff. Durations are in
/// seconds, rounded only at display.
public struct ShiftTotals: Sendable, Equatable {
    public var feeds: Int = 0
    public var feedMl: Double = 0
    public var feedSeconds: TimeInterval = 0
    /// Time at the breast, both sides combined.
    public var breastSeconds: TimeInterval = 0

    public var diapers: Int = 0
    public var wet: Int = 0
    public var dirty: Int = 0
    /// Distinct colours in first-seen order — meconium clearing is the marker.
    public var stoolProgression: [StoolColor] = []

    public var sleepSeconds: TimeInterval = 0
    /// Only sessions that actually contributed time.
    public var stretches: Int = 0
    public var longestStretchSeconds: TimeInterval = 0

    public var notes: Int = 0

    // Optional kinds. Zero unless the family has them enabled.
    public var pumpedMl: Double = 0
    public var medications: Int = 0
    /// Most recent weight in the shift, if one was taken.
    public var latestWeightGrams: Double?
    /// Flagged at or above.
    public static let feverThresholdF: Double = 100.4
    public var highestTempF: Double?

    public var hasFever: Bool {
        guard let t = highestTempF else { return false }
        return t >= Self.feverThresholdF
    }
}

public enum Totals {

    /// Totals for one baby across one shift, everything clipped to the shift window.
    public static func compute(
        events: [EventSnapshot],
        sessions: [SleepSnapshot],
        forBaby babyID: UUID,
        shift: ShiftWindow,
        asOf now: Date
    ) -> ShiftTotals {
        var totals = ShiftTotals()
        guard let window = shift.interval(asOf: now) else { return totals }

        // Sorted so `stoolProgression` reflects genuine first appearance.
        // `pump` is about the mother and carries no baby, so it is counted for the
        // shift regardless of which baby's totals these are.
        let relevant = events
            .filter { window.contains($0.at) && ($0.babyID == babyID || $0.kind == .pump) }
            .sorted { $0.at < $1.at }

        for event in relevant {
            switch event.kind {
            case .feed:
                totals.feeds += 1
                totals.feedMl += event.amountMl ?? 0
                totals.feedSeconds += TimeInterval(event.feedDurationSeconds ?? 0)
                totals.breastSeconds += TimeInterval(event.breastSeconds ?? 0)
            case .diaper:
                totals.diapers += 1
                let contents = event.diaperContents ?? .unknown
                if contents.countsAsWet { totals.wet += 1 }
                if contents.countsAsDirty { totals.dirty += 1 }
                if let stool = event.stoolColor,
                   !totals.stoolProgression.contains(stool) {
                    totals.stoolProgression.append(stool)
                }
            case .note:
                totals.notes += 1
                if let temp = event.tempF {
                    totals.highestTempF = max(totals.highestTempF ?? temp, temp)
                }
            case .pump:
                totals.pumpedMl += event.pumpedMl ?? 0
            case .medication:
                totals.medications += 1
            case .measurement:
                // `relevant` is sorted ascending, so the last one wins.
                if let grams = event.weightGrams { totals.latestWeightGrams = grams }
            }
        }

        let contributions = sessions
            .filter { $0.babyID == babyID }
            .map { SleepMath.seconds(of: $0, clippedTo: shift, asOf: now) }
            .filter { $0 > 0 }

        totals.sleepSeconds = contributions.reduce(0, +)
        totals.stretches = contributions.count
        totals.longestStretchSeconds = contributions.max() ?? 0

        return totals
    }
}
