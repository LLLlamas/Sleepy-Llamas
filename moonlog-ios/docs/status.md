# Status

Updated 2026-09-06.

**First TestFlight build shipped** — 0.1.0 (1788644622). Two caveats on that
specific build: it is local-only, and it **contains the DEBUG demo seed** (a fake
twin night), because `DEBUG` was defined in the Release configuration. Fixed
afterwards, and `scripts/archive.sh` now fails an archive that carries debug code.
Do not run a real shift on that build.

**0.1.0 (1788666101) was uploaded to TestFlight on 2026-09-05** and is the first
build safe to work a real shift on: no demo seed, no debug hooks, no warnings, no
CloudKit entitlement. It carries everything below. See `docs/testflight.md` for the
verification table and the command-line upload path.

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
| **Maroon lifted forward — `bgLift`, a page gradient, warmer surfaces** | done |
| **The palette contrast-checked for real, and five failures fixed** | done |
| **A clock at the top of Tonight, with whose night it is** | done |
| **Baby status as a bordered, state-tinted tile, ported from the PWA** | done |
| **One client family at a time — the switcher moved to Settings** | done |
| **History as its own screen, reachable during a shift** | done |
| **The status tile says when the state started, awake as well as asleep** | done |
| **"Ask before" — per-action confirmation preferences** | done |
| **Confirmations are alerts, so they have a Cancel button** | fixed |
| **The status tile toggles on tap, at the time you tapped** | done |
| **The tile wears the baby's colour, contrast-pinned per accent** | done |

184 tests green (91 in `MoonlogCoreTests`, 93 in `MoonlogTests`), up from 166.
Fifteen new: five in a new `FormattersTests` pinning both 12-hour clock formats at
midnight and noon, three on `SleepMath.lastWake`, and seven in a new
`ConfirmPreferencesTests`.

**A caveat worth keeping in view.** Test count is not a proxy for working software
here, and this project has proved it twice: `Totals.compute` was fully tested and
had no call path from the app until Summary existed, and both the Note button and
the handoff's Copy/Share shipped built-but-unreachable. A green suite says the logic
is right, not that anyone can get to it.

**Rendered on the iPhone 17 Pro simulator (iOS 26.5) and screenshotted**, not
assumed: Tonight in both Night and Day, Settings, Past nights, Add family, Add baby,
Summary, the feed sheet, and the Undo banner — produced by a real write through the
real path, not a faked banner.

**The simulator can now be driven, and that is the change worth carrying forward.**
`cliclick` and AppleScript are both blocked on this machine (no accessibility
privileges), which is why previous sessions recorded taps as impossible. What works
is a throwaway XcodeGen project holding a single UI-testing target, built in `/tmp`,
driving the *already-installed* app through
`XCUIApplication(bundleIdentifier: "com.sleepyllamas.moonlog")` — set launch
arguments, tap by accessibility label, `swipeUp` until a row is hittable, then
screenshot from the host with `simctl io`. No project file is touched. That is most
of a UI test target already, which makes item 2 below cheaper than it looks.

Driven by hand on 2026-09-06, each confirmed against the screenshot: the end-shift
alert and its Cancel (leaving the sheet intact), the delete-a-record alert reached
through `-moonlogEditFirst`, scrolling Settings to "Ask before", flipping "Wake and
sleep" on, relaunching **without reinstalling**, and tapping Wake on Mia's card to
see the alert appear — the end-to-end proof that a Settings toggle changes behaviour
on another screen across a launch.

Driven again after the tile changes, with pixels sampled from the screenshots rather
than eyeballed: the tile toggling on tap (no dialog, Undo banner, time = the tap), the
fills in Night and Day at both states, the subtitle's contrast on each fill, and the
sleep row in the timeline opening the editor.

**The export was driven end to end**, which matters because it has shipped
built-but-unreachable before. Summary's Copy puts the full plain-text handoff on the
pasteboard — read back and checked, not assumed. "Send the page" opens a real share
sheet on `Mia & Leo — Sun, Sep 6.html`. `-moonlogDumpHandoff` writes a 7.7KB HTML file
carrying the parent note, per-baby stats, feeds, stool colours and the sign-off.
Nothing stubbed anywhere on that path.

