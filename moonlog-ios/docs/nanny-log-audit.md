# Daytime handoff audit

Source audit: November 16, 2026. This audit covers `DayReportState`, the SwiftData
actor methods, `DayReportComposer` and the day-report editor, published-copy and
optional parent-receipt routes. It is independent of the lead's implementation
pass. Test execution results belong in `status.md` and `testing.md`; reading source
is not evidence that a control was driven on a device.

## Findings addressed during implementation

- **Copies needed a revision and date outside the app.** The initial exports lacked
  publication metadata. Frozen text and HTML now include the revision and ISO
  publication timestamp. Viewing old copies does not recompute their contents.
- **A digest needs canonical factual provenance.** The initial digest depended on
  rendered output, omitted record identities and could vary with relationship
  order. It now covers stable raw provenance, IDs, values, coverage, roster,
  context and display units with canonical ordering. SHA-256 and length-prefixed
  fields replace ambiguous joining or process-random hashing. Tagged optional values
  distinguish a missing value from a real string such as `<nil>`. A semantic facts
  version is explicit; presentation-only CSS is outside the digest.
- **Day mode needed its own reachable handoff route.** Summary and historical day
  shifts now link to the editor/review screen. The older raw-copy/share toolbar and
  separate parent-note editor are restricted to night shifts, so they cannot
  bypass the reviewed EOD copy or silently omit its personal narrative.
- **Draft edits needed a persistence path beyond an explicit button.** The editor
  now debounces writes through CareStore and attempts a flush on leaving. Failed
  saves retain entered text while the view is present and expose an error. This
  is not a guarantee of recovery from abrupt process termination or storage failure.
- **A new day-aware label scan crashed after erase.** Existing erase UI coverage
  exposed a walk through `family.shifts` after those SwiftData objects had been
  invalidated. Settings/history now use the neutral Past shifts label without
  reading that relationship. Reminder lifecycle identity uses query membership and
  safe persistent-model identifiers rather than dereferencing archived/deleted
  relationship objects. The full reachability suite was rerun after this global fix.
- **Adding context setup pushed Start shift out of reach.** Existing start-flow
  tests exposed the primary action falling below the initial viewport. Start is
  now a persistent bottom safe-area action with a 56-point target, while the
  editable setup fields remain scrollable. Shift times and confirmation semantics
  are unchanged; the full suite was rerun after this visibility fix.
- **The keyboard blocked later fields in UI testing.** Editing tests exposed that
  notes could become unreachable with the keyboard still up. The editor and local
  receipt sheet now have explicit Done controls with unique focus bindings and
  interactive scroll dismissal; the day UI flows were rerun after that fix.
- **Temporary storage must not look durable.** The existing factory's memory
  fallback could make ordinary saved-state wording misleading on the report page.
  The editor and published-copy view now warn when storage is temporary; draft and
  publication status explicitly say session only in that mode. Sharing a copy is
  still distinct from making the database itself recoverable.
- **Day labels also need a visual check.** The Today screenshot exposed a
  remaining Tonight heading in the timeline. That heading now follows the shift's
  explicit context, matching the already day-aware screen/tab and report output.
- **Unknown observations must not look like zero observations.** Day HTML says
  sleep was not logged rather than declaring none occurred. Unknown bottle amounts
  and feed methods are explicitly described; partial volume totals are qualified.
- **Actor rules must match the review UI.** Publication requires day context, a
  closed shift, a valid publication time, current factual digest and the same saved
  draft the caregiver reviewed. Receipt writes require the current exact revision.

## Behaviors checked in source

Published revisions are immutable values. Draft or factual changes make the prior
publication noncurrent while retaining its copy and receipts. Unchanged publication
and receipt retries are idempotent. Parent notes are stored separately from the
caregiver's narrative. Invalid operations run inside the existing atomic writer,
and unreadable saved JSON fails closed rather than being overwritten with a blank
report. The editor carries immutable identifiers/header values and reads fresh
actor snapshots after asynchronous operations, rather than dereferencing retained
SwiftData models after a delete or delayed merge.

Parent receipt is optional and does not gate ending, publishing, copy or sharing.
The flow describes the phone being handed to the parent, a typed name with
unverified identity, and receipt of a specific revision. It does not claim remote
identity, automatic delivery, a read receipt, agreement with all facts or consent
to care decisions. Sharing a frozen file is separate from recording a local receipt.

## Remaining limits

The existing factory can fall back to temporary memory if its disk store cannot
open. That mode is explicitly labelled as session only in the report flow; normal
on-disk save/reopen tests do not prove recovery of temporary-memory data.

Notification delivery, Focus behavior and Watch mirroring require real-device
checks. Parent accounts, household sharing, remote acknowledgements, a Watch app
and restorable backup/import are not supplied by this local workflow. CloudKit
remains disabled. The new source is not a newly uploaded TestFlight release.
