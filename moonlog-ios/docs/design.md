# Design

Native-first, Sleepy Llamas maroon identity. The app is used one-handed, in the
dark, by someone exhausted, and its output goes to a client family — so
legibility and not-getting-it-wrong beat elegance every time.

## Palette

Ported from the retired PWA's `tokens.css`, and **no longer verbatim**. Three
themes:

| Theme | Background | Use |
|---|---|---|
| Night | `#1a0a0e` deep maroon-black | default dark |
| Deep Night | `#100508` | when even Night is too bright |
| Day | `#fdf4f1` blush, `#a83246` maroon accent | daytime reading |

Call sites use **roles**, never raw hex: `ink`, `soft`, `faint`, `sleep`, `awake`,
`warn` (overdue feed), `stop` (fever / destructive).

### The contrast claim, measured

This document used to say the values were "contrast-checked against real
surfaces". Nothing enforced that, and when it was finally measured on 2026-09-06
the **Day theme failed five pairs**: `sleep` on `chip` at 3.71:1, `sleep` on
`raised2` at 4.00:1, `sleep` on `sleepFaint` at 4.11:1, and `faint` and `stop` on
`chip` at 4.49:1. Day's `faint`, `sleep`, `sleepFaint` and `stop` were corrected.

`PaletteTests` now measures every text role against every surface, every state
tint against its own faint wash, and `accentInk` on `accent`, at **WCAG 2.1
relative luminance** — linearised sRGB, not the crude weighted sum the
accent-distinctness test uses. That test compares two accents to each other,
where a rough distance is enough; a legibility threshold needs the real curve.

**Anything added to the palette has to pass that test before it can be looked at.**

### Making the maroon read

The web ramp leans on a very quiet `bg`→`raised` step — about six thousandths of
a luminance. A bright monitor flatters it. An OLED panel in a dark nursery does
not, and the identity was reading as plain black on the screen named after it.

Two changes, both on 2026-09-06:

- The surfaces above `bg` are lifted toward maroon in every theme.
- A new role, **`bgLift`**, is the colour the page fades *from* at the top, where
  the clock sits. `MoonBackground` draws it as a three-stop gradient settling to
  `bg` at 45% — a straight two-stop ramp puts the midpoint halfway down the
  screen and tints the timeline rows unevenly. Every screen gets it through
  `.moonBackground(_:)`; no view fills with `palette.bg` directly any more.

Night and Deep Night `bg` did **not** move — they are the brand anchor and the
PWA's `theme-color`. Day's `bg` did, one step warmer, because a cream page cannot
be made more maroon by lifting only what sits on top of it.

**Theme selection follows the system light/dark setting**, with Deep Night as an
explicit one-tap override.

There is deliberately **no time-based auto-switching**. It changes the screen under
a tired user at exactly the moment predictability matters most.

> Trap, hit once already: do not derive the theme from `@Environment(\.colorScheme)`
> and then apply `.preferredColorScheme` from that derivation. It is circular — the
> forced scheme becomes the value read next, so the theme latches on whatever it
> resolved first and never changes again. `preferredColorScheme` is applied *only*
> for the explicit Deep Night override.

## Type

**SF for the interface.** Inter is dropped. Fraunces is *intended* for the wordmark
and the exported keepsake handoff — neither exists yet, and no font file is bundled,
so today the app is SF throughout.

A departure from the PWA, made deliberately. SF is engineered for glanceability at
small sizes in low light and provides `.monospacedDigit()` — which matters more than
it sounds, because a running sleep timer in a proportional face jitters as digit
widths change, and that is a number re-read all night. Every timer, clock time and
elapsed label uses monospaced digits.

