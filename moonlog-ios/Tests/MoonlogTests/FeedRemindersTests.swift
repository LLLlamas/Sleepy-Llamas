import XCTest
@testable import Moonlog

/// The identity the whole no-schema reminder design rests on.
///
/// Nothing about a reminder is stored: the notification centre *is* the database (see
/// `FeedReminders`), keyed the same way ours is. Retime, delete, undo and correcting
/// which twin a feed belongs to are all one `add` or `remove` under the feed event's
/// own id. The day that identifier stops being exactly the event's UUID string, all
/// four break at once and break *quietly* — a cancel would remove nothing, a retime
/// would leave the old alarm pending beside the new one, and `pending()` would drop
/// every request on the floor because it parses identifiers back with
/// `UUID(uuidString:)`.
@MainActor
final class FeedRemindersTests: XCTestCase {

    func testTheNotificationIdentifierIsTheFeedEventsOwnUUIDString() throws {
        let eventID = try XCTUnwrap(UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))

        XCTAssertEqual(FeedReminders.identifier(for: eventID), eventID.uuidString)
        // Pinned literally as well, for the reason enum raw values are: this string is
        // a wire format shared with the notification centre across app launches, so a
        // prefix or a case change added here would orphan every pending reminder on
        // every device that had one set.
        XCTAssertEqual(
            FeedReminders.identifier(for: eventID), "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
    }
}
