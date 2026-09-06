# Architecture

## Layers

```
MoonlogCore  Sources/Core/    pure logic — no SwiftData, no SwiftUI, no Date.now
     ▲                          (a separate framework target)
     │
App          Sources/App/     Entry point + ModelContainerFactory (the CloudKit gate)
Models       Sources/Models/  @Model types. CloudKit-shaped by construction.
CareStore    Sources/Lib/     @ModelActor. The only writer, and the time rules.
Views        Sources/Views/   SwiftUI. Reads via @Query, writes via CareStore.
Theme        Sources/Theme/   Palette, accents.
```

**Why `MoonlogCore` is a separate target, not a folder.** A framework cannot import
the app, so it physically cannot reference a `@Model` type. That is the coupling
worth preventing: every calculation that broke in the web version — day bucketing,
day-of-life, totals, sleep reconciliation — lives there on value types, and its
tests run in milliseconds with no `ModelContainer` and no host app. A naming
convention would not have enforced it.

**Why every write goes through `CareStore`.** CloudKit forbids unique constraints and
`.deny`, so the rules the schema cannot state have to live somewhere a stray
`context.insert` cannot get around. That now includes the **time rules**:
`rejectFuture(_:)` and `requireOverlap(startAt:endAt:with:)`, called by `startShift`,
`endShift`, `updateShift`, `logEvent`, `updateEvent`, `toggleSleep`, `recordSleep` and
`updateSleepSession`. They used to exist only as advisories in `LogSheetChrome`, which
meant they held for a thumb on a sheet and for nothing else — the reconciler, a future
NFC tap, an import all wrote straight past them. The sheets still show the same
advisories as you type; that is a courtesy to the thumb, not the enforcement.

`rejectFuture` allows 60 seconds of slack, the same figure as Core's
`Date.isMeaningfullyInFuture`, so the sheet and the store cannot disagree about what
counts as the future. Two synced devices do not agree on the second; twelve hours
out is still refused. `requireOverlap` rejects a sleep session lying wholly outside
the shift window, where the timeline would show a duration that the totals and the
handoff — both of which clip to that window — would count as nothing.

`CareStoreError` conforms to `CustomStringConvertible` as well as `LocalizedError`,
because every call site renders a failure as `"\(error)"` and would otherwise put
"futureTimestamp" in front of a tired reader.

## Data model

```
Family   ─┬─ babies:  [Baby]
          └─ shifts:  [Shift]

Shift    ─── belongs to ONE Family, covers ALL of its babies
          ├─ events:        [LogEvent]
          └─ sleepSessions: [SleepSession]

LogEvent ────── belongs to a Shift AND a Baby (except `pump`, see below)
SleepSession ── belongs to a Shift AND a Baby
NoteTagPreset ─ belongs to a Family (user-defined note tags)
TagBinding ──── belongs to a Family (NFC)
```

Seven models. `SchemaCloudKitCompatibilityTests` asserts the exact set by name, so
one added or dropped fails a test rather than silently stopping syncing.

- **Family** is the client household. Every query and export is scoped to one, so
  one family's data can never appear in another's report. Which one is on screen is
  persisted in `@AppStorage("moonlog.currentFamilyID")` — a string, since
  `@AppStorage` cannot hold a `UUID` — and resolved on every render by
  `FamilySelection.resolve(storedID:among:)`, a pure rule with its own tests: an id
  naming a family the query can no longer see falls back to the oldest active one
  rather than leaving the doula on an empty screen. Tonight and Summary carry
  `.id(family.id)`, so per-family `@State` cannot leak across a switch.
- **One shift covers all of a family's babies.** A caregiver works one shift; the
  babies within it are separate subjects, not separate shifts.
- **Sleep is per baby.** With twins, "is she asleep" is a per-baby question. The web
  version could only ask it per shift, which is what multi-baby invalidates.
- **Volume unit is per family** (`Family.volumeUnit`). Storage stays canonical
  millilitres; display and entry follow the household. Weight follows the same unit
  system.
- **Event kinds beyond the core three are opt-in per family**
  (`Family.enabledKinds`). `pump` is about the mother and carries **no baby** —
  `EventKind.attachesToBaby` is false and totals count it for the shift. The writer
  enforces the difference: `CareStore.logEvent` takes a `UUID?`, gated by
  `requiredBaby(_:for:)`, which demands a baby for every kind that attaches to one. A
  pump can therefore be logged at all, and an unattributed feed — which neither twin's
  totals nor the handoff could count — still cannot.
- **A breast feed carries a duration per side** (`leftSeconds` / `rightSeconds`),
  since one feed commonly uses both. A single-sided feed leaves the other nil.
- **`LogEvent` is flat**, discriminated by `kindRaw`, rather than three models or a
  class hierarchy. Reasons in `docs/decisions.md`.

