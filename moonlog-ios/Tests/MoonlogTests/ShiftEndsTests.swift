import XCTest
import MoonlogCore
@testable import Moonlog

/// The two places a time is *offered* rather than recorded: the hour the end sheet
/// pre-fills, and the clock a timeline row prints as the end of a record.
///
/// Neither is a store invariant, so neither is in `CareStore` — but both decide what
/// the doula confirms with one tap at 6am, and a wrong suggestion confirmed is
/// indistinguishable from a wrong record.
final class ShiftEndsTests: XCTestCase {

    private let at = Date(timeIntervalSince1970: 1_788_000_000)

    // MARK: - What the end sheet offers

    /// Leaving on time is the common night. The clock says 6:03 and she means 6:00 —
    /// the totals and the parents' document both clip to this window, so those three
    /// minutes are sleep nobody watched.
    func testTheBookedHourIsOfferedOnceItHasArrived() {
        let booked = at
        XCTAssertEqual(
            ShiftHoursSheet.suggestedEnd(planned: booked, now: at.addingTimeInterval(180)),
            booked)
    }

    /// Leaving early. The booked hour has not happened, and the sheet refuses a
    /// future time anyway — offering it would pre-fill a field that cannot save.
    func testAnHourStillToComeIsNotOffered() {
        let now = at
        XCTAssertEqual(
            ShiftHoursSheet.suggestedEnd(planned: at.addingTimeInterval(3600), now: now),
            now)
    }

    /// Every shift started before the booking existed has none.
    func testWithNoBookingTheClockIsTheSuggestion() {
        XCTAssertEqual(ShiftHoursSheet.suggestedEnd(planned: nil, now: at), at)
    }

    // MARK: - Which rows print two clocks

    /// A feed's "Time" is when it started and its "Duration" is how long it ran, so
    /// the row can name both ends. Twenty minutes, not a second more — the row is
    /// read against the next feed's due time.
    func testABottleEndsItsDurationAfterItStarted() {
        let feed = LogEvent(kind: .feed, at: at)
        feed.feedMethodRaw = FeedMethod.bottleFormula.rawValue
        feed.feedDurationSeconds = 20 * 60
        XCTAssertEqual(feed.timelineEndAt, at.addingTimeInterval(20 * 60))
    }

    /// The two sides are consecutive, not concurrent: the baby is on one breast and
    /// then the other. Taking the longer side would report a feed that finished
    /// before it did.
    func testABreastFeedEndsAfterBothSidesAddedUp() {
        let feed = LogEvent(kind: .feed, at: at)
        feed.feedMethodRaw = FeedMethod.breast.rawValue
        feed.leftSeconds = 10 * 60
        feed.rightSeconds = 5 * 60
        XCTAssertEqual(feed.timelineEndAt, at.addingTimeInterval(15 * 60))
    }

    /// The length is read **by method**, never by adding the three columns up. The
    /// model is flat, so a bottle's row carries `leftSeconds` too; summing them would
    /// give the trailing edge a length the row's own subtitle disagrees with, and
    /// `Handoff.warmFeed` reports neither.
    func testALengthIsReadFromTheMethodsOwnColumns() {
        let bottle = LogEvent(kind: .feed, at: at)
        bottle.feedMethodRaw = FeedMethod.bottleFormula.rawValue
        bottle.feedDurationSeconds = 20 * 60
        bottle.leftSeconds = 10 * 60
        XCTAssertEqual(bottle.timelineEndAt, at.addingTimeInterval(20 * 60))

        let breast = LogEvent(kind: .feed, at: at)
        breast.feedMethodRaw = FeedMethod.breast.rawValue
        breast.feedDurationSeconds = 20 * 60
        breast.leftSeconds = 10 * 60
        XCTAssertEqual(breast.timelineEndAt, at.addingTimeInterval(10 * 60))
    }

    /// A feed with no method recorded reads as breast, which is what
    /// `Handoff.warmFeed` does with the same `nil`.
    func testAMethodlessFeedIsReadAsBreast() {
        let feed = LogEvent(kind: .feed, at: at)
        feed.rightSeconds = 7 * 60
        XCTAssertEqual(feed.timelineEndAt, at.addingTimeInterval(7 * 60))
    }

    /// Duration is optional on every feed sheet. Without one there is no end to
    /// claim, and the row prints a single clock rather than a range of zero width.
    func testAFeedWithNoDurationHasNoEnd() {
        let feed = LogEvent(kind: .feed, at: at)
        feed.feedMethodRaw = FeedMethod.bottleFormula.rawValue
        XCTAssertNil(feed.timelineEndAt)
        XCTAssertNil(LogEvent(kind: .feed, at: at).timelineEndAt)
    }

    /// A diaper, a note, a weighing and a pump are instants. A range on one of them
    /// would be invented — and `feedDurationSeconds` is on the same flat model, so
    /// nothing but the kind stops it being read.
    func testEveryOtherKindIsAnInstant() {
        for kind in EventKind.allCases where kind != .feed {
            let event = LogEvent(kind: kind, at: at)
            event.feedMethodRaw = FeedMethod.bottleFormula.rawValue
            event.feedDurationSeconds = 20 * 60
            XCTAssertNil(event.timelineEndAt, "\(kind.rawValue) claimed a length")
        }
    }
}
