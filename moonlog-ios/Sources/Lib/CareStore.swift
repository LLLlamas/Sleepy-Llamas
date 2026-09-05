import Foundation
import SwiftData
import MoonlogCore

/// The only writer. CloudKit forbids unique constraints and `.deny`, so invariants
/// like "one open sleep session per baby" and "never hard-delete a baby" live here
/// instead of in the schema — a stray `context.insert` elsewhere bypasses them all.
/// See `docs/architecture.md`.
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
            // Appended, so an existing twin's card never moves.
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            accent: BabyAccent.forIndex(existing.count)
        )
        baby.family = family
        modelContext.insert(baby)
        try modelContext.save()
        return baby.id
    }

    func setVolumeUnit(_ unit: VolumeUnit, familyID: UUID) throws {
        guard let family = try family(familyID) else { throw CareStoreError.familyNotFound }
        family.volumeUnitRaw = unit.rawValue
        try modelContext.save()
    }

    func setOptionalKinds(_ kinds: [EventKind], familyID: UUID) throws {
        guard let family = try family(familyID) else { throw CareStoreError.familyNotFound }
        family.setOptionalKinds(kinds)
        try modelContext.save()
    }

    /// Note tags are user-defined. Until this existed they could only be created by
    /// the DEBUG demo seed, so the tag row never appeared in a real install.
    func addNoteTag(_ label: String, familyID: UUID) throws {
        guard let family = try family(familyID) else { throw CareStoreError.familyNotFound }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CareStoreError.emptyName }
        let existing = family.noteTags ?? []
        guard !existing.contains(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        let tag = NoteTagPreset(
            label: trimmed, sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
        tag.family = family
        modelContext.insert(tag)
        try modelContext.save()
    }

    func deleteNoteTag(_ id: UUID) throws {
        guard let tag = try one(
            FetchDescriptor<NoteTagPreset>(predicate: #Predicate { $0.id == id }))
        else { return }
        modelContext.delete(tag)
        try modelContext.save()
    }

    /// Accent is the user's choice; the auto-assigned default only makes twins
    /// distinct before anyone picks.
    func updateBaby(_ babyID: UUID, name: String? = nil, accent: BabyAccent? = nil) throws {
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CareStoreError.emptyName }
            baby.name = trimmed
        }
        if let accent { baby.accentRaw = accent.rawValue }
        try modelContext.save()
    }

    /// Archives rather than deletes: a hard delete would strip the baby's name from
    /// every past handoff. There is deliberately no public delete.
    func archiveBaby(_ babyID: UUID) throws {
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        baby.isArchived = true
        try modelContext.save()
    }

    // MARK: - Shift lifecycle

    /// `startedAt` is set or confirmed by the doula, never read off the clock.
    /// Refuses if one is already open — a second open shift becomes invisible in
    /// every screen and its logs unreachable.
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

    /// Ends a shift without opening a replacement — the doula is leaving the baby
    /// with the parents. An in-progress sleep is deliberately left open; totals clip
    /// to the shift window instead. See `docs/architecture.md`.
    func endShift(_ shiftID: UUID, endedAt: Date) throws {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        guard shift.isOpen else { throw CareStoreError.shiftAlreadyClosed }
        guard endedAt >= shift.startedAt else { throw CareStoreError.endBeforeStart }
        shift.close(at: endedAt)
        try modelContext.save()
    }

    /// Filtered in the predicate, not in memory — filtering a limited fetch can
    /// silently miss one. Returns a value type: `@Model` is not `Sendable`.
    func openShift(familyID: UUID) throws -> ShiftSummary? {
        return try one(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.isOpen && $0.familyIDRaw == familyID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])).map(ShiftSummary.init)
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
        event.attach(to: shift, baby: baby)
        modelContext.insert(event)
        try modelContext.save()
        return event.id
    }

    /// Applies a patch to an existing event. Payload fields are set wholesale by
    /// the caller's closure, so clearing a value means assigning nil — the sheets
    /// rebuild the whole payload rather than diffing it.
    func updateEvent(
        _ eventID: UUID,
        at: Date,
        configure: (LogEvent) -> Void
    ) throws {
        guard let event = try one(
            FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == eventID }))
        else { throw CareStoreError.eventNotFound }
        event.at = at
        configure(event)
        try modelContext.save()
    }

    /// Moves an event to a different baby. The whole reason the confirmation names
    /// the baby is so a wrong-twin tap is caught — this is how it gets fixed.
    func reassignEvent(_ eventID: UUID, toBaby babyID: UUID) throws {
        guard let event = try one(
            FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == eventID }))
        else { throw CareStoreError.eventNotFound }
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        event.baby = baby
        event.babyIDRaw = baby.id
        try modelContext.save()
    }

    func deleteEvent(_ eventID: UUID) throws {
        let descriptor = FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == eventID })
        guard let event = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(event)
        try modelContext.save()
    }

    // MARK: - Sleep

    /// Serialised by the actor, so a double-tap cannot open two sessions; the
    /// reconciler mops up anything sync delivers.
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

    /// Corrects the running session, or records one that was missed.
    ///
    /// Reconciles afterwards. Without it, correcting a session that was *already
    /// closed* — the "I tapped Wake ten minutes late" case — falls through to the
    /// insert branch and writes a second, overlapping session. Totals sum sessions
    /// independently, so the parents would be told the baby slept roughly twice as
    /// long as she did.
    func recordSleep(shiftID: UUID, babyID: UUID, startAt: Date, endAt: Date?) throws {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        if let endAt, endAt <= startAt { throw CareStoreError.endBeforeStart }

        if let existing = try storedOpenSleepSession(shiftID: shiftID, babyID: babyID) {
            existing.startAt = startAt
            if let endAt { existing.close(at: endAt) }
        } else {
            let session = SleepSession(startAt: startAt, endAt: endAt)
            session.attach(to: shift, baby: baby)
            modelContext.insert(session)
        }
        try modelContext.save()
        try reconcileSleep(shiftID: shiftID, babyID: babyID)
    }

    /// Corrects a specific session by id — the path the timeline uses. Unlike
    /// `recordSleep` this never inserts, so editing cannot duplicate.
    func updateSleepSession(_ id: UUID, startAt: Date, endAt: Date?) throws {
        guard let session = try one(
            FetchDescriptor<SleepSession>(predicate: #Predicate { $0.id == id }))
        else { return }
        if let endAt, endAt <= startAt { throw CareStoreError.endBeforeStart }
        session.startAt = startAt
        if let endAt {
            session.close(at: endAt)
        } else {
            session.endAt = nil
            session.isOpen = true
        }
        try modelContext.save()
        try reconcileSleep(
            shiftID: session.shiftIDRaw ?? UUID(), babyID: session.babyIDRaw ?? UUID())
    }

    /// Removes a sleep session outright. A closed session is otherwise unreachable.
    func deleteSleepSession(_ id: UUID) throws {
        guard let session = try one(
            FetchDescriptor<SleepSession>(predicate: #Predicate { $0.id == id }))
        else { return }
        modelContext.delete(session)
        try modelContext.save()
    }

    func openSleepSession(shiftID: UUID, babyID: UUID) throws -> SleepSnapshot? {
        try storedOpenSleepSession(shiftID: shiftID, babyID: babyID)?.snapshot
    }

    private func storedOpenSleepSession(shiftID: UUID, babyID: UUID) throws -> SleepSession? {
        return try one(FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.isOpen && $0.babyIDRaw == babyID && $0.shiftIDRaw == shiftID },
            sortBy: [SortDescriptor(\.startAt)]))
    }

    /// Required, not defensive: CloudKit cannot enforce uniqueness, so two devices
    /// can both open a session for one baby and the store accepts both.
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

    // Three near-identical bodies rather than one generic: #Predicate needs a
    // concrete key path, so a generic over `PersistentModel` will not compile.
    private func family(_ id: UUID) throws -> Family? {
        try one(FetchDescriptor<Family>(predicate: #Predicate { $0.id == id }))
    }

    private func baby(_ id: UUID) throws -> Baby? {
        try one(FetchDescriptor<Baby>(predicate: #Predicate { $0.id == id }))
    }

    private func shift(_ id: UUID) throws -> Shift? {
        try one(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id }))
    }

    private func one<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> T? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
    case emptyName
    case eventNotFound
}