### Denormalised ids

`LogEvent.babyIDRaw`, `LogEvent.shiftIDRaw`, `SleepSession.*`, `Shift.familyIDRaw`
duplicate their relationship. Deliberate, for three reasons:

1. `#Predicate` over a relationship forces a join and is a common source of
   `unsupportedPredicate`. A `UUID?` comparison is trivially supported.
2. Under CloudKit a relationship can be transiently `nil` on a device that has the
   child record but not yet the link.
3. `.deny` is unavailable, so if a baby is ever deleted `.nullify` clears the
   relationship — and the raw id is the only thing preserving attribution.

Invariant: `event.babyIDRaw == event.baby?.id`. Maintained by `attach(to:baby:)`,
asserted in tests. Its `baby` is optional so that a pump routes through the one place
that sets a relationship and its id together, rather than around it.

### Denormalised `isOpen`

`Shift.isOpen` mirrors `endedAt == nil`; `SleepSession.isOpen` mirrors `endAt == nil`
(the two models use different field names). Predicates on
optional `Date` comparisons have a poor track record, and these are the queries that
decide whether the app can log at all. Maintained by `close(at:)`.

## The shift lifecycle

Start and end are values the doula **sets or confirms** — never inferred from the
clock. A shift ends by leaving the baby with the parents, so:

- Ending a shift does **not** open a replacement. Between visits there is genuinely
  no open shift, and that is a normal state.
- An in-progress sleep session is left **open**. "Asleep since 5:40, still asleep
  when I left" is the record the parents want.
- Totals therefore **clip** sessions to the shift window instead of closing them.
  One rule that also absorbs back-dated strays. See `docs/testing.md`.
- Both hours are amendable afterwards through `updateShift(_:startedAt:endedAt:)`,
  where `nil` leaves that end where it is. `ShiftHoursSheet` is the way in for both
  correcting a running shift and ending one, since ending is the last chance to fix
  the start. Narrowing the window is refused when it would strand an already-logged
  sleep session outside it. A closed shift deliberately **cannot be reopened** here:
  `close(at:)` is the only thing keeping `isOpen` honest, and there is no `reopen()`
  to pair with it.

## The write path

Every write from Tonight goes through one function, `perform(_:busyFor:_:)`. It holds
a per-baby lock across the actor round trip — the card reads through the main context,
which is a merge behind, so without it a second tap on Sleep closes the session the
first one just opened — raises the confirmation banner, and surfaces any failure as an
alert. A care log that silently drops an entry is worse than one that stops.

Each write action returns an `Undo?`: a `@Sendable (CareStore) async throws -> Void`
describing the call that reverses it. `nil` means the write is not undoable, and then
no Undo button is offered rather than one that quietly does nothing. An undoable
banner holds six seconds instead of two. Reversal is a compensating call on the store
rather than `UndoManager` — reasoning in `docs/decisions.md`.

A delete is undone by putting the record back under its own identity, not by logging a
lookalike. `LogEvent.restoration` captures an `EventRestoration`, a `Sendable` value
type that outlives the model object it came from, and `CareStore.restoreEvent(_:)`
re-inserts with the original `id`, `createdAt` and source.
`restoreSleepSession(id:shiftID:babyID:startAt:endAt:)` does the same for sleep;
`recordSleep` could not serve, because when a session is already open it corrects
*that* one instead of inserting, so undoing a deleted closed session would have
dragged a live one backwards in time. Both restores return early if the id is already
present, so a second tap on Undo cannot duplicate.

### What re-reads the screen

`CareStore` is a `@ModelActor` writing through its own context, so the main context's
relationship arrays — `shift.events`, `shift.sleepSessions` — are a merge behind
after every write. `TonightView` holds a `refreshToken`, bumped after each write and
each undo, and read in `body` through `Tonight(..., generation:)`. That dependency is
now stated outright. Until it existed the job was done by accident: the confirmation
banner's `@State` happened to mutate about two seconds after every write, so deleting
the banner would have silently stopped the timeline updating after a log.

**The remote case is still open.** Nothing bumps `refreshToken` when a merge arrives
from another device, and once CloudKit is on that is exactly what a second phone
produces. Whether SwiftData's own observation of those relationship arrays covers it
is unverified and cannot be verified until the iCloud capability exists — see
`docs/cloudkit.md`. Treat a remotely-changed timeline as untested, not as working.

## What the app deliberately does not have

- No importer. The PWA held only test data; the native app starts clean.
- No hard delete for a baby — `isArchived` only. An archived baby still appears in
  the handoff for any shift that logged something for her — that is
  `Handoff.roster(_:loggedFor:)` — and anything else unattributed lands in a
  catch-all block rather than vanishing.
- No `UndoManager`. See the write path above.
- No auto-started shift.
