# Consolidated feed reminders and remembered hours

Source integration: November 16, 2026. This describes unshipped source, not a new
TestFlight release. Full simulator test results are recorded separately by the
integration lead; physical notification delivery has not been verified here.

## Selected behavior

A reminder belongs to **one logged feed**, not to a family-wide feeding schedule.
Logging another feed does not silently cancel an earlier reminder. The card shows
the soonest pending reminder for that baby. A reminder belonging to an earlier
feed never changes the latest feed's elapsed-time warning threshold.

The picker offers Off or 90–240 minutes, in 30-minute steps. First use is Off;
subsequent new feeds remember the last successfully saved choice. The choice is
visible and editable on every feed. These are caregiver-chosen reminders, not
medical feeding recommendations. Notification text says “Feed reminder”.

The feed save completes before notification scheduling. Denied permission, an
elapsed reminder time or an OS scheduling error must not lose a feed, dismiss an
unsaved error form, or encourage a duplicate save. Permission denial in the picker
resets the choice to Off with an explanation and Settings link. Failure after the
feed commits leaves a persistent dismissible notice on the logging screen after
the sheet closes; it is not an alert raised beneath a disappearing sheet.

## Identity and lifecycle

- The notification identifier remains the feed UUID string, preserving the older
  branch's cross-launch mapping. Requests are local to the installing device.
- Editing a feed replaces its request using that identity. Clearing the reminder
  cancels it. Replacing removes an already-delivered old notice too.
- Deleting cancels pending and delivered notices. Undo restores the original record
  ID and, if still schedulable, its original reminder. An expired reminder is not
  replaced with a new instant merely to make Undo look successful.
- Wrong-baby correction rewrites the title/thread under the same ID. A failed
  rewrite removes the misaddressed notice rather than leaving the wrong baby named.
- Ending a shift cancels that shift's feed notices. Other families' open shifts
  retain theirs.
- Launch, foreground and roster/open-shift identity changes reconcile notification
  IDs with a fresh database read. Closed shifts, deleted feeds/families and archived
  babies are excluded. Erase-everything leaves no eligible event IDs. A failed
  database read does not guess that the store is empty and remove everything.
- Reconciliation queries the notification center before reading current eligible
  IDs, so a request created during the asynchronous OS query is checked against the
  newer database state rather than accidentally removed with an earlier snapshot.

No reminder field is added to the persisted event schema. The notification center
holds the current pending request, while Core owns timing calculations. Initial
editing waits for that request read so an existing reminder is not seeded as Off
and silently cancelled on a quick cold launch.

## Display, privacy and delivery limits

The notification is silent (`sound = nil`) with normal active interruption level.
Focus, notification permissions and device settings can delay or suppress it. The
UI says this explicitly. The baby's name appears in the title; device notification
preview settings control lock-screen exposure. These notifications should be
cancelled before the device is handed to a different person or reassigned.

This is not a Watch app and does not enable WatchConnectivity, remote push,
CloudKit, parent accounts or shared reports. Apple describes Watch notifications
as routed according to phone/watch state and mirroring settings; do not promise a
wrist tap from the presence of a scheduled request. Notification taps currently
open the app normally; baby-specific deep navigation remains a later feature.

Before a device pilot, verify authorization denial and revocation, notification
failure after saving, background/foreground, Focus, phone locked/unlocked, paired
Watch locked/unlocked, feed edits/delete/Undo/wrong-baby, end shift and erase. No
real reminder, parent message or TestFlight upload was sent by this work.

## Remembered hours and day context

The family stores usual start/end wall-clock minutes. A new legacy family has no
stored window. Starting a new shift defaults actual start to now; the remembered
end is a visible editable plan. “Use usual family hours” is an explicit gesture to
apply the calendar-aware suggestion to both pickers. It must not infer attendance
merely because the app opened. DST and midnight calculations stay in Core.

Starting a shift is awaited. A failed save keeps entered values, unlatches Start
and explains the error. Day care/Night care is explicitly selected before starting
and persisted on the shift. Existing shifts read as Night. This changes context
labels, not the device theme or recorded shift boundaries.

## Verification added

- Pure reminder arithmetic, future/elapsed boundaries, DST, text formatting and
  malformed interval/date rejection.
- Calendar-aware usual-hour defaults, including midnight and DST fixtures.
- Reminder-aware card thresholds, including an older reminder plus a newer feed.
- Real in-memory store reconciliation across end shift, another family, deleting a
  family/feed, erase, archiving a baby, Undo identity and wrong-twin correction.
- Reachability tests for denied permission and a scheduling failure after the feed
  commits. The latter uses DEBUG-only deterministic outcomes; it does not establish
  OS permission behavior or actual device delivery. Archive guards must continue to
  prove these hook strings absent in Release.

## Primary references checked

- [Apple: schedule a local notification](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
- [Apple: request identifiers replace pending requests](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier).
- [Apple: notification request initialization](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/init(identifier:content:trigger:)).
- [Apple: notifications on Apple Watch](https://support.apple.com/en-gb/108369).
- [Apple: iPhone and Watch notification routing and Focus](https://support.apple.com/en-au/108274).

These sources inform implementation and the device checklist. They do not prove
this app's notifications have delivered on a user's hardware.
