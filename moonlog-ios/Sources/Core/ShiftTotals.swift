import Foundation

/// The numbers that appear on the Summary screen and in the handoff given to the
/// parents. Durations are held in **seconds** and rounded only at display.
public struct ShiftTotals: Sendable, Equatable {
    public var feeds: Int = 0
    public var feedMl: Double = 0
    public var feedSeconds: TimeInterval = 0

    public var diapers: Int = 0
    public var wet: Int = 0
    public var dirty: Int = 0
    /// Distinct stool colours seen, in the order they first appeared. Whether
    /// meconium has cleared is a clinical marker, so first-seen order is the
    /// meaningful ordering.
    public var stoolProgression: [StoolColor] = []

    public var sleepSeconds: TimeInterval = 0
    /// Sessions that actually contributed time to this shift. The web version
    /// counted every session handed to it, including ones clipped away to nothing.
    public var stretches: Int = 0
    public var longestStretchSeconds: TimeInterval = 0

    public var notes: Int = 0
    /// Any temperature at or above this is flagged. Matches the PWA's threshold.
    public static let feverThresholdF: Double = 100.4
    public var highestTempF: Double?

    public var hasFever: Bool {
        guard let t = highestTempF else { return false }
        return t >= Self.feverThresholdF
    }
}

public enum Totals {

    /// Totals for one baby across one shift.
    ///
    /// Everything is clipped to the shift window, so a back-dated entry or a sleep
    /// session left open at the end contributes only the part that belongs to this
    /// shift — see `SleepMath.interval(of:clippedTo:asOf:)`.
    public static func compute(
        events: [EventSnapshot],
        sessions: [SleepSnapshot],
        forBaby babyID: UUID,
        shift: ShiftWindow,
        asOf now: Date
    ) -> ShiftTotals {
        var totals = ShiftTotals()
        guard let window = shift.interval(asOf: now) else { return totals }

        // Sorted so `stoolProgression` records genuine first-appearance order
        // rather than whatever order the store handed back.
        let relevant = events
            .filter { $0.babyID == babyID && window.contains($0.at) }
            .sorted { $0.at < $1.at }

        for event in relevant {
            switch event.kind {
            case .feed:
                totals.feeds += 1
                totals.feedMl += event.amountMl ?? 0
                totals.feedSeconds += TimeInterval(event.feedDurationSeconds ?? 0)
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
