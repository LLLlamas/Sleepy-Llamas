# Daytime Nanny Log research

Reviewed November 16, 2026. This focused refresh builds on the prior daytime
Moonlog memo in the repository's `Doula-Research` directory. It is product and
technical research, not evidence of measured willingness to pay or a competitor
feature audit performed inside paid apps.

## Market findings and resulting choices

Talli already covers daytime activities, feed/sleep/diaper records and caregiver
invitations on iOS and Android. A separate daytime skin would not create a distinct
category. Its Premium page advertises customizable event inputs, event-relative
reminders and CSV export. We should preserve reliable logging and make a reviewed,
personal handoff the initial product focus, without claiming that competitors lack
report review or acknowledgements: their marketing pages cannot prove absence.
Sources: [Talli Baby](https://talli.me/pages/apps-talli-baby),
[Talli Premium](https://talli.me/pages/apps-talli-premium).

Baby Connect advertises caregiver profile access, notes/diary entries, activity
logging, reports and multiple device types. This supports keeping the first release
narrow: a working caregiver workflow and a readable report, rather than attempting
to match every adjacent platform or integration immediately.
Source: [Baby Connect](https://en.babyconnect.com/).

The opportunity is a hypothesis: a caregiver's factual log, personal observations,
practical handoff notes and open questions in one explicitly reviewed version may
save parents time. Validate with consenting Sleepy Llamas families before treating
it as a standalone subscription business. Do not generate observations that a
caregiver did not write or review.

## Notification findings

Apple says notification permission should be requested in context, and permission
settings must be checked before scheduling because users can change them. A denied
reminder must not reject a valid saved feed. Local requests can be cancelled by
identifier; foreground presentation is handled through the notification-center
delegate. Scheduling is not evidence of actual presentation or attention.
Sources: [permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications),
[scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

Implementation consequences: stable family/baby identifiers, reconcile reminder
requests after edit/delete/move/end-shift, and describe reminders as optional logging
conveniences. Physical-device delivery, denied permissions, Focus and Watch mirroring
need real-device validation; simulator calculations do not establish those results.

## Sharing and acknowledgement findings

Apple's CloudKit collaboration sample requires a sharing flow, participants,
permissions and shared data handling. One user's private database syncing is not
cross-user collaboration. Enabling the existing private-store flag would not create
secure parent access. No CloudKit capability is enabled by this work.
Source: [sharing with other iCloud users](https://developer.apple.com/documentation/CloudKit/sharing-cloudkit-data-with-other-icloud-users).

The owner explicitly chose optional same-phone handoff first. A typed parent name
on the caregiver's phone is not authenticated identity, a remote read receipt,
medical consent or approval of every care decision. Store an optional receipt tied
to the exact report revision and preserve the parent's note separately. Ending,
publishing and sharing must all work without acknowledgement.

## Review and revision contract

Draft narrative remains editable. Publishing saves an immutable local copy of the
reviewed narrative and factual text/HTML, with a version, timestamp and stable source
digest. A subsequent change to facts or narrative makes the previous receipt
historical. Republish a new revision; do not rewrite the old published copy or carry
its receipt forward. Invoking a share sheet does not prove a message was sent,
delivered, opened or read.

Totals describe the recorded shift window, not the whole day. Unknown bottle
amounts remain unknown, with partial volume totals explicitly qualified. Parent
questions do not silently change a caregiver's record. Shared access, invitations,
revocation and remote confirmation remain a separate architecture phase.
