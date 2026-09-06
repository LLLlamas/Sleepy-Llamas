# Status

Updated 2026-09-05.

**First TestFlight build shipped** — 0.1.0 (1788644622). Two caveats on that
specific build: it is local-only, and it **contains the DEBUG demo seed** (a fake
twin night), because `DEBUG` was defined in the Release configuration. Fixed
afterwards, and `scripts/archive.sh` now fails an archive that carries debug code.
Do not run a real shift on that build. Nothing since has been archived — everything
below is on the branch, not in TestFlight.

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
| **Time rules enforced in `CareStore`, not just in the sheets** | done |
| **Undo on every write, including the sleep toggle** | done |
| **Confirmable shift start and end times** | done |
| **A second client family — switcher and add-family** | done |
| **Wrong-twin remedy: "Wrong baby?" moves a record** | done |
| **Pump, medication and weight: create, edit and delete** | done |
| **Archived babies keep their records in the handoff** | done |
| **The keepsake handoff — responsive HTML for the parents** | done |
| **A note to the parents, written and editable per shift** | done |

159 tests green (79 in `MoonlogCoreTests`, 80 in `MoonlogTests`).

**A caveat worth keeping in view.** Test count is not a proxy for working software
here, and this project has proved it twice: `Totals.compute` was fully tested and
had no call path from the app until Summary existed, and both the Note button and
the handoff's Copy/Share shipped built-but-unreachable. A green suite says the logic
is right, not that anyone can get to it.

Everything in the bold rows above was **rendered on the iPhone 17 Pro simulator and
screenshotted**, not assumed: the Undo banner (produced by a real write through the
real path, not a faked banner), the "Wrong baby?" control, the pump and weight
sheets, the shift-hours sheet, and the family switcher. What was *not* driven by
hand, because the simulator cannot be tapped from here: the toolbar menu's contents,
the reassign menu expanded, and the effect of actually tapping Undo. Those are
compiled and unit-tested but unwitnessed. **A UI test target would close that gap
and is the single highest-value piece of tooling this project does not have.**

`Totals`, `SleepMath`, `DayOfLife`, `Handoff` and `SleepReconciler` are wired in.
`DayBuckets` and `MoonClock` still have no call sites outside `MoonlogCore` —
`DayBuckets` is what a multi-night trends view will need, and `Family.calendar`
duplicates what `MoonClock` exists to provide.

## Next, in order

**CloudKit is deferred, not next** — see the correction below and `docs/cloudkit.md`.
**NFC is backlog**, scoped in `docs/next-features.md` and not being built.

1. **Edit a baby's birth date and the caregiver name.** Both are wrong-forever
   today, and both appear on the handoff and on the keepsake page.
2. **A UI test target.** See the caveat above — it is the one piece of tooling that
   would close the gap this project keeps falling into.
3. **A re-importable export (JSON to Files).** The keepsake page is what the parents
   keep; it is not a backup the doula can restore from. This is what would close
   that, and it is much cheaper and safer than sync.
4. `SummaryView`'s archived-baby gap (known issue 6 below).

### The backup picture, corrected

An earlier version of this document said there was **"no backup at all."** That was
wrong, and the error mattered because it ranked the work. Verified: the store is at
`Library/Application Support/default.store`, nothing in `Sources/` excludes it from
backup, so it is carried by iCloud Backup and by encrypted Finder backups. A lost or
replaced phone restores it.

What is genuinely still exposed is narrower: **deleting the app** on a working phone,
and having no *re-importable* export of your own history. The handoff — text or
keepsake — is a document for the parents, not something this app can read back.

## Known issues

Carried over and re-audited on 2026-09-05. The five that could put wrong data in
front of the parents are fixed; what is left is listed honestly below.

**Fixed since the last audit**

0. The keepsake handoff and the plain text used to describe the same night
   differently in five places — the page dropped unattributed records and note tags
   entirely, lost the day of life for a single baby, phrased medication differently,
   and sourced weight from somewhere else. Fixed by making one phrasing shared
   between them: `Handoff.warmFeed`, `noteDetail`, `medicationDetail` and
   `strayLine` are now internal and both renderers call them. **The rule to hold: a
   fact that appears in both documents is phrased in exactly one place.**

1. ~~Tonight's refresh rests on an accident~~ — fixed *for local writes*. The
   dependency is now an explicit `refreshToken` read in `TonightView.body` and
   bumped in `perform`, so removing the confirmation banner can no longer silently
   stop the timeline updating. **The remote-change half is still open** and is now
   item 2 in "Next".
2. ~~`CareStore` validates no times~~ — `rejectFuture` and `requireOverlap` now live
   in the actor and apply to every caller, not just to a thumb in `LogSheetChrome`.
   A sleep session can no longer be dragged wholly outside the shift, and a shift's
   window can no longer be narrowed past a session already logged inside it.
3. ~~`reassignEvent` is unreachable~~ — a "Wrong baby?" menu sits next to the baby
   chip on every edit sheet. The record moves and keeps its `createdAt` and source.
