import XCTest
import SwiftData
import MoonlogCore
@testable import Moonlog

/// Reconciliation must consult the current store, not stale main-context arrays.
/// These tests do not grant notification permissions or send OS notifications.
@MainActor
final class ReminderLifecycleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_788_000_000)

    private func fixture() async throws -> (ModelContainer, CareStore, UUID, UUID, UUID, UUID) {
        let config = ModelConfiguration(schema: ModelContainerFactory.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ModelContainerFactory.schema, configurations: config)
        let store = CareStore(modelContainer: container)
        let family = try await store.createFamily(name: "Family one")
        let baby = try await store.addBaby(to: family, name: "Mia", birthAt: start.addingTimeInterval(-86400))
        let shift = try await store.startShift(familyID: family, startedAt: start, caregiver: "Cat")
        let feed = try await store.logEvent(kind: .feed, at: start, shiftID: shift, babyID: baby) { _ in }
        return (container, store, family, baby, shift, feed)
    }

    func testEndingOneFamilyShiftLeavesOtherFamiliesEligible() async throws {
        let (container, store, family, _, shift, feed) = try await fixture()
        let other = try await store.createFamily(name: "Family two")
        let baby = try await store.addBaby(to: other, name: "Leo", birthAt: start.addingTimeInterval(-86400))
        let otherShift = try await store.startShift(familyID: other, startedAt: start, caregiver: "Cat")
        let otherFeed = try await store.logEvent(kind: .feed, at: start, shiftID: otherShift, babyID: baby) { _ in }
        XCTAssertEqual(try FeedReminders.validEventIDs(in: container), Set([feed, otherFeed]))
        try await store.endShift(shift, endedAt: start.addingTimeInterval(3600))
        XCTAssertEqual(try FeedReminders.validEventIDs(in: container), Set([otherFeed]))
        try await store.deleteFamily(family)
        XCTAssertEqual(try FeedReminders.validEventIDs(in: container), Set([otherFeed]))
        try await store.eraseEverything()
        XCTAssertTrue(try FeedReminders.validEventIDs(in: container).isEmpty)
    }

    func testDeletedFeedAndArchivedBabyAreNotEligible() async throws {
        let (container, store, _, baby, shift, feed) = try await fixture()
        try await store.deleteEvent(feed)
        XCTAssertTrue(try FeedReminders.validEventIDs(in: container).isEmpty)
        _ = try await store.logEvent(kind: .feed, at: start, shiftID: shift, babyID: baby) { _ in }
        XCTAssertEqual(try FeedReminders.validEventIDs(in: container).count, 1)
        try await store.archiveBaby(baby)
        XCTAssertTrue(try FeedReminders.validEventIDs(in: container).isEmpty)
    }

    func testUndoAndWrongTwinKeepTheSameNotificationIdentity() async throws {
        let (container, store, family, _, _, feed) = try await fixture()
        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<LogEvent>())
        let restoration = try XCTUnwrap(events.first { $0.id == feed }?.restoration)
        try await store.deleteEvent(feed)
        XCTAssertTrue(try FeedReminders.validEventIDs(in: container).isEmpty)
        try await store.restoreEvent(restoration)
        XCTAssertEqual(try FeedReminders.validEventIDs(in: container), Set([feed]))
        let twin = try await store.addBaby(to: family, name: "Leo", birthAt: start.addingTimeInterval(-86400))
        try await store.reassignEvent(feed, toBaby: twin)
        XCTAssertEqual(try FeedReminders.validEventIDs(in: container), Set([feed]))
        XCTAssertEqual(FeedReminders.identifier(for: feed), feed.uuidString)
    }
}
