# Continuity and responsiveness audit

Reviewed 2026-09-07. Scope: interruption recovery, save feedback, asynchronous
work, repeated actions, and growing datasets. Read `CLAUDE.md`, architecture,
design, testing and status documentation alongside the implementation. This is a
source audit, not a device performance measurement or a guarantee against hangs.
No app implementation changed in this pass. Simulator validation is tracked in
the main audit; this pass did not run competing simulator jobs.

Priorities: **P1** before relying on recovery during a real interrupted shift;
**P2** next usability/reliability pass; **P3** measure before optimizing.

## Findings

### C1 — P1: a failed save discards the entry form

`Sources/Views/LogSheetChrome.swift:249` sets `isSaving`, calls the synchronous
`onSave`, then dismisses immediately at line 254. The actual result arrives later
inside `TonightView.perform` (`Sources/Views/TonightView.swift:592`). Its failure
path presents only a message at line 606. `FeedSheet.swift:14` and the other log
sheets hold input in local `@State`; there is no retained failed-entry payload or
retry route. The parent note has the same pattern
(`Sources/Views/ParentNoteSheet.swift:58`, `SummaryView.swift:91`).

**Caregiver consequence:** after entering amounts, times, or a long note, a storage
error returns the user to Tonight and asks them to remember and retype the work.
An alert prevents silent failure but does not preserve the work. This follows
directly from the callback contract; an injected persistence failure is still
needed to verify the complete visible presentation sequence.

**Remedy:** make save completion explicit (`async throws` or a result callback),
retain the form on failure, and dismiss only after success. Show “Saving…” while
preventing duplicate submission. Preserve a family/baby/shift-scoped draft if the
user needs to leave before completion. Do not add automatic retries until each
submission has a stable operation identity: a slow or uncertain save must not
become two feeds.

**Validation:** inject a delayed save and a failed save for feed, note, sleep,
parent note and shift hours. Assert exact input survives, Retry creates exactly
one record, and another baby's controls remain usable where safe.

### C2 — P1: unsaved input has no interruption recovery

Log sheets retain values only in view state (`Sources/Views/FeedSheet.swift:14`,
`Sources/Views/NoteSheet.swift:14`). Their sheet presentation has no dirty-draft
policy (`Sources/Views/TonightView.swift:171`); no draft persistence or scene-phase
recovery exists in `Sources/App/MoonlogApp.swift:35`. Cancel dismisses immediately
(`Sources/Views/LogSheetChrome.swift:228`). Family changes intentionally reset the
view identity (`Sources/Views/RootView.swift:163`), correctly protecting attribution
but also removing that screen's temporary state.

**Caregiver consequence:** accidental swipe-dismiss or process termination can
erase unfinished input. Backgrounding alone is not proven to lose a retained
SwiftUI view; do not equate it with termination. A time defaults to sheet-open time
(`FeedSheet.swift:37`), so returning much later also needs an understandable
timestamp rather than silently replacing the user's original time.

**Remedy:** persist small, scoped drafts and offer “Resume entry” with the baby and
original event time visible. Clear drafts only after confirmed success or explicit
discard. Apply discard protection only to changed input, avoiding an extra
confirmation on every empty sheet. Preserve explicit timestamps across recovery.

**Validation:** type a note and change feed values, then swipe-dismiss, lock/unlock,
background for several minutes, and terminate/relaunch separately. Verify draft
restoration and correct household attribution, including a switch to another family.

### C3 — P2: sleep's busy period is a timer, not confirmed visible state

`Sources/Views/TonightView.swift:465` guards a busy baby, and `perform` removes the
lock only after the action plus an unconditional two-second sleep at line 603.
The comment explicitly identifies a main-context merge delay. `refreshToken` is
bumped once immediately after the actor result (line 597), rather than after an
observed merge. `CareStore.toggleSleep` serializes mutations
(`Sources/Lib/CareStore.swift:411`), but a second accepted toggle closes the session
the first opened; serialization alone does not deduplicate user intent.

**Caregiver consequence:** a successful fast write still leaves sleep interaction
temporarily unavailable. Under a merge slower than the assumed two seconds the
card may still show the previous state when interaction resumes. The latter is a
race hypothesis requiring delayed-merge testing, not a reproduced wrong-state bug.

