# Status

Updated 2026-09-05.

**First TestFlight build shipped** — 0.1.0 (1788644622). Two caveats on that
specific build: it is local-only, and it **contains the DEBUG demo seed** (a fake
twin night), because `DEBUG` was defined in the Release configuration. Fixed
afterwards, and `scripts/archive.sh` now fails an archive that carries debug code.
Do not run a real shift on that build.

## Built

| Area | State |
|---|---|
| XcodeGen project, 4 targets | done |
| `MoonlogCore` — clock, day buckets, day-of-life, totals, reconciler | done |
| SwiftData models + CloudKit schema test | done, mutation-verified |
| `CareStore` write layer | done |
| Onboarding, start/end shift, add baby | done |
| Tonight — adaptive twins layout, merged timeline | done |
| Log sheets: feed, diaper, sleep, note | done |
| Baby rename + colour picker | done |
| Bottom tabs: Tonight / Summary / Settings | done |
| Summary — per-baby totals for the shift | done |
| Settings — Deep Night, volume unit, optional kinds, note tags, storage mode | done |
| Haptics | done |
| App icon, privacy manifest, export compliance | done |
| Signing, archive, TestFlight upload | done |

96 tests green.

**A caveat worth keeping in view.** Test count is not a proxy for working software
here. Before Summary existed, `Totals.compute` had no call path from the app at all
and its 13 tests covered unreachable code. `SleepMath`, `DayBuckets` and `MoonClock`
still have **zero call sites outside `MoonlogCore`** — `TonightView` reimplements
their aggregation inline. The logic is right and will be needed; it is not yet
wired in, and a green suite does not say otherwise.

## Next, in order

Each of the first three lets wrong data reach the parents or loses it.

1. **Edit and delete a logged event.** Timeline rows have a tap target with no
   gesture on it. `CareStore.deleteEvent` exists with no caller and there is no
   `updateEvent` at all. A feed logged against the wrong twin is permanent.
2. **History.** Ending a shift makes that night permanently invisible —
   `RootView` has no path to a closed shift. Combined with (1), the app can capture
   a night perfectly and then neither show it nor fix it.
3. **Export / handoff.** Summary is on screen, but there is no way to get it to the
   parents — no share sheet, no document, no file. And no backup of any kind.
4. **A confirmable shift end time.** `endShift` reads the clock, contradicting the
   rule that start and end are set by the doula. Ending 30 minutes late widens the
   window and credits sleep that was not witnessed.
5. **A second client family.** `RootView` uses `families.first` and onboarding only
   appears when there are none, so the second household is unreachable.
6. **Wire `TonightView` to `MoonlogCore`** rather than reimplementing it inline.

## Needs the user

| What | When | Why |
|---|---|---|
| ~~Xcode signing~~ | done | Cloud-managed distribution signing; no local Apple Distribution cert exists, which is expected. |
| ~~App Store Connect record~~ | done | Created; build uploaded 2026-09-05. |
| ~~Field encryption~~ | done | Nine fields, pinned by test. |
| **Decide on CloudKit sync** | before relying on the app | Needs the iCloud capability, a container, and Background Modes → Remote notifications, with `MOONLOG_CLOUDKIT` flipped at the same moment (`docs/cloudkit.md`). Until then there is no backup at all. |
| NFC Tag Reading on the App ID | before NFC | Developer portal. No NFC UI exists yet. |

## Open questions

- **Day 0 vs Day 1** for day-of-life. Currently clinical (birth day = Day 1),
  decided without an explicit answer. Visible in the handoff; one constant to change.
- **Wake lock.** Deliberately absent — a screen held awake all night in a dark
  nursery costs battery for no benefit. Revisit only if it proves annoying.
- **Overdue-feed alerts** only render while the app is foregrounded. A notification
  or Live Activity would need to be a deliberate choice, not an accident.
