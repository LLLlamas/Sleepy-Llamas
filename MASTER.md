# Sleepy Llamas Master

This is the working source of truth for the Sleepy Llamas repo. Keep current
implementation notes here, and keep older Markdown files short so details do
not drift.

## Repo Map

| Area | Path | Purpose |
| --- | --- | --- |
| Website | `src/`, `public/`, `astro.config.mjs` | Sleepy Llamas Astro site. |
| Moonlog | `moonlog/` | Offline-first newborn night-logging PWA. |
| Booking reference | `calendar-booking-system.md` | Archived technical notes for the older Dogs & Llamas calendar/booking flow. |
| Doula research | `Doula-Research/` | Research/source material and archived Moonlog product brief. |
| Deploy | `.github/workflows/deploy.yml` | Builds the Astro site, then builds Moonlog into `dist/Moonlog/`. |

## Current Branch

Moonlog iteration is happening on `moonlog-work`.

## Moonlog Product

Moonlog is an offline-first PWA for logging newborn feeds, diapers, sleep, and
notes through a night shift. It is designed for a tired caregiver using one hand
in a dark room.

Core principles:

- One-handed first: primary actions stay in the bottom thumb zone.
- Low glare: Night and Deep Night are first-class themes.
- Fast over exhaustive: common logs should take only a couple taps.
- Offline and private: IndexedDB local storage, no backend, no network data sync.
- Glanceable: the home screen answers last feed, last diaper, and current sleep state.

## Moonlog Stack

- Vite, React, TypeScript.
- `vite-plugin-pwa` with Workbox for installable/offline app shell.
- Dexie and `dexie-react-hooks` for local reactive IndexedDB storage.
- `date-fns` for formatting and relative time.
- Plain CSS variables and custom CSS in `moonlog/src/styles/`.
- Self-hosted variable fonts via `@fontsource-variable/fraunces` and `@fontsource-variable/inter`.

## Moonlog Commands

```bash
cd moonlog
npm install
npm run dev
npm run typecheck
npm run build
npm run preview
```

Dev defaults to Vite port `5179` in `vite.config.ts`. In this desktop thread the
preview has also been run at `http://127.0.0.1:5174/` when needed.

## Moonlog Deploy

Production Moonlog lives under the GitHub Pages subpath:

```text
https://LLLlamas.github.io/Sleepy-Llamas/Moonlog/
```

`moonlog/vite.config.ts` uses `base: '/Sleepy-Llamas/Moonlog/'` for production
builds. The Pages workflow installs root dependencies, builds the Astro site,
installs Moonlog dependencies, builds Moonlog, and copies `moonlog/dist/` into
`dist/Moonlog/`.

## Moonlog Current UX

### Tonight

- Header shows Moonlog, baby name/day, centered current date/time, and an
  awake/asleep state pill.
- The sleep status tile is first and spans the full tile grid.
- Sleep status tile content is center-aligned with a centered accent mark.
- Sleep tile copy uses the entered baby name, such as `Luna is asleep`.
- The sleep tile uses a soft left-to-right glow using the current state color:
  blue/calm while asleep, gold/accent while awake.
- Last feed and Last diaper show the entry time as the large value.
- The small text shows relative age, such as `12 mins ago`.
- Last feed also includes duration when present, such as `18 min feed`.
- The Last feed tile warms near and beyond the configured due-soon threshold.
- Timeline entries are editable. Tap an event or sleep row to edit/delete.
- The old separate `Add past sleep` button is removed because sleep entries can
  be edited from the timeline.

### Quick Actions

- Docked actions: Feed, Diaper, Sleep/Awake, Note.
- The sleep action reflects the current state clearly.
- Tap sleep while awake to start a sleep session.
- Tap sleep while asleep to log wake time.
- Long-press the sleep action to back-fill or manually add a sleep session.

### Logging Sheets

- Feed, diaper, note, and sleep logging use timestamps only.
- Date pickers are reserved for shift context and baby birthday.
- Feed duration is minutes-only, capped at 60 minutes, with a scroller instead
  of plus/minus controls.
- Sleep duration uses hour/minute scrollers and time inputs for asleep/woke.
- Create actions show a brief undo toast for about 1.8 seconds.
- Non-undo confirmation toasts are shorter.

### Summary

