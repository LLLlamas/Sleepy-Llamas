# Moonlog — Night Logging PWA

**Working title:** Moonlog (a.k.a. *Sleepy-Llamas Nightlog*) · name is swappable.
**One line:** An offline-first PWA for logging a newborn's feeds, diapers, sleep, and notes through the night — fast, one-handed, and easy on the eyes in a dark nursery.
**Companion to:** the *Night Shift Field Guide* (same Sleepy-Llamas project, same nightlight aesthetic).
**This doc is:** an implementation spec to hand to Claude Code. Decisions are made, not left open — change anything you disagree with, but it's meant to be buildable as written.

---

## 1. The one constraint that drives everything

This app is used **at 3 a.m., one-handed, in the dark, by someone holding a baby and running on no sleep.** Every design decision serves that. Specifically:

1. **One-handed & thumb-reachable.** Primary actions live in the bottom third of the screen. Tap targets ≥ 56px.
2. **Dark & low-glare by default.** It must not wake the baby or blast the caregiver. A *Deep Night* mode goes dimmer still.
3. **Fast over complete.** Logging a feed or diaper is **1–2 taps** with smart defaults. Detail is optional.
4. **Offline-first.** It's a real PWA — works in airplane mode with zero network. Data is local and private (never transmitted).
5. **Glanceable.** The home screen answers the only questions that matter half-asleep: *when was the last feed? the last diaper? is the baby asleep right now?*

If a feature fights any of these five, cut it.

---

## 2. Core loop (the 3 a.m. cycle)

```
Baby stirs → open app (already on Tonight) →
  see "last feed 2h40m ago" → tap FEED →
  sheet: type defaults to last used, tap amount, SAVE (toast: "Feed logged 3:12 · Undo") →
  change diaper → tap DIAPER → Wet, SAVE →
  settle → tap SLEEP (toggle to "asleep", timer starts) →
  put phone down.
```

Whole loop should be doable in ~5 taps without looking hard at the screen.

---

## 3. Screens & components

Three tabs in a slim bottom nav: **Tonight · Summary · Settings**. On Tonight, the four quick-log buttons sit just above the nav, in the thumb zone.

### 3a. Tonight (home)

```
┌─────────────────────────────────┐
│ 🌙 Moonlog        Theo · Day 3   │  header: app + baby name + age-in-days
│ Shift 8:05p · 6h 12m             │  active-shift elapsed, live clock
├─────────────────────────────────┤
│  LAST FEED      LAST DIAPER      │  ← "since last" status tiles (the killer feature)
│   2h 40m          0h 48m         │     tabular numerals, update live
│  ───────────    ───────────      │
│  SLEEP                           │
│   Asleep · 1h 02m   [tap=woke]   │  ← shows running timer if a sleep session is open
├─────────────────────────────────┤
│  TIMELINE  (reverse chronological)│
│  • 3:12a  Bottle · formula 2oz   │  tap row → edit/delete
│  • 2:55a  Wet                    │
│  • 1:40a  Note: small spit-up    │
│  • 1:05a  Asleep → 2:50a (1h45m) │  sleep sessions render as a span
│  • …                             │
├─────────────────────────────────┤
│ [  FEED ] [DIAPER] [SLEEP] [NOTE]│  ← thumb-zone quick actions (open sheets)
│      Tonight   Summary   Settings │  ← slim bottom tab bar
└─────────────────────────────────┘
```