Still unwitnessed: tapping the client-family picker to actually switch household,
tapping Undo, the contents of Tonight's overflow menu, and **Deep Night** — which is a
Settings toggle rather than an OS appearance, so an appearance-switching run never
reaches it. Its tile fills are therefore the only two of the eight that are asserted
but not seen.

**A UI test target would close that gap and is the single highest-value piece of
tooling this project does not have.** Tonight produced the sharpest argument for it
yet: pushing History from Settings landed on a **blank screen**, because the
`.navigationDestination` was declared inside a `Section`, and a `navigationDestination`
in a lazy container is not registered until that row has been built. Nothing failed.
The suite stayed green. It was caught by looking at a screenshot.

`Totals`, `SleepMath`, `DayOfLife`, `Handoff` and `SleepReconciler` are wired in.
`DayBuckets` and `MoonClock` still have no call sites outside `MoonlogCore` —
`DayBuckets` is what a multi-night trends view will need, and `Family.calendar`
duplicates what `MoonClock` exists to provide.

## Next, in order

**CloudKit is deferred, not next** — see the correction below and `docs/cloudkit.md`.
**NFC is backlog**, scoped in `docs/next-features.md` and not being built.

1. **Edit a baby's birth date.** Wrong-forever today, and it drives day-of-life on
   both the handoff and the keepsake page.
2. **A UI test target.** See the caveat above — it is the one piece of tooling that
   would close the gap this project keeps falling into. Tonight's blank-screen
   `navigationDestination` bug is the freshest argument for it: a whole screen
   rendered empty, and only a screenshot said so.
3. `SummaryView`'s archived-baby gap (known issue 6 below).
4. **Four Swift 6 `Sendable` warnings.** `FeedEntry`, `DiaperEntry`, `NoteEntry` and
   `ExtraEntry` conform at the bottom of `TonightView.swift` rather than beside the
   structs, which is a warning today and an error in the Swift 6 language mode. Cheap
   to fix, and `docs/testflight.md` claimed a warning-free Release build until this
   was measured on 2026-09-06.

**Dropped on 2026-09-05, deliberately:**

- *Editing the caregiver name.* It is one person, every night. The field is already
  `@AppStorage("moonlog.lastCaregiver")`, so it is typed once and pre-filled from
  then on; `Shift.caregiver` is a snapshot taken at start. Correcting it on an
  already-started shift is the only thing not possible, and it does not matter when
  the answer never changes.
- *A JSON export.* The on-disk store persists across launches and is carried by the
  phone's own backup, which covers the case this would have covered. Revisit only if
  a phone is ever lost *without* a restore, or if history has to move between
  devices.

### The backup picture, corrected

An earlier version of this document said there was **"no backup at all."** That was
wrong, and the error mattered because it ranked the work. Verified: the store is at
`Library/Application Support/default.store`, nothing in `Sources/` excludes it from
backup, so it is carried by iCloud Backup and by encrypted Finder backups. A lost or
replaced phone restores it.

What is genuinely still exposed is narrower: **deleting the app** on a working phone,
and having no *re-importable* export of your own history. The handoff — text or
keepsake — is a document for the parents, not something this app can read back.

## What the tile change does not do

Measured on device, worth knowing before it is called finished:

- **Sage loses its hue in the dark-theme fill.** A sage baby's awake fill samples
  `#4F4C4B` — very nearly grey. Sage is a muted green and the card is maroon, so the
  blend cancels most of the chroma; gold survives it, sage does not. The border, the
  glyph and the elapsed badge still carry sage, so identity holds — but for that
  accent, in that theme, the fill is contributing lightness and not colour. Fixing it
  means blending with chroma preserved rather than component-wise, which is a bigger
  change than the one asked for.
- **Day's asleep fill has no margin.** It measures 1.1998:1 against the card — over
  the 1.18 the test demands, under the 1.20 the other seven clear. It reads as a quiet
  cream-tan block rather than the blank white it was, but it is the weakest of the
  eight and any future deepening of Day's surfaces will eat it.

## Known issues

Carried over and re-audited on 2026-09-06. The five that could put wrong data in
front of the parents are fixed; what is left is listed honestly below.

