import Foundation

/// Value-type views of the persisted records.
///
/// Every calculation in `MoonlogCore` works on these, never on `@Model` classes.
/// Two payoffs: the tests run without a `ModelContainer`, and being `Sendable`
/// value types they can cross actor boundaries when trends are computed off the
/// main thread.

public struct SleepSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let babyID: UUID
    public let startAt: Date
    /// `nil` means the session was still open. That is a legitimate, meaningful
    /// state at the end of a shift — the doula left while the baby was asleep.
    public let endAt: Date?

    public init(id: UUID = UUID(), babyID: UUID, startAt: Date, endAt: Date? = nil) {
        self.id = id
        self.babyID = babyID
        self.startAt = startAt
        self.endAt = endAt
    }

    public var isOpen: Bool { endAt == nil }
}

/// The window a shift covers.
///
/// `startedAt` and `endedAt` are values the doula sets or confirms — they are not
/// inferred from the clock. `endedAt == nil` means the shift is still running.
public struct ShiftWindow: Sendable, Hashable {
    public let startedAt: Date
    public let endedAt: Date?

    public init(startedAt: Date, endedAt: Date? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var isOpen: Bool { endedAt == nil }

    /// The accounting window. A closed shift stops at its end; an open one runs to
    /// `now`. Returns `nil` for a zero- or negative-length window, which callers
    /// treat as "nothing to count" rather than crashing.
    public func interval(asOf now: Date) -> DateInterval? {
        let end = endedAt ?? now
        guard end > startedAt else { return nil }
        return DateInterval(start: startedAt, end: end)
    }
}

public enum EventKind: String, Sendable, CaseIterable {
    case feed, diaper, note
}

public struct EventSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let babyID: UUID
    public let kind: EventKind
    public let at: Date

    public init(id: UUID = UUID(), babyID: UUID, kind: EventKind, at: Date) {
        self.id = id
        self.babyID = babyID
        self.kind = kind
        self.at = at
    }
}
