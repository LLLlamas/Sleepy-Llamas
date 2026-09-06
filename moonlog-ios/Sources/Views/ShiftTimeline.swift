import Foundation
import MoonlogCore

/// Builds the merged, reverse-chronological rows for a shift.
///
/// Shared by Tonight and by a past night's detail so the two cannot drift — a
/// history screen that renders yesterday differently from how tonight looked would
/// undermine the whole point of keeping the record.
enum ShiftTimeline {

    static func entries(
        for shift: Shift,
        unit: VolumeUnit,
        now: Date,
        editable: Bool
    ) -> [TimelineEntry] {
        let events = shift.events ?? []
        let sessions = shift.sleepSessions ?? []
        var out: [TimelineEntry] = []
        out.reserveCapacity(events.count + sessions.count)

        for event in events {
            out.append(
                TimelineEntry(
                    id: event.id, at: event.at, babyID: event.babyIDRaw,
                    icon: event.kind.icon,
                    title: event.timelineTitle(unit: unit),
                    detail: event.timelineDetail(unit: unit),
                    // Only the three core kinds have edit sheets. Routing a pump or
                    // a weight here opened a note sheet against it, which could
                    // write note fields onto a record that never renders them.
                    edit: editable && EventKind.core.contains(event.kind)
                        ? event.babyIDRaw.map { .editEvent(id: event.id, babyID: $0) }
                        : nil))
        }

        for session in sessions {
            out.append(
                TimelineEntry(
                    id: session.id, at: session.startAt, babyID: session.babyIDRaw,
                    icon: "moon.zzz.fill", title: "Asleep",
                    // Clipped to the shift, like Totals — an unclipped duration made
                    // the timeline and the Summary disagree about one sleep.
                    detail: session.isOpen
                        ? "still asleep"
                        : session.snapshot.map {
                            Fmt.duration(
                                SleepMath.seconds(of: $0, clippedTo: shift.window, asOf: now))
                        } ?? nil,
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
