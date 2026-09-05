# Testing

Two suites:

- **`MoonlogCoreTests`** — host-free, milliseconds. Pure logic. This is where the
  web version's real bugs lived, so this is where the coverage is deepest.
- **`MoonlogTests`** — app-hosted. Schema compatibility, persistence, delete rules,
  and that `#Predicate` shapes actually compile and return rows (predicate breakage
  is a *runtime* failure in SwiftData, so the type checker cannot catch it).

```bash
xcodebuild -project Moonlog.xcodeproj -scheme Moonlog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

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

`-moonlogTab summary|settings` and `-moonlogOpenSheet feed|diaper|sleep|note` open a
specific screen for screenshotting. It seeds a twin night with
one baby asleep and one awake, which is the state that exercises the layout.

Some bugs only appear when the thing runs: the CloudKit launch crash and the theme
latch were both invisible to the test suite.
