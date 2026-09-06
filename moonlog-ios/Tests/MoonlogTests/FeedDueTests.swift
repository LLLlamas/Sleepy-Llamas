import XCTest
@testable import Moonlog

/// The overdue-feed rule. It regressed in the retired web version, was ported
/// broken, and was fixed once already — a future-dated feed must count as overdue
/// rather than as "just fed", or one skewed record suppresses the warning all night.
final class FeedDueTests: XCTestCase {

    private func baby(lastFeed: Date?) -> BabyPresentation {
        BabyPresentation(
            id: UUID(), name: "Mia", accent: .gold, dayOfLife: 6,
            asleepSince: nil, awakeSince: nil,
            lastFeedAt: lastFeed, lastDiaperAt: nil)
    }

    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    func testNotDueWithNoFeedYet() {
        XCTAssertFalse(baby(lastFeed: nil).feedIsDue(now: now))
    }

    func testNotDueJustAfterAFeed() {
        XCTAssertFalse(baby(lastFeed: now.addingTimeInterval(-600)).feedIsDue(now: now))
    }

    func testNotDueJustUnderTheThreshold() {
        XCTAssertFalse(baby(lastFeed: now.addingTimeInterval(-3 * 3600 + 60))
            .feedIsDue(now: now))
    }

    func testDueAtTheThreshold() {
        XCTAssertTrue(baby(lastFeed: now.addingTimeInterval(-3 * 3600)).feedIsDue(now: now))
    }

    /// The bug. Reachable via sync from a device with a skewed clock.
    func testAFutureDatedFeedCountsAsOverdueRatherThanRecent() {
        XCTAssertTrue(
            baby(lastFeed: now.addingTimeInterval(3600)).feedIsDue(now: now),
            "a future stamp must not read as 'just fed' and silence the warning")
    }

    func testThresholdIsConfigurable() {
        let b = baby(lastFeed: now.addingTimeInterval(-2 * 3600))
        XCTAssertFalse(b.feedIsDue(now: now))
        XCTAssertTrue(b.feedIsDue(now: now, after: 90 * 60))
    }
}
