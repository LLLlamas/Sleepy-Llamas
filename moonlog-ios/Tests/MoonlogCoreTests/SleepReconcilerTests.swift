import XCTest
@testable import MoonlogCore

final class SleepReconcilerTests: XCTestCase {

    private let babyA = UUID()
    private let babyB = UUID()
    private func at(_ wall: String) -> Date { makeDate(wall, Zone.newYork) }

    /// **The property that matters.** Two devices reconciling the same set must
    /// reach the same answer, or they will fight over the record forever.
    func testResultIsIndependentOfArrivalOrder() {
        let base = at("2026-09-04 22:00")
        let sessions = (0..<6).map { i in
            SleepSnapshot(
                babyID: babyA,
                startAt: base.addingTimeInterval(Double(i) * 1800),
                endAt: i.isMultiple(of: 2) ? base.addingTimeInterval(Double(i) * 1800 + 600) : nil)
        }

        let reference = SleepReconciler.reconcile(sessions, forBaby: babyA)
        for seed in 0..<25 {
            var shuffled = sessions
            // Deterministic shuffle so a failure is reproducible.
            var rng = SeededGenerator(seed: UInt64(seed))
            shuffled.shuffle(using: &rng)
            XCTAssertEqual(SleepReconciler.reconcile(shuffled, forBaby: babyA), reference)
        }
    }

    /// A double-tap in the dark registers twice. Those are one session.
    func testDuplicateTapsWithinTheMergeWindowCollapse() {
        let start = at("2026-09-05 01:00")
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: start),
            SleepSnapshot(babyID: babyA, startAt: start.addingTimeInterval(3)),
        ]
        let result = SleepReconciler.reconcile(sessions, forBaby: babyA)

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.mergedAway.count, 1)
        XCTAssertTrue(result.sessions[0].isOpen, "still open if either side was open")
    }

    /// Two genuinely separate stretches hours apart are not a double-tap.
    func testDistinctSessionsHoursApartAreNotMerged() {
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-04 22:00"),
                          endAt: at("2026-09-04 23:30")),
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 02:00"),
                          endAt: at("2026-09-05 04:00")),
        ]
        let result = SleepReconciler.reconcile(sessions, forBaby: babyA)
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertTrue(result.mergedAway.isEmpty)
        XCTAssertTrue(result.repairedEnds.isEmpty)
    }

    /// The CloudKit case: two open sessions for one baby, four hours apart. The
    /// earlier one was never closed, so close it where the later begins rather
    /// than letting both run.
    func testTwoOpenSessionsLeaveOnlyTheLatestOpen() {
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-04 22:00")),
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 02:00")),
        ]
        let result = SleepReconciler.reconcile(sessions, forBaby: babyA)

        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(result.sessions[0].endAt, at("2026-09-05 02:00"))
        XCTAssertTrue(result.sessions[1].isOpen)
        XCTAssertEqual(result.repairedEnds, [result.sessions[0].id])
    }

    func testOverlappingSessionsAreTruncatedToTheNextStart() {
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-04 22:00"),
                          endAt: at("2026-09-05 03:00")),
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-05 01:00"),
                          endAt: at("2026-09-05 04:00")),
        ]
        let result = SleepReconciler.reconcile(sessions, forBaby: babyA)
        XCTAssertEqual(result.sessions[0].endAt, at("2026-09-05 01:00"))
        XCTAssertEqual(result.sessions[1].endAt, at("2026-09-05 04:00"))
    }

    /// After reconciling, sessions never overlap. Stated as a property so it holds
    /// for inputs beyond the specific cases above.
    func testReconciledSessionsNeverOverlap() {
        let base = at("2026-09-04 20:00")
        let offsets: [Double] = [0, 60, 3600, 3660, 7200, 7000, 14400, 14400]
        let sessions = offsets.enumerated().map { i, offset in
            SleepSnapshot(
                babyID: babyA,
                startAt: base.addingTimeInterval(offset),
                endAt: i.isMultiple(of: 3) ? nil : base.addingTimeInterval(offset + 5400))
        }
        let result = SleepReconciler.reconcile(sessions, forBaby: babyA)

        for (a, b) in zip(result.sessions, result.sessions.dropFirst()) {
            XCTAssertLessThan(a.startAt, b.startAt)
            if let end = a.endAt {
                XCTAssertLessThanOrEqual(end, b.startAt, "no overlap after reconciliation")
            } else {
                XCTFail("only the final session may remain open")
            }
        }
        XCTAssertTrue(result.sessions.last?.isOpen ?? false)
    }

    func testOtherBabiesAreUntouched() {
        let sessions = [
            SleepSnapshot(babyID: babyA, startAt: at("2026-09-04 22:00")),
            SleepSnapshot(babyID: babyB, startAt: at("2026-09-04 22:01")),
            SleepSnapshot(babyID: babyB, startAt: at("2026-09-05 02:00")),
        ]
        let result = SleepReconciler.reconcile(sessions, forBaby: babyA)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertTrue(result.sessions.allSatisfy { $0.babyID == babyA })
        XCTAssertTrue(result.mergedAway.isEmpty, "babyB's near-simultaneous start is not a dupe")
    }

    func testEmptyInputIsHandled() {
        let result = SleepReconciler.reconcile([], forBaby: babyA)
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertTrue(result.mergedAway.isEmpty)
        XCTAssertTrue(result.repairedEnds.isEmpty)
    }
}

/// Reproducible shuffling — a randomly-ordered failure that cannot be replayed is
/// worse than no test.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
