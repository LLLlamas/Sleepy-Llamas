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
}

public enum FeedMethod: String, Sendable, CaseIterable {
    case breastLeft = "breast-left"
    case breastRight = "breast-right"
    case bottleBreastmilk = "bottle-breastmilk"
    case bottleFormula = "bottle-formula"
    case unknown

    public var isBottle: Bool {
        self == .bottleBreastmilk || self == .bottleFormula
    }
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
    public let id: UUID
    public let babyID: UUID
    public let kind: EventKind
    public let at: Date

    // Feed payload
    public let feedMethod: FeedMethod?
    /// Canonical millilitres, as in the PWA. Converted at display only.
    public let amountMl: Double?
    /// Seconds, not the PWA's minutes — so durations aggregate without the
    /// round-then-sum drift.
    public let feedDurationSeconds: Int?

    // Diaper payload
    public let diaperContents: DiaperContents?
    public let stoolColor: StoolColor?

    // Note payload
    public let noteTags: [String]
    public let tempF: Double?

    public init(
        id: UUID = UUID(),
        babyID: UUID,
        kind: EventKind,
        at: Date,
        feedMethod: FeedMethod? = nil,
        amountMl: Double? = nil,
        feedDurationSeconds: Int? = nil,
        diaperContents: DiaperContents? = nil,
        stoolColor: StoolColor? = nil,
        noteTags: [String] = [],
        tempF: Double? = nil
    ) {
        self.id = id
        self.babyID = babyID
        self.kind = kind
        self.at = at
        self.feedMethod = feedMethod
        self.amountMl = amountMl
        self.feedDurationSeconds = feedDurationSeconds
        self.diaperContents = diaperContents
        self.stoolColor = stoolColor
        self.noteTags = noteTags
        self.tempF = tempF
    }
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
