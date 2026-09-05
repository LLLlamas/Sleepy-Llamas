# Status

Updated 2026-09-05.

## Built

| Area | State |
|---|---|
| XcodeGen project, 4 targets | done |
| `MoonlogCore` — clock, day buckets, day-of-life, totals, reconciler | done, 49 tests |
| SwiftData models + CloudKit schema test | done, mutation-verified |
| `CareStore` write layer | done |
| Tonight screen — adaptive twins layout, timeline | done, runs on simulator |
| Baby rename + colour picker | done |
| Per-family volume unit, L/R breast feeds | done |
| Optional kinds (pump, medication, weight) | model only — no UI yet |
| User-defined note tags | model only — no UI yet |

91 tests green. Field encryption applied. Verified running in Night and Day themes.

## Next

1. **Log sheets** — Feed / Diaper / Sleep / Note. Tapping an action currently opens
   a placeholder. This is what makes the app usable.
2. Start-shift and onboarding flows (currently placeholders).
3. Edit and delete from the timeline.
4. History → trends → export.
5. NFC.

## Needs the user

| What | When | Why |
|---|---|---|
| **Sign in to Xcode with your Apple ID** | before any device build | **Blocking.** `security find-identity` reports zero signing identities and there are no provisioning profiles — Xcode has no account on this machine. Xcode → Settings → Accounts → **+** → Apple ID. Automatic signing does the rest. |
| iCloud capability + container + Background Modes → Remote notifications | before sync works | Xcode UI and the developer portal. Flip `MOONLOG_CLOUDKIT` at the same time. |
| NFC Tag Reading on the App ID | before NFC | Developer portal. |
| `git push -u origin moonlog-ios` | whenever | Outward-facing, so it is the user's call. Nothing has left the machine. A local archive to TestFlight does not need it. |

## Open questions

- **Day 0 vs Day 1** for day-of-life. Currently clinical (birth day = Day 1),
  decided without an explicit answer. Visible in the handoff; one constant to change.
- Last-feed / last-diaper chips on the card are icon-only. Legible, but unverified as
  obvious at 3am.
