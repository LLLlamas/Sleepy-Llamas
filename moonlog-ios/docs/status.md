# Status

Updated 2026-09-07.

**195 unit tests green** (91 `MoonlogCoreTests`, 104 `MoonlogTests`) plus **21
reachability tests** in `MoonlogUITests`. No Release warnings.

**0.1.0 is on TestFlight and is safe to work a real shift on** — local-only, no
CloudKit, no debug hooks. `docs/testflight.md` has the build list and the upload
path.

**A green suite is not working software.** `Totals.compute` was fully tested with no
call path from the app; the Note button and the handoff's Copy/Share shipped
built-but-unreachable. That is what the reachability suite is for — run it before
every archive, and add a case whenever a control moves.

## Built

Onboarding, start/end shift, add baby · Tonight with an adaptive twins layout and a
merged timeline · log sheets for feed, diaper, sleep and note · pump, medication and
weight as optional kinds · edit, delete and move-to-the-other-baby on every record ·
Undo on every write · Summary · History as its own screen · the handoff in plain text
and as a keepsake HTML page, with a parents' note · Settings: client families, babies,
appearance, volume unit, optional kinds, note tags, "Ask before", storage mode, erase
everything · haptics · app icon, privacy manifest, export compliance, signing, archive
and upload.

Under it: `MoonlogCore` (clock, day buckets, day-of-life, totals, sleep maths,
reconciler), SwiftData models with a CloudKit-compatibility test, and `CareStore` as
the only write path — with the time rules enforced in the actor rather than in the
sheets.

`DayBuckets` and `MoonClock` still have no call site outside `MoonlogCore`.
`DayBuckets` is what a multi-night trends view will need; `Family.calendar`
duplicates `MoonClock`.

## Still open

1. **A disabled Save says nothing about why.** A note with nothing in it and a pump
   with no volume refuse silently; `saveEnabled` is a `Bool` with no reason attached.
   (Feeds are no longer gated — a feed saves on its time alone.)
2. **Settings toggle rows respond only on the switch**, not across the row, unlike
   every other row on that screen. Measured: the row centre and the label both leave
   the setting off, and a `contentShape` on the label does not fix it.
3. **`EventKind` has no `unknown` case.** `LogEvent.kind` falls back to `.note`, so a
   kind written by a later build would read here as a note — a record of the wrong
   thing rather than of nothing. Every other wire-format enum has the guard. Closing
   it means adding a case to several exhaustive switches.
4. **Summary's Copy sits in the top-left corner** — the worst reach for a right thumb.
   Once a night, so undecided rather than open.
5. **Undo has three gaps**, all deliberate and commented where they apply: recording a
   sleep from the sheet (`recordSleep` corrects-or-inserts and does not say which),
   ending a shift (`updateShift` will not reopen one, because `close(at:)` is what
   keeps `isOpen` honest), and adding a baby (archiving is not un-adding).
6. Smaller: the handoff lists feed and note times but not diaper times;
   `Fmt.paddedDuration` has no rollover past 24h; `OnboardingView`'s
   `.navigationTitle` is dead, overridden by the tab's stack.

**Not covered by the 2026-09-07 crash and data-loss pass**, and worth saying so: an
app killed mid-write, and Undo re-applying onto a record changed since. That pass
ranked *silent wrong data > silent data loss > crash mid-shift > crash at launch >
performance*, and found one thing — the in-memory fallback was announced only in
Settings, so a whole night could be logged and lost in silence. `NightHeader` carries
that warning now. Otherwise: no force unwraps, `try!`, `as!` or `fatalError` outside
the last-resort in-memory container; every write goes through `StoreWrite.run`, which
surfaces a throw as an alert; the actor returns snapshots, never `@Model` objects.

## Two things the tile change does not do

- **Sage loses its hue in the dark fill.** A sage baby's awake fill samples `#4F4C4B`
  — very nearly grey; the muted green cancels against the maroon where gold survives.
  Border, glyph and badge still carry sage, so identity holds, but the fill is
  contributing lightness and not colour. Fixing it means blending with chroma
  preserved rather than component-wise.
- **Day's asleep fill has no margin** — 1.1998:1 against the card, over the 1.18 the
  test demands and under the 1.20 the other seven clear. Any future deepening of Day's
  surfaces will eat it.

## Needs the user

| What | When | Why |
|---|---|---|
| iCloud capability + container + Background Modes | **deferred** | Only if CloudKit is actually wanted. The store is in the phone's own backup already, so nothing is waiting on this. `docs/cloudkit.md` is kept whole for that day. |
| NFC Tag Reading on the App ID | **backlog** | Developer portal, if NFC is picked up. Scoped in `docs/next-features.md`; nothing is being built. |

Signing, the App Store Connect record and field encryption are all done.

## Open questions

- **Day 0 vs Day 1.** Currently clinical — birth day is Day 1. One constant to change.
- **Wake lock**, deliberately absent. A screen held awake all night costs battery for
  no benefit. Revisit only if it proves annoying.
- **Overdue-feed alerts only render in the foreground.** A notification or Live
  Activity would have to be a decision, not an accident.
- **Undo's window is six seconds**, untested against a real night.

## DEBUG screenshot hooks

`DemoSeed` is gated behind launch arguments and can never fire in a real run; the
archive script refuses a Release binary containing one.

```bash
xcrun simctl launch <device> com.sleepyllamas.moonlog \
  -moonlogSeedDemo YES \                       # a realistic twin night
  -moonlogTab summary|settings \
  -moonlogOpenSheet feed|diaper|sleep|note|pump|medication|weight \
  -moonlogEditFirst YES \                      # edit sheet for the newest record
  -moonlogShiftHours end|correct \
  -moonlogSettingsSheet family|baby|history \  # the surfaces that live in Settings
  -moonlogDemoWrite YES \                      # one real write, for the Undo banner
  -moonlogDumpHandoff YES                      # writes the keepsake page to Documents
```

`-moonlogSettingsSheet` fires from a `.task` on `SettingsView`, so it needs
`-moonlogTab settings` alongside it.

**Every new hook must also be added to `scripts/archive.sh`.** The Release-binary
greps are a hand-maintained alternation; a hook missing from it is a hook the guard
will happily ship.

To look at the keepsake page — a string assertion cannot tell you whether a document
is legible, and a `file://` URL will not open in the simulator's Safari:

```bash
C=$(xcrun simctl get_app_container booted com.sleepyllamas.moonlog data)
cp "$C/Documents/handoff.html" /tmp/ && (cd /tmp && python3 -m http.server 8777 &)
xcrun simctl openurl booted http://localhost:8777/handoff.html
```

The seed turns all three optional kinds on so they are reachable, and carries a second
household — "Okafor", one baby, **no shift** — so the client-family picker has
somewhere to switch to. Between visits is the normal state for a family you are not
with tonight.
