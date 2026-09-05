# Status

Updated 2026-09-05. **First TestFlight build shipped** — 0.1.0 (1788644622),
local-only, not yet safe for a real shift (no edit/delete of a logged entry).

## Built

| Area | State |
|---|---|
| XcodeGen project, 4 targets | done |
| `MoonlogCore` — clock, day buckets, day-of-life, totals, reconciler | done, 49 tests |
| SwiftData models + CloudKit schema test | done, mutation-verified |
| `CareStore` write layer | done |
| Tonight screen — adaptive twins layout, timeline | done, runs on simulator |
| Baby rename + colour picker | done |
| Log sheets: feed, diaper, sleep, note | done |
| Onboarding, start/end shift, add baby | done |
| App icon, privacy manifest, export compliance | done |
| Per-family volume unit, L/R breast feeds | done |
| Optional kinds (pump, medication, weight) | model only — no UI yet |
| User-defined note tags | model only — no UI yet |

95 tests green. Field encryption applied; device signing verified. Verified running in Night and Day themes.

## Next

1. **Edit and delete from the timeline** — a mis-logged feed or diaper cannot be
   corrected. The most important gap before a real night.
2. Family settings: optional event kinds and note tags are modelled but seed-only.
3. Summary / handoff for the parents.
4. History → trends → export.
5. NFC.

## Before TestFlight

See `docs/testflight.md` for the full list. Three of them are hard blockers on
upload, not polish.

## Needs the user

| What | When | Why |
|---|---|---|
| ~~Xcode signing~~ | done | Signed in 2026-09-05. Device build verified: "Apple Development: Lorenzo Llamas", wildcard team profile, all four targets. Signing under team `GYFN949Q5E` — the same team as The-Llamas-Cookbook. |
| iCloud capability + container + Background Modes → Remote notifications | before sync works | Xcode UI and the developer portal. Flip `MOONLOG_CLOUDKIT` at the same time. |
| NFC Tag Reading on the App ID | before NFC | Developer portal. |
| `git push -u origin moonlog-ios` | whenever | Outward-facing, so it is the user's call. Nothing has left the machine. A local archive to TestFlight does not need it. |

## Open questions

- **Day 0 vs Day 1** for day-of-life. Currently clinical (birth day = Day 1),
  decided without an explicit answer. Visible in the handoff; one constant to change.
- Last-feed / last-diaper chips on the card are icon-only. Legible, but unverified as
  obvious at 3am.
