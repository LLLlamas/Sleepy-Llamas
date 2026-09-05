# Architecture

## Layers

```
MoonlogCore  Sources/Core/    pure logic — no SwiftData, no SwiftUI, no Date.now
     ▲                          (a separate framework target)
     │
App          Sources/App/     Entry point + ModelContainerFactory (the CloudKit gate)
Models       Sources/Models/  @Model types. CloudKit-shaped by construction.
CareStore    Sources/Lib/     @ModelActor. The only writer. Plus Haptics, Formatters.
Views        Sources/Views/   SwiftUI. Reads via @Query, writes via CareStore.
Theme        Sources/Theme/   Palette, accents.
```

**Why `MoonlogCore` is a separate target, not a folder.** A framework cannot import
the app, so it physically cannot reference a `@Model` type. That is the coupling
worth preventing: every calculation that broke in the web version — day bucketing,
day-of-life, totals, sleep reconciliation — lives there on value types, and its
tests run in milliseconds with no `ModelContainer` and no host app. A naming
convention would not have enforced it.

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
  one family's data can never appear in another's report.
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
  does not enforce this yet: `CareStore.logEvent` takes a non-optional `babyID`, so
  a pump event cannot actually be created until that signature changes.
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
asserted in tests.

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

## What the app deliberately does not have

- No importer. The PWA held only test data; the native app starts clean.
- No hard delete for a baby — `isArchived` only.
- No auto-started shift.