- Summary top area shows the current date and current time.
- Badge says `EDIT`.
- Copy says `Shift started at ...`.
- Totals include feeds, diaper counts, stool progression, sleep, and notes.
- The handoff text is editable before copy/share.
- Ending a shift archives the current shift and starts a new one.

### Settings

- Baby name.
- Date and time of birth. This input is sized for mobile screens.
- Caregiver for the current shift.
- Theme: Night, Deep Night, Day.
- Amount units: oz or ml.
- Temperature unit display.
- Default feed method.
- Due-soon threshold.
- Keep screen awake when supported.
- Storage persistence status/request.
- Export JSON.
- Clear current shift or all data.

## Moonlog Data Model

Times are stored as ISO strings. Bottle amounts are stored canonically in mL and
converted for display.

```ts
interface Baby {
  id: string;
  name: string;
  birthAt: string;
}

interface Shift {
  id: string;
  babyId: string;
  startedAt: string;
  endedAt?: string;
  caregiver?: string;
}

type LogEvent = FeedEvent | DiaperEvent | NoteEvent;

interface SleepSession {
  id: string;
  shiftId: string;
  startAt: string;
  endAt?: string;
}
```

Dexie stores:

```ts
db.version(1).stores({
  babies: 'id',
  shifts: 'id, babyId, startedAt',
  events: 'id, shiftId, type, at',
  sleepSessions: 'id, shiftId, startAt',
});
```

## Moonlog File Map

| Path | Notes |
| --- | --- |
| `moonlog/src/App.tsx` | Main app shell, baby/shift lifecycle, tab/sheet routing. |
| `moonlog/src/components/Header.tsx` | Tonight header with current date/time and state pill. |
| `moonlog/src/components/StatusTiles.tsx` | Sleep, last feed, and last diaper tiles. |
| `moonlog/src/components/QuickActions.tsx` | Docked feed/diaper/sleep/note actions. |
| `moonlog/src/components/Timeline.tsx` | Editable reverse chronological event/session list. |
| `moonlog/src/components/sheets/` | Feed, diaper, note, sleep, time, delete controls. |
| `moonlog/src/components/ui/DurationScroller.tsx` | Shared wheel-style duration picker. |
| `moonlog/src/screens/Tonight.tsx` | Home screen composition. |
| `moonlog/src/screens/Summary.tsx` | Editable handoff, copy/share, end shift. |
| `moonlog/src/screens/Settings.tsx` | Baby, shift, display, persistence, data controls. |
| `moonlog/src/db/` | Dexie schema, types, hooks, mutations. |
| `moonlog/src/lib/` | Time, labels, units, summary, haptics, wake lock helpers. |
| `moonlog/src/state/` | Settings, now tick, toast providers. |
| `moonlog/src/styles/` | Tokens and global component styling. |

## Moonlog Design Notes

- Use calm, tactile, non-generic visual treatments.
- Keep cards tight and readable, with real hierarchy.
- Avoid marketing-page patterns in the app surface.
- Preserve stable dimensions for tiles, dock actions, icon buttons, and wheels.
- Respect `prefers-reduced-motion`.
- Avoid adding new decorative systems unless they clarify state or reduce friction.
- The asleep/awake treatment should make state obvious without feeling alarming.

## Safety And Privacy

- Moonlog records care events. It does not diagnose, advise, or alarm.
- Temperature threshold styling is a visual cue only.
- No medication dosing features.
- No accounts, cloud sync, or network data transmission in v1.
- Export is explicit JSON download from the local device.

## Website And Booking Notes

The root Astro app is the Sleepy Llamas website. The older booking system notes
are kept as an archive because they document a separate Supabase-backed flow:

- Static frontend.
- Supabase Postgres tables and RPCs.
- PIN-gated admin actions.
- Supabase Edge Function email relay through Gmail SMTP.
- Manual Venmo/Zelle handoff.

Do not treat the booking reference as Moonlog architecture. Moonlog currently
has no backend.

## Documentation Policy

- Update this `MASTER.md` first for current project state.
- Keep `README.md` as a short repo entry point.
- Keep `moonlog/README.md` as a short Moonlog entry point that points here.
- Keep archived docs clearly marked as historical.
- Avoid duplicating long specs across multiple Markdown files.
