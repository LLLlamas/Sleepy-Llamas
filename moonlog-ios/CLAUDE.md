# Moonlog iOS — working agreement

Native SwiftUI + SwiftData rebuild of the Moonlog night-logging app, for a night
doula working across client families. Read `docs/` before changing architecture.

## Hard constraints

1. **This branch (`moonlog-ios`) must never reach `main`.** No merges, no PRs, and
   never manually dispatch `deploy.yml` against it. `main` builds the live Sleepy
   Llamas website plus the frozen PWA; an Xcode project landing there triggers a
   Pages deploy. `workflow_dispatch` can target any ref, so this is a discipline,
   not a guarantee the tooling enforces.
2. **Never touch `moonlog/` (the PWA) or anything else outside `moonlog-ios/`.**
   The PWA is frozen — no fixes, no features. It stays installed and readable until
   this app replaces it. `git status` should only ever show `moonlog-ios/`.
3. **Do not enable `MOONLOG_CLOUDKIT` until the iCloud capability actually exists.**
   See `docs/cloudkit.md` — getting this wrong crashes the app at launch with no
   catchable error.

## Commands

```bash
cd moonlog-ios
xcodegen generate                      # after ANY change to project.yml or new source dirs
xcodebuild -project Moonlog.xcodeproj -scheme Moonlog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

`Moonlog.xcodeproj` is generated and gitignored — never edit it, never commit it.
Adding a new `Sources/` subdirectory means adding it to `project.yml`; XcodeGen
errors on a source path that does not exist yet.

Device build (verifies signing):

```bash
xcodebuild -project Moonlog.xcodeproj -scheme Moonlog \
  -destination "generic/platform=iOS" -allowProvisioningUpdates build
```

Before archiving: `agvtool new-version -all $(date -u +%s)`. `CURRENT_PROJECT_VERSION`
must be a Unix timestamp or App Store Connect rejects the build, and `xcodegen
generate` resets it to a placeholder.

## Architecture rules

- **`MoonlogCore` is a separate framework and must stay free of SwiftData, SwiftUI
  and `Date.now`.** It cannot import the app, so it physically cannot reach a
  `@Model` type. Every calculation that broke in the web version lives there,
  operating on value types, tested without a container or a host app.
- **All writes go through `CareStore`.** A stray `context.insert` elsewhere bypasses
  the invariants CloudKit will not let the schema express. Reads may use `@Query`.
- **The actor never returns `@Model` objects.** They are not `Sendable`. Return
  `ShiftSummary`, `SleepSnapshot` and friends.
- **Never set `endAt`/`endedAt` directly** — use `close(at:)`, which keeps the
  denormalised `isOpen` flag honest.
- **Never attach an event by hand** — use `attach(to:baby:)`, the single place that
  keeps a relationship and its denormalised id in step.
- **Calendar arithmetic for calendar quantities, `TimeInterval` for physical
  durations, never multiply to cross a day boundary.** See `docs/testing.md`.

## Conventions

- Amounts stored in millilitres, durations in seconds. Round once, at display.
- Enum raw values are CloudKit wire format. Add cases; never rename one.
- Colour is never the only signal. See `docs/design.md`.
- Comments explain *why*, especially where the code looks odd — most oddities here
  are a CloudKit constraint or a bug being designed out.

## Docs

| File | What it covers |
|---|---|
| `docs/architecture.md` | Layers, data model, why each boundary exists |
| `docs/cloudkit.md` | Verified constraints and the launch-crash trap |
| `docs/design.md` | Palette, themes, twins layout, accessibility rules |
| `docs/testing.md` | Invariants, DST fixtures, mutation testing |
| `docs/decisions.md` | Decision log with rationale |
| `docs/status.md` | What is built, what is next, what needs the user |
