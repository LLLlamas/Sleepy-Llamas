import Foundation

// Value-type views of the persisted records. Everything in `MoonlogCore` works on
// these: the tests need no `ModelContainer`, and being `Sendable` they cross actor
// boundaries safely.

public struct SleepSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let babyID: UUID
    public let startAt: Date
    /// `nil` means still open — legitimate at the end of a shift.
    public let endAt: Date?

    public init(id: UUID = UUID(), babyID: UUID, startAt: Date, endAt: Date? = nil) {
        self.id = id
        self.babyID = babyID
        self.startAt = startAt
        self.endAt = endAt
    }

    public var isOpen: Bool { endAt == nil }
}

/// The window a shift covers. Set or confirmed by the doula, never inferred.
public struct ShiftWindow: Sendable, Hashable {
    public let startedAt: Date
    public let endedAt: Date?

    public init(startedAt: Date, endedAt: Date? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var isOpen: Bool { endedAt == nil }

    /// A closed shift stops at its end; an open one runs to `now`. `nil` for a
    /// zero-length window — callers count nothing rather than crashing.
    public func interval(asOf now: Date) -> DateInterval? {
        let end = endedAt ?? now
        guard end > startedAt else { return nil }
        return DateInterval(start: startedAt, end: end)
    }
}

// MARK: - Domain enums
//
// Raw values are WIRE FORMAT: they become CloudKit fields, and a promoted schema is
// additive-only. Add cases freely; never rename an existing value.
//
// Each has an `unknown` case that is never written but is always readable, so an
// older build receiving a record from a newer one degrades gracefully instead of
// failing to decode.

public enum EventKind: String, Sendable, CaseIterable {
    case feed, diaper, note
    // Optional kinds — off by default, enabled per family.
    case pump, medication, measurement

    /// The three the app is built around. Always available, always in the thumb row.
    public static let core: [EventKind] = [.feed, .diaper, .note]

    /// Opt-in extras. `pump` is about the mother, so it carries no baby.
    public static let optional: [EventKind] = [.pump, .medication, .measurement]

    public var attachesToBaby: Bool { self != .pump }
}

public enum FeedMethod: String, Sendable, CaseIterable {
    /// One feed, not one side. Sides carry their own durations on the event, since
    /// a single feed commonly uses both.
    case breast
    case bottleBreastmilk = "bottle-breastmilk"
    case bottleFormula = "bottle-formula"
    case unknown

    public var isBottle: Bool { self == .bottleBreastmilk || self == .bottleFormula }
}

public enum DiaperContents: String, Sendable, CaseIterable {
    case wet, dirty, both, unknown

    public var countsAsWet: Bool { self == .wet || self == .both }
    public var countsAsDirty: Bool { self == .dirty || self == .both }
}

/// Ordered by clinical progression — whether meconium has cleared is a marker the
/// doula reports, so the order is meaningful, not decorative.
public enum StoolColor: String, Sendable, CaseIterable {
    case meconium, transitional, green, brown, yellow
}

public struct EventSnapshot: Sendable, Hashable, Identifiable {
    /// Stands in for "no baby" on a `pump`, which belongs to the shift rather than
    /// to a child. Fixed so it can never collide with a real baby and never varies
    /// between builds of the same record.
    public static let noBaby = UUID(uuidString: "00000000-0000-0000-0000-00000000BABE")!

    public let id: UUID
    public let babyID: UUID
    public let kind: EventKind
    public let at: Date

    // Feed payload. Amounts are canonical millilitres, converted at display.
    public let feedMethod: FeedMethod?
    public let amountMl: Double?
    /// Bottle duration. For a breast feed the sides carry their own.
    public let feedDurationSeconds: Int?
    public let leftSeconds: Int?
    public let rightSeconds: Int?

    // Diaper payload
    public let diaperContents: DiaperContents?
    public let stoolColor: StoolColor?

    // Note payload
    /// The note body. Absent from the snapshot originally, which meant the handoff
    /// could count notes but not say what they said.
    public let text: String?
    public let noteTags: [String]
    public let tempF: Double?

    // Optional kinds
    public let pumpedMl: Double?
    public let medicationName: String?
    public let doseText: String?
    public let weightGrams: Double?

    public init(
        id: UUID = UUID(),
        babyID: UUID,
        kind: EventKind,
        at: Date,
        feedMethod: FeedMethod? = nil,
        amountMl: Double? = nil,
        feedDurationSeconds: Int? = nil,
        leftSeconds: Int? = nil,
        rightSeconds: Int? = nil,
        diaperContents: DiaperContents? = nil,
        stoolColor: StoolColor? = nil,
        text: String? = nil,
        noteTags: [String] = [],
        tempF: Double? = nil,
        pumpedMl: Double? = nil,
        medicationName: String? = nil,
        doseText: String? = nil,
        weightGrams: Double? = nil
    ) {
        self.id = id
        self.babyID = babyID
        self.kind = kind
        self.at = at
        self.feedMethod = feedMethod
        self.amountMl = amountMl
        self.feedDurationSeconds = feedDurationSeconds
        self.leftSeconds = leftSeconds
        self.rightSeconds = rightSeconds
        self.diaperContents = diaperContents
        self.stoolColor = stoolColor
        self.text = text
        self.noteTags = noteTags
        self.tempF = tempF
        self.pumpedMl = pumpedMl
        self.medicationName = medicationName
        self.doseText = doseText
        self.weightGrams = weightGrams
    }

    /// Total time at the breast, both sides.
    public var breastSeconds: Int? {
        guard leftSeconds != nil || rightSeconds != nil else { return nil }
        return (leftSeconds ?? 0) + (rightSeconds ?? 0)
    }
}

/// Volume unit, set per family — households mark bottles differently, and the
/// handoff should read the way that family expects.
public enum VolumeUnit: String, Sendable, CaseIterable {
    case oz, ml

    public var displayName: String { self == .oz ? "Ounces" : "Millilitres" }
}

/// A tag scan never writes silently, but recording the source makes a mis-scan
/// traceable.
public enum EventSource: String, Sendable, CaseIterable {
    case manual
    case nfcTag = "nfc-tag"
}

public enum TagAction: String, Sendable, CaseIterable {
    case toggleSleep = "toggle-sleep"
    case logFeed = "log-feed"
    case logDiaper = "log-diaper"
}


public extension Date {
    /// A minute of slack, so setting "now" by hand is never rejected by a race
    /// between the picker and the save. Used by every sheet that bounds a time.
    var isMeaningfullyInFuture: Bool {
        self > Date().addingTimeInterval(60)
    }
}