- **Status tiles** are the hero. The "last feed" tile gives a gentle **due-soon cue**: neutral under ~2h, warms toward amber as it crosses ~3h since last feed (configurable). Non-alarming, no sound, no popup — just color. (Mirrors the guide's "wake to feed every 2–3h until back to birth weight.")
- **Timeline** is a reactive list of the current shift's events, newest first. Each row: icon, time, one-line summary, relative age. Tap to edit or delete (with confirm).
- **Empty state:** "Quiet so far. Tap below to log the first feed."

### 3b. Quick-log sheets (bottom sheets that slide up)

Each is a focused sheet with a single big **Save** button at the bottom. `Esc`/swipe-down/back closes.

**Feed sheet**
- Time: defaults to **now**; `–5 / +5 min` steppers for "it happened a few minutes ago."
- Method chips: `Breast L` · `Breast R` · `Bottle — breastmilk` · `Bottle — formula`. **Defaults to last method used.**
- Amount stepper (shown for bottle): `+/- 0.5 oz` (or ml per Settings). Optional.
- Duration (optional, minutes). Note (optional).

**Diaper sheet**
- Time (default now).
- Contents chips: `Wet` · `Dirty` · `Both`.
- **Stool color swatches** (shown when Dirty/Both): visual swatches `Meconium (black)` · `Transitional (green-brown)` · `Green` · `Brown` · `Yellow/seedy`. This directly tracks the day-3 meconium → transitional → yellow progression from the guide.
- Note (optional).

**Note sheet**
- Free text.
- Quick tags: `Spit-up` · `Fussy` · `Jaundice watch` · `Pumped` · `Temp` · `+ custom`.
- If `Temp` selected → numeric field (°F/°C per Settings). Show a **visual flag** if ≥ 100.4°F / 38°C: highlight + small inline text "fever threshold — see escalation steps." **This is a visual cue only, never a diagnosis or instruction** (see §9).

**Sleep** is not a sheet — it's a **toggle** on the status tile: tap "Put down" to open a sleep session (timer starts); tap "Woke up" to close it. Long-press → manual session entry (start/end times) for back-filling.

**On every save:** brief toast "Feed logged · 3:12 · **Undo**" (auto-dismiss ~4s) + optional haptic (`navigator.vibrate(15)`). Undo removes the just-created record.

### 3c. Summary (handoff)

```
SHIFT SUMMARY — Theo, Day 3
8:05 PM – 6:40 AM

Feeds      6   (~14 oz total)
Diapers    8   (5 wet · 3 dirty)   stool: transitional → yellow
Sleep      7h 20m  across 5 stretches  (longest 2h 10m)
Notes      2

[ Copy summary ]   [ Share ]        ← clipboard + Web Share API
[ End shift & start fresh ]
```

- Totals computed from the shift's events/sessions.
- A clean chronological recap below the totals.
- **Copy / Share** produces the plain-text summary (template in §7) — this is the morning handoff to the parents and the bridge back to the field guide.
- **End shift** closes the current shift, archives it (recent shifts list), and starts a new empty one.

### 3d. Settings

- **Baby:** name, date & time of birth (drives "Day N" and age display). Support editing; v1 = single baby (see non-goals).
- **Units:** oz / ml.
- **Theme:** `Night` (default) · `Deep Night` (dimmer) · `Day`.
- **Feed default:** which method is pre-selected.
- **Due-soon threshold:** hours since last feed before the tile warms (default 3h).
- **Temperature unit & threshold display** (°F/°C) — info only.
- **Data:** export JSON · clear current shift · clear all (with confirms). Show "Storage: persistent ✓/✗" (see §8 iOS note).

---

## 4. Interaction & motion

- **Thumb zone:** all primary actions in the bottom ~40% of the viewport. Tab bar + quick actions never move on scroll.
- **Sheets:** slide up, dim the backdrop slightly. Honor `prefers-reduced-motion` (fade instead of slide).
- **Live timers:** a single app-level `now` tick (every 30s) drives all relative times and running sleep timer — don't spin up a timer per row.
- **Haptics:** light vibrate on save/undo (guard for unsupported browsers).
- **Toast + Undo:** every destructive or create action is undoable for a few seconds.
- **Wake Lock (optional, nice-to-have):** offer a "keep screen on" toggle during a feed via the Screen Wake Lock API; note Safari/iOS support is partial — degrade silently.

---

## 5. Visual design system (carry over from the field guide)

Same nightlight identity so the two pieces feel like one product.

**Fonts**
- Display / big numbers: **Fraunces** (use `font-variant-numeric: tabular-nums` so timer digits don't jump).
- UI / body: **Inter**.
- Micro-labels / data chips: a mono stack (`ui-monospace, 'JetBrains Mono', monospace`).

**Tokens** (define as CSS variables on `:root`, switch via `html[data-theme="…"]`):

```css
/* Night (default) */
--bg:#191512; --raised:#221d19; --raised2:#2b2421; --chip:#2f2723;
--ink:#f4ebe1; --soft:#cdbfb0; --faint:#9b8b7c;
--line:#39302a; --line-strong:#4a3e36;
--accent:#f0a868; --accent-deep:#cf8a4e; --accent-faint:#3a2c20;
--calm:#86b8a4;                 /* sleep/positive */
--warn:#e2925f;                 /* due-soon / caution */
--stop:#ef8a76;                 /* fever flag / destructive */

/* Deep Night — same hues, darker & dimmer for true 3 a.m. */
--bg:#0f0d0b; --raised:#161311; --ink:#e7dccd; --accent:#d8945a; /* …etc */

/* Day — warm paper for prep reading */
--bg:#f4efe6; --raised:#fffdf9; --ink:#241e1a; --soft:#5e5249;
--accent:#b9651b; --accent-deep:#9c530f; --calm:#3f7d68;
```

**Component feel:** rounded cards (12–16px radius), soft shadows, 1px warm borders, generous spacing, big readable type. Bottom sheets and tiles use `--raised`. Keep it calm — spend the one bit of boldness on the big status numerals.

---

## 6. Data model (TypeScript)

Amounts stored canonically in **mL**; convert for display (1 oz = 29.5735 mL; round display to nearest 0.5 oz). Times stored as ISO 8601 strings.

```ts
type ISO = string;

interface Baby {
  id: string;
  name: string;
  birthAt: ISO;            // for Day N + age
}

interface Shift {
  id: string;
  babyId: string;
  startedAt: ISO;
  endedAt?: ISO;
  caregiver?: string;
}

interface FeedEvent {
  id: string;
  shiftId: string;
  type: 'feed';
  at: ISO;
  method: 'breast-left' | 'breast-right' | 'bottle-breastmilk' | 'bottle-formula';
  amountMl?: number;       // bottle only
  durationMin?: number;
  note?: string;
  createdAt: ISO;
}

interface DiaperEvent {
  id: string;
  shiftId: string;
  type: 'diaper';
  at: ISO;
  contents: 'wet' | 'dirty' | 'both';
  stool?: 'meconium' | 'transitional' | 'green' | 'brown' | 'yellow';
  note?: string;
  createdAt: ISO;
}

interface NoteEvent {
  id: string;
  shiftId: string;
  type: 'note';
  at: ISO;
  text?: string;
  tags?: string[];         // 'spit-up' | 'fussy' | 'jaundice' | 'pumped' | 'temp' | custom
  tempF?: number;          // present if a temperature was logged
  createdAt: ISO;
}

type LogEvent = FeedEvent | DiaperEvent | NoteEvent;

// Sleep is a session, not a pair of events — cleaner totals + "asleep now?" check
interface SleepSession {
  id: string;
  shiftId: string;
  startAt: ISO;
  endAt?: ISO;             // open session => baby currently asleep
}
```

**Dexie schema:**

```ts
db.version(1).stores({
  babies:        'id',
  shifts:        'id, babyId, startedAt',
  events:        'id, shiftId, type, at',
  sleepSessions: 'id, shiftId, startAt',
});
```

**Derived queries (via `useLiveQuery`):**
- *Active shift* = the shift with no `endedAt`.
- *Since last feed* = `now − max(events where type='feed' && shiftId=active).at`.
- *Asleep now?* = an open `SleepSession` (no `endAt`) exists for the active shift.
- *Totals* = reduce events/sessions of the active shift.

---

## 7. Summary text template (copy / share output)

```
🌙 Night summary — Theo, Day 3
Shift: 8:05 PM – 6:40 AM (caregiver: Lorenzo)

FEEDS — 6 (~14 oz)
  8:30p  Bottle/formula 2oz
  11:05p Breast L (18m)
  1:40a  Bottle/breastmilk 2.5oz
  …
DIAPERS — 8 (5 wet, 3 dirty) · stool transitional → yellow
SLEEP — 7h 20m across 5 stretches (longest 2h 10m)
NOTES
  1:05a  Small spit-up after feed
  3:40a  Temp 99.1°F, content

— logged with Moonlog
```

Keep it plain text so it pastes cleanly into Messages / email / Notes.

---

## 8. PWA setup

**Stack** (decisive — matches your existing Vite/React comfort):
- **Vite + React + TypeScript**
- **`vite-plugin-pwa`** (Workbox under the hood) — `registerType: 'autoUpdate'`, generates SW + injects manifest
- **Dexie** + **`dexie-react-hooks`** (`useLiveQuery`) for reactive, offline, persistent storage
- **`date-fns`** for relative-time + formatting
- **Tailwind** (v4) *or* plain CSS modules — either is fine; if Tailwind, wire the tokens above into the theme and keep component classes thin. (Plain CSS variables + a small `ui/` component set also works and matches the guide 1:1.)
- No router needed for 3 tabs — a tiny `view` state or `react-router` with 3 routes; pick whichever is simpler.
- **No backend in v1.**

**`manifest`:**
```jsonc
{
  "name": "Moonlog",
  "short_name": "Moonlog",
  "description": "Night logging for newborn care",
  "start_url": "/",
  "display": "standalone",
  "orientation": "portrait",
  "background_color": "#191512",
  "theme_color": "#191512",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

**Service worker:** precache the built app shell (Workbox default). There's no API to cache — data lives in IndexedDB — so runtime caching is minimal.

**iOS specifics (you ship iOS, so call these out):**
- Add `<meta name="apple-mobile-web-app-capable" content="yes">`, `apple-mobile-web-app-status-bar-style` (black-translucent), and an `apple-touch-icon` (180×180). iOS ignores the manifest icon for the home screen.
- iOS install = Share → *Add to Home Screen* (no install prompt). Add a tiny one-time hint for iOS users.
- **Request persistent storage** on first run: `await navigator.storage?.persist()` — iOS may evict IndexedDB under storage pressure; surface the result in Settings.
- Add safe-area padding (`env(safe-area-inset-bottom)`) so the bottom nav clears the home indicator.

---

## 9. Safety & privacy (keep consistent with the guide)

- **Non-medical by design.** The app records what happened; it does not interpret, advise, or alarm. The fever-threshold highlight on a temp entry is a **visual cue only** — copy must never tell the user what to do medically. (Optionally link to the field guide's escalation steps; don't replicate medical instructions.)
- **No medication dosing feature** — meds, if noted at all, are free text only.
- **Local & private.** All data stays on the device; nothing is transmitted. State this plainly in Settings — it's a genuine feature for handling an infant's data.
- **No reminders/alarms in v1.** This is a logger, not a feed-timer with notifications (see non-goals).

---

## 10. Build plan (phased — ship each phase testable)

**Phase 1 — Shell + PWA.** Vite+React+TS, `vite-plugin-pwa`, manifest + icons, theme tokens (Night/Deep Night/Day), bottom tab nav, empty Tonight screen.
*DoD: installs to home screen on iOS & Android; opens and renders fully offline; theme toggle works.*

**Phase 2 — Data layer.** Dexie schema + hooks; create a baby in Settings; start/active-shift logic; persistent-storage request.
*DoD: a baby + shift survive a hard reload; "Day N" computes correctly.*

**Phase 3 — Logging.** Feed / Diaper / Note sheets, Sleep toggle (sessions), reactive timeline, toast + undo, edit/delete.
*DoD: all four types log one-handed in ≤2 taps; timeline updates live; undo works.*

**Phase 4 — Glance.** Status tiles with live relative timers + running sleep timer + due-soon color cue; single app-level tick.
*DoD: tiles update without reload; due-soon warms past the threshold.*

**Phase 5 — Summary & share.** Totals, recap, copy + Web Share, end-shift/archive, recent-shifts list.
*DoD: copied summary matches the §7 template and pastes cleanly.*

**Phase 6 — Polish.** Settings complete (units/theme/threshold), haptics, reduced-motion, safe-area, a11y pass (focus, contrast AA in dark), empty states, optional wake lock.
*DoD: all acceptance criteria (§11) pass.*

---

## 11. Acceptance criteria (overall definition of done)

- [ ] Installable PWA; **fully functional offline** after first load.
- [ ] Data **persists** across reloads and app restarts (IndexedDB).
- [ ] Log a feed / diaper / note in **≤ 2 taps** from Tonight; sleep is a **1-tap** toggle.
- [ ] Status tiles show **time since last feed / diaper** and **current sleep state**, updating live.
- [ ] Due-soon cue warms past the configured threshold (no sound/popup).
- [ ] **Copy/Share** produces a clean plain-text night summary.
- [ ] **Dark/Deep-Night default**, AA contrast, `prefers-reduced-motion` respected, safe-area handled.
- [ ] Everything reachable **one-handed** in the thumb zone; targets ≥ 56px.
- [ ] No network calls; data never leaves the device.

---

## 12. Out of scope for v1 (don't build yet)

Accounts/auth · cloud sync / multi-device · multiple concurrent caregivers · multiple babies (single baby in v1; schema already supports more) · cross-night charts & analytics · **push notifications / feed alarms** · medical interpretation of any kind · voice input.

---

## 13. Phase-2 ideas (note, don't build)

Recent-shifts history with simple trends (feeds/day, sleep totals) · optional gentle "due soon" local nudge · CSV export · multi-baby switcher · optional Supabase sync for a second caregiver (you already use Supabase) · share a read-only summary link.

---

## 14. Handoff notes for Claude Code

Suggested structure:

```
moonlog/
  index.html                  (apple-touch-icon, status-bar meta, safe-area)
  vite.config.ts              (vite-plugin-pwa config + manifest)
  public/icons/               (192, 512, maskable-512, apple-touch-180)
  src/
    main.tsx
    App.tsx                   (theme provider + tab nav + now-tick)
    db/{db.ts, hooks.ts, types.ts}
    lib/{time.ts, units.ts, summary.ts}
    components/
      StatusTiles.tsx  Timeline.tsx  QuickActions.tsx  TabBar.tsx
      sheets/{FeedSheet,DiaperSheet,NoteSheet,SleepToggle}.tsx
      ui/{Sheet,Chip,Stepper,Swatch,Toast}.tsx
    screens/{Tonight,Summary,Settings}.tsx
    styles/{tokens.css, global.css}
```

Suggested kickoff for Claude Code:
> "Build Phase 1 of the Moonlog spec: scaffold Vite + React + TS with vite-plugin-pwa, add the manifest + placeholder icons, implement the three theme tokens via `html[data-theme]`, and stub the Tonight screen with the bottom tab bar and four quick-action buttons in the thumb zone. Make it installable and offline-capable, then stop so I can verify before Phase 2."

Build phase by phase; verify the PWA installs and runs offline before adding data, and keep the five constraints in §1 as the tie-breaker for any decision.
