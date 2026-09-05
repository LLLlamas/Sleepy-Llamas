import Foundation
import SwiftData
import MoonlogCore

/// Owns every write to the care records.
///
/// It exists because several invariants cannot be expressed in the schema:
/// CloudKit forbids unique constraints and the `.deny` delete rule, so "one open
/// sleep session per baby" and "never hard-delete a baby that has records" have to
/// be enforced here instead. Funnelling writes through one type is what makes that
/// possible — a stray `context.insert` elsewhere would bypass all of it.
///
/// `@ModelActor` keeps the work off the main thread; imports and trend queries can
/// be long.
@ModelActor
actor CareStore {

    // MARK: - Households

    func createFamily(
        name: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> UUID {
        let family = Family(name: name, timeZoneIdentifier: timeZoneIdentifier)
        modelContext.insert(family)
        try modelContext.save()
        return family.id
    }

    func addBaby(
        to familyID: UUID,
        name: String,
        birthAt: Date
    ) throws -> UUID {
        guard let family = try family(familyID) else { throw CareStoreError.familyNotFound }
        let existing = family.activeBabies
        let baby = Baby(
            name: name,
            birthAt: birthAt,
            // Append to the end so an existing twin's card never moves. Position is
            // muscle memory at 3am.
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            accent: BabyAccent.forIndex(existing.count)
        )
        baby.family = family
        modelContext.insert(baby)
        try modelContext.save()
        return baby.id
    }

    /// Archives rather than deletes.
    ///
    /// `.deny` would have been the natural guard against removing a baby that still
    /// has records, but CloudKit rejects that rule. A hard delete would nullify the
    /// relationship on every event, and although `babyIDRaw` preserves attribution
    /// the baby's *name* would be gone from every past handoff. So there is no
    /// public delete at all.
    func archiveBaby(_ babyID: UUID) throws {
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        baby.isArchived = true
        try modelContext.save()
    }

    // MARK: - Shift lifecycle

    /// Starts a shift for a family. `startedAt` is a value the doula sets or
    /// confirms, so it is passed in rather than read off the clock.
    ///
    /// Refuses if one is already open: two open shifts is the web version's bug
    /// where the second becomes invisible in every screen and its logs unreachable.
    func startShift(
        familyID: UUID,
        startedAt: Date,
        caregiver: String?
    ) throws -> UUID {
        guard let family = try family(familyID) else { throw CareStoreError.familyNotFound }
        if try openShift(familyID: familyID) != nil {
            throw CareStoreError.shiftAlreadyOpen
        }
        let shift = Shift(
            startedAt: startedAt,
            caregiver: caregiver,
            timeZoneIdentifier: family.timeZoneIdentifier
        )
        shift.attach(to: family)
        modelContext.insert(shift)
        try modelContext.save()
        return shift.id
    }

    /// Ends a shift. It does **not** open a replacement.
    ///
    /// The doula finishes by leaving the baby with the parents, so between shifts
    /// there is genuinely no active shift. The web version auto-started a fresh one,
    /// which is where its orphaned-sleep bug came from.
    ///
    /// An in-progress sleep is deliberately left open — "asleep since 5:40, still
    /// asleep when I left" is the honest record for the parents, and totals clip to
    /// the shift window rather than letting it accrue forever.
    func endShift(_ shiftID: UUID, endedAt: Date) throws {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        guard shift.isOpen else { throw CareStoreError.shiftAlreadyClosed }
        guard endedAt >= shift.startedAt else { throw CareStoreError.endBeforeStart }
        shift.close(at: endedAt)
        try modelContext.save()
    }

    /// Filters in the predicate rather than in memory. An earlier version fetched
    /// open shifts with a limit and filtered afterwards, which could silently miss
    /// one — exactly the class of quietly-wrong answer this rewrite exists to stop.
    ///
    /// Returns a value type, not the `@Model`. `@Model` classes are not `Sendable`,
    /// so handing one across the actor boundary would be a data race waiting to
    /// happen; everything outside this actor works on snapshots.
    func openShift(familyID: UUID) throws -> ShiftSummary? {
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.isOpen && $0.familyIDRaw == familyID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).first.map(ShiftSummary.init)
    }

    // MARK: - Logging

    func logEvent(
        kind: EventKind,
        at: Date,
        shiftID: UUID,
        babyID: UUID,
        source: EventSource = .manual,
        configure: (LogEvent) -> Void = { _ in }
    ) throws -> UUID {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }

        let event = LogEvent(kind: kind, at: at, source: source)
        configure(event)
        // The single attach point, so the relationship and its denormalised id
        // can never disagree.
        event.attach(to: shift, baby: baby)
        modelContext.insert(event)
        try modelContext.save()
        return event.id
    }

    func deleteEvent(_ eventID: UUID) throws {
        let descriptor = FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == eventID })
        guard let event = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(event)
        try modelContext.save()
    }

    // MARK: - Sleep

    /// Toggles sleep for one baby, atomically with respect to this actor.
    ///
    /// The web version read the open session and wrote outside a transaction, from
    /// two undisabled controls, so a double-tap could open two sessions. Here the
    /// actor serialises it and the reconciler mops up anything CloudKit delivers.
    @discardableResult
    func toggleSleep(shiftID: UUID, babyID: UUID, at date: Date) throws -> SleepToggle {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }

        try reconcileSleep(shiftID: shiftID, babyID: babyID)

        if let open = try storedOpenSleepSession(shiftID: shiftID, babyID: babyID) {
            guard date >= open.startAt else { throw CareStoreError.endBeforeStart }
            open.close(at: date)
            try modelContext.save()
            return .closed(open.id)
        }

        let session = SleepSession(startAt: date)
        session.attach(to: shift, baby: baby)
        modelContext.insert(session)
        try modelContext.save()
        return .opened(session.id)
    }

    func openSleepSession(shiftID: UUID, babyID: UUID) throws -> SleepSnapshot? {
        try storedOpenSleepSession(shiftID: shiftID, babyID: babyID)?.snapshot
    }

    private func storedOpenSleepSession(shiftID: UUID, babyID: UUID) throws -> SleepSession? {
        let descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.isOpen && $0.babyIDRaw == babyID && $0.shiftIDRaw == shiftID },
            sortBy: [SortDescriptor(\.startAt)])
        return try modelContext.fetch(descriptor).first
    }

    /// Repairs duplicate or overlapping sessions using the deterministic reconciler.
    ///
    /// Required rather than defensive: CloudKit cannot enforce uniqueness, so two
    /// devices can both open a session for the same baby and the store accepts
    /// both. The UI would show one while the other accrued invisibly.
    func reconcileSleep(shiftID: UUID, babyID: UUID) throws {
        let descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.babyIDRaw == babyID && $0.shiftIDRaw == shiftID })
        let stored = try modelContext.fetch(descriptor)
        guard stored.count > 1 else { return }

        let snapshots = stored.compactMap(\.snapshot)
        let result = SleepReconciler.reconcile(snapshots, forBaby: babyID)

        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        for id in result.mergedAway {
            if let doomed = byID[id] { modelContext.delete(doomed) }
        }
        for repaired in result.sessions {
            guard let session = byID[repaired.id] else { continue }
            if session.endAt != repaired.endAt {
                if let end = repaired.endAt {
                    session.close(at: end)
                } else {
                    session.endAt = nil
                    session.isOpen = true
                }
            }
        }
        try modelContext.save()
    }

    // MARK: - Lookups

    private func family(_ id: UUID) throws -> Family? {
        try modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate { $0.id == id })).first
    }

    private func baby(_ id: UUID) throws -> Baby? {
        try modelContext.fetch(FetchDescriptor<Baby>(predicate: #Predicate { $0.id == id })).first
    }

    private func shift(_ id: UUID) throws -> Shift? {
        try modelContext.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id })).first
    }
}

/// A `Sendable` view of an open shift, safe to cross the actor boundary.
struct ShiftSummary: Sendable, Equatable, Identifiable {
    let id: UUID
    let familyID: UUID?
    let window: ShiftWindow
    let caregiver: String?
    let timeZoneIdentifier: String

    init(_ shift: Shift) {
        self.id = shift.id
        self.familyID = shift.familyIDRaw
        self.window = shift.window
        self.caregiver = shift.caregiver
        self.timeZoneIdentifier = shift.timeZoneIdentifier
    }
}

enum SleepToggle: Equatable {
    case opened(UUID)
    case closed(UUID)
}

enum CareStoreError: Error, Equatable {
    case familyNotFound
    case babyNotFound
    case shiftNotFound
    case shiftAlreadyOpen
    case shiftAlreadyClosed
    case endBeforeStart
}
