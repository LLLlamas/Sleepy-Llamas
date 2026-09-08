# Reliability and data integrity audit

Reviewed 2026-09-07 against the current source and knowledgebase. This is a source
audit, not proof of a crash-free app. No production data was changed, no CloudKit
capability was enabled, and no fault-injection or simulator tests were run by this
reviewer. The coordinated audit's test results belong in the main audit/status
document. Line references below describe the source at review time.

Priorities: **P1** address before relying on recovery under adverse conditions;
**P2** harden before extending writers, importing data, or enabling sync. “Verified
in source” identifies a concrete code path; “risk” means the adverse runtime
condition has not been reproduced.

## Findings

### R1 — P1: rejected writes can leave mutations pending

**Verified in source:** `CareStore.updateBaby` changes name and accent before it
validates the supplied birth date (`Sources/Lib/CareStore.swift:186–196`). A call
with a new name plus tomorrow's birth date throws after the name has changed in
the actor's context. No actor method or `StoreWrite` rolls back on failure.
An eventual successful `save()` on that same long-lived context can commit the
earlier rejected changes. Independently, persistence failures occur after most
methods have mutated or inserted their records.

This breaks the meaning of “Couldn't save”: the caregiver cannot safely assume
the attempted change was discarded. The validation order is demonstrated by
source; durable carry-over after a storage failure needs a fault-injection test.

**Remedy:** validate every input before changing models, and give each logical
write a transaction boundary with rollback on error. Do not implement rollback
only in the view: the actor owns the context and all callers need the guarantee.
Test a combined rename/accent/future-date rejection followed by an unrelated
successful save and verify the original values from a fresh context. Add injected
save failures for inserts, edits and deletes.

### R2 — P1: sleep correction commits before reconciliation succeeds

**Verified in source:** `recordSleep` saves at `CareStore.swift:455`, then calls
`reconcileSleep` at 456; `updateSleepSession` does the same at 478–480, and
restoration at 500–501. Reconciliation fetches, merges/deletes and saves separately
(525–549). A second-stage failure can therefore report the whole operation as
failed after its first stage is durable. Killing the process between the two
stages can preserve overlapping sessions; totals sum sessions independently.
`toggleSleep` also performs reconciliation before validating that the requested
wake is after the existing session's start (416–419).

**Risk:** storage-failure/process-termination windows were not exercised. Existing
tests prove normal reconciliation, not atomic recovery.

**Remedy:** make mutation plus reconciliation one commit, using an internal
reconciliation routine that does not save on its own. Test failure before commit
and reopen the disk-backed store to verify either the whole operation or none of
it survived. Consider an explicit repair path for already inconsistent stores.

### R3 — P1: fallback storage still has a terminal launch path

**Verified in source:** disk-open failure falls back to memory, whose initializer
uses `try!` (`Sources/App/ModelContainerFactory.swift:79–89`). A defaulted schema
does not make a throwing initializer an absolute guarantee. If that initializer
throws, the app terminates instead of showing recovery UI. No such failure was
reproduced during this audit.

The existing in-memory warning on Tonight is valuable
(`Sources/Views/NightHeader.swift:69–80`), but it appears only after a shift exists;
the factory exposes no retry/reopen action. The launch container is static
(`Sources/App/MoonlogApp.swift:18–27`). Logging in memory remains temporary even
when the success banner appears.

**Remedy:** model startup as a recoverable result and provide a store-independent
recovery screen when neither disk nor memory opens. Offer a deliberate retry and
clear export/recovery guidance for temporary mode without deleting the original
store. Inject disk and memory initializer failures to verify every startup branch,
including onboarding, and verify the warning survives navigation.

### R4 — P2: duplicate logical IDs can trigger a dictionary trap

**Verified in source:** `Dictionary(uniqueKeysWithValues:)` assumes unique model
UUIDs in `CareStore.swift:90–91` (baby ordering), `CareStore.swift:534` (sleep
reconciliation), and `Sources/Views/ShiftDetailView.swift:44–46` (past-night
rendering). The schema intentionally has no uniqueness constraints, and explicit
IDs can be supplied to model initializers. Duplicate keys cause a runtime trap;
ordinary app UUID creation is not evidence that duplicates currently exist.

**Risk:** malformed/imported/restored records or future sync behavior could turn
opening a past night or running the repair routine into a repeatable crash. This
is conditional hardening, not a claim of observed random UUID collisions.

**Remedy:** define deterministic duplicate handling and preserve evidence of the
conflict. Group before building dictionaries; do not silently discard conflicting
care records. Seed duplicate logical IDs in fixtures and test ordering, history
rendering and reconciliation. Keep CloudKit disabled until its conflict paths are
validated on devices.

