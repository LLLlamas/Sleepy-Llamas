import Foundation
import CryptoKit
import MoonlogCore

/// The source digest and the document use the same surviving records, roster and
/// clipped shift window. A published document never calls this renderer again.
enum DayReportComposer {
    struct Facts: Sendable {
        let fingerprint: String
        let text: String
    }

    static func facts(family: Family, shift: Shift) -> Facts {
        let text = renderText(family: family, shift: shift)
        let provenance = sourceProvenance(family: family, shift: shift)
        let components = provenance + [family.id.uuidString, family.name, shift.id.uuidString,
                          shift.careContext.rawValue, shift.caregiver ?? "",
                          shift.parentNote ?? "", family.timeZoneIdentifier, "report-facts-v1"]
        // Length prefixes avoid collisions caused by joining free-text fields on
        // a separator they can themselves contain. SHA256 is stable across launches.
        let bytes = components.reduce(into: Data()) { data, component in
            let value = Data(component.utf8)
            data.append(Data("\(value.count):".utf8)); data.append(value)
        }
        return Facts(fingerprint: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), text: text)
    }

    static func text(family: Family, shift: Shift, draft: DayReportDraft, version: Int, publishedAt: Date) -> String {
        let notes = narrative(draft)
        return "Nanny Log · End-of-day handoff\nRevision \(version) · published \(publishedStamp(publishedAt, shift: shift))\nReviewed by \(draft.caregiverName)\n\n"
            + notes + "\n\nCARE LOG\n" + renderText(family: family, shift: shift)
            + "\n\nSaved report copy. Sharing does not confirm delivery or receipt."
    }

    static func html(family: Family, shift: Shift, draft: DayReportDraft, version: Int, publishedAt: Date) -> String {
        let stamp = "<aside style=\"padding:1rem;text-align:center;font-family:system-ui\">Nanny Log · Revision \(version) · published \(publishedStamp(publishedAt, shift: shift))<br>Saved report copy; sharing does not confirm delivery or receipt.</aside>"
        return renderHTML(family: family, shift: shift, draft: draft).replacingOccurrences(of: "<body>", with: "<body>" + stamp)
    }

    private static func publishedStamp(_ date: Date, shift: Shift) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: shift.timeZoneIdentifier) ?? .gmt
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a zzz"
        return formatter.string(from: date) + " (" + date.formatted(.iso8601) + ")"
    }

    private static func sourceProvenance(family: Family, shift: Shift) -> [String] {
        func value<T>(_ item: T?) -> String { item.map { "some:" + String(describing: $0) } ?? "none" }
        var parts = [String(shift.startedAt.timeIntervalSinceReferenceDate),
                     value(shift.endedAt?.timeIntervalSinceReferenceDate), shift.timeZoneIdentifier,
                     family.volumeUnitRaw, String(shift.isOpen)]
        for baby in shift.roster(of: family).sorted(by: { a, b in a.sortOrder == b.sortOrder ? a.id.uuidString < b.id.uuidString : a.sortOrder < b.sortOrder }) {
            parts += ["baby", baby.id.uuidString, baby.name, String(baby.birthAt.timeIntervalSinceReferenceDate),
                      String(baby.sortOrder), String(baby.isArchived)]
        }
        for event in shift.liveEvents.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            parts += ["event", event.id.uuidString, value(event.babyIDRaw), event.kindRaw,
                      String(event.at.timeIntervalSinceReferenceDate), value(event.feedMethodRaw),
                      value(event.amountMl), value(event.feedDurationSeconds), value(event.leftSeconds),
                      value(event.rightSeconds), value(event.diaperContentsRaw), value(event.stoolColorRaw),
                      value(event.text), value(event.tagsRaw), value(event.tempF), value(event.pumpedMl),
                      value(event.medicationName), value(event.doseText), value(event.weightGrams)]
        }
        for sleep in shift.liveSleepSessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            parts += ["sleep", sleep.id.uuidString, value(sleep.babyIDRaw),
                      String(sleep.startAt.timeIntervalSinceReferenceDate), value(sleep.endAt?.timeIntervalSinceReferenceDate)]
        }
        return parts
    }

    private static func roster(_ family: Family, _ shift: Shift) -> [HandoffBaby] {
        shift.roster(of: family).sorted { a, b in a.sortOrder == b.sortOrder ? a.id.uuidString < b.id.uuidString : a.sortOrder < b.sortOrder }.map {
            HandoffBaby(id: $0.id, name: $0.name,
                        dayOfLife: DayOfLife.calendarDay(birthAt: $0.birthAt, forShift: shift.window,
                                                       calendar: family.calendar), isArchived: $0.isArchived)
        }
    }

    private static func renderText(family: Family, shift: Shift) -> String {
        Handoff.text(babies: roster(family, shift), shift: shift.window, caregiver: nil,
                     events: shift.liveEvents.compactMap(\.snapshot).sorted { a, b in a.at == b.at ? a.id.uuidString < b.id.uuidString : a.at < b.at },
                     sessions: shift.liveSleepSessions.compactMap(\.snapshot).sorted { a, b in a.startAt == b.startAt ? a.id.uuidString < b.id.uuidString : a.startAt < b.startAt }, unit: family.volumeUnit,
                     timeZone: TimeZone(identifier: shift.timeZoneIdentifier) ?? .gmt,
                     asOf: shift.endedAt ?? Date(), context: shift.careContext)
    }

    private static func renderHTML(family: Family, shift: Shift, draft: DayReportDraft?) -> String {
        HandoffHTML.render(babies: roster(family, shift), shift: shift.window,
                           caregiver: draft?.caregiverName, note: draft.map(narrative),
                           events: shift.liveEvents.compactMap(\.snapshot).sorted { a, b in a.at == b.at ? a.id.uuidString < b.id.uuidString : a.at < b.at },
                           sessions: shift.liveSleepSessions.compactMap(\.snapshot).sorted { a, b in a.startAt == b.startAt ? a.id.uuidString < b.id.uuidString : a.startAt < b.startAt }, unit: family.volumeUnit,
                           timeZone: TimeZone(identifier: shift.timeZoneIdentifier) ?? .gmt,
                           asOf: shift.endedAt ?? Date(), context: shift.careContext)
    }

    private static func narrative(_ draft: DayReportDraft) -> String {
        [("Today's summary", draft.summary), ("Notes for the handoff", draft.eveningNotes),
         ("Questions / supplies to follow up", draft.questions)]
            .map { label, value in "\(label)\n\(value.isEmpty ? "Nothing added." : value)" }.joined(separator: "\n\n")
    }
}

enum DayReportPersistenceError: Error, LocalizedError, Equatable {
    case unreadable, endShiftFirst, wrongContext
    var errorDescription: String? {
        switch self {
        case .unreadable: return "The saved report could not be opened. Nothing was replaced. Keep this shift and try again."
        case .endShiftFirst: return "End the shift before publishing its final report. Your draft can be saved now."
        case .wrongContext: return "End-of-day reports belong to day-care shifts."
        }
    }
}

/// Actor-to-view projection: views never retain or dereference invalidated models
/// after an asynchronous save, family deletion or household switch.
struct DayReportSnapshot: Sendable {
    let state: DayReportState
    let facts: DayReportComposer.Facts
    let isOpen: Bool
}
