import Foundation
import MoonlogCore
import SwiftData
import UserNotifications

/// Narrow boundary lets lifecycle tests delay OS acceptance without touching real
/// notifications. Authorization and pending reads remain the system's responsibility.
@MainActor
protocol FeedNotificationRequests {
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    func removeAllPending()
    func removeAllDelivered()
}

@MainActor
private final class SystemFeedNotificationRequests: FeedNotificationRequests {
    private var center: UNUserNotificationCenter { .current() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    func removeAllPending() { center.removeAllPendingNotificationRequests() }
    func removeAllDelivered() { center.removeAllDeliveredNotifications() }
}

/// Erasing the app's records also erases their notification content immediately.
/// An add already awaiting the OS must not resurrect an erased family's notice.
@MainActor
final class FeedNotificationLifecycle {
    private let requests: any FeedNotificationRequests
    private(set) var epoch: UInt64 = 0

    init(requests: any FeedNotificationRequests) { self.requests = requests }

    func cancelAll() {
        epoch &+= 1
        requests.removeAllPending()
        requests.removeAllDelivered()
    }

    func add(_ request: UNNotificationRequest, scheduledAtEpoch expected: UInt64) async throws {
        guard expected == epoch else { throw CancellationError() }
        defer {
            if expected != epoch {
                // cancelAll may run while add is suspended. Remove only this old ID;
                // a newly created family's unrelated requests must remain untouched.
                requests.removePending([request.identifier])
                requests.removeDelivered([request.identifier])
            }
        }
        try await requests.add(request)
        guard expected == epoch else { throw CancellationError() }
    }
}

/// Schedules the silent "remind me in X" notification for a feed. The *when* and the
/// *wording* are `FeedReminder` in Core; this is only the half that has to talk to iOS.
///
/// **This is the one file in the project that imports `UserNotifications`.** Core must
/// stay Foundation-only for the Watch app (see the note at the top of `FeedReminder`),
/// and keeping the framework import to a single file means the one place that can put a
/// sound on a notification is the one place that never does.
///
/// ## Why there is no `@Model` for a reminder
///
/// The `UNNotificationRequest.identifier` **is the feed event's UUID string**. Nothing
/// is stored, nothing syncs, and the schema does not change — the notification centre
/// is the database, keyed the same way ours is. That one choice pays for four features
/// that would otherwise each need code:
///
/// - **Retime.** `add` with an identifier that already has a pending request *replaces*
///   it. Changing 90 minutes to 180 is a second `schedule` call, not a cancel-then-add
///   that can half-fail.
/// - **Delete.** Deleting the feed cancels by the id already in hand. No lookup table to
///   fall out of step with the store — the failure mode a side table would have is an
///   alarm for a record that no longer exists.
/// - **Undo.** `CLAUDE.md` requires undo to restore a record under its *original* id
///   rather than log a lookalike, so re-scheduling after an undone delete lands on the
///   same identifier the first reminder used. A lookalike id would have orphaned it.
/// - **Wrong twin.** Correcting which baby a feed belongs to rewrites the same request:
///   new title, new `threadIdentifier`, same identifier, so the twins do not both get
///   tapped for one feed.
///
/// The cost is that a reminder does not survive to another device — which is correct.
/// A wrist tap is for the phone in the room with the baby, not for iCloud.
@MainActor
enum FeedReminders {

    private static var center: UNUserNotificationCenter { .current() }
    private static let lifecycle = FeedNotificationLifecycle(requests: SystemFeedNotificationRequests())

    /// The identity that makes the whole design work: one pending request per feed event.
    static func identifier(for eventID: UUID) -> String { eventID.uuidString }

    /// Keys for `userInfo`, so the future tap handler and this file agree on spelling.
    enum UserInfoKey {
        static let eventID = "moonlog.eventID"
        static let babyID = "moonlog.babyID"
    }

