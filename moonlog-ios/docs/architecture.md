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
Theme        Sources/Theme/   Palette, accents, and the page wash.
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
  `.id(family.id)`, so per-family `@State` cannot leak across a switch. Choosing a
  different household is a Settings act, not something reachable from Tonight — see
  the screens below.
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

## The screens

Three tabs, each in its own `NavigationStack`, all assembled by `RootView`:

| Screen | File | What it holds |
|---|---|---|
| Tonight | `Views/TonightView.swift` | the running shift — header, baby cards, timeline, every log sheet |
| Summary | `Views/SummaryView.swift` | the running shift's totals and the handoff. Nothing else |
| Settings | `Views/SettingsView.swift` | the household picker, the baby roster, per-family prefs, appearance, data |
| Past nights | `Views/HistoryView.swift` | one household's closed shifts, pushed from Settings |

`RootView` owns everything app-wide: the theme, `moonlog.currentFamilyID`, and two
of the app's three `@Query`s — active families, and open shifts. It resolves the
current `Family` and its open `Shift?` and hands both down; Tonight and Summary
never query for them. The third and last `@Query` is `HistoryView`'s closed shifts.
Four queries scattered across four screens is how the web version ended up with
four different answers to "which shift is this".

Settings takes a **`FamilyRoster`** — `SettingsView(roster:onError:)`, the roster
carrying `current`, `all`, `select` and `create`. One value rather than four
arguments because two of them are `Family`-shaped and two are closures, which is
exactly the initialiser where the wrong thing gets bound and the compiler agrees.
`RootView` still owns the stored id; the roster only hands Settings a way to set it.

**One client family is on screen at a time, and switching is deliberate.** The
switcher was a toolbar menu on Tonight, one tap from the log buttons — a control
that changes *whose night you are logging* does not belong next to the controls
that log it. It is now an inline picker in Settings' first section. That menu was
also serving as the standing answer to "whose night is this?", so `NightHeader`
prints the family name above the clock; moving the switcher without that would have
traded two taps of convenience for the mis-logging risk the menu was guarding
against.

**Past nights lives on its own screen.** `PastNightsSection` used to render under
tonight's totals on Summary, but only in the branch where no shift was open — so it
was unreachable during a shift, which is the one moment "how long did she go last
night?" gets asked. It moved to `HistoryView` with the closed-shift query, and now
has exactly one call site. Summary's empty state points at Settings › Past nights.

The push is a `.navigationDestination(isPresented:)` declared on Settings' **`Form`**,
never inside the `Section` holding the row. A `navigationDestination` inside a lazy
container is not registered until that row has been built, and pushing before then
lands on a blank screen. No test catches this; it was found by screenshot.

**One page base.** `.moonBackground(_:)` in `Theme/MoonStyles.swift` is the only
thing any screen sets as its background — a `MoonBackground` gradient from
`palette.bgLift` down to `palette.bg`, described once so the identity cannot drift
between screens the way tab-bar clearance did before it became a constant. The
navigation bar uses `bgLift` to meet it. Nothing calls `.background(palette.bg)`.

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

### Asking first

Whether an action confirms is a user preference, so the gate is a wrapper around the
call site rather than a step inside `perform`. `TonightView.confirming(_:_:_:)` either
runs the closure now or parks it on a `ConfirmPrompt` for the one
`.confirmationDialog` the screen owns; the question and the button verb come off
`ConfirmableAction`, so adding a confirmable action does not mean adding a dialog to
keep in step.

In practice only the sleep toggle comes through it. **The other three are raised by
the sheet that owns the control**, and that is not a stylistic preference — each of
those controls dismisses its sheet as it acts, so a dialog set from the callback and
presented back on Tonight would be handed across a view that is going away, and a
confirmation that fails to appear is an action that silently does nothing.

- **Deleting a record** → `LogSheetChrome`, which all five log sheets inherit at
  once, so one gate covers every delete. Gating it in `perform` as well would stack
  two dialogs.
- **Moving a record to the other twin** → `LogSheetChrome` again; the "Wrong baby?"
  menu dismisses on choosing.
- **Ending a shift** → `ShiftHoursSheet`, on the button that commits. Its `onSave`
  runs while the sheet is still presented and `dismiss()` is the next line.

See `docs/decisions.md`.

`ConfirmPreferences` is an `@Observable` object in the environment beside
`careStore`, holding its values in memory and writing through to `UserDefaults` —
one key per action, so a case added later falls back to its own default rather than
being read as off by every install that stored the set before it existed.

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
