import XCTest
@testable import MoonlogCore

final class DayReportTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)
    private func state() -> DayReportState {
        DayReportState(draft: DayReportDraft(caregiverName: " Catalina ", summary: "A walk in the park.", eveningNotes: "Bottles on the rack.", questions: "Bring the stroller tomorrow?"))
    }
    private func publish(_ state: inout DayReportState, source: String = "facts-1", seconds: Double = 0) throws -> DayReportPublication {
        try state.publish(sourceFingerprint: source, plainText: "Factual care log", html: "<p>Factual care log</p>", at: when.addingTimeInterval(seconds))
    }

    func testPublicationFreezesTheReviewedNarrativeAndCalculatedDocument() throws {
        var report = state()
        let first = try publish(&report)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.draft.caregiverName, "Catalina")
        report.draft.summary = "Corrected observation"
        XCTAssertNil(report.currentPublication(for: "facts-1"))
        XCTAssertEqual(report.publications[0].draft.summary, "A walk in the park.")
        XCTAssertEqual(report.publications[0].plainText, "Factual care log")
    }

    func testUnchangedRetryReturnsOriginalPublicationAndTime() throws {
        var report = state()
        let first = try publish(&report)
        let retried = try publish(&report, seconds: 120)
        XCTAssertEqual(first, retried)
        XCTAssertEqual(report.publications.count, 1)
    }

    func testFactualChangeCreatesRevisionAndDoesNotCarryOldAcknowledgement() throws {
        var report = state()
        let first = try publish(&report)
        let ack = try report.acknowledge(publicationID: first.id, version: first.version, sourceFingerprint: "facts-1", parentName: "Ana", note: "Please bring the stroller.", at: when.addingTimeInterval(60))
        XCTAssertEqual(ack.method, .inPersonOnCaregiverDevice)
        XCTAssertNil(report.currentPublication(for: "corrected-facts"))
        XCTAssertThrowsError(try report.acknowledge(publicationID: first.id, version: first.version, sourceFingerprint: "corrected-facts", parentName: "Ana", at: when.addingTimeInterval(90)))
        let revised = try publish(&report, source: "corrected-facts", seconds: 120)
        XCTAssertEqual(revised.version, 2)
        XCTAssertTrue(report.acknowledgements(for: revised).isEmpty)
        XCTAssertEqual(report.acknowledgements(for: first), [ack])
        XCTAssertEqual(report.publications.count, 2)
    }

    func testNarrativeEditAlsoMakesOldParentReceiptHistorical() throws {
        var report = state()
        let first = try publish(&report)
        _ = try report.acknowledge(publicationID: first.id, version: 1, sourceFingerprint: "facts-1", parentName: "Ana", at: when)
        report.draft.questions = "Different question"
        XCTAssertNil(report.currentPublication(for: "facts-1"))
        let next = try publish(&report, seconds: 1)
        XCTAssertEqual(next.version, 2)
        XCTAssertTrue(report.acknowledgements(for: next).isEmpty)
    }

    func testParentReceiptIsOptionalAndIsNotPartOfTheCaregiverNarrative() throws {
        var report = state()
        let publication = try publish(&report)
        XCTAssertTrue(report.acknowledgements(for: publication).isEmpty)
        let originalDraft = report.draft
        let receipt = try report.acknowledge(publicationID: publication.id, version: 1, sourceFingerprint: "facts-1", parentName: " Ana ", note: " Parent's question ", at: when)
        XCTAssertEqual(receipt.parentName, "Ana")
        XCTAssertEqual(receipt.note, "Parent's question")
        XCTAssertEqual(report.draft, originalDraft)
        let retry = try report.acknowledge(publicationID: publication.id, version: 1, sourceFingerprint: "facts-1", parentName: "Ana", note: "Parent's question", at: when.addingTimeInterval(10))
        XCTAssertEqual(retry, receipt)
        XCTAssertEqual(report.acknowledgements.count, 1)
    }

    func testRejectsWrongRevisionAndEarlierOrNamelessReceiptWithoutMutation() throws {
        var report = state()
        let publication = try publish(&report)
        let before = report
        XCTAssertThrowsError(try report.acknowledge(publicationID: UUID(), version: 1, sourceFingerprint: "facts-1", parentName: "Ana", at: when))
        XCTAssertThrowsError(try report.acknowledge(publicationID: publication.id, version: 2, sourceFingerprint: "facts-1", parentName: "Ana", at: when))
        XCTAssertThrowsError(try report.acknowledge(publicationID: publication.id, version: 1, sourceFingerprint: "facts-1", parentName: " ", at: when))
        XCTAssertThrowsError(try report.acknowledge(publicationID: publication.id, version: 1, sourceFingerprint: "facts-1", parentName: "Ana", at: when.addingTimeInterval(-1)))
        XCTAssertEqual(report, before)
    }

    func testStateSurvivesPersistenceRoundTripWithHistoryAndParentNote() throws {
        var report = state()
        let publication = try publish(&report)
        _ = try report.acknowledge(publicationID: publication.id, version: 1, sourceFingerprint: "facts-1", parentName: "Ana", note: "A question", at: when)
        report.draft.summary = "Unsaved-to-publication revision"
        let saved = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(DayReportState.self, from: saved), report)
    }

    func testInvalidPublicationDoesNotDestroyDraftOrPriorSnapshot() throws {
        var report = state()
        _ = try publish(&report)
        report.draft.caregiverName = " "
        let before = report
        XCTAssertThrowsError(try publish(&report, source: "new-facts", seconds: 1))
        XCTAssertEqual(report, before)
        report.draft.caregiverName = "Catalina"
        XCTAssertThrowsError(try report.publish(sourceFingerprint: "", plainText: "x", html: "x", at: when))
        XCTAssertThrowsError(try report.publish(sourceFingerprint: "new-facts", plainText: "", html: "x", at: when))
        XCTAssertThrowsError(try report.publish(sourceFingerprint: "new-facts", plainText: "x", html: "x", at: Date(timeIntervalSinceReferenceDate: .nan)))
    }

    func testDayHandoffsUseDayLanguageWithoutChangingDefaultNightOutput() {
        let baby = HandoffBaby(id: UUID(), name: "Mia", dayOfLife: 6)
        let shift = ShiftWindow(startedAt: when, endedAt: when.addingTimeInterval(8 * 3600))
        let zone = TimeZone(secondsFromGMT: 0)!
        let day = Handoff.text(babies: [baby], shift: shift, caregiver: "Cat", events: [], sessions: [], unit: .ml, timeZone: zone, asOf: when, context: .day)
        let night = Handoff.text(babies: [baby], shift: shift, caregiver: "Cat", events: [], sessions: [], unit: .ml, timeZone: zone, asOf: when)
        XCTAssertTrue(day.contains("Mia's day"))
        XCTAssertFalse(day.contains("Good morning"))
        XCTAssertTrue(night.contains("Mia's night"))
        XCTAssertTrue(night.contains("Good morning"))
        let html = HandoffHTML.render(babies: [baby], shift: shift, caregiver: "Cat", note: "A sunny walk.", events: [], sessions: [], unit: .ml, timeZone: zone, asOf: when, context: .day)
        XCTAssertTrue(html.contains("Mia&#39;s day") || html.contains("Mia's day"))
        XCTAssertTrue(html.contains("Totals cover this shift, not a full day."))
        XCTAssertFalse(html.contains("Good morning"))
        XCTAssertFalse(html.contains("the night was watched over"))
        XCTAssertTrue(html.contains("A sunny walk."))
        XCTAssertTrue(html.contains("not logged"))
    }

    func testDayFeedCompletenessDoesNotTurnUnknownAmountsIntoApparentZeroes() {
        let baby = HandoffBaby(id: UUID(), name: "Mia", dayOfLife: 6)
        let shift = ShiftWindow(startedAt: when, endedAt: when.addingTimeInterval(3600))
        let zone = TimeZone(secondsFromGMT: 0)!
        let events = [
            EventSnapshot(babyID: baby.id, kind: .feed, at: when.addingTimeInterval(1), feedMethod: .bottleFormula, amountMl: 60),
            EventSnapshot(babyID: baby.id, kind: .feed, at: when.addingTimeInterval(2), feedMethod: .bottleFormula),
            EventSnapshot(babyID: baby.id, kind: .feed, at: when.addingTimeInterval(3), feedMethod: .unknown),
        ]
        let text = Handoff.text(babies: [baby], shift: shift, caregiver: nil, events: events, sessions: [], unit: .ml, timeZone: zone, asOf: when, context: .day)
        let html = HandoffHTML.render(babies: [baby], shift: shift, caregiver: nil, note: nil, events: events, sessions: [], unit: .ml, timeZone: zone, asOf: when, context: .day)
        for output in [text, html] {
            XCTAssertTrue(output.contains("amount not recorded"))
            XCTAssertTrue(output.contains("Method not recorded for 1 feed."))
            XCTAssertTrue(output.contains("Volume totals include recorded amounts only."))
            XCTAssertFalse(output.contains("— 0 mL"))
        }
    }

}
