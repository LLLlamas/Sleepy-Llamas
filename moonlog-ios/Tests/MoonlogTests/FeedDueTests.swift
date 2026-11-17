import XCTest
@testable import Moonlog

/// The overdue-feed rule. It regressed in the retired web version, was ported
/// broken, and was fixed once already — a future-dated feed must count as overdue
/// rather than as "just fed", or one skewed record suppresses the warning all night.
final class FeedDueTests: XCTestCase {

    private func baby(
        lastFeed: Date?, reminderAt: Date? = nil, reminderFeedAt: Date? = nil
    ) -> BabyPresentation {
        BabyPresentation(
            id: UUID(), name: "Mia", accent: .gold, dayOfLife: 6,
            asleepSince: nil, awakeSince: nil,
            lastFeedAt: lastFeed, lastDiaperAt: nil,
            feedReminderAt: reminderAt, reminderFeedAt: reminderFeedAt ?? lastFeed)
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

    // MARK: - A pending reminder's own interval
    //
    // With a reminder set, the card judges "overdue" against the gap the doula
    // actually chose (`feedReminderAt − lastFeedAt`) instead of the three-hour
    // default, so the chip and the countdown beside it are two readings of one
    // number. `feedDueAfter` was moved off the card and onto `BabyPresentation` so
    // that derivation could be asserted at all — a view's `private var` cannot be.
    // `testThresholdIsConfigurable` only pins a threshold *shorter* than the default,
    // which a `min(interval, defaultFeedInterval)` clamp would survive.

    /// The contradiction the reminder-aware threshold exists to fix: a four-hour
    /// reminder still counting down "in 1h" while the chip beside it had already
    /// flipped to overdue at three.
    func testAThresholdLongerThanTheDefaultIsNotOverdueAtThreeHours() {
        XCTAssertFalse(
            baby(lastFeed: now.addingTimeInterval(-3 * 3600)).feedIsDue(now: now, after: 4 * 3600),
            "the three-hour default must not leak in and overrule a longer interval")
    }

    /// The other direction, so the rule cannot become "a longer interval never trips".
    func testAThresholdLongerThanTheDefaultIsOverdueOnceItPasses() {
        XCTAssertTrue(
            baby(lastFeed: now.addingTimeInterval(-4 * 3600)).feedIsDue(now: now, after: 4 * 3600))
    }

    // MARK: - feedDueAfter, the derivation itself

    /// The whole point: the threshold comes from the pending reminder, so the chip
    /// and the countdown can never disagree about one feed.
    func testFeedDueAfterComesFromThePendingReminder() {
        let fed = now.addingTimeInterval(-3600)
        let b = baby(lastFeed: fed, reminderAt: fed.addingTimeInterval(150 * 60))
        XCTAssertEqual(b.feedDueAfter, 150 * 60, accuracy: 0.5)
    }

    /// With nothing pending there is no better answer than the house rule.
    func testFeedDueAfterFallsBackToThreeHoursWithNoReminder() {
        XCTAssertEqual(
            baby(lastFeed: now.addingTimeInterval(-3600)).feedDueAfter,
            BabyPresentation.defaultFeedInterval, accuracy: 0.5)
    }

    /// A fire date at or before the feed it belongs to is only reachable via a
    /// skewed clock. Falling back beats declaring every feed overdue forever.
    func testFeedDueAfterFallsBackWhenTheReminderPrecedesTheFeed() {
        let fed = now.addingTimeInterval(-3600)
        let b = baby(lastFeed: fed, reminderAt: fed.addingTimeInterval(-60))
        XCTAssertEqual(b.feedDueAfter, BabyPresentation.defaultFeedInterval, accuracy: 0.5)
    }

    /// A reminder with no feed to measure from cannot yield an interval.
    func testFeedDueAfterFallsBackWithNoFeedYet() {
        XCTAssertEqual(
            baby(lastFeed: nil, reminderAt: now.addingTimeInterval(3600)).feedDueAfter,
            BabyPresentation.defaultFeedInterval, accuracy: 0.5)
    }

    /// End to end through the card's actual call: a 4h reminder must not read
    /// overdue at 3h, which is the contradiction that prompted all of this.
    func testAPendingReminderGovernsOverdueEndToEnd() {
        let fed = now.addingTimeInterval(-3 * 3600)
        let b = baby(lastFeed: fed, reminderAt: fed.addingTimeInterval(4 * 3600))
        XCTAssertFalse(b.feedIsDue(now: now, after: b.feedDueAfter))
    }

    /// The soonest pending reminder is not always the newest feed's — a feed logged
    /// after one that set a reminder does not cancel it. Measuring that fire date
    /// against the NEWEST feed mixes two events and can make a baby fed ten minutes
    /// ago read as overdue.
    ///
    /// Feed A at 00:00 sets a 3h reminder (fires 03:00). Feed B at 02:50 sets none.
    /// At 03:00 she was fed ten minutes ago and nothing is overdue.
    func testAReminderFromAnEarlierFeedDoesNotMakeTheLatestFeedOverdue() {
        let feedA = now.addingTimeInterval(-3 * 3600)
        let feedB = now.addingTimeInterval(-600)
        let b = baby(
            lastFeed: feedB,
            reminderAt: feedA.addingTimeInterval(3 * 3600),
            reminderFeedAt: feedA)
        XCTAssertFalse(
            b.feedIsDue(now: now, after: b.feedDueAfter),
            "ten minutes after a feed is not overdue, whatever an older feed's reminder says")
    }
}