    static func authorization() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Only ever called from a user gesture — never at launch, never in `.onAppear`.
    ///
    /// The system prompt can be shown **once**, ever. Spending it on app launch, before
    /// the doula has logged anything, is spending it on a question she has no reason to
    /// say yes to yet; there is no second chance short of sending her to Settings.
    static func requestAuthorization() async -> Bool {
        #if DEBUG
        // Deterministic UI coverage of denial and permission changing during save.
        // No prompt or fake outcome can exist in a Release binary.
        if ProcessInfo.processInfo.arguments.contains("-moonlogReminderDenied") { return false }
        if ProcessInfo.processInfo.arguments.contains("-moonlogReminderSaveFailure") { return true }
        #endif
        // No `.sound`: the app has no use for a permission it must never exercise, and
        // an alert offering "Sounds" to someone standing over a sleeping baby is its own
        // small alarm. `.badge` likewise — nothing here counts.
        do {
            return try await center.requestAuthorization(options: [.alert])
        } catch {
            // A thrown request means no permission was granted; the caller only needs
            // the answer, and there is nothing actionable to say about the reason.
            return false
        }
    }

    /// Schedule (or replace) the reminder for one feed.
    ///
    /// - Throws: `ReminderError.alreadyElapsed` if the offset has already passed —
    ///   back-dating a feed by four hours must not set an alarm for the past.
    ///   `ReminderError.notAuthorized` if notifications are off.
    static func schedule(
        eventID: UUID,
        babyID: UUID,
        babyName: String,
        feedAt: Date,
        afterMinutes: Int,
        timeZone: TimeZone,
        expectedEpoch: UInt64
    ) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-moonlogReminderSaveFailure") {
            throw ReminderError.notAuthorized
        }
        #endif
        // Resolve the chosen absolute deadline before querying OS authorization.
        // Remaining time is rechecked after that suspension point below.
        let schedulingEpoch = expectedEpoch
        let now = Date.now

        // Core owns this arithmetic and is tested on it, including the spring-forward
        // fixture. Recomputing it here would be a second implementation to keep honest.
        guard let fireAt = FeedReminder.scheduleDate(
            feedAt: feedAt, afterMinutes: afterMinutes, now: now
        ) else { throw ReminderError.alreadyElapsed }

        let content = UNMutableNotificationContent()
        content.title = babyName
        // Body deliberately carries no name — see `FeedReminder.body`; the title has it.
        content.body = FeedReminder.body(lastFedAt: feedAt, timeZone: timeZone)

        // Non-negotiable. A baby is asleep in the room this fires in; the wrist tap is
        // the entire point and a sound would undo the thing being logged.
        content.sound = nil

        // Twins group as two stacks on the lock screen rather than one interleaved pile,
        // so a half-awake glance reads "this one" and not "a feed is due".
        content.threadIdentifier = babyID.uuidString

        content.userInfo = [
            UserInfoKey.eventID: eventID.uuidString,
            UserInfoKey.babyID: babyID.uuidString,
        ]

        // `.timeSensitive` is what would break through a Focus mode — the mode a doula on
        // a night shift is most likely to be in. It needs the
        // `com.apple.developer.usernotifications.time-sensitive` entitlement, which means
        // a hand-written entitlements file *and* the capability enabled in the developer
        // portal; this project has neither, and our Info.plist is generated. `.active`
        // until that is set up deliberately.
        content.interruptionLevel = .active

        // A **time-interval** trigger, not a calendar one. The offset is a physical
        // duration: three hours after a feed is three hours of a baby's stomach whatever
        // the clock does in between, so crossing a DST boundary — or the doula's phone
        // picking up a new zone mid-shift — must not move it. A calendar trigger would
        // re-resolve its components against the new zone.

        // Re-checked here rather than trusted from when the sheet opened: permission can
        // be revoked in Settings while a feed is being typed. **Unverified belief, worth
        // testing on device:** `add` is thought *not* to fail observably when
        // authorization is absent — it succeeds and the notification simply never
        // presents. If that is right, this pre-check is the only thing standing between
        // the doula and a reminder she was told was set and that will never arrive.
        let status = await authorization()
        guard status == .authorized || status == .provisional else {
            throw ReminderError.notAuthorized
        }

        let interval = fireAt.timeIntervalSince(Date.now)
        // `UNTimeIntervalNotificationTrigger` raises an ObjC exception, not a Swift
        // error, for a non-positive interval — uncatchable, so it is worth a guard even
        // though the earlier eligibility check accepted it. The deadline may have
        // elapsed while the asynchronous authorization query was in flight.
        guard interval > 0 else { throw ReminderError.alreadyElapsed }

