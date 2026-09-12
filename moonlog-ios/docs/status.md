# Status

Updated 2026-09-08.

**225 unit tests green** (121 `MoonlogCoreTests`, 104 `MoonlogTests`) plus **26
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

## The night screen and the handoff, 2026-09-07

- **The tile.** "Day N" is off the card (and out of what VoiceOver says about it).
  Pressing it no longer dims it — that read as unavailable, not as pressed. The asleep
  fill is see-through on Night and Deep Night; see the note on Day below. The trailing
  edge names the sleep: start plus a running elapsed while asleep, and the whole of the
  last one as `3:42a–4:22a` once awake.
- **The sun and moon are drawn shapes**, with the moon's z's and the sun's rays moving
  independently of the glyph and a shake-and-swell on state change. No symbol effect
  animates a glyph's parts independently, which is why they are not SF Symbols. All of
  it stops under Reduce Motion. The drift is bounded as of 2026-09-08 — see
  `decisions.md`.
- **A diaper looks like a diaper.** `square.on.square` read as "duplicate". The glyph is
  a drawn shape — leg cutouts, chosen over a tabbed top (a cow's head), a flat top (a
  plant pot) and a subtracted waistband (good at 22pt, fills in at 11). It travels as a
  sentinel name through the `String`-carrying value types that already move icons
  around; `CareGlyph` is the one place that resolves it, and the one place that must
  keep the sentinel away from `Image(systemName:)`, which renders a silent blank.
- **Colour on every diaper**, wet included, saved exactly as the swatches show it.
  A night can now have a colour progression with no dirty diaper at all, so the label
  is "Stool" or "Colour" by whether a dirty one contributed — decided in
  `Handoff.diaperColourLabel` and used by both documents and the Summary card, so the
  three cannot drift.
- **Feeds repeat.** A row naming the last feed's values, which fills nothing until it
  is tapped. Nothing is prefilled: an amount nobody chose must not reach the parents.
- **The handoff reads as a letter.** Both documents open with a greeting and close with
  a sign-off; the keepsake has the doula's note folded into the letter rather than
  bolted beside it, gold hairline section rules, an inset keepsake border, four stat
  tiles including notes, pills, and a per-stretch sleep timeline the app never had.
  Print keeps its colour (`print-color-adjust: exact`) and the page has no horizontal
  overflow at 320pt. Rendered and checked in light, dark and PDF — not read off the CSS.

## Times on every record, 2026-09-08

- **Every logged record carries its time** in both handoff documents, and a sleep
  stretch names its start, its wake and its length rather than a bare duration —
  on the timeline as well as on the page. **Summary carries the full log** under the
  totals, read-only. Why, and what it reverses, is in `decisions.md`.
- **The glyph drift is bounded** rather than `repeatForever`, and the resting frame
  was recomposed because it is now what the tile shows all night. `decisions.md`.
- **Save answers on the whole bar.** It was measured at **38×20pt — the size of the
  word — inside a 370×56pt bar**: `.plain` hit-tests a button's *contents*, so the
  width bought by `.frame(maxWidth: .infinity)` was layout and nothing else, on the
  one control every log of the night ends with. A `contentShape` fixes it.
  `ReachabilityTests` asserts the frame, not just a tap — a normalised coordinate is
  taken against the element's own frame, so "tap the edge of Save" lands back on the
  word and passes when the frame has collapsed to it. Verified to fail without the fix.
  The card controls and Summary's rows were measured too and were already full-size.

## The 2026-09-07 audit pass

Three source audits — `docs/audit-ux.md`, `docs/audit-reliability.md`,
`docs/audit-continuity.md` — were written against this checkout and are kept as the
backlog. They are **source** audits: nothing in them was reproduced on a device, and
the line numbers describe the tree before this pass changed it.

What closed:

- **A logical write is one commit.** `CareStore.write` disables autosave, saves once
  at the outermost depth and rolls back on a throw, so nested reconciliation shares
  the commit and a rejected update cannot leave mutations pending for the next
  successful save to carry. Input is validated before anything is mutated.
- **Save awaits the write.** Every log sheet's `onSave` is `async throws`; the sheet
  latches, says "Saving…", and dismisses only on success. A failure keeps every
  entered value and offers Retry, instead of returning to Tonight with an alert and
  asking you to remember what you typed. Same for the note to the parents.
- **A disabled Save says why**, beside the button — "Add a note, choose a tag, or
  record a temperature." (Feeds were already ungated.)
- **Amounts, minutes, weights and temperature are typed, not only stepped.** A 4 oz
  bottle was eight presses of a stepper; 100.4°F was eighteen. The steppers stay for
  the small nudge. Invalid text blocks Save and stays visible rather than silently
  saving the last valid number.
- **`Fmt` tolerates malformed stored values** — NaN, infinity, negative, and values
  past `Int`'s range render as "—" rather than trapping while the timeline opens.
  The writer refuses them at the actor.
