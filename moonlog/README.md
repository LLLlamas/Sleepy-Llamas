# 🌙 Moonlog

An offline-first PWA for logging a newborn's feeds, diapers, sleep, and notes through
the night — fast, one-handed, and easy on the eyes in a dark nursery. Companion to the
Sleepy Llamas *Night Shift Field Guide*.

Built to the spec in [`../Doula-Research/moonlog-pwa-spec.md`](../Doula-Research/moonlog-pwa-spec.md),
restyled in the Sleepy Llamas **maroon** brand identity (dark maroon-black Night / Deep
Night for 3 a.m. use, blush/cream Day mode for prep reading).

## Stack

- **Vite + React + TypeScript**
- **vite-plugin-pwa** (Workbox) — auto-updating service worker, precached app shell
- **Dexie** + `dexie-react-hooks` (`useLiveQuery`) — reactive, offline IndexedDB storage
- **date-fns** — relative time + formatting
- Plain CSS variables (no Tailwind) — three themes via `html[data-theme]`

No backend. **All data stays on the device and is never transmitted.**

## Run

```bash
cd moonlog
npm install
npm run dev        # http://localhost:5179
```

> **Node 18 note:** Workbox 7.3+ requires Node ≥20. `package.json` pins
> `workbox-build`/`workbox-window` to **7.1.0** via `overrides` so the build works on
> Node 18. If you upgrade to Node 20+, you can drop those pins.

## Build & preview

```bash
npm run build      # generates icons, bundles, emits the service worker + manifest
npm run preview    # serve the production build (service worker active here, not in dev)
npm run typecheck  # tsc --noEmit
```

Icons are generated from `scripts/gen-icons.mjs` (a dependency-free PNG encoder using
Node's built-in `zlib`) into `public/icons/` on every `dev`/`build`.

## Deploy

Moonlog ships as a subpath of the existing Sleepy Llamas GitHub Pages site:

```
https://LLLlamas.github.io/Sleepy-Llamas/Moonlog/
```

`vite.config.ts` sets `base: '/Sleepy-Llamas/Moonlog/'` for builds (dev stays at `/`),
so the manifest `start_url`/`scope`, the service-worker scope, and every asset URL are
rooted there. The repo's GitHub Pages workflow
([`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)) builds the Astro site,
then builds Moonlog and copies it into `dist/Moonlog/` before publishing — one deploy,
two apps. It triggers on push to `main`.

> If the deploy path ever changes, update `BASE` in `vite.config.ts` (it flows to the
> manifest, SW scope, and asset URLs automatically).

## Install (iOS)

Open `https://LLLlamas.github.io/Sleepy-Llamas/Moonlog/` in Safari →
**Share → Add to Home Screen**. It then launches full-screen and works fully offline.
Settings shows whether persistent storage was granted (iOS may evict IndexedDB under
storage pressure; the app requests persistence on first run).

## Project layout

```
index.html              apple-touch-icon, status-bar meta, safe-area, pre-paint theme
vite.config.ts          vite-plugin-pwa + manifest + Google-Fonts runtime cache
scripts/gen-icons.mjs   generates 192/512/maskable-512/apple-touch-180 PNGs
src/
  main.tsx              providers (Settings, Now-tick, Toast)
  App.tsx               baby/shift lifecycle, tab nav, sheet routing
  db/{types,db,hooks}   Dexie schema + reactive queries + mutations
  lib/{time,units,summary,labels,haptics,id}
  state/{SettingsContext,NowContext,ToastContext}
  components/           StatusTiles, Timeline, QuickActions, TabBar, Header
    ui/                 Sheet, Chip, Stepper, Swatch
    sheets/             Feed, Diaper, Note, Sleep, TimeField, DeleteRow
  screens/              Onboarding, Tonight, Summary, Settings
  styles/{tokens,global}.css
```

## Safety & privacy

Non-medical by design — Moonlog records what happened; it does not diagnose, advise, or
alarm. The temperature fever-threshold highlight (100.4°F / 38°C) is a **visual cue
only**. All logs are local to the device.