**Found and fixed on 2026-09-06, and it had shipped:** the app's one confirmation —
"Delete this entry for Mia?" — was a `confirmationDialog` inside a sheet, which iOS
presents as a **popover**, and a popover has no cancel action. It offered a red
Delete and no visible way out. Nothing failed, nothing was logged, and the suite was
green; it took driving the UI to see it. All confirmations are alerts now.

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

6. **`SummaryView` still derives its cards from `activeBabies`.** Untouched today.
   Archiving a baby mid-shift removes her totals from the Summary tab and from a
   past night's summary cards, exactly as it used to from the handoff. Moving
   History out of `SummaryView` changed the route to the second half of that and
   nothing else: `SummaryCards` has two call sites still, `SummaryView` for the
   running shift and `ShiftDetailView` for a past night, now reached through
   Settings › Past nights instead of down the Summary tab. Not the two-line fix the
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
10. **Undo has three deliberate gaps.** Two are still commented at their call sites
   in `TonightView.perform`: recording a sleep from the sheet (`recordSleep`
   corrects-or-inserts and does not report which, so there is no single move to
   reverse) and ending a shift (`updateShift` will not reopen a closed one, because
   `close(at:)` is the only thing keeping `isOpen` honest). The third — adding a
   baby, where archiving is not the same thing as never having added her — is now
   commented nowhere: Add baby moved to `SettingsView`, which writes through
   `StoreWrite.run` and has no Undo to decline. Same gap, no longer visible at the
   call site.
11. ~~Switching families with a past night pushed on the Summary tab~~ — retired
    rather than fixed. Summary no longer pushes anything, and the switcher is no
    longer on that tab. The constraint it was guarding is real and now reads:
    **the client-family picker must stay at the root of the Settings stack.** A
    switcher reachable from a pushed screen could change the family under a
    `ShiftDetailView`, which captures its `Family` model object and would go on
    rendering the previous household's night. Written down in
    `SettingsView.clientSection` as well; nothing in the code enforces it.
12. **The ported status tile only carries a time for one of the two states it
    names.** `BabyPresentation` has `asleepSince` and nothing for the waking half,
    so an asleep baby's tile reads "Since 11:17p · tap to adjust" with the elapsed
    time on the trailing edge, and an awake baby's reads "Tap to log a sleep you
    missed" with no since-time and no elapsed at all. Found while porting it, not
    fixed: an awake-since would have to come from the last ended session's `endAt`,
    which the presentation does not carry and `TonightView` does not compute.

## Needs the user

| What | When | Why |
|---|---|---|
| ~~Xcode signing~~ | done | Cloud-managed distribution signing. |
| ~~App Store Connect record~~ | done | Build uploaded 2026-09-05. |
| ~~Field encryption~~ | done | Ten fields, pinned by test. |
| iCloud capability + container + Background Modes | **deferred** | Only when CloudKit is actually wanted — see the corrected backup picture above and `docs/cloudkit.md`, which is kept whole for that day. Nothing is waiting on this. |
| NFC Tag Reading on the App ID | **backlog** | Developer portal, when NFC is picked up. Scoped in `docs/next-features.md`; nothing is being built. |

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
  -moonlogSettingsSheet family|baby|history \  # the surfaces that moved into Settings
  -moonlogDemoWrite YES \                      # one real write, for the Undo banner
  -moonlogDumpHandoff YES                      # writes the keepsake page to Documents
```

`-moonlogSettingsSheet` fires from a `.task` on `SettingsView`, so it needs
`-moonlogTab settings` alongside it or the screen it lives on is never built. The
three surfaces it reaches — Add family, Add baby, Past nights — all moved off
Tonight and Summary this session, and tapping is otherwise the only way to them.

**Every new hook has to be added to `scripts/archive.sh` as well.** The greps for
debug markers in the Release binary are a hand-maintained alternation on line 37;
`moonlogSettingsSheet` was added to it. A hook missing from that list is a hook the
archive guard will happily ship.

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

It also seeds a **second household — "Okafor", one baby "Ada", no shift** — so the
client-family picker in Settings has somewhere to switch to. Between visits is the
normal state for a family you are not with tonight, and it is what the picker will
most often be switching *to*, so it deliberately carries no shift.
