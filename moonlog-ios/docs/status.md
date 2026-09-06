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
| Edit / delete a logged entry, and sleep sessions | done |
| Handoff — plain text, Copy and Share | done |
| History — past nights, each with its own summary, timeline and handoff | done |
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

1. **Undo on writes.** The only recovery is edit/delete after the fact; the PWA
   offered undo on every write and on the sleep toggle.
2. **A confirmable shift end time**, and the ability to correct a shift's start.
   `endShift` reads the clock, contradicting the rule that both are set by the
   doula. Ending 30 minutes late widens the window and credits sleep nobody saw.
3. **A second client family.** `RootView` uses `families.first` and onboarding only
   appears when there are none, so the second household is unreachable.
4. **Any backup.** No export and no CloudKit — deleting the app deletes every
   client's records.
5. **Edit a baby's birth date and the caregiver name.** Both are wrong-forever
   today, and both appear on the handoff.
6. The keepsake handoff document (the PWA's themed, printable page).

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
