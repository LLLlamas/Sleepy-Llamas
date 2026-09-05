import XCTest
import SwiftData
import MoonlogCore
@testable import Moonlog

/// The invariants CloudKit will not let the schema express, so the store has to.
final class CareStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var store: CareStore!

    private let shiftStart = Date(timeIntervalSince1970: 1_788_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(
            schema: ModelContainerFactory.schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: ModelContainerFactory.schema, configurations: config)
        store = CareStore(modelContainer: container)
    }

    override func tearDown() {
        store = nil
        container = nil
    }

    private func makeFamilyWithTwins() async throws -> (UUID, UUID, UUID) {
        let family = try await store.createFamily(name: "Nguyen")
        let birth = Date(timeIntervalSince1970: 1_787_000_000)
        let mia = try await store.addBaby(to: family, name: "Mia", birthAt: birth)
        let leo = try await store.addBaby(to: family, name: "Leo", birthAt: birth)
        return (family, mia, leo)
    }

    // MARK: - Shift lifecycle

    /// Two open shifts is the web version's bug where the second becomes invisible
    /// in every screen and its logs unreachable.
    func testCannotOpenASecondShiftWhileOneIsRunning() async throws {
        let (family, _, _) = try await makeFamilyWithTwins()
        _ = try await store.startShift(familyID: family, startedAt: shiftStart, caregiver: "Cat")

        do {
            _ = try await store.startShift(
                familyID: family, startedAt: shiftStart.addingTimeInterval(60), caregiver: "Cat")
            XCTFail("expected a second open shift to be refused")
        } catch {
            XCTAssertEqual(error as? CareStoreError, .shiftAlreadyOpen)
        }
    }

    /// Ending a shift ends it. The doula is leaving the baby with the parents, so
    /// there is no next shift until she starts one.
    func testEndingAShiftDoesNotOpenAReplacement() async throws {
        let (family, _, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        try await store.endShift(shift, endedAt: shiftStart.addingTimeInterval(8 * 3600))

        let open = try await store.openShift(familyID: family)
        XCTAssertNil(open, "no shift should be open between visits")
    }

    /// An in-progress sleep stays open at handoff. "Still asleep when I left" is
    /// the record the parents want; totals clip to the shift window instead.
    func testEndingAShiftLeavesAnInProgressSleepOpen() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        try await store.toggleSleep(
            shiftID: shift, babyID: mia, at: shiftStart.addingTimeInterval(7 * 3600 + 2400))

        let end = shiftStart.addingTimeInterval(8 * 3600)
        try await store.endShift(shift, endedAt: end)

        let snapshot = try await store.openSleepSession(shiftID: shift, babyID: mia)
        XCTAssertNotNil(snapshot, "the session stays open — it is clipped, not closed")

        // And the total is bounded by the shift end rather than growing.
        let session = try XCTUnwrap(snapshot)
        let window = ShiftWindow(startedAt: shiftStart, endedAt: end)
        XCTAssertEqual(
            SleepMath.seconds(of: session, clippedTo: window,
                              asOf: end.addingTimeInterval(7 * 24 * 3600)),
            20 * 60, accuracy: 0.5)
    }

    func testCannotEndAShiftBeforeItStarted() async throws {
        let (family, _, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        do {
            try await store.endShift(shift, endedAt: shiftStart.addingTimeInterval(-60))
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error as? CareStoreError, .endBeforeStart)
        }
    }

    func testCannotEndAnAlreadyClosedShift() async throws {
        let (family, _, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        let end = shiftStart.addingTimeInterval(3600)
        try await store.endShift(shift, endedAt: end)
        do {
            try await store.endShift(shift, endedAt: end)
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error as? CareStoreError, .shiftAlreadyClosed)
        }
    }

    /// A new shift after the last one closed must be allowed — the doula comes back
    /// the next night.
    func testCanStartAFreshShiftAfterTheLastOneClosed() async throws {
        let (family, _, _) = try await makeFamilyWithTwins()
        let first = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        try await store.endShift(first, endedAt: shiftStart.addingTimeInterval(8 * 3600))

        let second = try await store.startShift(
            familyID: family, startedAt: shiftStart.addingTimeInterval(24 * 3600),
            caregiver: "Cat")
        XCTAssertNotEqual(second, first)
        let openNow = try await store.openShift(familyID: family)
        XCTAssertEqual(openNow?.id, second)
    }

    // MARK: - Twins

    func testSleepTogglesAreIndependentPerBaby() async throws {
        let (family, mia, leo) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        try await store.toggleSleep(shiftID: shift, babyID: mia, at: shiftStart)

        let miaOpen = try await store.openSleepSession(shiftID: shift, babyID: mia)
        let leoOpen = try await store.openSleepSession(shiftID: shift, babyID: leo)
        XCTAssertNotNil(miaOpen, "Mia is asleep")
        XCTAssertNil(leoOpen, "Leo is not, and Mia's session must not say otherwise")
    }

    /// Twins get distinct accents automatically, and stable positions.
    func testTwinsGetDistinctAccentsAndStableOrder() async throws {
        let (family, mia, leo) = try await makeFamilyWithTwins()
        let context = ModelContext(container)
        let babies = try context.fetch(FetchDescriptor<Baby>())
            .filter { $0.family?.id == family }
            .sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(babies.map(\.id), [mia, leo])
        XCTAssertNotEqual(babies[0].accent, babies[1].accent)
    }

    /// The web version's double-tap-in-the-dark bug. The actor serialises the
    /// read-then-write that was previously unguarded.
    func testRapidRepeatedTogglesNeverLeaveTwoOpenSessions() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        for i in 0..<9 {
            try await store.toggleSleep(
                shiftID: shift, babyID: mia, at: shiftStart.addingTimeInterval(Double(i) * 600))
        }

        let context = ModelContext(container)
        let open = try context.fetch(FetchDescriptor<SleepSession>())
            .filter { $0.babyIDRaw == mia && $0.isOpen }
        XCTAssertEqual(open.count, 1, "odd number of toggles leaves exactly one open")
    }

    // MARK: - Manual sleep entry

    /// The web version added 24 hours instead of refusing, so nudging "woke" back
    /// past "asleep" silently recorded a 23-hour sleep.
    func testRecordSleepRejectsAnEndBeforeItsStart() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        do {
            try await store.recordSleep(
                shiftID: shift, babyID: mia,
                startAt: shiftStart.addingTimeInterval(3600),
                endAt: shiftStart.addingTimeInterval(1800))
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error as? CareStoreError, .endBeforeStart)
        }
    }

    /// Correcting a mistimed toggle must edit the running session, never open a
    /// second one alongside it.
    func testRecordSleepCorrectsTheRunningSessionInsteadOfAddingOne() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        try await store.toggleSleep(
            shiftID: shift, babyID: mia, at: shiftStart.addingTimeInterval(3600))

        let corrected = shiftStart.addingTimeInterval(1800)
        try await store.recordSleep(
            shiftID: shift, babyID: mia, startAt: corrected, endAt: nil)

        let sessions = try ModelContext(container)
            .fetch(FetchDescriptor<SleepSession>())
            .filter { $0.babyIDRaw == mia }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].startAt, corrected)
        XCTAssertTrue(sessions[0].isOpen)
    }

    func testRecordSleepClosesTheRunningSessionWhenGivenAnEnd() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        try await store.toggleSleep(shiftID: shift, babyID: mia, at: shiftStart)

        let end = shiftStart.addingTimeInterval(5400)
        try await store.recordSleep(
            shiftID: shift, babyID: mia, startAt: shiftStart, endAt: end)

        let stillOpen = try await store.openSleepSession(shiftID: shift, babyID: mia)
        XCTAssertNil(stillOpen)
        let sessions = try ModelContext(container).fetch(FetchDescriptor<SleepSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].endAt, end)
    }

    func testRecordSleepCreatesAClosedSessionWhenNoneIsRunning() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        try await store.recordSleep(
            shiftID: shift, babyID: mia,
            startAt: shiftStart.addingTimeInterval(600),
            endAt: shiftStart.addingTimeInterval(4200))

        let sessions = try ModelContext(container).fetch(FetchDescriptor<SleepSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertFalse(sessions[0].isOpen)
        XCTAssertEqual(sessions[0].babyIDRaw, mia, "attribution set via attach")
    }

    /// The correction path. Wake the baby, then adjust the time — there is no open
    /// session any more, so `recordSleep` used to fall through to its insert branch
    /// and write a SECOND overlapping session. Totals sum sessions independently, so
    /// the handoff reported roughly double the real sleep.
    func testCorrectingAJustClosedSessionDoesNotDoubleCount() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        // Asleep 22:00, "Wake" tapped at 23:30.
        try await store.toggleSleep(shiftID: shift, babyID: mia, at: shiftStart)
        try await store.toggleSleep(
            shiftID: shift, babyID: mia, at: shiftStart.addingTimeInterval(5400))

        // Realises the wake tap was late; corrects to 22:00–23:20.
        try await store.recordSleep(
            shiftID: shift, babyID: mia,
            startAt: shiftStart,
            endAt: shiftStart.addingTimeInterval(4800))

        let sessions = try ModelContext(container)
            .fetch(FetchDescriptor<SleepSession>())
            .filter { $0.babyIDRaw == mia }
            .sorted { $0.startAt < $1.startAt }

        // Whatever the merge decides, the invariant is that nothing overlaps —
        // overlapping sessions are what produce the doubled total.
        for (a, b) in zip(sessions, sessions.dropFirst()) {
            let aEnd = try XCTUnwrap(a.endAt, "only the last session may be open")
            XCTAssertLessThanOrEqual(aEnd, b.startAt, "sessions must not overlap")
        }

        let snapshots = sessions.compactMap(\.snapshot)
        let window = ShiftWindow(startedAt: shiftStart, endedAt: nil)
        let total = SleepMath.totalSeconds(
            of: snapshots, clippedTo: window,
            asOf: shiftStart.addingTimeInterval(6 * 3600))
        XCTAssertLessThanOrEqual(
            total, 5400,
            "total cannot exceed the real 90-minute stretch — it was ~2x before")
    }

    // MARK: - Reconciliation

    /// Simulates what CloudKit can actually deliver: two devices each opening a
    /// session for the same baby. No schema constraint can prevent it.
    func testReconcileCollapsesDuplicateOpenSessionsFromSync() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        // Insert two open sessions three seconds apart behind the store's back,
        // the way a sync merge would.
        let context = ModelContext(container)
        let shiftModel = try XCTUnwrap(
            context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == shift })).first)
        let babyModel = try XCTUnwrap(
            context.fetch(FetchDescriptor<Baby>(predicate: #Predicate { $0.id == mia })).first)
        for offset in [0.0, 3.0] {
            let s = SleepSession(startAt: shiftStart.addingTimeInterval(offset))
            s.attach(to: shiftModel, baby: babyModel)
            context.insert(s)
        }
        try context.save()

        try await store.reconcileSleep(shiftID: shift, babyID: mia)

        let remaining = try ModelContext(container)
            .fetch(FetchDescriptor<SleepSession>())
            .filter { $0.babyIDRaw == mia }
        XCTAssertEqual(remaining.count, 1, "a double-registered tap collapses to one")
        XCTAssertTrue(remaining[0].isOpen)
    }

    // MARK: - Editing

    /// The accent is the user's choice. The auto-assigned default only exists so
    /// twins are distinct before anyone picks.
    func testUpdatingBabyNameAndAccent() async throws {
        let (_, mia, _) = try await makeFamilyWithTwins()
        try await store.updateBaby(mia, name: "  Amelia  ", accent: .lilac)

        let baby = try XCTUnwrap(
            ModelContext(container)
                .fetch(FetchDescriptor<Baby>(predicate: #Predicate { $0.id == mia })).first)
        XCTAssertEqual(baby.name, "Amelia", "whitespace trimmed")
        XCTAssertEqual(baby.accent, .lilac)
    }

    func testUpdatingEitherFieldAloneLeavesTheOther() async throws {
        let (_, mia, _) = try await makeFamilyWithTwins()
        try await store.updateBaby(mia, accent: .sky)
        try await store.updateBaby(mia, name: "Amelia")

        let baby = try XCTUnwrap(
            ModelContext(container)
                .fetch(FetchDescriptor<Baby>(predicate: #Predicate { $0.id == mia })).first)
        XCTAssertEqual(baby.name, "Amelia")
        XCTAssertEqual(baby.accent, .sky)
    }

    /// A blank name would leave a timeline row identified by colour alone.
    func testBlankNameIsRejected() async throws {
        let (_, mia, _) = try await makeFamilyWithTwins()
        do {
            try await store.updateBaby(mia, name: "   ")
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error as? CareStoreError, .emptyName)
        }
    }

    // MARK: - Babies are archived, never deleted

    func testArchivingABabyKeepsItAndItsRecords() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")
        _ = try await store.logEvent(
            kind: .feed, at: shiftStart.addingTimeInterval(600), shiftID: shift, babyID: mia)

        try await store.archiveBaby(mia)

        let context = ModelContext(container)
        let babies = try context.fetch(FetchDescriptor<Baby>())
        XCTAssertEqual(babies.count, 2, "archived, not deleted")
        XCTAssertTrue(try XCTUnwrap(babies.first { $0.id == mia }).isArchived)

        let events = try context.fetch(FetchDescriptor<LogEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].babyIDRaw, mia, "attribution intact")

        let familyModel = try XCTUnwrap(
            context.fetch(FetchDescriptor<Family>(predicate: #Predicate { $0.id == family })).first)
        XCTAssertEqual(familyModel.activeBabies.map(\.name), ["Leo"])
    }

    // MARK: - Logging

    func testLoggingAttachesBothRelationshipAndDenormalisedID() async throws {
        let (family, mia, _) = try await makeFamilyWithTwins()
        let shift = try await store.startShift(
            familyID: family, startedAt: shiftStart, caregiver: "Cat")

        _ = try await store.logEvent(
            kind: .feed, at: shiftStart.addingTimeInterval(600),
            shiftID: shift, babyID: mia
        ) { event in
            event.feedMethodRaw = FeedMethod.bottleFormula.rawValue
            event.amountMl = 60
            event.feedDurationSeconds = 900
        }

        let event = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<LogEvent>()).first)
        XCTAssertEqual(event.babyIDRaw, event.baby?.id)
        XCTAssertEqual(event.shiftIDRaw, event.shift?.id)
        XCTAssertEqual(event.feedMethod, .bottleFormula)
        XCTAssertEqual(event.amountMl, 60)
    }

    func testLoggingAgainstAMissingShiftThrows() async throws {
        let (_, mia, _) = try await makeFamilyWithTwins()
        do {
            _ = try await store.logEvent(
                kind: .feed, at: shiftStart, shiftID: UUID(), babyID: mia)
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error as? CareStoreError, .shiftNotFound)
        }
    }
}
