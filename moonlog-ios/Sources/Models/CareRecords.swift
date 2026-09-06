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
    @Attribute(.allowsCloudEncryption) var caregiver: String? = nil

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
    /// A breast feed commonly uses both sides, so each carries its own time.
    var leftSeconds: Int? = nil
    var rightSeconds: Int? = nil

    // Diaper payload
    var diaperContentsRaw: String? = nil
    var stoolColorRaw: String? = nil

    // Note payload
    @Attribute(.allowsCloudEncryption) var text: String? = nil
    @Attribute(.allowsCloudEncryption) var tempF: Double? = nil
    /// Joined raw tag values — see `Family.optionalKindsRaw` for why not `[String]`.
    var tagsRaw: String? = nil

    // Optional kinds. `pump` carries no baby; it is about the mother.
    var pumpedMl: Double? = nil
    @Attribute(.allowsCloudEncryption) var medicationName: String? = nil
    @Attribute(.allowsCloudEncryption) var doseText: String? = nil
    @Attribute(.allowsCloudEncryption) var weightGrams: Double? = nil

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

    /// The value type `MoonlogCore` works on. Its absence is why `Totals.compute`
    /// had no reachable call path from the app.
    var snapshot: EventSnapshot? {
        // A stable sentinel, not a fresh UUID. `pump` carries no baby, and minting
        // one per snapshot build meant any code grouping by babyID would see a new
        // phantom baby on every render.
        guard let babyID = babyIDRaw ?? (kind == .pump ? EventSnapshot.noBaby : nil)
        else { return nil }
        return EventSnapshot(
            id: id, babyID: babyID, kind: kind, at: at,
            feedMethod: feedMethod, amountMl: amountMl,
            feedDurationSeconds: feedDurationSeconds,
            leftSeconds: leftSeconds, rightSeconds: rightSeconds,
            diaperContents: diaperContents, stoolColor: stoolColor,
            text: text, noteTags: tags, tempF: tempF,
            pumpedMl: pumpedMl, medicationName: medicationName,
            doseText: doseText, weightGrams: weightGrams)
    }

    var tags: [String] {
        // Short-circuit: most events have no tags, and this otherwise allocated
        // three arrays each on every snapshot build.
        guard let tagsRaw, !tagsRaw.isEmpty else { return [] }
        return tagsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
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

/// A note tag the user has defined. A model rather than a stored array so tags can
/// be renamed, and so two devices adding tags concurrently both survive the merge.
@Model
final class NoteTagPreset {
    var id: UUID = UUID()
    var label: String = ""
    var sortOrder: Int = 0
    var family: Family? = nil

    init(id: UUID = UUID(), label: String, sortOrder: Int = 0) {
        self.id = id
        self.label = label
        self.sortOrder = sortOrder
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

    var action: TagAction { TagAction(rawValue: actionRaw) ?? .unknown }
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
    /// `baby` is optional because `pump` is about the mother and carries none.
    /// Routing that case through here anyway keeps this the single place where a
    /// relationship and its denormalised id can ever be set.
    func attach(to shift: Shift, baby: Baby?) {
        self.shift = shift
        self.shiftIDRaw = shift.id
        self.baby = baby
        self.babyIDRaw = baby?.id
    }
}

/// A deleted event, held as value types so it can cross the actor boundary and
/// outlive the model object it came from. See `LogEvent.restoration`.
struct EventRestoration: Sendable {
    let id: UUID
    let kind: EventKind
    let at: Date
    let createdAt: Date
    let source: EventSource
    let sourceTagToken: String?
    let shiftID: UUID
    let babyID: UUID?

    let feedMethodRaw: String?
    let amountMl: Double?
    let feedDurationSeconds: Int?
    let leftSeconds: Int?
    let rightSeconds: Int?
    let diaperContentsRaw: String?
    let stoolColorRaw: String?
    let text: String?
    let tempF: Double?
    let tagsRaw: String?
    let pumpedMl: Double?
    let medicationName: String?
    let doseText: String?
    let weightGrams: Double?

    /// Payload only. Identity and parentage are the store's to set, through
    /// `attach(to:baby:)`.
    func applyPayload(to event: LogEvent) {
        event.feedMethodRaw = feedMethodRaw
        event.amountMl = amountMl
        event.feedDurationSeconds = feedDurationSeconds
        event.leftSeconds = leftSeconds
        event.rightSeconds = rightSeconds
        event.diaperContentsRaw = diaperContentsRaw
        event.stoolColorRaw = stoolColorRaw
        event.text = text
        event.tempF = tempF
        event.tagsRaw = tagsRaw
        event.pumpedMl = pumpedMl
        event.medicationName = medicationName
        event.doseText = doseText
        event.weightGrams = weightGrams
        event.sourceTagToken = sourceTagToken
    }
}

extension LogEvent: BabyRecord {}

extension LogEvent {
    /// Everything needed to put this event back exactly as it was.
    ///
    /// Undo restores the record, not a lookalike. Re-logging would mint a fresh id
    /// — breaking anything already pointing at the old one — reset `createdAt`, and
    /// drop `sourceTagToken`, which is what makes a mis-scan traceable later.
    var restoration: EventRestoration? {
        guard let shiftIDRaw else { return nil }
        return EventRestoration(
            id: id, kind: kind, at: at, createdAt: createdAt,
            source: source, sourceTagToken: sourceTagToken,
            shiftID: shiftIDRaw, babyID: babyIDRaw,
            feedMethodRaw: feedMethodRaw, amountMl: amountMl,
            feedDurationSeconds: feedDurationSeconds,
            leftSeconds: leftSeconds, rightSeconds: rightSeconds,
            diaperContentsRaw: diaperContentsRaw, stoolColorRaw: stoolColorRaw,
            text: text, tempF: tempF, tagsRaw: tagsRaw,
            pumpedMl: pumpedMl, medicationName: medicationName,
            doseText: doseText, weightGrams: weightGrams)
    }
}
extension SleepSession: BabyRecord {}
