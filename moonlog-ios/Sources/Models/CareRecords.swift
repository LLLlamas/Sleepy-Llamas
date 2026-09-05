import Foundation
import SwiftData
import MoonlogCore

/// One caregiver session, covering **all** of a family's babies.
///
/// Start and end are values the doula sets or confirms — they are not inferred
/// from the clock. A shift ends by leaving the baby with the parents, so ending
/// one does not open another; between shifts there is simply no open shift.
@Model
final class Shift {
    var id: UUID = UUID()
    var startedAt: Date = Date.distantPast
    var endedAt: Date? = nil
    var caregiver: String? = nil

    /// Denormalised so the "is there an open shift" query is a Bool comparison.
    /// Predicates over optional `Date` comparisons have a poor track record, and
    /// this is the query that decides whether the app can log at all.
    /// Invariant: `isOpen == (endedAt == nil)`, asserted in tests.
    var isOpen: Bool = true

    /// The zone in force for this shift, copied from the family at creation so a
    /// family that relocates cannot corrupt older shifts.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var family: Family? = nil
    /// Denormalised for the same reasons as `LogEvent.babyIDRaw`: predicates over a
    /// relationship force a join, and this is the query that decides whether the
    /// app can log at all. Set via `attach(to:)`.
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

    /// The value type the domain layer works on. Everything in `MoonlogCore`
    /// operates on these rather than on `@Model` classes.
    func attach(to family: Family) {
        self.family = family
        self.familyIDRaw = family.id
    }

    var window: ShiftWindow {
        ShiftWindow(startedAt: startedAt, endedAt: endedAt)
    }

    /// Keeps the denormalised flag honest. Never set `endedAt` directly.
    func close(at date: Date) {
        endedAt = date
        isOpen = false
    }
}

/// Feed, diaper and note in one flat model, discriminated by `kindRaw`.
///
/// Flat rather than three models because the merged reverse-chronological timeline
/// is the app's primary read, and `FetchDescriptor.fetchLimit` is per-model-type —
/// three models could not be paged at the store level, so showing the newest 50
/// rows would mean loading every event of all three kinds.
///
/// Flat rather than `@Model` inheritance because that needs iOS 26 and has
/// reported crashes at the inheritance + optional-relationships intersection,
/// which CloudKit mandates.
@Model
final class LogEvent {
    var id: UUID = UUID()

    /// A raw `String`, never an enum. `#Predicate` cannot compare enum-typed
    /// properties: a captured enum throws `unsupportedPredicate`, a case literal
    /// will not compile, and reaching through `.rawValue` inside the macro
    /// **hard-crashes uncatchably**. Compare this column directly, with the raw
    /// value captured outside the predicate.
    var kindRaw: String = EventKind.note.rawValue

    var at: Date = Date.distantPast
    var createdAt: Date = Date.distantPast

    // Feed payload
    var feedMethodRaw: String? = nil
    var amountMl: Double? = nil
    /// Seconds, not the PWA's minutes, so durations aggregate without
    /// round-then-sum drift.
    var feedDurationSeconds: Int? = nil

    // Diaper payload
    var diaperContentsRaw: String? = nil
    var stoolColorRaw: String? = nil

    // Note payload
    var text: String? = nil
    var tempF: Double? = nil

    /// Where this came from — manual entry or an NFC tag — so a mis-scan is
    /// traceable after the fact.
    var sourceRaw: String = EventSource.manual.rawValue
    var sourceTagToken: String? = nil

    var shift: Shift? = nil
    var baby: Baby? = nil

    /// Denormalised parent ids. Two reasons, both real:
    /// 1. Predicates over a relationship force a join and are a common source of
    ///    `unsupportedPredicate`. A `UUID?` comparison is trivially supported.
    /// 2. Under CloudKit a relationship can be transiently `nil` on a device that
    ///    has the child record but not yet the link — and if a baby is ever
    ///    deleted, `.nullify` would otherwise lose attribution permanently.
    /// Invariant: `babyIDRaw == baby?.id`, asserted in tests.
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

    /// The only supported way to attach an event, so the relationship and its
    /// denormalised id can never disagree. Invariant asserted in tests.
    func attach(to shift: Shift, baby: Baby) {
        self.shift = shift
        self.shiftIDRaw = shift.id
        self.baby = baby
        self.babyIDRaw = baby.id
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .note }
    var source: EventSource { EventSource(rawValue: sourceRaw) ?? .manual }
    var feedMethod: FeedMethod? { feedMethodRaw.flatMap(FeedMethod.init(rawValue:)) }
    var diaperContents: DiaperContents? {
        diaperContentsRaw.flatMap(DiaperContents.init(rawValue:))
    }
    var stoolColor: StoolColor? { stoolColorRaw.flatMap(StoolColor.init(rawValue:)) }
}

/// Sleep is a session, not a pair of events — cleaner totals and a direct answer
/// to "is she asleep right now", which with twins is a **per-baby** question.
@Model
final class SleepSession {
    var id: UUID = UUID()
    var startAt: Date = Date.distantPast

    /// `nil` means still asleep. That is a legitimate end state for a shift: the
    /// doula left while the baby was sleeping. Totals clip to the shift window
    /// rather than closing the session, so the record stays honest without the
    /// duration growing forever.
    var endAt: Date? = nil

    /// Invariant: `isOpen == (endAt == nil)`. See `Shift.isOpen`.
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

    /// See `LogEvent.attach(to:baby:)`.
    func attach(to shift: Shift, baby: Baby) {
        self.shift = shift
        self.shiftIDRaw = shift.id
        self.baby = baby
        self.babyIDRaw = baby.id
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

    /// Either the tag's hardware UID as hex (the v1 scheme — works with any tag,
    /// needs no writing and no associated domain) or an app-minted token written
    /// into the tag's URL. Kept generic so both schemes can coexist.
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
