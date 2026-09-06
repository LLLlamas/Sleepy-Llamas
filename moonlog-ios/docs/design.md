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

The awake/asleep state is a bordered, state-tinted tile, ported from the PWA's
sleep tile: a 2pt border in `sleep` or `awake`, a fill in the matching faint wash,
and the copy "Mia is asleep". A tinted block is legible across a dark room in a
way a coloured word in a row is not.

Two departures from the web original, both deliberate:

- Its subtitle says **"tap to adjust"**, not "tap when Mia wakes". The web tile
  toggled when tapped; this one opens the adjust-sleep sheet, and the Wake/Sleep
  button below is what toggles. Copy that describes the wrong gesture is worse
  than no copy.
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

## Discoverability

Editing a baby is reached by a **visible chevron** on the card header, not a
long-press. The PWA hid manual sleep entry behind an unadvertised 500ms hold with
the hint in a `title=` attribute that never renders on touch — it was the only route
to that feature and was effectively invisible. Do not repeat it.
