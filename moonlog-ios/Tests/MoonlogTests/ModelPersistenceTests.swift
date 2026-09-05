import XCTest
import SwiftData
import MoonlogCore
@testable import Moonlog

/// Persistence-layer behaviour that only a real store can verify: relationship
/// wiring, delete rules, and that the `#Predicate` shapes we rely on actually
/// compile and return rows. Predicate breakage is a *runtime* failure in
/// SwiftData, so it cannot be caught by the type checker.
@MainActor
final class ModelPersistenceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(
            schema: ModelContainerFactory.schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: ModelContainerFactory.schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func makeHousehold() throws -> (Family, Baby, Baby, Shift) {
        let family = Family(name: "Nguyen")
        let mia = Baby(name: "Mia", birthAt: Date(timeIntervalSince1970: 1_780_000_000),
                       sortOrder: 0, accent: .gold)
        let leo = Baby(name: "Leo", birthAt: Date(timeIntervalSince1970: 1_780_000_000),
                       sortOrder: 1, accent: .sage)
        let shift = Shift(startedAt: Date(timeIntervalSince1970: 1_788_000_000),
                          caregiver: "Cat")
        mia.family = family
        leo.family = family
        shift.family = family
        context.insert(family)
        context.insert(mia)
        context.insert(leo)
        context.insert(shift)
        try context.save()
        return (family, mia, leo, shift)
    }

    // MARK: - Wiring

    func testRelationshipsAndInversesPopulate() throws {
        let (family, mia, _, shift) = try makeHousehold()

        XCTAssertEqual(family.babies?.count, 2)
        XCTAssertEqual(family.shifts?.count, 1)
        XCTAssertEqual(mia.family?.id, family.id)
        XCTAssertEqual(shift.family?.id, family.id)
    }

    /// Twin order must be stable — card position is muscle memory at 3am.
    func testActiveBabiesIsSortedAndExcludesArchived() throws {
        let (family, mia, leo, _) = try makeHousehold()
        XCTAssertEqual(family.activeBabies.map(\.name), ["Mia", "Leo"])

        leo.isArchived = true
        try context.save()
        XCTAssertEqual(family.activeBabies.map(\.name), ["Mia"])
        _ = mia
    }

    func testAttachKeepsRelationshipAndDenormalisedIDInStep() throws {
        let (_, mia, _, shift) = try makeHousehold()
        let event = LogEvent(kind: .feed, at: Date(timeIntervalSince1970: 1_788_003_600))
        event.attach(to: shift, baby: mia)
        context.insert(event)
        try context.save()

        XCTAssertEqual(event.babyIDRaw, event.baby?.id)
        XCTAssertEqual(event.shiftIDRaw, event.shift?.id)
    }

    // MARK: - Delete rules

    func testDeletingAShiftCascadesToItsEvents() throws {
        let (_, mia, _, shift) = try makeHousehold()
        let event = LogEvent(kind: .diaper, at: Date(timeIntervalSince1970: 1_788_003_600))
        event.attach(to: shift, baby: mia)
        context.insert(event)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<LogEvent>()).count, 1)

        context.delete(shift)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<LogEvent>()).count, 0)
    }

    /// The reason `babyIDRaw` exists. `.deny` would have been the natural guard
    /// against deleting a baby that still has records, but CloudKit rejects it — so
    /// if a baby ever is deleted, `.nullify` clears the relationship and the
    /// denormalised id is the only thing preserving attribution.
    func testDeletingABabyKeepsItsEventsAndTheirAttribution() throws {
        let (_, mia, _, shift) = try makeHousehold()
        let miaID = mia.id
        let event = LogEvent(kind: .feed, at: Date(timeIntervalSince1970: 1_788_003_600))
        event.attach(to: shift, baby: mia)
        context.insert(event)
        try context.save()

        context.delete(mia)
        try context.save()

        let surviving = try context.fetch(FetchDescriptor<LogEvent>())
        XCTAssertEqual(surviving.count, 1, "a deleted baby must not destroy the record")
        XCTAssertNil(surviving[0].baby, "relationship is nullified")
        XCTAssertEqual(surviving[0].babyIDRaw, miaID, "attribution survives anyway")
    }

    // MARK: - Predicates

    /// Filtering on the raw String column must work. Comparing an enum-typed
    /// property throws `unsupportedPredicate` at runtime, and reaching through
    /// `.rawValue` inside the macro hard-crashes — hence the stored raw column.
    func testPredicateOnRawKindColumnCompilesAndReturnsRows() throws {
        let (_, mia, _, shift) = try makeHousehold()
        for kind in [EventKind.feed, .feed, .diaper, .note] {
            let event = LogEvent(kind: kind, at: Date(timeIntervalSince1970: 1_788_003_600))
            event.attach(to: shift, baby: mia)
            context.insert(event)
        }
        try context.save()

        // Captured OUTSIDE the macro — the pattern that reliably compiles.
        let feedRaw = EventKind.feed.rawValue
        let descriptor = FetchDescriptor<LogEvent>(
            predicate: #Predicate { $0.kindRaw == feedRaw },
            sortBy: [SortDescriptor(\.at, order: .reverse)])

        XCTAssertEqual(try context.fetch(descriptor).count, 2)
    }

    func testPredicateOnDenormalisedBabyIDCompilesAndReturnsRows() throws {
        let (_, mia, leo, shift) = try makeHousehold()
        for (baby, count) in [(mia, 3), (leo, 1)] {
            for _ in 0..<count {
                let event = LogEvent(kind: .feed, at: Date(timeIntervalSince1970: 1_788_003_600))
                event.attach(to: shift, baby: baby)
                context.insert(event)
            }
        }
        try context.save()

        let miaID = mia.id
        let descriptor = FetchDescriptor<LogEvent>(
            predicate: #Predicate { $0.babyIDRaw == miaID })
        XCTAssertEqual(try context.fetch(descriptor).count, 3)
    }

    /// `isOpen` is denormalised so the "is anything running" query is a Bool
    /// comparison rather than an optional-Date one. It must never disagree with
    /// the field it mirrors.
    func testCloseKeepsTheIsOpenFlagHonest() throws {
        let (_, mia, _, shift) = try makeHousehold()
        XCTAssertTrue(shift.isOpen)

        let session = SleepSession(startAt: Date(timeIntervalSince1970: 1_788_003_600))
        session.attach(to: shift, baby: mia)
        context.insert(session)
        try context.save()
        XCTAssertTrue(session.isOpen)

        session.close(at: Date(timeIntervalSince1970: 1_788_007_200))
        shift.close(at: Date(timeIntervalSince1970: 1_788_010_800))
        try context.save()

        XCTAssertFalse(session.isOpen)
        XCTAssertEqual(session.isOpen, session.endAt == nil)
        XCTAssertFalse(shift.isOpen)
        XCTAssertEqual(shift.isOpen, shift.endedAt == nil)
    }

    /// The bridge into MoonlogCore: a persisted session becomes the value type the
    /// pure logic works on.
    func testSnapshotBridgesIntoTheDomainLayer() throws {
        let (_, mia, _, shift) = try makeHousehold()
        let session = SleepSession(startAt: Date(timeIntervalSince1970: 1_788_003_600))
        session.attach(to: shift, baby: mia)
        context.insert(session)
        try context.save()

        let snapshot = try XCTUnwrap(session.snapshot)
        XCTAssertEqual(snapshot.babyID, mia.id)
        XCTAssertTrue(snapshot.isOpen)

        let seconds = SleepMath.seconds(
            of: snapshot, clippedTo: shift.window,
            asOf: Date(timeIntervalSince1970: 1_788_007_200))
        XCTAssertEqual(seconds, 3600, accuracy: 0.5)
    }
}