### R5 — P2: the actor accepts a baby from another family

**Verified in source:** logging fetches shift and baby independently
(`CareStore.swift:333–340`, `367–372`); reassignment only checks that the baby
exists (392–397). Sleep creation/correction/restoration follows the same pattern
(411–427, 439–453, 489–499). None verifies the baby's family matches the shift's
family. Current views normally supply a scoped roster, so no cross-family tap
route was demonstrated. The actor nevertheless does not enforce the documented
household isolation boundary for future NFC/import/other callers.

**Remedy:** centralize the shift/baby membership check, define treatment of
archived babies for historical corrections, and reject cross-family assignments
before mutation. Test every public create, restore and reassignment path with two
families. Pump's optional baby handling also needs an explicit invariant: its
current helper accepts a supplied baby although the docs describe no baby.

### R6 — P2: Undo has no conflict check and can be consumed by failure

**Verified in source:** an event edit's Undo writes its entire prior payload
(`Sources/Views/TonightView.swift:522–529`) without checking whether the record
still matches the completed edit. Sleep Undo similarly reopens by ID (495–498).
`runUndo` removes the stored action before the async operation (627–639), so a
failed Undo cannot be retried from the banner. Restoration by ID is already
idempotent, which protects duplicate restoration taps but not stale edits.

**Risk:** a later write or future sync change can be overwritten. Current local
single-device interaction reduces the conflict window; it does not establish a
general conflict-safe undo contract.

**Remedy:** carry the expected post-write state or revision and compare inside
the actor before reversing. Preserve a retryable action after failure where it is
still applicable. Test a changed record, deleted record, failed Undo, and a sleep
Undo after reconciliation has changed session identity. Keep the documented
non-undoable actions explicit.

### R7 — P2: malformed numeric payloads reach trapping format conversions

**Verified in source:** volume and weight formatters convert `Double` to `Int`
without finite/range checks (`Sources/Core/Formatters.swift:104`, 113, 122, 151,
154); duration helpers do so at 12, 48 and 55. The actor's payload closures have no
numeric validation (`CareStore.swift:337–341`, 383–387). Non-finite or sufficiently
large values can trap during display. Current amount steppers have bounds, so
ordinary amount entry is protected; malformed stored data and future writers are
the principal risk, not an observed crash from normal tapping.

**Remedy:** reject non-finite/out-of-domain values at the writer and make display
formatters tolerate invalid stored values with an explicit unavailable marker.
Add NaN, infinity, negative, and conversion-limit tests, including summed volumes.

## Additional recovery gaps

- Family onboarding uses three separately saved actor calls
  (`Sources/Views/RootView.swift:179–187`). A later failure can leave an incomplete
  household after an error. Make setup one logical write or provide an explicit
  resumable state; test interruption between each stage.
- `eraseEverything` explicitly clears orphan families, shifts, babies, events,
  sleep and note tags, but not orphan `TagBinding` records
  (`CareStore.swift:113–135`). Root cascades cover attached bindings only. Include
  an orphan binding fixture when extending erase coverage.
- Unknown event kinds are interpreted as notes
  (`Sources/Models/CareRecords.swift:157`). Preserve unknown wire values visibly
  and avoid editing them as a different event kind. This is already on the backlog.

## What is already helping

Writes are centralized in a model actor, ordinary UI errors are surfaced, actor
reads return snapshots, time checks cover many mutations, restoration preserves
record identities, and the CloudKit entitlement gate avoids the known launch
trap. Pure sleep reconciliation has useful invariant coverage. These are sound
foundations; none replaces failure-path and disk-reopen testing.

`ModelPersistenceTests` and `CareStoreTests` create **in-memory** containers
(`Tests/MoonlogTests/ModelPersistenceTests.swift:16–20` and
`Tests/MoonlogTests/CareStoreTests.swift:14–18`). Their names must not be read as
evidence of durability after force-quit, a locked phone, low storage or an upgrade.
`RecoveryTests` currently exercises reachable Undo and confirmation/move controls,
not startup recovery or interrupted saves.

## Next verification gate

Before a release claiming stronger recovery, run the normal unit/reachability
suites and add targeted disk-backed reopen tests, injected fetch/save/open failures,
interrupted sleep reconciliation, and combined invalid updates. On a physical
device, verify lock/background/relaunch during and after Save, incoming
interruptions with a draft open, long-shift data, and the previous shipped store
upgrading to the candidate. Record device/OS/build, observed outcomes and remaining
limits; do not promise that any app can never crash or be terminated by iOS.
