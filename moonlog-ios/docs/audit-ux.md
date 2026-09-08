# UX audit — 2026-09-07

Scope: general ease of use, obvious actions, redundant controls, sensible defaults,
and interruption recovery. Limited-hand use and accessibility are secondary lenses,
following the clarified request. This is a source audit, not an observed usability
study or a claim of simulator/device validation. Source line references describe the
checkout at audit time; recommendations below are not implemented by this document.

Read against `CLAUDE.md`, design, architecture and status documentation, the logging
sheets, Tonight, Summary, Settings, and reachability tests.

## What already works well

- Sleep/wake is one tap by default, with the baby's name in the state and accessible
  action label (`BabyStatusCard.swift:126`, `:288`). Colour is supplementary.
- A breast feed can be recorded with Feed → Save without inventing a duration;
  this path has an explicit two-tap UI regression test
  (`ReachabilityTests.swift:48`). Wet diaper similarly defaults to a useful record.
- Shared log Save is fixed at the bottom, full width (`LogSheetChrome.swift:231`,
  `:248`); editing and wrong-baby reassignment reuse the familiar sheet.
- Family switching stays separate from logging. Keep that deliberate separation;
  removing a tap here would increase wrong-family entry risk.
- Summary retains the most recently finished shift (`SummaryView.swift:37`), so
  finishing a shift does not remove the handoff at the moment it is needed.

## Findings and recommended order

P1 = recovery or missing core workflow; P2 = repeated friction or discoverability;
P3 = polish or a design hypothesis requiring observation.

| Priority | Source-verified finding | Recommendation and acceptance condition |
|---|---|---|
| P1 | Save calls a synchronous callback and dismisses immediately (`LogSheetChrome.swift:249–254`); the actual async write fails later in `TonightView.perform` (`:580–608`). Sheet fields are local `@State`, and the error alert offers only OK (`TonightView.swift:163`). A failed save leaves no in-app retry carrying the draft. Parent note has the same pattern (`ParentNoteSheet.swift:57–60`). | Retain the draft until acknowledged persistence; show saving state, keep values on failure and offer Retry. Inject a write failure after entering a multi-field feed/note and verify exact values remain, retry creates one record, and success alone dismisses. |
| P1 | Manual missed sleep entry has no direct route. `SleepSheet.swift:4–10` explicitly makes it editor-only; `TonightView.swift:798` only has `editSleep`, and the tile now toggles the current state. | Add an explicit “Log earlier sleep” route in the timeline/secondary actions, using the existing time rules. Do not require a false current sleep toggle followed by correction. Verify adding an earlier completed sleep without changing current awake/asleep state. |
| P2 | Every new feed defaults to Breast and zero amount (`FeedSheet.swift:37–42`); volume is stepper-only in 0.5 oz or 10 ml increments (`LogSheetChrome.swift:349–367`). A routine 4 oz bottle needs eight plus presses as well as opening, choosing method and saving. | Make volume directly editable alongside the stepper. Consider an explicitly visible remembered method per baby; do not silently prefill a previously consumed amount as fact. Confirm unit conversion and editing of existing amounts still preserve values. |
| P2 | The full status tile and the fourth action button do the same sleep toggle (`BabyStatusCard.swift:126–138`, `:255–265`). The row duplicates the largest control while compressing Feed, Diaper and Note. | Trial a three-action row with the labelled tappable status tile retained. Compare discovery and accidental toggles before removing the duplicate permanently; a second route can be useful if the tile does not look actionable to new users. |
| P2 | A note's text field says “Optional”, while an empty note disables Save (`NoteSheet.swift:48–61`, `:78–80`). Shared chrome accepts only a Boolean reasonless gate (`LogSheetChrome.swift:39`, `:111`, `:266`). Other required-content sheets use the same gate. | Show the missing requirement beside Save and in the relevant section, e.g. “Add a tag, note, or temperature.” Keep optional detail optional. Test empty and whitespace-only cases with a visible and spoken explanation. |
| P2 | Adding/editing the note to parents is buried inside the share menu (`SummaryView.swift:135–143`), although it edits the handoff rather than shares it. Past nights is under Settings (`SettingsView.swift:335`), away from Summary. | Put a visible “Note to parents” action with the handoff content; add a Past nights navigation entry from Summary using the existing history screen. Keep settings routing if useful, but avoid separate implementations of either action. |
| P2 | New temperature starts at 98.6 and moves by 0.1 only (`NoteSheet.swift:40`, `:86`); entering 100.4 requires 18 increment presses. | Add direct numeric entry and a clear read-back, preserving domain validation. Do not replace this with unconfirmed “normal temperature” presets; entered values must represent an observation. |
| P2 | Each successful per-baby write keeps actions guarded for an extra two seconds (`TonightView.swift:591–603`). The status tile is disabled, but row buttons only early-return and dim (`BabyStatusCard.swift:272–288`), so accessibility may still describe an available action. | Expose a consistent disabled/busy state and brief saving feedback. Replace the fixed delay only once model-refresh acknowledgement safely prevents double-tap toggles. Verify a quick Feed → Diaper sequence does not feel like an ignored tap. |
| P2 | Undo expires in six seconds and the next write replaces it (`TonightView.swift:613–624`). There is no durable recent-action recovery list. | Test a longer or dismissible Undo presentation and preserve correction from the timeline. Any action requiring timed recovery should remain recoverable after an interruption; assess a small recent-action history separately from permanent record editing. |
| P3 | Shift ending is menu → End shift → End → confirmation by default (`TonightView.swift:115–128`, `ShiftHoursSheet.swift:119–150`). Copy, shift commit and parent-note Save are top-bar actions while routine log Save is at the bottom. | Keep the time-review step because the shift end is meaningful data. Trial making its final consequence explicit enough to reduce a redundant confirmation only after a safe reversal exists or the existing preference is chosen. Align commit placement across sheets; moving Copy is lower impact than routine logging. |

