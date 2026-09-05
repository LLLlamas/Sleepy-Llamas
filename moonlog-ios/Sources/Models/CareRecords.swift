import Foundation
import SwiftData
import MoonlogCore

/// One caregiver session, covering all of a family's babies. Start and end are set
/// or confirmed by the doula, never inferred from the clock.
@Model
final class Shift {
    var id: UUID = UUID()
    var startedAt: Date = Date.distantPast
    var endedAt: Date? = nil
    var caregiver: String? = nil

    /// Denormalised so the query deciding whether the app can log at all is a Bool
    /// comparison, not an optional-Date one. Invariant: `isOpen == (endedAt == nil)`.
    var isOpen: Bool = true

    /// Copied from the family at creation, so relocating cannot corrupt old shifts.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var family: Family? = nil
    /// Denormalised: predicates over a relationship force a join. Set via `attach(to:)`.
    var familyIDRaw: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \LogEvent.shift)
    var events: [LogEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \SleepSession.shift)
    var sleepSessions: [SleepSession]? = []

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        caregiver: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isOpen = endedAt == nil
        self.caregiver = caregiver
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// `MoonlogCore` works on value types, never on `@Model` classes.
    func attach(to family: Family) {
        self.family = family
        self.familyIDRaw = family.id
    }

    var window: ShiftWindow {
        ShiftWindow(startedAt: startedAt, endedAt: endedAt)
    }

    /// Never set `endedAt` directly — this keeps `isOpen` honest.
    func close(at date: Date) {
        endedAt = date
        isOpen = false
    }
}

/// Feed, diaper and note in one flat model, discriminated by `kindRaw`. Flat rather
/// than three models or a class hierarchy — reasoning in `docs/decisions.md`.
@Model
final class LogEvent {
    var id: UUID = UUID()

    /// Raw `String`, never an enum. `#Predicate` cannot compare enums, and reaching
    /// through `.rawValue` inside the macro hard-crashes uncatchably. Compare this
    /// column directly, with the raw value captured outside the predicate.
    var kindRaw: String = EventKind.note.rawValue

    var at: Date = Date.distantPast
    var createdAt: Date = Date.distantPast

    // Feed payload
    var feedMethodRaw: String? = nil
    var amountMl: Double? = nil
    /// Seconds, so durations aggregate without round-then-sum drift.
    var feedDurationSeconds: Int? = nil

    // Diaper payload
    var diaperContentsRaw: String? = nil
    var stoolColorRaw: String? = nil

    // Note payload
    var text: String? = nil
    var tempF: Double? = nil

    /// Manual or NFC, so a mis-scan is traceable.
    var sourceRaw: String = EventSource.manual.rawValue
    var sourceTagToken: String? = nil

    var shift: Shift? = nil
    var baby: Baby? = nil

    /// Denormalised parent ids: predicates avoid a join, and attribution survives
    /// both a transiently-nil relationship during sync and a `.nullify` delete.
    /// Invariant: `babyIDRaw == baby?.id`. See `docs/architecture.md`.
    var babyIDRaw: UUID? = nil
    var shiftIDRaw: UUID? = nil

    init(
        id: UUID = UUID(),
        kind: EventKind,
        at: Date,
        createdAt: Date = .now,
        source: EventSource = .manual
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.at = at
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .note }
    var source: EventSource { EventSource(rawValue: sourceRaw) ?? .manual }
    var feedMethod: FeedMethod? { feedMethodRaw.flatMap(FeedMethod.init(rawValue:)) }
    var diaperContents: DiaperContents? {
        diaperContentsRaw.flatMap(DiaperContents.init(rawValue:))
    }
    var stoolColor: StoolColor? { stoolColorRaw.flatMap(StoolColor.init(rawValue:)) }
}

/// A session, not a pair of events — cleaner totals, and "is she asleep" is a
/// per-baby question once there are twins.
@Model
final class SleepSession {
    var id: UUID = UUID()
    var startAt: Date = Date.distantPast

    /// `nil` means still asleep — a legitimate end state for a shift. Totals clip to
    /// the shift window rather than closing it.
    var endAt: Date? = nil

    /// Invariant: `isOpen == (endAt == nil)`.
    var isOpen: Bool = true

    var baby: Baby? = nil
    var shift: Shift? = nil
    var babyIDRaw: UUID? = nil
    var shiftIDRaw: UUID? = nil

    init(id: UUID = UUID(), startAt: Date, endAt: Date? = nil) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.isOpen = endAt == nil
    }

    var snapshot: SleepSnapshot? {
        guard let babyID = babyIDRaw else { return nil }
        return SleepSnapshot(id: id, babyID: babyID, startAt: startAt, endAt: endAt)
    }

    func close(at date: Date) {
        endAt = date
        isOpen = false
    }
}

/// A physical NFC tag bound to an action and a baby.
@Model
final class TagBinding {
    var id: UUID = UUID()

    /// Hardware UID hex (v1) or an app-minted token written into the tag's URL.
    /// Generic so both schemes can coexist.
    var tagToken: String = ""

    var label: String = ""
    var actionRaw: String = TagAction.logDiaper.rawValue
    var targetBabyIDRaw: UUID? = nil
    var family: Family? = nil

    init(
        id: UUID = UUID(),
        tagToken: String,
        label: String,
        action: TagAction,
        targetBabyID: UUID? = nil
    ) {
        self.id = id
        self.tagToken = tagToken
        self.label = label
        self.actionRaw = action.rawValue
        self.targetBabyIDRaw = targetBabyID
    }

    var action: TagAction { TagAction(rawValue: actionRaw) ?? .logDiaper }
}

/// A record owned by a shift and attributed to a baby.
///
/// `attach` is the only supported way to wire one up, so a relationship and its
/// denormalised id can never disagree. See `docs/architecture.md`.
protocol BabyRecord: AnyObject {
    var shift: Shift? { get set }
    var baby: Baby? { get set }
    var shiftIDRaw: UUID? { get set }
    var babyIDRaw: UUID? { get set }
}

extension BabyRecord {
    func attach(to shift: Shift, baby: Baby) {
        self.shift = shift
        self.shiftIDRaw = shift.id
        self.baby = baby
        self.babyIDRaw = baby.id
    }
}

extension LogEvent: BabyRecord {}
extension SleepSession: BabyRecord {}
