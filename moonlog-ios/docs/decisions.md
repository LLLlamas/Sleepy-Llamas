# Decision log

Newest first. Each entry records what was decided, why, and what would reverse it.

---

## Five baby accents, defined per theme, not as palette roles
**2026-09-05**

Accents were originally `--accent` / `--sleep` / `--warn`. In the Day theme that
made "gold" resolve to maroon, sitting almost on top of "rose" — twins were
distinguishable at night and barely so by day. Each accent now carries its own
per-theme value.

A sixth, "clay", was tried and dropped: in a warm maroon palette a terracotta is
inescapably close to gold, and the contrast test caught it in all three themes. Two
colours a tired person can confuse are worse than one fewer option.

*Reverses if:* someone needs more than five babies in one family, which would mean
finding hues that survive the distinctness test rather than reusing roles.

---

## SF for the interface, Fraunces only for brand moments
**2026-09-05**

A deliberate departure from the PWA's brand type. SF is engineered for glanceability
at small sizes in low light and gives `.monospacedDigit()` free — a sleep timer in a
proportional face jitters as digit widths change, and it is re-read all night.
Fraunces stays on the wordmark and the exported keepsake handoff, where a display
serif earns its place.

*Reverses if:* the app stops feeling like Sleepy Llamas. Cheap to change.

---

## No PWA importer; the PWA is frozen
**2026-09-05**

The PWA only ever held test data, so the native app starts clean. The 17 audit
findings against it become a specification of defects not to reintroduce, not a work
list. `legacyID` columns were removed while it was still free — a CloudKit field
cannot be deleted after the schema is promoted to production.

---

## Clip sleep sessions to the shift window; never auto-close them
**2026-09-05**

A shift ends by leaving the baby with the parents, often still asleep. So the
session stays open and honest — "asleep since 5:40, still asleep when I left" — and
totals clip to the shift window instead.

One rule replaces three fixes: it stops an archived shift's total growing forever,
stops a back-dated entry crediting one shift with another's hours, and preserves the
true record. Also means ending a shift does not open a replacement.

*Supersedes* an earlier plan to close the session and start a fresh shift, which was
written before the workflow was understood.

---

## Day of life uses the clinical convention (birth day = Day 1)
**2026-09-05**

The PWA counts completed 24-hour blocks, so it calls a ten-hour-old baby "Day 0" and
rolls over at the birth *minute*. Neither matches how a pediatrician counts, and the
minute-rollover means the same handoff reports a different Day N depending on when
it is copied. There is a shift-pinned overload so the number is stable for a shift.

*Made without an explicit answer from the user* — flagged, and a one-constant change.

---

## `LogEvent` is one flat model, not three and not a class hierarchy
**2026-09-05**

- Three models cannot be paged: `FetchDescriptor.fetchLimit` is per-type, so a
  merged timeline would mean loading every event of all three kinds to show 50 rows.
- `@Model` inheritance needs iOS 26 and has reported crashes at the inheritance +
  optional-relationships intersection, which CloudKit mandates.
- `#Predicate` cannot compare enum properties at all, so raw `String` columns are
  needed regardless — and reaching through `.rawValue` inside the macro
  *hard-crashes uncatchably*.

Cost: the schema cannot enforce "a feed has a method". Bought back with a payload
projection and tests. CloudKit could not have enforced it either.

---

## CloudKit behind a compile flag, not a runtime probe
**2026-09-05**

Requesting a CloudKit store without the entitlement does not throw — it traps
asynchronously and kills the app. A runtime check is impossible on iOS
(`SecTaskCopyValueForEntitlement` is not public; `ubiquityIdentityToken` keys off a
different entitlement). See `docs/cloudkit.md`.

---

## Target iOS 18, not 26
**2026-09-05**

Everything v1 needs is available at 18 — SwiftData, `#Index`, CloudKit mirroring,
Core NFC, Live Activities — and it keeps older devices in play. Only AlarmKit
(feed-due alarms) needs 26, and it is last in the order and will be `@available`-gated.

---

## Background NFC dropped for v1
**2026-09-05**

Two independent reasons:

1. It cannot log silently. iOS always shows a notification the user must tap, and a
   locked phone must be unlocked first. The real delta versus "open app, tap Scan"
   is small.
2. The `apple-app-site-association` file cannot live at our URL. It must be served
   from the **domain root**, and `LLLlamas.github.io/.well-known/...` is served by a
   different repository — probed live, it 404s. Nothing in this repo can appear
   there.

In-app tag reading and writing need no web infrastructure and are still planned.

*Reverses if:* a custom domain is bought and `.well-known/` served from a host that
controls headers.

---

## iOS work lives on a branch, not a separate repo
**2026-09-05**

`deploy.yml` only triggers on pushes to `main`, so an unmerged branch is invisible to
CI. Chosen over a separate repository so TestFlight builds come straight off this
branch. The one hole is `workflow_dispatch`, which can target any ref — hence the
discipline in `CLAUDE.md`.