- **The actor enforces household membership.** Logging, correcting, restoring and
  reassigning all check that the baby belongs to the shift's family. Reassignment
  also refuses a kind that attaches to no baby.
- **Duplicate logical ids no longer trap.** `Dictionary(uniqueKeysWithValues:)` on
  model ids is gone; conflicts throw and keep both records.
- **A family and its first baby are one write.** A rejected birth date used to leave
  a nameless household on the switcher.
- **"Log earlier sleep"**, per baby, in Tonight's overflow menu. The tile toggles at
  the moment it is tapped, so a sleep that ended while both hands were full had no
  route at all. It never opens a session — the actor refuses anything the reconciler
  would merge into the sleep running now.
- **The note to the parents and Past nights are on Summary**, not buried in the share
  menu and a tab away in Settings.
- Accessibility: the card's chips carry combined labels, its status text wraps instead
  of shrinking to 70%, and the chip row and action row go vertical at accessibility
  text sizes. Tap targets on the baby header and busy action buttons are honest.

**One display rule changed.** `Fmt.amount` no longer snaps ounces to the half-ounce
grid. That snap was lossless while amounts could only be stepped; with direct entry a
typed 2.25 oz would have read back as 2.5. The cost is that a 90 ml feed shown to an
ounces household now reads "3.04 oz" rather than "3 oz". Sums (`amountTotal`) are
unchanged at one decimal.

## Still open

1. **No draft survives leaving the sheet.** Save now holds its values through a
   *failed* write, but a swipe-dismiss or a process kill still loses unfinished
   input; there is no scene-phase recovery. `audit-continuity.md` C2.
2. **Sleep's busy period is still a fixed two-second timer**, not an observed merge,
   and Undo is still one action for six seconds — replaced by the next write.
   `audit-continuity.md` C3, C4.
3. **Undo has no conflict check.** An event edit's reversal writes its whole prior
   payload without checking the record still matches, and `runUndo` clears the action
   before awaiting it, so a failed Undo cannot be retried. `audit-reliability.md` R6.
4. **The in-memory fallback still ends in `try!`.** If that initializer throws the app
   terminates instead of showing recovery UI, and there is no retry or reopen route.
   `audit-reliability.md` R3.
5. **History and the timeline have no upper bound.** Both fetch every closed shift and
   filter in memory. P3 — measure on a populated store before optimising.
   `audit-continuity.md` C5.
6. **Settings toggle rows respond only on the switch**, not across the row, unlike
   every other row on that screen. Measured: the row centre and the label both leave
   the setting off, and a `contentShape` on the label does not fix it.
7. **`EventKind` has no `unknown` case.** `LogEvent.kind` falls back to `.note`, so a
   kind written by a later build would read here as a note — a record of the wrong
   thing rather than of nothing. Every other wire-format enum has the guard. Closing
   it means adding a case to several exhaustive switches.
8. **Summary's Copy sits in the top-left corner** — the worst reach for a right thumb.
   Once a night, so undecided rather than open.
9. **Undo has three gaps**, all deliberate and commented where they apply: recording a
   sleep from the sheet (`recordSleep` corrects-or-inserts and does not say which),
   ending a shift (`updateShift` will not reopen one, because `close(at:)` is what
   keeps `isOpen` honest), and adding a baby (archiving is not un-adding).
10. Smaller: the handoff lists feed and note times but not diaper times;
   `Fmt.paddedDuration` has no rollover past 24h; `OnboardingView`'s
   `.navigationTitle` is dead, overridden by the tab's stack.

**Not covered by either 2026-09-07 pass**, and worth saying so: an app killed
mid-write, and Undo re-applying onto a record changed since. No fault injection was
run — the transaction boundary above is verified by reading the code and by the unit
suite, not by a failed disk write or a forced termination.

The earlier crash and data-loss pass ranked *silent wrong data > silent data loss >
crash mid-shift > crash at launch > performance*, and found one thing — the in-memory
fallback was announced only in Settings, so a whole night could be logged and lost in
silence. `NightHeader` carries that warning now. Otherwise: no force unwraps, `try!`, `as!` or `fatalError` outside
the last-resort in-memory container; every write goes through `StoreWrite.run`, which
surfaces a throw as an alert; the actor returns snapshots, never `@Model` objects.

## Two things the tile change does not do

- **Sage loses its hue in the dark fill.** A sage baby's awake fill samples `#4F4C4B`
  — very nearly grey; the muted green cancels against the maroon where gold survives.
  Border, glyph and badge still carry sage, so identity holds, but the fill is
  contributing lightness and not colour. Fixing it means blending with chroma
  preserved rather than component-wise.
- **Day's asleep fill has no margin** — 1.204:1 against the card, over the 1.18 the test
  demands and under the 1.20 the other seven clear. Any future deepening of Day's
  surfaces will eat it, and it is why Day was left alone when the other two themes'
  asleep fills were made see-through: the whole of Day's remaining room buys 1.189:1,
  a change no eye can find, at the cost of the last of that margin. Making Day's asleep
  tile genuinely transparent needs a lighter Day card.

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