        let request = UNNotificationRequest(
            identifier: identifier(for: eventID),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        // A previous delivery must not keep displaying an old baby/time after retime.
        center.removeDeliveredNotifications(withIdentifiers: [identifier(for: eventID)])
        // Replaces any pending request under the same identifier — this *is* retime.
        try await lifecycle.add(request, scheduledAtEpoch: schedulingEpoch)
    }

    /// Called directly by the confirmed erase action before its asynchronous store
    /// write. Privacy cleanup does not depend on a later SwiftUI observation task.
    static func cancelAll() { lifecycle.cancelAll() }

    /// Capture before the database write, not only when scheduling starts.
    static var schedulingEpoch: UInt64 { lifecycle.epoch }

    static func cancel(_ eventID: UUID) async {
        let id = identifier(for: eventID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        // Also pull it back off the lock screen if it already fired: a reminder for a
        // feed that has since been deleted or moved would otherwise sit there pointing
        // at a record that is gone.
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Fresh read-context avoids relying on the UI context's delayed relationship merge.
    /// This covers closed shifts, deleted families/feeds and archived babies on launch,
    /// foreground and roster changes. Read failure keeps existing requests for retry.
    static func validEventIDs(in container: ModelContainer) throws -> Set<UUID> {
        let context = ModelContext(container)
        let families = try context.fetch(FetchDescriptor<Family>(
            predicate: #Predicate { !$0.isArchived }))
        let shifts = try context.fetch(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.isOpen }))
        var roster: [UUID: Set<UUID>] = [:]
        for family in families { roster[family.id] = Set(family.activeBabies.map(\.id)) }
        var valid: Set<UUID> = []
        for shift in shifts {
            guard let familyID = shift.familyIDRaw, let babyIDs = roster[familyID] else { continue }
            for event in shift.liveEvents where event.kind == .feed {
                if let babyID = event.babyIDRaw, babyIDs.contains(babyID) { valid.insert(event.id) }
            }
        }
        return valid
    }

    static func reconcile(in container: ModelContainer) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }
        // Read after async OS queries. A feed created while awaiting them must not
        // have its newly scheduled request removed against an older store snapshot.
        guard let valid = try? validEventIDs(in: container) else { return }
        let stale = Set(pending + delivered).filter {
            guard let id = UUID(uuidString: $0) else { return false }
            return !valid.contains(id)
        }
        center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        center.removeDeliveredNotifications(withIdentifiers: Array(stale))
    }

    /// `[eventID: fireDate]` — one async read, folded for a whole screen.
    ///
    /// A list of feeds needs to know which rows have a bell on them. Asking per row is
    /// one system round-trip per row; asking once and looking up in a dictionary is one.
    /// Requests whose identifier is not a UUID are skipped rather than guessed at — they
    /// are not ours.
    static func pending() async -> [UUID: Date] {
        await center.pendingNotificationRequests().reduce(into: [UUID: Date]()) { result, request in
            guard
                let id = UUID(uuidString: request.identifier),
                let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
                let fireAt = trigger.nextTriggerDate()
            else { return }
            result[id] = fireAt
        }
    }
}

enum ReminderError: Error, Equatable {
    case notAuthorized
    case alreadyElapsed
}

/// Same double conformance as `CareStoreError`, for the same reason: every alert in this
/// app renders `"\(error)"`, and `LocalizedError` alone would put "notAuthorized" in
/// front of a tired reader at 3am.
extension ReminderError: CustomStringConvertible {
    var description: String { errorDescription ?? "The reminder couldn't be set." }
}

extension ReminderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        // Leads with the feed being safe. The write and the alarm are separate things,
        // and the one the doula needs to know about first is that her record is not lost
        // — otherwise this alert reads as "the feed failed", and she logs it twice.
        case .notAuthorized:
            return "The feed was saved, but the reminder wasn't set — notifications are off for Moonlog. Turn them on in Settings."
        case .alreadyElapsed:
            return "That reminder time has already passed. Pick a longer gap."
        }
    }
}