## Tap paths from source

Counts assume the baby card is already visible, an open shift, default confirmation
preferences, default new-entry values, and ordinary single presses. They exclude
scrolling, time edits, keyboard characters and the system share destination picker.
These are calculated paths, not timed or device-measured results.

| Task | Path | Taps |
|---|---|---:|
| Sleep or wake now | Status tile | 1 |
| Breast feed, unspecified duration | Feed → Save | 2 |
| Wet diaper | Diaper → Save | 2 |
| Both diaper, no optional colour | Diaper → Both → Save | 3 |
| Tag-only note | Note → tag → Save | 3 |
| 4 oz bottle, no duration | Feed → bottle method → plus × 8 → Save | 11 |
| 120 ml bottle, no duration | Feed → bottle method → plus × 12 → Save | 15 |
| Breast feed, 15 minutes each side | Feed → left plus × 3 → right plus × 3 → Save | 8 |
| Correct wrong baby on a non-sleep record | Timeline record → Wrong baby? → other baby | 3 |
| Add parents' note from Tonight | Summary → share icon → Add note → type → Save | 4 plus typing |

## Secondary accessibility checks

These are source-backed layout risks, not confirmed clipping or screen-reader bugs:

- Status text has one-line limits and shrinks to 70%, while action labels sit in a
  fixed-height 56pt four-column row (`BabyStatusCard.swift:160–170`, `:255–282`).
  Use multiline content and a two-column/vertical layout at larger text sizes.
- Tags have fixed 44pt height (`NoteSheet.swift:126`) and “Wrong baby?” has padding
  but no minimum target size (`LogSheetChrome.swift:91–100`). The baby editor header
  likewise has no minimum height (`BabyStatusCard.swift:95–109`). Document the
  difference between a layout constant and verified rendered hit regions.
- The feed and diaper segmented pickers have no explicit large-text alternative
  (`FeedSheet.swift:77`, `DiaperSheet.swift:63`). Test long labels and the largest
  accessibility text sizes before claiming readability.
- The last-feed/diaper chips show mostly icons and elapsed values, without explicit
  combined semantic labels (`BabyStatusCard.swift:223–248`). Check that VoiceOver
  distinguishes “last feed” from “last diaper” and announces “due” usefully.
- There is no explicit success announcement/focus management around the timed Undo
  banner (`TonightView.swift:645`). Test actual VoiceOver reading and recovery
  before treating an accessibility label or UI-test existence as sufficient.

## Validation still required

Drive a small and large iPhone with one and two babies, long names, Day/Night/Deep
Night, largest Dynamic Type, VoiceOver and Switch Control. Observe opening and
saving each sheet with the keyboard visible; backdate an event; correct the wrong
baby; end and share a shift; leave and return during draft entry and during Save.
Test failure recovery, notification/phone interruption, app backgrounding and
relaunch separately. Source inspection cannot establish draft survival after a
process kill or actual focus order and target dimensions.

`ReachabilityTests.swift:48–63` checks the two-tap breast-feed path and bottom Save
position. The inspected UI tests do not exercise an accessibility text-size matrix,
VoiceOver announcements, numeric entry efficiency or interrupted-draft recovery.
No new runtime test was run for this documentation-only audit.

## Knowledgebase corrections discovered

`docs/design.md` still describes the tile opening the adjust-sleep sheet after an
earlier paragraph correctly describes toggling; current code toggles. Its “adaptive
twins” implications should be checked against Tonight's actual stacked cards.
`docs/architecture.md` describes a `navigationDestination` history push and a
`confirmationDialog` despite current guidance and source using NavigationLink/alert.
Treat the code and current explicit working agreement as authoritative until those
contradictions are corrected. Cross-document edits are owned by the lead audit.
