import XCTest
import SwiftData
import MoonlogCore
@testable import Moonlog

@MainActor
final class DayReportPersistenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_788_000_000)
    private var end: Date { start.addingTimeInterval(8 * 3600) }
    private var container: ModelContainer!
    private var store: CareStore!

    override func setUpWithError() throws {
        container = try ModelContainer(for: ModelContainerFactory.schema,
                                       configurations: ModelConfiguration(schema: ModelContainerFactory.schema,
                                                                          isStoredInMemoryOnly: true))
        store = CareStore(modelContainer: container)
    }

    private func fixture(closed: Bool = true, context: CareContext = .day) async throws -> (UUID, UUID, UUID) {
        let family = try await store.createFamily(name: "Test household", timeZoneIdentifier: "America/New_York")
        let baby = try await store.addBaby(to: family, name: "Mia", birthAt: start.addingTimeInterval(-20 * 86400))
        let shift = try await store.startShift(familyID: family, startedAt: start,
                                               plannedEndAt: end, caregiver: "Cat", careContext: context)
        if closed { try await store.endShift(shift, endedAt: end) }
        return (family, baby, shift)
    }

    private func facts(_ shiftID: UUID) throws -> DayReportComposer.Facts {
        let context = ModelContext(container)
        let shift = try XCTUnwrap(context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == shiftID })).first)
        return DayReportComposer.facts(family: try XCTUnwrap(shift.family), shift: shift)
    }

    private func saveDraft(_ shift: UUID, draft: DayReportDraft) async throws -> DayReportState {
        let expected = try await store.dayReportState(shift).draft
        return try await store.saveDayReportDraft(shift, draft: draft, expectedDraft: expected)
    }

    private func publish(_ shift: UUID) async throws -> DayReportState {
        let state = try await store.dayReportState(shift)
        return try await store.publishDayReport(shift, reviewedFingerprint: facts(shift).fingerprint,
                                                reviewedDraft: state.draft, at: end.addingTimeInterval(1))
    }

    func testLegacyContextDefaultsToNightAndNewDayContextPersists() async throws {
        XCTAssertEqual(Shift(startedAt: start).careContext, .night)
        let (_, _, day) = try await fixture()
        let context = ModelContext(container)
        let shift = try XCTUnwrap(context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == day })).first)
        XCTAssertEqual(shift.careContext, .day)
    }

    func testShiftHoursRememberedInSameSuccessfulStartTransaction() async throws {
        let (familyID, _, _) = try await fixture()
        let context = ModelContext(container)
        let family = try XCTUnwrap(context.fetch(FetchDescriptor<Family>(predicate: #Predicate { $0.id == familyID })).first)
        let startParts = family.calendar.dateComponents([.hour, .minute], from: start)
        XCTAssertEqual(family.defaultShiftStartMinute, (startParts.hour ?? 0) * 60 + (startParts.minute ?? 0))
        XCTAssertNotNil(family.defaultShiftEndMinute)
    }

    func testPublicationRequiresEndedShiftButDraftCanBeSavedDuringCare() async throws {
        let (_, _, shift) = try await fixture(closed: false)
        let entered = DayReportDraft(caregiverName: "Cat", summary: "Play and a walk", questions: "Bring diapers")
        _ = try await saveDraft(shift, draft: entered)
        do { _ = try await publish(shift); XCTFail("running shift published") }
        catch { XCTAssertEqual(error as? DayReportPersistenceError, .endShiftFirst) }
        let retained = try await store.dayReportState(shift)
        XCTAssertEqual(retained.draft, entered)
        XCTAssertTrue(retained.publications.isEmpty)
        XCTAssertTrue(try facts(shift).text.contains("so far"))
    }

    func testPublicationIsImmutableIdempotentAndEmbedsRevisionTimeInBothExports() async throws {
        let (_, _, shift) = try await fixture()
        _ = try await saveDraft(shift, draft: DayReportDraft(caregiverName: "Cat", summary: "A calm day"))
        let first = try await publish(shift)
        let again = try await publish(shift)
        let publication = try XCTUnwrap(first.latestPublication)
        XCTAssertEqual(again.publications, first.publications)
        XCTAssertTrue(publication.plainText.contains("Revision 1"))
        XCTAssertTrue(publication.html.contains("Revision 1"))
        XCTAssertTrue(publication.html.contains(publication.publishedAt.formatted(.iso8601)))
        _ = try await saveDraft(shift, draft: DayReportDraft(caregiverName: "Cat", summary: "A corrected day"))
        let changed = try await store.dayReportState(shift)
        XCTAssertNil(changed.currentPublication(for: try facts(shift).fingerprint))
        XCTAssertEqual(changed.publications.first, publication)
    }

    func testChangedCareRecordInvalidatesCurrentReceiptButKeepsHistoricalCopy() async throws {
        let (_, baby, shift) = try await fixture()
        let feed = try await store.logEvent(kind: .feed, at: start.addingTimeInterval(600), shiftID: shift, babyID: baby) {
            $0.feedMethodRaw = FeedMethod.bottleFormula.rawValue
        }
        let first = try await publish(shift)
        let publication = try XCTUnwrap(first.latestPublication)
        XCTAssertTrue(publication.plainText.contains("not recorded"))
        let received = try await store.acknowledgeDayReport(shift, publicationID: publication.id, version: 1,
                                                           parentName: "Parent", note: "More diapers tomorrow", at: end.addingTimeInterval(2))
        XCTAssertEqual(received.acknowledgements(for: publication).count, 1)
        try await store.updateEvent(feed, at: start.addingTimeInterval(600)) { $0.amountMl = 60 }
        let changedFingerprint = try facts(shift).fingerprint
        let changed = try await store.dayReportState(shift)
        XCTAssertNil(changed.currentPublication(for: changedFingerprint))
        do {
            _ = try await store.acknowledgeDayReport(shift, publicationID: publication.id, version: 1,
                                                     parentName: "Parent", note: "", at: end.addingTimeInterval(3))
            XCTFail("stale report received")
        } catch { XCTAssertEqual(error as? DayReportError, .stalePublication) }
        let revised = try await store.publishDayReport(shift, reviewedFingerprint: changedFingerprint,
                                                       reviewedDraft: changed.draft, at: end.addingTimeInterval(4))
        XCTAssertEqual(revised.latestPublication?.version, 2)
        XCTAssertTrue(revised.acknowledgements(for: try XCTUnwrap(revised.latestPublication)).isEmpty)
        XCTAssertEqual(revised.publications.first, publication)
        XCTAssertEqual(revised.acknowledgements(for: publication).count, 1)
    }

    func testPublishRejectsChangedReviewedDraftStaleFactsAndEarlyTimestampWithoutLosingDraft() async throws {
        let (_, _, shift) = try await fixture()
        let original = try await store.dayReportState(shift)
        let oldFingerprint = try facts(shift).fingerprint
        let entered = DayReportDraft(caregiverName: "Cat", summary: "Saved new note")
        _ = try await saveDraft(shift, draft: entered)
        do {
            _ = try await store.publishDayReport(shift, reviewedFingerprint: oldFingerprint,
                                                 reviewedDraft: original.draft, at: end.addingTimeInterval(1))
            XCTFail("changed draft published")
        } catch { XCTAssertEqual(error as? DayReportError, .stalePublication) }
        do {
            _ = try await store.publishDayReport(shift, reviewedFingerprint: "outdated",
                                                 reviewedDraft: entered, at: end.addingTimeInterval(1))
            XCTFail("stale facts published")
        } catch { XCTAssertEqual(error as? DayReportError, .stalePublication) }
        do {
            _ = try await store.publishDayReport(shift, reviewedFingerprint: oldFingerprint,
                                                 reviewedDraft: entered, at: start)
            XCTFail("review before coverage ended")
        } catch { XCTAssertEqual(error as? DayReportError, .invalidDate) }
        let retained = try await store.dayReportState(shift)
        XCTAssertEqual(retained.draft, entered)
        XCTAssertTrue(retained.publications.isEmpty)
    }

    func testNilAndLiteralSentinelTextHaveDifferentSourceDigests() async throws {
        let (_, baby, shift) = try await fixture()
        let note = try await store.logEvent(kind: .note, at: start.addingTimeInterval(600), shiftID: shift, babyID: baby) {
            $0.tagsRaw = "Play"
        }
        let before = try facts(shift).fingerprint
        try await store.updateEvent(note, at: start.addingTimeInterval(600)) { $0.text = "<nil>" }
        XCTAssertNotEqual(try facts(shift).fingerprint, before)
    }

    func testStaleEditorCannotReplaceNewerWholeDraftOrItsOtherFields() async throws {
        let (_, _, shift) = try await fixture()
        let base = try await store.dayReportState(shift).draft
        var newer = base
        newer.summary = "The latest summary"
        newer.eveningNotes = "New handoff information from another editor"
        _ = try await store.saveDayReportDraft(shift, draft: newer, expectedDraft: base)
        var stale = base
        stale.summary = "An older queued edit"
        do {
            _ = try await store.saveDayReportDraft(shift, draft: stale, expectedDraft: base)
            XCTFail("stale draft replaced newer notes")
        } catch { XCTAssertEqual(error as? DayReportError, .draftConflict) }
        let retained = try await store.dayReportState(shift)
        XCTAssertEqual(retained.draft, newer)
    }

    func testUnreadableSavedReportFailsClosedRatherThanReplacingHistory() async throws {
        let (_, _, shiftID) = try await fixture()
        let context = ModelContext(container)
        let shift = try XCTUnwrap(context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == shiftID })).first)
        shift.dayReportJSON = "not valid JSON"; try context.save()
        // A fresh writer represents the next launch and cannot inherit a cached model.
        let freshStore = CareStore(modelContainer: container)
        do { _ = try await freshStore.saveDayReportDraft(shiftID, draft: DayReportDraft(caregiverName: "Cat"), expectedDraft: DayReportDraft()); XCTFail("corrupt history replaced") }
        catch { XCTAssertEqual(error as? DayReportPersistenceError, .unreadable) }
        XCTAssertEqual(shift.dayReportJSON, "not valid JSON")
    }

    func testSavedDraftPublicationAndOptionalReceiptSurviveDiskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "handoff.store")
        let shiftID = try await seedDiskStore(url)
        let reopened = try ModelContainer(for: ModelContainerFactory.schema,
                                          configurations: ModelConfiguration(schema: ModelContainerFactory.schema, url: url, cloudKitDatabase: .none))
        let freshStore = CareStore(modelContainer: reopened)
        let state = try await freshStore.dayReportState(shiftID)
        XCTAssertEqual(state.draft.summary, "Saved for tomorrow")
        XCTAssertEqual(state.publications.count, 1)
        XCTAssertEqual(state.acknowledgements.count, 1)
        XCTAssertEqual(state.acknowledgements.first?.note, "Thank you")
    }

    private func seedDiskStore(_ url: URL) async throws -> UUID {
        let disk = try ModelContainer(for: ModelContainerFactory.schema,
                                     configurations: ModelConfiguration(schema: ModelContainerFactory.schema, url: url, cloudKitDatabase: .none))
        let writer = CareStore(modelContainer: disk)
        let family = try await writer.createFamily(name: "Disk family")
        _ = try await writer.addBaby(to: family, name: "Mia", birthAt: start.addingTimeInterval(-86400))
        let shift = try await writer.startShift(familyID: family, startedAt: start, caregiver: "Cat", careContext: .day)
        try await writer.endShift(shift, endedAt: end)
        let draft = DayReportDraft(caregiverName: "Cat", summary: "Saved for tomorrow")
        let base = try await writer.dayReportState(shift).draft
        _ = try await writer.saveDayReportDraft(shift, draft: draft, expectedDraft: base)
        let read = ModelContext(disk)
        let model = try XCTUnwrap(read.fetch(FetchDescriptor<Shift>()).first)
        let fingerprint = DayReportComposer.facts(family: try XCTUnwrap(model.family), shift: model).fingerprint
        let state = try await writer.publishDayReport(shift, reviewedFingerprint: fingerprint, reviewedDraft: draft, at: end.addingTimeInterval(1))
        let publication = try XCTUnwrap(state.latestPublication)
        _ = try await writer.acknowledgeDayReport(shift, publicationID: publication.id, version: 1,
                                                  parentName: "Parent", note: "Thank you", at: end.addingTimeInterval(2))
        return shift
    }
}
