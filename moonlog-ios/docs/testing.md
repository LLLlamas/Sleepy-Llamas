# Testing

Two unit targets, plus the separate UI reachability scheme:

- **`MoonlogCoreTests`** — host-free, milliseconds. Pure logic. This is where the
  web version's real bugs lived, so this is where the coverage is deepest.
- **`MoonlogTests`** — app-hosted. Schema compatibility, persistence, delete rules,
  and that `#Predicate` shapes actually compile and return rows (predicate breakage
  is a *runtime* failure in SwiftData, so the type checker cannot catch it).

```bash
xcodebuild -project Moonlog.xcodeproj -scheme Moonlog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

## Fresh pre-release audit follow-up

Against initial PR #3 head `ab3177f45601a6d65dc6ba22d695b37bd4f78b0f`, a fresh
audit found closed-correction reachability, draft concurrency, sleep-boundary
meaning and explicit-erase notification blockers. Fixes add seven deterministic
writer tests, actor optimistic-conflict coverage, sleep-boundary cases and three
fake notification-driver erase races. The post-fix run passed **318 tests with zero
failures** (170 Core, 148 app/persistence):
`/tmp/moonlog-testflight-audit-unit-final.xcresult` and its matching log.

The six focused day UI cases and complete shipping/archive/upload gates are pending
at this checkpoint; root records those results separately. The earlier 302-unit and
combined 37-UI results below remain historical rather than being relabelled as new
release evidence. See `pre-release-audit-2026-11-16.md` for the precise findings,
implemented fixes and nonblocking limits.

## November 16 integration validation

The integrated `Moonlog` scheme passed **302 tests with zero failures**: 165 Core
and 137 app/persistence tests. Local evidence is
`/tmp/moonlog-nannylog-final-unit.xcresult` and the matching log. The integrated
app build also succeeded. An unsigned simulator Release build passed with no
source/linker diagnostics beyond expected App Intents extraction chatter. All 14
source-derived DEBUG markers were absent from app and embedded Core binaries. The
archive guard recognizes quoted hooks with or without a leading hyphen. Evidence is
`/tmp/moonlog-nannylog-release-final.log` and the source-derived checker
`/tmp/check-moonlog-nanny-release.py`. The final tree includes the keyboard,
sticky Start, temporary-storage and delete-safety fixes; its build number remains
`1789610519`. This does not
establish device signing, archive readiness or upload success.

**37 unique UI scenarios have passing evidence across the full and focused runs.**
The second full run passed all 32 existing cases and both reminder cases; its raw
result was 36/37 because a daytime test tapped the center of a Form row rather than
the rendered switch. The corrected test explicitly taps/asserts the switch, and
all three daytime cases then passed in the focused rerun. This is combined coverage,
not a single all-green 37-case run. Evidence:
`/tmp/moonlog-nannylog-integrated-ui-2.xcresult` and
`/tmp/moonlog-nannylog-day-ui-final.xcresult`, with matching logs. The focused result
includes draft survival after relaunch, explicit review, immutable publication,
optional receipt cancellation, successful typed-name/parent-note receipt and the
share menu. No message/share destination was selected.

Added coverage includes:

| Area | What is exercised |
|---|---|
| `DayReportTests` | Immutable publications, idempotent retries, factual/narrative revision invalidation, optional local receipt, wrong/stale revisions, validation, Codable roundtrip, day-aware rendering and unknown amounts |
| `DayReportPersistenceTests` | Day/legacy context, remembered hours, open-shift publication rejection, version/time in both exports, changed-source/draft checks, optional-presence digest collision, corrupt JSON failure and disk reopen with draft/publication/receipt |
| `FeedReminderTests` / `ShiftDefaultsTests` | Physical reminder offsets, invalid input, DST/time-zone boundaries, calendar-based prefill and honest start/end suggestions |
| `ReminderLifecycleTests` | Family scope, closed/deleted/archived eligibility, notification identity across Undo and wrong-baby correction |
| `DayReportReachabilityTests` | Today route, active-shift publishing disabled, editable saved notes after relaunch, review reset after edits, immutable copy, optional receipt cancellation/successful local receipt entry and share-menu reachability |
| `ReminderReachabilityTests` | Denied permission still saves a feed; a scheduling failure after save remains visible after the sheet dismisses |

The real baseline-to-integrated simulator upgrade reused the same installed app
container without a reset. Before/after SQLite comparison preserved every old
model column value for 2 families, 3 babies, 3 shifts, 14 events and 4 sleep sessions;
new nullable report/context fields were NULL for the legacy shifts. This is stronger
than merely constructing the new schema in memory. Evidence is
`/tmp/moonlog-nannylog-migration-result.txt` and its temporary store snapshots.

The report's CloudKit-encryption compatibility whitelist intentionally includes
`Shift.dayReportJSON`; the exact-set assertion stays strict. Adding nullable fields
does not enable CloudKit or establish remote sharing.

UI tests use synthetic local demo data, record only synthetic local receipts and
inspect share menus without choosing a destination. They do not send messages or
claim authenticated parent review. OS
notification delivery, permission changes on a physical phone, Focus and Watch
mirroring need real-device checks. The 500 ms draft debounce and leave-screen flush
are not a guarantee for the last uncommitted edits if the process is abruptly killed.
Published HTML/text documents are not restorable database backups.

No archive, build-number stamp or upload was performed for these tests. Earlier
September results and release history remain historical, rather than being carried
forward as evidence for the November source.

## The one time rule

> **Calendar arithmetic for calendar quantities. `TimeInterval` for physical
> durations. Never multiply to cross a day boundary.**

"Which night is this?" and "how many days old is she?" are calendar questions
(`startOfDay(for:)`, `date(byAdding:)`, `dateInterval(of:for:)`). "How long did she
sleep?" is physics (`timeIntervalSince`, absolute instants, DST-immune by
construction). Conflating them caused every date bug in the PWA.

## DST fixtures

`TestSupport.swift` defines four fixture zones. Only `DayOfLifeTests` iterates all
of them; the rest pick the zone that exposes the behaviour under test, and most use
New York:

| Zone | Why |
|---|---|
| `America/New_York` | standard spring-forward / fall-back |
| `Europe/London` | transition at 01:00, not 02:00 |
| **`Australia/Lord_Howe`** | **30-minute shift** — breaks any code assuming ±1 hour |
| `America/Phoenix` | no DST, control |

Lord Howe is the important one: a "±1 hour" special case passes New York and fails
there.

## Invariants worth keeping

- **Bucketing is a partition** — a sleep session's per-day contributions sum to its
  total duration, *and* are split at the boundary rather than assigned to the start
  day. Both assertions are needed; see below.
- **Day intervals** are contiguous, non-overlapping, and 23/24/24.5/25 hours as the
  zone dictates.
- **Round once** — totals equal `round(Σ seconds)`, never `Σ round(seconds)`.
- **Day of life is monotonic** and increases exactly once per calendar day.
- **Per-baby independence** — Baby A's state must not affect any query about Baby B.
- **Reconciliation is order-independent** — `reconcile(shuffled) == reconcile(sorted)`.
- **Schema stays CloudKit-compatible**, asserted mechanically over `Schema.entities`.
- **Accents stay mutually distinct** in every theme.
- **Every text role holds AA** against every surface it is drawn on, in all three themes.

Those last two are measured differently and the difference is load-bearing. Accent
distinctness uses a crude weighted sum of the raw sRGB channels: it only asks whether two
babies' dots can be told apart, where a rough distance is enough. The palette contrast
tests use real WCAG 2.1 relative luminance — each channel linearised before it is
weighted, then `(lighter + 0.05) / (darker + 0.05)` — because text on a surface is a
legibility threshold, not a comparison, and only the real curve says where 4.5:1 actually
falls. Using the cheap measure there would have kept the Day theme's five real failures
invisible; `docs/design.md` records which pairs they were.

## Preferences that change behaviour

`ConfirmPreferencesTests` covers the one failure mode a screenshot cannot: a
confirmation that stops appearing is invisible until the night it was needed, and one
that appears where it should not trains the thumb to dismiss dialogs unread.

The test that earns its place is `testFreshInstallUsesEachActionsOwnDefault`. Reading
with `bool(forKey:)` returns `false` for a key nobody has written, which is
indistinguishable from a user who switched it off — so every action defaulting to
*on* would have shipped defaulting to off, silently, on every fresh install. The
storage keys are asserted literally for the same reason enum raw values are: renaming
one resets that setting for everyone who had already changed it.

Tests inject a scratch `UserDefaults(suiteName:)` and tear down its persistent
domain. Never `.standard` — the simulator keeps it between runs, so one test's write
would decide the next test's defaults.

## Mutation testing

Assert that a test can fail. It has repeatedly paid off here:

- Breaking the *apparently* load-bearing line in `SleepMath` changed nothing — the
  interval intersection was doing the work. Only reproducing the web version's
  behaviour fully made the test fail, at which point it reported 606,000 seconds —
  roughly 168 hours of sleep a week after the shift ended.
- For the clip-vs-assign bug, **the partition sum alone does not catch it** — a
  session lying entirely inside the bucketed range sums correctly however it is
  distributed. Only the per-day split assertion exposes it.
- The schema compatibility test was verified by adding a bad property and a `.deny`
  rule; it failed naming both.
- The accent contrast test failed on its first run against colours *I had just
  chosen*, which is how "clay" got removed.

## Running the app

```bash
xcrun simctl launch <device> com.sleepyllamas.moonlog -moonlogSeedDemo YES
```

`DemoSeed` is DEBUG-only and requires **both** the launch argument and an empty
store. It is never "seed when empty" alone, because an empty store is a legitimate
first-run state.

`-moonlogTab summary|settings`, `-moonlogOpenSheet feed|diaper|sleep|note` and
`-moonlogSettingsSheet family|baby|history` open a specific screen for screenshotting. It
seeds a twin night with one baby asleep and one awake, which is the state that exercises
the layout, plus a second household — Okafor, one baby, no shift — so the client-family
picker has something to switch to.

Being `#if DEBUG` is only half the guard. `scripts/archive.sh` derives quoted hook
names from DEBUG source regions, recognizing both plain and hyphen-prefixed names,
and scans the app plus embedded Core binary. New hooks need no hand-maintained
alternation. The collector must remain nonempty and include the original marker
set; the current 14-marker Release check includes the new daytime/reminder hooks.

