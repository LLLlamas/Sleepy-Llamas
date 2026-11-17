import XCTest
@testable import MoonlogCore

final class SleepHandoffBoundaryTests: XCTestCase {
    private let baby = UUID()
    private let zone = TimeZone(identifier: Zone.newYork)!
    private func at(_ value: String) -> Date { makeDate(value, Zone.newYork) }
    private var shift: ShiftWindow {
        ShiftWindow(startedAt: at("2026-09-04 22:00"), endedAt: at("2026-09-05 06:00"))
    }
    private var laterWake: SleepSnapshot {
        SleepSnapshot(babyID: baby, startAt: at("2026-09-05 05:40"), endAt: at("2026-09-05 07:00"))
    }

    func testLaterWakeStillCountsAsContinuingAtTheClosedShiftBoundary() throws {
        let session = laterWake
        let stretch = try XCTUnwrap(SleepMath.stretch(of: session, clippedTo: shift,
                                                     asOf: at("2026-09-05 14:00")))
        XCTAssertEqual(stretch.end, at("2026-09-05 06:00"))
        XCTAssertEqual(stretch.seconds, 1200)
        XCTAssertTrue(stretch.isOpen, "the coverage clip is not a wake record")
        XCTAssertEqual(SleepMath.continuingSession(in: [session], forBaby: baby,
            clippedTo: shift, asOf: .distantFuture)?.id, session.id)
    }

    func testWakeExactlyAtTheCoverageBoundaryRemainsAFinishedSleep() throws {
        let ended = SleepSnapshot(babyID: baby, startAt: laterWake.startAt, endAt: shift.endedAt)
        let stretch = try XCTUnwrap(SleepMath.stretch(of: ended, clippedTo: shift, asOf: .distantFuture))
        XCTAssertFalse(stretch.isOpen)
        XCTAssertNil(SleepMath.continuingSession(in: [ended], forBaby: baby, clippedTo: shift, asOf: .distantFuture))
        XCTAssertTrue(Handoff.sleepTail(stretch, endLabel: "6:00a").contains("→ 6:00a"))
    }

    func testSleepStartingExactlyAtHandoffIsAStateWithoutInventedDuration() {
        let justStarted = SleepSnapshot(babyID: baby, startAt: shift.endedAt!)
        XCTAssertNil(SleepMath.stretch(of: justStarted, clippedTo: shift, asOf: .distantFuture))
        XCTAssertEqual(SleepMath.continuingSession(in: [justStarted], forBaby: baby,
            clippedTo: shift, asOf: .distantFuture)?.id, justStarted.id)
    }

    func testTextAndDesignedPageDoNotInventAWakeAtHandoff() {
        let babies = [HandoffBaby(id: baby, name: "Mia", dayOfLife: 6)]
        let text = Handoff.text(babies: babies, shift: shift, caregiver: "Cat", events: [],
            sessions: [laterWake], unit: .oz, timeZone: zone, asOf: .distantFuture)
        let html = HandoffHTML.render(babies: babies, shift: shift, caregiver: "Cat", note: nil, events: [],
            sessions: [laterWake], unit: .oz, timeZone: zone, asOf: .distantFuture)
        XCTAssertTrue(text.contains("still asleep, since"), text)
        XCTAssertTrue(text.contains("still asleep · 20m so far"), text)
        XCTAssertFalse(text.contains("→ 6:00a"), "clipping invented a wake in the text")
        XCTAssertTrue(html.contains("Still asleep, since"), html)
        XCTAssertTrue(html.contains("still asleep · 20m so far"), html)
        XCTAssertFalse(html.contains("→ 6:00a"), "clipping invented a wake in the designed page")
    }

    func testAnOpenSessionEntirelyAfterTheShiftDoesNotClaimAsleepAtHandoff() {
        let future = SleepSnapshot(babyID: baby, startAt: at("2026-09-05 08:00"))
        XCTAssertNil(SleepMath.continuingSession(in: [future], forBaby: baby,
                                                clippedTo: shift, asOf: .distantFuture))
        let text = Handoff.text(babies: [HandoffBaby(id: baby, name: "Mia", dayOfLife: 6)],
            shift: shift, caregiver: "Cat", events: [], sessions: [future], unit: .oz,
            timeZone: zone, asOf: .distantFuture)
        XCTAssertFalse(text.contains("still asleep"), text)
    }
}
