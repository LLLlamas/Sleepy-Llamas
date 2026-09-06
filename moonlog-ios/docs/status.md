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

112 tests green.

**A caveat worth keeping in view.** Test count is not a proxy for working software
here, and this project has proved it twice: `Totals.compute` was fully tested and
had no call path from the app until Summary existed, and both the Note button and
the handoff's Copy/Share shipped built-but-unreachable. A green suite says the logic
is right, not that anyone can get to it.

`Totals`, `SleepMath`, `DayOfLife`, `Handoff` and `SleepReconciler` are now wired in.
`DayBuckets` and `MoonClock` still have no call sites outside `MoonlogCore` —
`DayBuckets` is what a multi-night trends view will need, and `Family.calendar`
duplicates what `MoonClock` exists to provide.

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

## Known issues, from two audits (2026-09-05)

Recorded rather than fixed. None currently produces wrong data, but the first two
would if the surrounding code moved.

1. **Tonight's refresh rests on an accident.** The screen no longer ticks, so it
   depends entirely on SwiftData observation — and `CareStore` is a `@ModelActor`
   writing through its own context, so the main context's relationship arrays
   refresh only once the cross-context merge lands. What actually forces the
   re-read today is the confirmation banner's `@State` mutation ~2s after a write.
   If that banner is removed or made non-`@State`, the timeline silently stops
   updating after a log. **And once CloudKit is on, a change from another device
   has no trigger at all.** Wants an explicit invalidation before sync goes live.
2. **`CareStore` validates no times.** Future-blocking and outside-the-shift
   advisories live only in `LogSheetChrome`, so any non-view caller bypasses them.
   `CLAUDE.md` says invariants live in the actor precisely because a stray write
   elsewhere bypasses them; the time rules are not there. A sleep session can also
   be dragged wholly outside the shift, where it shows in the timeline with a
   duration but contributes nothing to the totals or the handoff.
3. **`reassignEvent` is unreachable.** Its own docstring calls it the remedy for a
   wrong-twin tap — the app's named failure mode — and nothing calls it. The actual
   remedy is delete-and-re-log, which loses `createdAt` and the NFC source fields.
4. **Pump, medication and weight have no create or edit path.** They can be enabled
   in Settings and logged by nothing. Their timeline rows are deliberately not
   tappable, because the only sheet they used to route to was the note sheet.
5. **An archived baby's records vanish from the handoff.** The roster comes from
   `activeBabies`, so archiving mid-shift silently removes everything already
   logged against that baby. There is no unattributed catch-all section.
6. Smaller: the handoff lists feed and note times but not diaper times; it mixes
   two clock registers (`9:00 PM` in the header, `3:12a` in rows);
   `Fmt.paddedDuration` has no day rollover past 24h and clamps negatives silently;
   `OnboardingView`'s `.navigationTitle("Welcome")` is dead, overridden by the tab's
   stack.
7. `DayBuckets` and `MoonClock` still have no call sites outside `MoonlogCore`.
   `DayBuckets` is what a multi-night trends view will need; `Family.calendar`
   duplicates what `MoonClock` exists to provide.

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
