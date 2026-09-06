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

    /// The starting note tags, carried over from the retired PWA. They shipped
    /// empty before, so the tag row never appeared and every user had to invent the
    /// vocabulary. "Jaundice watch" is deliberate phrasing — an observation, not a
    /// diagnosis, matching the app's scope.
    static let defaultNoteTags = ["Spit-up", "Fussy", "Jaundice watch", "Pumped", "Temp"]

    func createFamily(
        name: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> UUID {
        let family = Family(name: name, timeZoneIdentifier: timeZoneIdentifier)
        modelContext.insert(family)
        for (i, label) in Self.defaultNoteTags.enumerated() {
            let tag = NoteTagPreset(label: label, sortOrder: i)
            tag.family = family
            modelContext.insert(tag)
        }
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
        try rejectFuture(startedAt)
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
        try rejectFuture(endedAt)
        guard endedAt >= shift.startedAt else { throw CareStoreError.endBeforeStart }
        shift.close(at: endedAt)
        try modelContext.save()
    }

    /// The note that goes to the parents. Editable for as long as the shift exists —
    /// it is the one part of the handoff written rather than recorded, and the
    /// sentence you want at 6am is rarely the one you had at 5.
    func setShiftNote(_ shiftID: UUID, text: String?) throws {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        shift.parentNote = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try modelContext.save()
    }

    /// Corrects a shift's own hours after the fact. Both ends belong to the doula,
    /// which is why `startShift` and `endShift` are handed a time rather than reading
    /// one — ending thirty minutes late widens the window and credits sleep nobody
    /// watched. `nil` leaves that end alone; a closed shift cannot be reopened here,
    /// because `close(at:)` is the only thing keeping `isOpen` honest.
    func updateShift(_ shiftID: UUID, startedAt: Date? = nil, endedAt: Date? = nil) throws {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        let start = startedAt ?? shift.startedAt
        let end = endedAt ?? shift.endedAt
        try rejectFuture(start)
        if let end {
            try rejectFuture(end)
            guard end >= start else { throw CareStoreError.endBeforeStart }
        }

        // Narrowing the window can strand a session outside it, where the timeline
        // still shows a duration but the totals and the handoff — which both clip to
        // this window — count nothing. Refuse rather than silently drop the hours.
        let proposed = ShiftWindow(startedAt: start, endedAt: end)
        for session in shift.sleepSessions ?? [] {
            try requireOverlap(startAt: session.startAt, endAt: session.endAt, with: proposed)
        }

        shift.startedAt = start
        if let endedAt { shift.close(at: endedAt) }
        try modelContext.save()
    }

    // MARK: - Time rules
    //
    // These live here, not in the sheets. `LogSheetChrome` shows the same advisories
    // as you type, but that is a courtesy to the thumb — it is not the enforcement.
    // Anything that is not a sheet (the reconciler, an NFC tap, a future import)
    // reaches these instead. `CLAUDE.md` puts invariants in the actor for exactly
    // this reason.

    /// The same `isMeaningfullyInFuture` the sheets bound their pickers with, so the
    /// advisory and the enforcement can never disagree — a sheet saying a time is
    /// fine while the actor refuses it would be maddening at 3am. Its minute of
    /// slack covers clock skew between two synced devices; twelve hours out — the
    /// web version's actual bug, which suppressed the overdue-feed warning for the
    /// rest of the night — is still refused.
    private func rejectFuture(_ date: Date) throws {
        guard !date.isMeaningfullyInFuture else { throw CareStoreError.futureTimestamp }
    }

    /// An open session has no end yet, so it runs to `distantFuture` for this test
    /// and always overlaps an open shift. Touching at an instant is not overlap: a
    /// session ending exactly at the start contributes nothing.
    private func requireOverlap(startAt: Date, endAt: Date?, with window: ShiftWindow) throws {
        let sessionEnd = endAt ?? .distantFuture
        let shiftEnd = window.endedAt ?? .distantFuture
        guard sessionEnd > window.startedAt, startAt < shiftEnd else {
            throw CareStoreError.outsideShift
        }
    }

    /// Filtered in the predicate, not in memory — filtering a limited fetch can
    /// silently miss one. Returns a value type: `@Model` is not `Sendable`.
    func openShift(familyID: UUID) throws -> ShiftSummary? {
        return try one(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.isOpen && $0.familyIDRaw == familyID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])).map(ShiftSummary.init)
    }

    // MARK: - Logging

    /// `babyID` is optional only because `pump` is about the mother. Every other
    /// kind must name a baby: an unattributed feed cannot be counted for either
    /// twin, so the totals and the handoff would quietly drop it.
    func logEvent(
        kind: EventKind,
        at: Date,
        shiftID: UUID,
        babyID: UUID?,
        source: EventSource = .manual,
        configure: (LogEvent) -> Void = { _ in }
    ) throws -> UUID {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        let baby = try requiredBaby(babyID, for: kind)
        try rejectFuture(at)

        let event = LogEvent(kind: kind, at: at, source: source)
        configure(event)
        event.attach(to: shift, baby: baby)
        modelContext.insert(event)
        try modelContext.save()
        return event.id
    }

    /// Puts a deleted event back as it was, for Undo. Deliberately not `logEvent`:
    /// a new tap deserves a new identity, an undo does not — see
    /// `LogEvent.restoration`. Re-running it is harmless, so a double-tap on Undo
    /// cannot produce two copies.
    func restoreEvent(_ restoration: EventRestoration) throws {
        guard let shift = try shift(restoration.shiftID) else {
            throw CareStoreError.shiftNotFound
        }
        let restoredID = restoration.id
        if try one(FetchDescriptor<LogEvent>(
            predicate: #Predicate { $0.id == restoredID })) != nil { return }

        let baby = try requiredBaby(restoration.babyID, for: restoration.kind)
        let event = LogEvent(
            id: restoration.id, kind: restoration.kind, at: restoration.at,
            createdAt: restoration.createdAt, source: restoration.source)
        restoration.applyPayload(to: event)
        event.attach(to: shift, baby: baby)
        modelContext.insert(event)
        try modelContext.save()
    }

    private func requiredBaby(_ babyID: UUID?, for kind: EventKind) throws -> Baby? {
        guard kind.attachesToBaby else { return babyID.flatMap { try? baby($0) } }
        guard let babyID, let baby = try baby(babyID) else {
            throw CareStoreError.babyNotFound
        }
        return baby
    }

    /// Applies a patch to an existing event. Payload fields are set wholesale by
    /// the caller's closure, so clearing a value means assigning nil — the sheets
    /// rebuild the whole payload rather than diffing it.
    func updateEvent(
        _ eventID: UUID,
        at: Date,
        configure: (LogEvent) -> Void
    ) throws {
        guard let event = try event(eventID) else { throw CareStoreError.eventNotFound }
        try rejectFuture(at)
        event.at = at
        configure(event)
        try modelContext.save()
    }

    /// Moves an event to a different baby. The whole reason the confirmation names
    /// the baby is so a wrong-twin tap is caught — this is how it gets fixed.
    func reassignEvent(_ eventID: UUID, toBaby babyID: UUID) throws {
        guard let event = try event(eventID) else { throw CareStoreError.eventNotFound }
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        event.baby = baby
        event.babyIDRaw = baby.id
        try modelContext.save()
    }

    func deleteEvent(_ eventID: UUID) throws {
        guard let event = try event(eventID) else { return }
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
        try rejectFuture(date)

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
        try rejectFuture(startAt)
        if let endAt { try rejectFuture(endAt) }
        if let endAt, endAt <= startAt { throw CareStoreError.endBeforeStart }
        try requireOverlap(startAt: startAt, endAt: endAt, with: shift.window)

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
        try rejectFuture(startAt)
        if let endAt { try rejectFuture(endAt) }
        if let endAt, endAt <= startAt { throw CareStoreError.endBeforeStart }
        if let shiftID = session.shiftIDRaw, let shift = try shift(shiftID) {
            try requireOverlap(startAt: startAt, endAt: endAt, with: shift.window)
        }
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

    /// Puts a deleted sleep session back under its own id, for Undo.
    ///
    /// `recordSleep` cannot serve as the undo here: when another session is already
    /// open it corrects *that* one rather than inserting, so undoing a deleted
    /// closed session would silently drag a live one back in time. Re-running this
    /// is harmless, so a double-tap on Undo cannot produce two copies.
    func restoreSleepSession(
        id: UUID, shiftID: UUID, babyID: UUID, startAt: Date, endAt: Date?
    ) throws {
        guard let shift = try shift(shiftID) else { throw CareStoreError.shiftNotFound }
        guard let baby = try baby(babyID) else { throw CareStoreError.babyNotFound }
        if try one(FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.id == id })) != nil { return }

        let session = SleepSession(id: id, startAt: startAt, endAt: endAt)
        session.attach(to: shift, baby: baby)
        modelContext.insert(session)
        try modelContext.save()
        try reconcileSleep(shiftID: shiftID, babyID: babyID)
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

    private func event(_ id: UUID) throws -> LogEvent? {
        try one(FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id }))
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
    case futureTimestamp
    case outsideShift
}

/// Every view already surfaces failures as `"\(error)"`, so the readable text has
/// to come through `description` as well — conforming to `LocalizedError` alone
/// would leave the alerts saying "futureTimestamp".
extension CareStoreError: CustomStringConvertible {
    var description: String { errorDescription ?? "Something went wrong." }
}

extension CareStoreError: LocalizedError {
    /// The alert is the only thing the doula sees when a write is refused at 3am,
    /// so it says what to do, not which case fired.
    var errorDescription: String? {
        switch self {
        case .familyNotFound: return "That client family is no longer on this device."
        case .babyNotFound: return "That baby is no longer on this device."
        case .shiftNotFound: return "That shift is no longer on this device."
        case .shiftAlreadyOpen: return "A shift is already running. End it first."
        case .shiftAlreadyClosed: return "That shift has already ended."
        case .endBeforeStart: return "That would end before it started. Check the times."
        case .emptyName: return "A name is needed."
        case .eventNotFound: return "That entry has already been removed."
        case .futureTimestamp: return "That time hasn't happened yet."
        case .outsideShift: return "That falls outside the shift, where it wouldn't be counted."
        }
    }
}