Minimum tap target is 56pt, carried over from the PWA's `--tap`. One exception:
the note-tag chips are 44pt (Apple's floor) so a row of them fits without wrapping.

## The night header

Tonight opens with `NightHeader`: the family name and shift start in a small
tracked uppercase line, then the current time set large in `accent` — gold at
night, maroon by day — then the date written out in full.

The clock is the biggest thing in the app deliberately. Every log a doula makes
is "when did that happen, relative to now", and the PWA answered that in a
19-pixel line beside the wordmark, which is the size you use for something nobody
needs. It is `@ScaledMetric`, so it grows for someone who has told the system they
need larger text — opting the one deliberately-large number out of Dynamic Type
would defeat the point of making it large.

It ticks on its own `TimelineView`. The rule that the rest of Tonight does not
tick is unchanged: the timeline re-renders on writes, not on the clock.

The family name is there for a second reason — see "One family at a time" below.

## Baby status

The awake/asleep state is a bordered, tinted tile, ported from the PWA's sleep tile:
a 2pt border, a fill, and the copy "Mia is asleep". A tinted block is legible across
a dark room in a way a coloured word in a row is not.

**Tapping it toggles**, at the time you tapped. It is the biggest target on the card
and the thing done most often at 3am, so it takes no configuration and asks nothing —
the same write the Wake/Sleep button below makes. It used to open the adjust-sleep
sheet, which meant the largest control on the screen asked a question instead of
answering one. Correcting a time afterwards lives where the record is: the sleep row
in tonight's timeline, which is tappable for a running session as well as a finished
one.

### The tile wears the baby's colour, not the state's

Both states are tinted by **that baby's accent**. The border and the moon/sun glyph
are the accent itself; the fill is the accent blended most of the way back to the
card, and **asleep is the same colour faded further** — which reads as darker on the
night themes and as more transparent by day, because both mean "closer to the card".

It used to be sage for asleep and gold for awake, the same two colours on every card.
With twins that meant the two tiles could swap hues without changing which baby was
which, and hue said nothing about whose card you were looking at.

So hue is identity now and depth of fill is state. **That is a deliberate demotion of
colour as a state signal**, and it is only defensible because state was never carried
by colour alone here: the glyph is a moon or a sun, the sentence says "Mia is asleep"
in words, and the elapsed counter appears only while asleep. Colour stays the third
signal — it has changed what it is third *for*.

**Each fill has two jobs, and they pull against each other.** It must stand off the
card enough to read as *this baby's colour*, and stand off the other state enough to
read as awake or asleep. Deepening one costs the other. The six blend factors are the
measured balance point per theme — every theme clears 1.20:1 on both, while `ink` and
`soft` hold 4.5:1 on the fill and the accent outline holds 3:1.

The outline and glyph are held to 3:1 rather than 4.5 because they are UI components,
not text — WCAG 1.4.11. Holding them to 4.5 was tried and forced the accent 44% of the
way to `ink`, bleaching out the one thing the tile's colour now exists to say.

The tile's subtitle uses `soft` rather than `faint`. `faint` was what capped how deep
either fill could go, and the fills needed that depth; it is also a line read at 3am,
so the brighter role is the better call regardless.

**This was shipped wrong once, and the suite did not catch it.** The asleep fill was
first set at 0.95 on every theme, which put it 1.06:1 from the card — not a faded
version of the baby's colour but nothing at all, an outline with an empty middle. The
test asserted only that the two fills *differed*, and an invisible fill differs from a
visible one perfectly well. A screenshot caught it. `PaletteTests` now asserts both
jobs.

Its second line says **when the state started, then what the tap does** — "Since
3:42am · tap to adjust". Both halves are departures from the web original, and both
are deliberate:

- **"tap to adjust", not "tap when Mia wakes".** The web tile toggled when tapped;
  this one opens the adjust-sleep sheet, and the Wake/Sleep button below is what
  toggles. Copy that describes the wrong gesture is worse than no copy.
- **The time is on both states, not just asleep.** Awake used to say nothing about
  when it began, which was the more useful of the two. It comes from the last closed
  sleep's `endAt`, and is simply absent before the baby has slept — the tile says
  "Tap to log a sleep you missed" and claims no time it does not have.

The time belongs on that second line and not appended to the state sentence above
it. Appended, it wrapped inside its own parenthetical; the asleep tile is the tight
one because it alone carries the elapsed badge on its trailing edge. The state stays
one short bold line, in `am`/`pm` rather than the handoff's single-letter `3:42a`.
- Sentence case, not `AWAKE`/`SLEEPING`. The PWA never shouted here either — its
  only uppercase is 10-pixel mono micro-labels.

The tint is still never the only signal: the baby's name is *in the sentence*.

## Multiple babies

**Adaptive layout.** One baby renders a single status block. Two or more render a
compact card each — both states visible simultaneously, each with its own buttons —
over one shared merged timeline.

There is **no active-baby selector**. A mode you can set wrong is the hazard twins
introduce, and mis-logging to the wrong baby is the failure this layout exists to
prevent.

### Colour is never the only signal

The user picks each baby's accent from five options. Colour is the **third**
identifying signal, behind:

1. **The name**, always visible — on the card, in the log sheet, and in the
   post-save confirmation. Timeline rows show it whenever the family has more than
   one baby; with a single baby it is redundant and suppressed.
2. **Stable position**, fixed by `sortOrder`, so the top card never moves. Muscle
   memory beats reading at 3am.

Why: hue discrimination degrades in a dark room and is absent for colourblind users.
Swatches are labelled, and the selected one carries a checkmark as well as a ring.

**Five accents, not six.** Gold, rose, lilac, sky, sage. A terracotta "clay" was
tried and removed — in a warm maroon palette it sits inescapably close to gold, and
the contrast tests caught it in every theme. Two colours a tired person can confuse
are worse than one fewer option. `PaletteTests` enforces mutual distinctness and
background contrast for every accent in every theme.

## One family at a time

A night doula works one household per shift. From 2026-09-06 the app is built
that way: there is a single selected client family, and everything Tonight logs
belongs to it without asking.

**Switching household lives in Settings**, first section, as an inline picker with
a checkmark on the live one — every option visible without opening a menu. It was
previously a dropdown in Tonight's toolbar. Two things were wrong with that: it
made a whole-app mode change a one-tap neighbour of the buttons pressed forty
times a night, and "Add client family" sat in the same menu, so taking on a new
client and logging a feed were adjacent gestures.

`Add baby` moved to Settings for the same reason. It was the *first* item in
Tonight's overflow menu, one slip above "End shift".

What the switcher was also doing was answering "whose night am I logging?" That
answer still has to be given, or moving it trades a convenience for exactly the
mis-logging risk it guarded against — so `NightHeader` states the family name on
Tonight, permanently, without offering to change it.

> **Constraint, load-bearing:** the picker must stay at the **root** of the
> Settings stack. `ShiftDetailView` captures its `Family` and `Shift` as model
> objects, so a switcher reachable from a pushed screen could change the family
> underneath one and leave it rendering the previous household's night.

Twins are unaffected: within the one family, both babies still render a card each
with their own buttons, and there is still no active-baby selector.

## Asking before acting

Whether an action confirms is a setting, listed one row per action under **"Ask
before"** in Settings, app-wide rather than per family — it is how the doula wants
the app to behave, not a fact about the household.

**Most of them default to off, and Undo is why.** Every action on the list except
ending a shift leaves an Undo on the banner for six seconds. A confirmation is worth
its interruption only where the action is hard to take back or easy to fire by
mistake; everywhere else it costs something real, because at 3am an unnecessary
dialog trains the thumb to dismiss dialogs unread. So ending a shift and the two
deletes ask by default; the sleep toggle and moving a record to the other twin do
not.

Opening a log sheet is not on the list and should not be added to it. A sheet is a
form, not a question, and a form you can cancel already is its own confirmation.

Each one **names the consequence** rather than asking "Are you sure?", and its
button carries a verb — "End shift", "Delete", "Move" — so nobody has to re-read
the title to work out which button they want.

They are **alerts, not confirmation dialogs**. A `confirmationDialog` presented from
inside a sheet renders as a popover, and iOS drops the cancel action in that
presentation — the app's one delete confirmation had shipped offering a red Delete
and no visible way out. It also anchored its tail to the wrong thing and floated over
the screen behind. Verified by screenshot, both before and after.

## Discoverability

Editing a baby is reached by a **visible chevron** on the card header, not a
long-press. The PWA hid manual sleep entry behind an unadvertised 500ms hold with
the hint in a `title=` attribute that never renders on touch — it was the only route
to that feature and was effectively invisible. Do not repeat it.
