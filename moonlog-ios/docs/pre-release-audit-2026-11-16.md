# Pre-release audit — November 16, 2026

The fresh audit began against PR #3 head
`ab3177f45601a6d65dc6ba22d695b37bd4f78b0f`, before merge into `moonlog-ios`
and before any new TestFlight upload. This is native-only work; the live website,
frozen PWA and unrelated working-tree changes are outside the release. Fixes were
made in the isolated release checkout, rather than resetting the shared workspace.

Prior 302-unit and combined 37-UI validation remains historical evidence for the
initial implementation. The audit did not treat those passes as proof of release
readiness. Four source-audit blockers were followed by a fifth blocker observed
in focused UI integration; each received a scoped fix and regression coverage.

## Confirmed blockers and fixes

### Closed care records could not be corrected through the UI

The actor could update care records after a shift ended, but the history/Summary
routes were read-only and logging no longer exposed that shift. Correcting facts
before reviewing a new EOD revision therefore had no working user route.

A closed-shift correction screen is now reachable from the EOD review and history
routes. It reuses the existing log sheets and writer, supports correcting the closed
coverage window without reopening the shift, and retains Undo. Returning to the
report fetches fresh actor values, including the corrected date/header and factual
digest, while preserving unsaved personal observations. A changed factual log
requires a new review/revision; frozen earlier copies remain intact.

### Draft autosave could overwrite later edits or rewind a refresh

The initial `DayReportView` cancelled debounce tasks but submitted unconditional
whole-draft replacements through `saveDayReportDraft`. A submitted B write could
finish after a user reverted to saved A: the UI thought A was clean and queued no
restoration, leaving B on disk. A delayed exit request could also arrive after a
newer save, and checking `dirty` only after an awaited refresh could replace newly
saved text with an older snapshot.

All draft writes now require an optimistic expected draft at the actor. One editor
uses an ordered write coordinator for debounce, explicit save and exit. Each intent
is stamped synchronously before creating a Task; every edit and explicit reload
advances its fence, including a revert that queues no replacement save. Old requests
are rejected before actor submission, queued requests recheck after waiting, and
obsolete results/errors do not overwrite current UI state. Refresh uses captured
read tickets and committed generations. Ordinary Back waits for a successful save;
conflict recovery retains entered notes with copy and explicit discard/reload.

Seven deterministic writer tests cover delayed submission/completion, reverts,
refresh during save, explicit reload and conflicts. An actor test verifies a stale
editor cannot overwrite another editor's newer fields. Existing disk-reopen and
immutable-publication tests remain in force.

### Clipping a completed sleep invented a wake at the coverage boundary

`SleepMath.stretch` initially copied the raw session's open/closed state after
clipping its end. A sleep ending at 18:00 inside coverage ending 17:00 could be
reported as waking at 17:00, even though it continued beyond handoff. Text/HTML
continuation headers also only considered raw open sessions.

Continuation is now derived at the actual coverage cutoff and shared by the
stretch and handoff descriptions. Boundary tests cover completed sleep crossing a
closed window, exact-boundary waking, open sessions and noncontributing sessions.
The semantic report digest is `report-facts-v2`, so an earlier derived copy becomes
historical and needs fresh review rather than silently retaining current status.

### Erasing records did not synchronously clear identifiable notifications

The original erase path relied on eventual Root reconciliation after database
changes. Pending/delivered notices containing a baby's name could survive if the
app was suspended or terminated immediately after erase. In-flight logging or Undo
could also finish later and recreate a request.

Explicit erase now synchronously cancels pending and delivered app notifications
and advances a wipe epoch. Reminder-producing operations capture the epoch before
awaiting database work; scheduling checks it before and after the OS add. Three
fake-driver race tests assert the cancellation calls and prevent late callbacks
from resurrecting notices. This is scoped to explicit erase, not a claim that every
family deletion/rename path now has identical immediate cleanup semantics.

### Editing a saved feed could remain stuck loading reminder state

Focused UI integration opened a real saved feed and found the editor permanently
showing `Loading reminder…` when the OS returned an empty pending-request dictionary.
`remindersLoaded` was only read inside the sheet builder, so changing it did not
establish the required body dependency; assigning another empty dictionary also
did not rebuild the sheet's derived input. The failed hierarchy records the actual
ActivityIndicator at line 146:
`/tmp/moonlog-testflight-audit-day-attachments/239CAE0B-2C80-4C7F-B7AA-3DB2E18AA53D.txt`.

Readiness is now an explicit input to the derived `Tonight` value created by the
view body, and the sheet reads that derived readiness. Closed-shift corrections
bypass the OS reminder load entirely because they cannot set alarms. A new
`ReminderReachabilityTests.testExistingFeedEditLoadsWhenNoReminderRequestsExist`
opens an actual saved bottle with no pending request. The final focused rerun
passed **2/2**, covering that active-feed path and the closed-coverage/end-picker
and feed-edit flow without reminders. Evidence:
`/tmp/moonlog-testflight-audit-feed-readiness.xcresult` and its matching log.
The fifth finding is resolved in the tested source.

## Current validation

The post-fix unit run for the original four blockers passed **318 tests with zero
failures**: 170 Core and 148
app/persistence tests. Evidence:
`/tmp/moonlog-testflight-audit-unit-final.xcresult` and its matching log.

The first six focused day UI flows finished **5/6**: revision 2, Undo, historical
receipt and erase paths passed; the closed-feed case exposed the loading blocker
above. The final readiness rerun then passed **2/2**, covering the corrected
closed-feed flow and a new active saved-feed/no-request regression. Together these
provide passing evidence for **seven unique focused scenarios**, rather than one
single all-green seven-case run.

The full shipping run of 318 unit and 41 UI cases, signed device archive checks and
TestFlight upload remain **pending** at this audit checkpoint. Root owns those
actions and records their actual results/build number. This document does not
claim a new release or substitute focused checks for the full shipping gate.

## Known limits and bounded follow-ups

- Real-phone notification presentation, Focus and Watch mirroring remain device
  checks. A notification tap does not yet navigate directly to its baby/record.
- Optional parent receipt remains on the same phone with a typed, unauthenticated
  name. It is not remote reading, agreement with every fact or care consent.
- Family deletion/renaming still uses documented reconciliation behavior; the
  explicit erase guarantee must not be generalized to every lifecycle transition.
- The final uncommitted keystrokes can still be lost on abrupt process termination.
  Temporary-memory fallback is explicitly labelled session only. Restorable
  export/import and secure cross-device accounts are separate work.
- Reminder scheduling recalculates remaining time after authorization, and backup
  wording was qualified. Those are bounded corrections, not evidence of real-device
  delivery or a new backup/restore feature.