4. ~~Pump, medication and weight have no create or edit path~~ — one `ExtraSheet`
   serves all three, reached from Tonight's toolbar menu, and their timeline rows
   are tappable. Editing one used to fall through to the note sheet.
5. ~~An archived baby's records vanish from the handoff~~ — the roster is now the
   union of active babies and every baby this shift has records for, plus an
   "unattributed" catch-all for orphaned records.

**Still open**

6. **`SummaryView` still derives its cards from `activeBabies`.** Archiving a baby
   mid-shift removes her totals from the Summary tab and from a past night's
   summary cards, exactly as it used to from the handoff. Not the two-line fix the
   timeline was: including archived babies unconditionally would put an empty card
   on tonight's summary for every discharged baby, so it needs the same
   "has records in this shift" rule the handoff roster uses. `ShiftDetailView`'s
   timeline name/colour lookup **was** fixed.
7. Smaller: the handoff lists feed and note times but not diaper times; it mixes
   two clock registers (`9:00 PM` in the header, `3:12a` in rows);
   `Fmt.paddedDuration` has no day rollover past 24h and clamps negatives silently;
   `OnboardingView`'s `.navigationTitle("Welcome")` is dead, overridden by the tab's
   stack.
8. **`EventKind` has no `unknown` case.** `LogEvent.kind` falls back to `.note`, so
   a kind added by a later build would read here as a note — a record of the wrong
   thing rather than of nothing. Every other wire-format enum has the `unknown` case
   that prevents this; `TagAction` was given one on 2026-09-05, when its fallback
   turned out to be `.logDiaper`. Closing this one means adding a case to several
   exhaustive switches, which is why it is recorded rather than done.
9. `DayBuckets` and `MoonClock` still have no call sites outside `MoonlogCore`.
10. **Undo has three deliberate gaps**, each commented at its call site: recording a
   sleep from the sheet (`recordSleep` corrects-or-inserts and does not report
   which, so there is no single move to reverse), adding a baby (archiving is not
   the same thing as never having added her), and ending a shift (`updateShift`
   will not reopen a closed one, because `close(at:)` is the only thing keeping
   `isOpen` honest).
11. **Switching families with a past night pushed on the Summary tab is untested.**
    `SummaryView` carries `.id(family.id)`, which should tear the pushed detail
    down, but nobody has watched it happen.

## Needs the user

| What | When | Why |
|---|---|---|
| ~~Xcode signing~~ | done | Cloud-managed distribution signing. |
| ~~App Store Connect record~~ | done | Build uploaded 2026-09-05. |
| ~~Field encryption~~ | done | Nine fields, pinned by test. |
| **iCloud capability + container + Background Modes** | before relying on the app | The whole of `docs/cloudkit.md`. `MOONLOG_CLOUDKIT` must be flipped in the same moment, in **both** `configs:` entries. Until then there is no backup at all. |
| NFC Tag Reading on the App ID | before NFC | Developer portal. See `docs/next-features.md`. |

## Open questions

- **Day 0 vs Day 1** for day-of-life. Currently clinical (birth day = Day 1),
  decided without an explicit answer. Visible in the handoff; one constant to change.
- **Wake lock.** Deliberately absent — a screen held awake all night in a dark
  nursery costs battery for no benefit. Revisit only if it proves annoying.
- **Overdue-feed alerts** only render while the app is foregrounded. A notification
  or Live Activity would need to be a deliberate choice, not an accident.
- **Undo's window is six seconds.** Long enough to notice a wrong-twin tap, short
  enough that the banner is not still sitting there at the next feed. Untested
  against a real night.

## DEBUG screenshot hooks

`DemoSeed` is gated behind launch arguments and can never fire in a real run; the
archive script refuses a Release binary containing it. The hooks:

```bash
xcrun simctl launch <device> com.sleepyllamas.moonlog \
  -moonlogSeedDemo YES \                       # a realistic twin night
  -moonlogTab summary|settings \               # open on that tab
  -moonlogOpenSheet feed|diaper|sleep|note|pump|medication|weight \
  -moonlogEditFirst YES \                      # edit sheet for the newest record
  -moonlogShiftHours end|correct \             # the shift-hours sheet
  -moonlogDemoWrite YES \                      # one real write, for the Undo banner
  -moonlogDumpHandoff YES                      # writes the keepsake page to Documents
```

`-moonlogDumpHandoff` is how the keepsake page gets looked at, since a string
assertion cannot tell you whether a document is legible. Pull it off the simulator
and open it in a browser:

```bash
C=$(xcrun simctl get_app_container booted com.sleepyllamas.moonlog data)
cp "$C/Documents/handoff.html" /tmp/ && (cd /tmp && python3 -m http.server 8777 &)
xcrun simctl openurl booted http://localhost:8777/handoff.html
```

A `file://` URL will not open in the simulator's Safari; a local server will. The
demo seed carries a sample note so the note section is reachable.

The demo seed enables all three optional kinds so they are reachable in a
screenshot run. They stay off by default in a real family.
