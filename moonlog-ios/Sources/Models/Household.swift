import Foundation
import SwiftData
import MoonlogCore

// MARK: - CloudKit ground rules
//
// Every unusual choice in these models is a CloudKit requirement, each verified
// against this machine's SDK rather than assumed:
//
// * Non-optional stored properties need an **inline** default. Assigning in `init`
//   is NOT enough — `Schema.Attribute.defaultValue` is populated only by the
//   property initialiser, and the store rejects the schema at load time with
//   "requires that all attributes be optional, or have a default value set".
// * Every relationship must be optional and must HAVE an inverse. It does not have
//   to be *declared* — SwiftData infers it — but we declare it anyway, because
//   inference is ambiguous once two relationships point at the same type.
// * `.deny` is rejected outright ("unsupported delete rules"). `.cascade` is
//   accepted, though CloudKit does not guarantee it lands atomically on other
//   devices, so the UI must tolerate a transiently `nil` parent.
// * No `@Attribute(.unique)` and no `#Unique` — CloudKit cannot enforce either.
//   Identity is an app-minted UUID, deduplicated explicitly at write time where
//   it matters.

/// A client household. Every query and every export is scoped to one, so one
/// family's data can never appear in another's report.
@Model
final class Family {
    var id: UUID = UUID()
    @Attribute(.allowsCloudEncryption) var name: String = ""
    var createdAt: Date = Date.distantPast

    /// The **home's** zone, not the device's — otherwise a doula working elsewhere
    /// retroactively reshuffles months of a client's charts.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var isArchived: Bool = false

    /// Households mark bottles differently, so the unit is per family and the
    /// handoff reads the way that family expects.
    var volumeUnitRaw: String = VolumeUnit.oz.rawValue

    /// Which optional event kinds this family uses, as joined raw values. A joined
    /// string rather than `[String]`, which SwiftData stores as an opaque Codable
    /// blob that CloudKit merges last-writer-wins.
    var optionalKindsRaw: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Baby.family)
    var babies: [Baby]? = []

    @Relationship(deleteRule: .cascade, inverse: \Shift.family)
    var shifts: [Shift]? = []

    @Relationship(deleteRule: .cascade, inverse: \TagBinding.family)
    var tagBindings: [TagBinding]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteTagPreset.family)
    var noteTags: [NoteTagPreset]? = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Stable order: card position is muscle memory at 3am.
    var activeBabies: [Baby] {
        (babies ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var volumeUnit: VolumeUnit { VolumeUnit(rawValue: volumeUnitRaw) ?? .oz }

    /// Core kinds are always on; only the extras are opt-in.
    var enabledKinds: [EventKind] {
        EventKind.core + EventKind.optional.filter { optionalKindsRaw.contains($0.rawValue) }
    }

    func setOptionalKinds(_ kinds: [EventKind]) {
        optionalKindsRaw = kinds.map(\.rawValue).joined(separator: ",")
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return c
    }
}

@Model
final class Baby {
    var id: UUID = UUID()
    @Attribute(.allowsCloudEncryption) var name: String = ""
    @Attribute(.allowsCloudEncryption) var birthAt: Date = Date.distantPast

    /// Fixed, so the top card never moves.
    var sortOrder: Int = 0

    /// `BabyAccent.rawValue`. Colour is only ever the third identifying signal,
    /// behind name and stable position. See `docs/design.md`.
    var accentRaw: String = BabyAccent.gold.rawValue

    /// Archived, never deleted — `.deny` is unavailable, so `CareStore` enforces it.
    var isArchived: Bool = false

    var family: Family? = nil

    // `.nullify`, not `.cascade` — deleting a baby must not destroy logged history.
    // Attribution survives via `babyIDRaw`.
    @Relationship(deleteRule: .nullify, inverse: \LogEvent.baby)
    var events: [LogEvent]? = []

    @Relationship(deleteRule: .nullify, inverse: \SleepSession.baby)
    var sleepSessions: [SleepSession]? = []

    init(
        id: UUID = UUID(),
        name: String,
        birthAt: Date,
        sortOrder: Int = 0,
        accent: BabyAccent = .gold
    ) {
        self.id = id
        self.name = name
        self.birthAt = birthAt
        self.sortOrder = sortOrder
        self.accentRaw = accent.rawValue
    }

    var accent: BabyAccent {
        BabyAccent(rawValue: accentRaw) ?? .gold
    }
}
