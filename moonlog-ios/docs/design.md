# Design

Native-first, Sleepy Llamas maroon identity. The app is used one-handed, in the
dark, by someone exhausted, and its output goes to a client family — so
legibility and not-getting-it-wrong beat elegance every time.

## Palette

Ported verbatim from the retired PWA's `tokens.css`, which was contrast-checked
against real surfaces. Three themes:

| Theme | Background | Use |
|---|---|---|
| Night | `#1a0a0e` deep maroon-black | default dark |
| Deep Night | `#100508` | when even Night is too bright |
| Day | `#fdf6f4` blush, `#a83246` maroon accent | daytime reading |

Call sites use **roles**, never raw hex: `ink`, `soft`, `faint`, `sleep`, `awake`,
`warn` (overdue feed), `stop` (fever / destructive). The `faint` values are the
tightest for contrast — if a surface changes, re-measure rather than eyeball.

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

## Discoverability

Editing a baby is reached by a **visible chevron** on the card header, not a
long-press. The PWA hid manual sleep entry behind an unadvertised 500ms hold with
the hint in a `title=` attribute that never renders on touch — it was the only route
to that feature and was effectively invisible. Do not repeat it.
