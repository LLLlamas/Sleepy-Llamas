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

## Website Consulting Update November 2026

The website now leads with Catalina's whole-family consulting experience: parent
and nanny questions, newborn/postpartum support, siblings and changing routines,
home visits, and family-specific caregiver coaching. Overnight services remain
available in a secondary section with their existing package prices.

`src/config/services.ts` is the shared catalogue for service cards, inquiry choices
and structured data. `src/config/faqs.ts` supplies both the visible FAQ and its
structured data. Following the owner's subsequent request to raise rates, the
local catalogue now uses the following starting rates. These are premium launch
choices to validate through paid bookings, not rates established by market demand.

| Service | Starting rate | Included appointment time |
| --- | --- | --- |
| Family Life Consultation | $175 | 60 minutes |
| Newborn & Postpartum Consultation | $250 | 60 minutes |
| First Weeks Together | $450 | 60 minutes plus two 20-minute calls over 14 days |
| First Days Home Visit | $550 | Three hours plus a 20-minute follow-up |
| Nanny & Caregiver Coaching | $595 | Three hours plus a 20-minute check-in |
| Family follow-up | $65 | 20 minutes |
| Newborn/postpartum follow-up | $95 | 20 minutes |
| Additional home-support visit | $450 | Three hours, existing clients |

The free 15-minute fit call and existing overnight package prices are retained.
The first-weeks package is $10 above its $440 of standalone calls; it also includes
the updated written plan and two email question rounds. Do not describe it as a
discount bundle. The earlier comparison memo records the lower draft rates that
were current when researched; it is historical analysis, not the price source.
See `Doula-Research/rate-comparison-analysis-2026-11-15.txt` for that comparison.

The owner confirmed on November 15 that Catalina's postpartum doula certification
is complete. The public DoulaMatch profile still calling her a student is
outdated; reconcile it with the current status when updating that listing. Keep
eight years of overall family-care experience distinct from years in postpartum
doula practice. No external directory changes have been made from this chat.

The earlier SEO/client-acquisition audit is saved in
`Doula-Research/seo-client-acquisition-strategy-2026-11-15.txt`. Its live HTTP
checks found that the existing directory's lowercase project path returns 404,
while `/Sleepy-Llamas/` returns 200. The live site still has the older positioning
and custom-domain canonical; local fixes are not yet deployed. The first proposed
commercial routes are newborn/postpartum consultations, nanny/caregiver coaching,
and first-days-home visits. Those routes are now implemented locally as described
below. No directory, DNS, Google or advertising accounts have been changed.

### Service Pages And SEO November 16

The three commercial routes are implemented with distinct researched content in
`src/content/` and the shared `src/layouts/ServicePage.astro`:

- `/newborn-postpartum-consultations/`
- `/nanny-caregiver-coaching/`
- `/first-days-home-visit/`

Research memos are the November 16 newborn, caregiver and home-visit files in
`Doula-Research/`. They include current competitors/agencies, adjacent services,
recent professional articles and public parent questions; anecdotes are not
measured demand or customer endorsements. All approved catalogue rates remain.

`src/config/serviceRoutes.ts` supplies crawlable navigation/card/footer links.
Each page has unique metadata, its own visible questions and written deliverable,
and an inquiry form preselected to the service/format. Switching to a remote fit
call clears the in-person requirement. Extra-home-visit links preserve that
context in editable inquiry notes without replacing existing notes.

`src/lib/seo.ts` builds one Organization/Person/WebSite/WebPage/Service graph with
stable identities; service pages add breadcrumbs. Deprecated ProfessionalService
and retired FAQ rich-result markup are no longer emitted. The visible FAQs remain.
The site has a generated XML sitemap, consistent canonical/social URLs, a local
brand sharing image, a descriptive homepage title, and skip links. No project-path
robots file pretends to control the GitHub hostname root. No analytics service or
third-party tracking was installed; the saved-inquiry hook exposes only service ID.

See [PUBLISHING.md](PUBLISHING.md) for the current readiness evidence and activation
steps. A public read-only inspection found existing Supabase configuration in the
live bundle, but the project endpoint failed DNS from this environment. Its
database/migration and email-delivery status therefore remain unverified. Local
production variables, Supabase credentials/CLI, and GitHub CLI authentication were
unavailable; do not equate that with proof that GitHub has no stored secrets.

Consultation inquiries use `src/lib/inquiries.ts` and the separate
`consultation_inquiries` table, not overnight reservations. Success requires a
matching saved receipt; failures retain fields and offer a user-sent email draft.
Requests have basic server validation, anonymous write limits and idempotent retries.
Only a saved request is confirmed; owner email delivery is a separate outcome.

### Production Activation

The owner requested GitHub publication with Supabase deferred. The default
`PUBLIC_INQUIRY_MODE=email` validates the form and opens a draft for the parent to
review and send. It does not save online or claim submission. The overnight
calendar is hidden in favor of a direct inquiry without contacting the deferred backend. GitHub Actions
uses email mode unless repository variable `PUBLIC_INQUIRY_MODE` is set to `online`;
Supabase credentials are injected only in online mode.

Before enabling online mode:

1. Apply `supabase/migrations/202611160001_consultation_inquiries.sql` after the
   existing schema and service migration. The owner can review inquiries in the
   Supabase dashboard. This does not add a new website admin inbox.
2. Apply `supabase/migrations/202611160002_public_availability_privacy.sql` so the
   existing public calendar RPC returns status without family names or care notes.
3. Set the existing public Supabase URL and anon key in the build environment.
   GitHub Actions reads `PUBLIC_SUPABASE_URL` and
   `PUBLIC_SUPABASE_ANON_KEY` secrets in online mode. No local production credentials were available.
4. Verify the existing owner notification relay: `app_config`, `pg_net`, and
   the `send-email` function's server-side SMTP/shared-secret settings. Check
   `owner_notification` and `notification_request_id`; queued is not delivered.
5. Verify a real saved inquiry and owner notification, check the deployed domain
   and links, and confirm actual availability and service terms before promotion.

The static deployment remains the existing GitHub Pages configuration. Canonical
URLs now derive from Astro's configured site and base path, rather than assuming
the custom domain is active. No hosting migration was performed.

Unverified phone, WhatsApp and Venmo values are hidden. Add real business details
to `site.ts` when ready. A real founder portrait and consented client references
remain useful next assets; no likeness or endorsements were fabricated.

### Website Checks

Run `npm run build`, `npx --no-install tsc --noEmit`, and with the verified local
Node 26 runtime `node --test tests/inquiries.test.ts`. The SQL suites under
`tests/` exercise validated inserts, retries, anonymous restrictions, and public
calendar privacy in an isolated disposable PostgreSQL database. Browser checks
cover package preselection, missing-backend errors with retained fields, mobile
navigation and responsive layout. Live production delivery is not verified.

Also run `npm run check:site` for the six-page link/metadata/sitemap/form audit and
`bash tests/run-database-checks.sh` for reproducible disposable SQL checks.
GitHub Actions now runs `npm run check:publish -- --verify-api` before its build
and `npm run check:site` after it. In online mode publication fails if the public
configuration is missing/private-key-shaped or the read-only API schema lacks the inquiry RPC.
This guard submits no inquiries and does not establish SMTP delivery. Local
builds remain available without production configuration for review.

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
