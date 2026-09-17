import Foundation
import MoonlogCore

/// Builds the merged, reverse-chronological rows for a shift.
///
/// Shared by Tonight and by a past night's detail so the two cannot drift — a
/// history screen that renders yesterday differently from how tonight looked would
/// undermine the whole point of keeping the record.
enum ShiftTimeline {

    /// No `timeZone` here any more: every clock on a row is now set by
    /// `TimelineSection`, which already has the zone it renders in. Formatting a
    /// time in one place and the rest in another is how the two drifted.
    static func entries(
        for shift: Shift,
        unit: VolumeUnit,
        now: Date,
        editable: Bool
    ) -> [TimelineEntry] {
        let events = shift.liveEvents
        let sessions = shift.liveSleepSessions
        var out: [TimelineEntry] = []
        out.reserveCapacity(events.count + sessions.count)

        for event in events {
            out.append(
                TimelineEntry(
                    id: event.id, at: event.at, endAt: event.timelineEndAt,
                    babyID: event.babyIDRaw,
                    icon: event.kind.icon,
                    title: event.timelineTitle(unit: unit),
                    detail: event.timelineDetail(unit: unit),
                    // Every kind has its own edit sheet now. A pump carries no
                    // baby, so it routes with a nil one rather than staying inert —
                    // which is what kept pumps, medications and weights
                    // uncorrectable once logged.
                    edit: editable
                        ? .editEvent(id: event.id, babyID: event.babyIDRaw)
                        : nil))
        }

        for session in sessions {
            // Start, wake and how long it lasted — the row gave a duration alone, so
            // it said 2h 33m without ever saying until when. Clipped to the shift,
            // like Totals: an unclipped duration made the timeline and the Summary
            // disagree about one sleep.
            //
            // The two clocks go on the trailing edge and only the length stays in
            // the subtitle, so `sleepLength` rather than the `sleepTail` sentence the
            // two documents print. A stretch still running has no wake to name: its
            // `end` is only where the clip fell, so it passes no `endAt` and the
            // subtitle says "still asleep" instead.
            let stretch = session.snapshot.flatMap {
                SleepMath.stretch(of: $0, clippedTo: shift.window, asOf: now)
            }
            let woke = stretch.flatMap { $0.isOpen ? nil : $0.end }
            out.append(
                TimelineEntry(
                    id: session.id, at: session.startAt, endAt: woke,
                    babyID: session.babyIDRaw,
                    icon: "moon.zzz.fill", title: "Asleep",
                    detail: stretch.map(Handoff.sleepLength),
                    edit: editable
                        ? session.babyIDRaw.map { .editSleep(id: session.id, babyID: $0) }
                        : nil))
        }

        // Tie-broken on id: Swift's sort is not stable, so two records sharing an
        // instant could otherwise swap places between renders.
        out.sort { $0.at == $1.at ? $0.id.uuidString < $1.id.uuidString : $0.at > $1.at }
        return out
    }
}