Some bugs only appear when the thing runs: the CloudKit launch crash and the theme
latch were both invisible to the test suite.

## The reachability suite

`Tests/MoonlogUITests`, run through its own **`MoonlogUI` scheme**:

```bash
xcodebuild -project Moonlog.xcodeproj -scheme MoonlogUI \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

It is a second scheme rather than a second target in the first because it launches
the app once per test and takes minutes, where the unit suite takes under a second.
Bolted together, the fast one stops being run on every edit, and that one is the
one that catches things.

**What it is for is narrower than "UI tests".** This project's failures have not
been wrong logic — the logic has a suite and the suite is green. They have been
correct logic with **no route to it**: `Totals.compute` fully tested with no caller
until Summary existed; the Note button declared, passed a closure, and never
rendered, through two TestFlight builds; Copy and Share on the handoff; the
`reassignEvent` remedy; `archiveBaby` with no call site anywhere; History pushing a
blank screen because its `.navigationDestination` sat inside a `Section`. Every one
of those was invisible to a compiler and to 188 green unit tests.

So the assertions are about **whether a thumb can get there**, and they use
`isHittable` rather than `exists` — a row below the fold exists, and tapping it
silently does nothing. `MoonlogUITestCase.reveal(_:)` scrolls until an element is
genuinely tappable and fails saying which of the two it was.

**Isolation.** The seed only fires into an empty store, so without a reset the
second test in a run inherits whatever the first logged. `-moonlogResetStore YES`
empties the store *and* removes every `moonlog.` preference key, which is what a
fresh install actually looks like — the preference half matters because a test that
turns on "Ask before" would otherwise leave it on and fail an unrelated test three
classes later. It is gated on the seed argument as well, so it can never be the
thing that empties a real night.

**Add a case whenever a control moves**, and run it before an archive.
