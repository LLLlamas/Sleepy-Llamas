import Foundation

/// "Remind me in X" — when the reminder fires and what it says. Scheduling it is the
/// app's job; this half is pure, so it is tested without a host app.
///
/// Deliberately does **not** import `UserNotifications`. Nothing here needs it, and
/// the import alone would narrow the platforms this framework can build for — the
/// Watch app in `docs/next-features.md` depends on Core staying Foundation-only.
public enum FeedReminder {

    /// The offsets the sheet offers, in minutes. Half-hour steps from an hour and a
    /// half out to four, bracketing the three-hour overdue rule the status tile
    /// already applies (`BabyPresentation.feedIsDue`) rather than competing with it.
    public static let presetMinutes = [90, 120, 150, 180, 210, 240]

    /// A **physical** duration, not a calendar one — three hours after a feed is three
    /// hours of a baby's stomach, whatever the clock did in between. A reminder set at
    /// 00:30 on spring-forward day fires at 04:30 local, not 03:30.
    ///
    /// Which is why there is no `Calendar` anywhere in this file. See the one time
    /// rule in `docs/testing.md`: calendar arithmetic for calendar quantities,
    /// `TimeInterval` for physical ones.
    public static func fireDate(feedAt: Date, afterMinutes: Int) -> Date {
        feedAt.addingTimeInterval(TimeInterval(afterMinutes) * 60)
    }

    /// `nil` when the fire date has already passed — back-dating a feed by four hours
    /// must not schedule an alarm for the past.
    ///
    /// iOS *drops* a past trigger silently instead of erroring, so a caller that did
    /// not check would confirm a reminder that never arrives. Nil rather than clamped
    /// to `now`, on the same principle as Undo in `CLAUDE.md`: offer no button rather
    /// than one that quietly does nothing.
    ///
    /// Strictly after `now`, because a trigger landing on the current instant is
    /// already in the past by the time the request reaches the system.
    public static func scheduleDate(feedAt: Date, afterMinutes: Int, now: Date) -> Date? {
        guard afterMinutes > 0, afterMinutes <= 1440, feedAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { return nil }
        let fire = fireDate(feedAt: feedAt, afterMinutes: afterMinutes)
        return fire > now ? fire : nil
    }

    /// Body text for the notification: "Feed reminder · last fed 2:14 AM".
    ///
    /// The baby's name is absent on purpose — it belongs to the notification *title*,
    /// and repeating it here prints it twice on one lock screen. That is also why
    /// this takes no name parameter: an argument nothing reads misdescribes the API.
    ///
    /// Rendered in the supplied display zone. The live app supplies the device's
    /// zone so this agrees with its logging clock.
    public static func body(lastFedAt: Date, timeZone: TimeZone) -> String {
        "Feed reminder · last fed \(Fmt.clock(lastFedAt, timeZone: timeZone))"
    }
}