**Remedy:** return authoritative state/revision with the write and render or await
that state before releasing the control. Prefer desired-state commands with an
expected revision to a blind toggle where retries are possible. Provide visible
and accessible progress for a slow operation. A timeout must report an uncertain
result and reconcile it, not blindly retry a possibly committed mutation.

**Validation:** rapid taps, delayed save, delayed observation, Undo during the busy
period, and background/resume while pending. Assert one intended transition and
consistent card/timeline state without a hardcoded settling delay.

### C4 — P2: interruptions and the next log remove Undo

`Sources/Views/TonightView.swift:613` stores only one `pendingUndo`; every new
confirmation replaces it. The asynchronous six-second timer clears it at lines
619–623, with no foreground-time accounting or durable recovery record. `runUndo`
also clears the action before awaiting its result (lines 627–639), so a failed
Undo cannot be retried from the banner.

**Caregiver consequence:** repositioning a baby or answering an interruption can
consume the entire recovery window. Logging the other twin immediately removes
the first reversal. Timeline edit/move remains available for existing entries,
but it takes more navigation; deletion recovery is especially time-sensitive.

**Remedy:** retain a small recent-action history with clear subject/action labels,
or keep the latest undoable action available until explicitly replaced/dismissed.
Preserve failed Undo for retry where idempotent. Guard compensating edits against
overwriting newer edits before extending their lifetime. Avoid stacking new modal
confirmations on ordinary logging.

**Validation:** two successive baby actions, failed Undo, lock for more than six
seconds, and an intervening edit before reversal. Existing
`Tests/MoonlogUITests/RecoveryTests.swift:11` exercises immediate Undo only.

### C5 — P3: history and timeline growth are unbounded before rendering

History queries all closed shifts, then filters by household and takes 14 in
memory (`Sources/Views/HistoryView.swift:16`, line 24). Summary also queries all
closed shifts just to locate the current family's latest one
(`Sources/Views/SummaryView.swift:20`, line 39). Tonight rebuilds its record
projection (`Sources/Views/TonightView.swift:697`), sorts all timeline rows
(`Sources/Views/ShiftTimeline.swift:58`), and uses an eager stack
(`Sources/Views/TimelineSection.swift:44`). This is reasonable for a short night
but has no enforced upper bound. A `ScrollView` alone does not make that stack lazy.

**Remedy:** measure populated stores first; then scope closed-shift predicates to
a captured family UUID, fetch only the latest needed records, and paginate older
nights. If long shifts show layout hitches, use lazy rows with per-row backgrounds
or a bounded recent section without losing access to older records.

**Validation:** profile on an older supported physical iPhone with several years
of families/shifts and a deliberately long shift. Measure cold start, Tonight
scrolling, opening History, saving, and handoff composition. No measured hang or
latency regression is claimed here. Also inspect the CareStore executor in Instruments:
construction is on the main actor (`Sources/App/MoonlogApp.swift:26`), so the
`@ModelActor` annotation alone should not be treated as proof that synchronous
fetch/save work cannot affect UI responsiveness.

## Existing protections worth retaining

- Local persistence does not depend on a network response; CloudKit remains gated.
- Writes surface errors; Tonight adds success feedback and per-baby busy state.
- Log and shift Save buttons latch before dismissal, and add-family/add-baby
  buttons similarly guard duplicate taps (`OnboardingView.swift:177`, line 246).
- Confirmation-token checks prevent an older banner timer clearing a newer one
  (`TonightView.swift:620`).
- Family-specific view identity prevents a stale form being reused for another
  household. Draft recovery must preserve that protection.
- Sleep mutations are serialized and restores preserve record identity. Improve
  UI retry semantics without bypassing CareStore.

## Verification boundary

The existing recovery suite covers immediate Undo and reachability, not persisted
drafts, delayed/failing saves, process death mid-write, stalled observation, or
large-store performance. Main-context freshness after remote sync remains a
separate deferred CloudKit validation item. No network-wait loop or explicit
blocking sleep was identified in these foreground logging paths; `Task.sleep`
suspends rather than blocking a thread. None of that proves that the app cannot
stall. Fault injection and physical-device interruption testing are necessary
before closing C1–C5.
