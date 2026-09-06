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
   catchable error. It goes in **both** `configs:` entries in `project.yml`, never
   in `settings.base` — anything in `base` applies to Release too.

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

To archive for TestFlight:

```bash
./scripts/archive.sh    # stamps, archives, and REFUSES a build with debug code in it
```

It lands the archive where Organizer can see it and greps the Release binary for
debug-only markers. That guard exists because the demo seed once shipped inside a
TestFlight build — see the note on `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in
`project.yml`. No test can catch that; only the binary can be asked.

**Do not use `agvtool`.** It writes into the generated `.xcodeproj`, so the next
`xcodegen generate` discards it — and because our Info.plist is generated, it also
fails with `Cannot find "Moonlog.xcodeproj/../YES"`. The script stamps `project.yml`,
which is the source of truth and is committed.

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
  denormalised `isOpen` flag honest. One deliberate exception: the reconciler in
  `CareStore` re-opens a session by clearing both fields together, since there is
  no `reopen()`.
- **Never attach an event by hand** — use `attach(to:baby:)`, the single place that
  keeps a relationship and its denormalised id in step. Its `baby` is optional only
  because `pump` is about the mother; `CareStore` still refuses a baby-less record
  of any kind that `EventKind.attachesToBaby` covers.
- **Time rules are invariants, so they live in the actor.** Future-blocking and the
  shift-overlap rule are in `CareStore`, not in the sheets. `LogSheetChrome` shows
  the same advisories as you type, but that is a courtesy to the thumb — it is not
  the enforcement, and it does not apply to a non-view caller.
- **A write returns the action that reverses it.** `TonightView.perform` is the one
  path every write takes, and an action returning `nil` is one that cannot be
  undone — no Undo button is offered rather than one that quietly does nothing.
  Undoing a delete restores the record's own id and `createdAt`; re-logging would
  mint a lookalike.
- **Calendar arithmetic for calendar quantities, `TimeInterval` for physical
  durations, never multiply to cross a day boundary.** See `docs/testing.md`.
- **Never declare `.navigationDestination` inside a `Form`, `List` or any other
  lazy container.** It is not registered until the row containing it has been
  built, so a push that fires first lands on a blank screen with a working back
  button. Put it on the container. Cost when this was learned: one screenshot.

## Conventions

- Amounts stored in millilitres, durations in seconds. Round once, at display.
- Enum raw values are CloudKit wire format. Add cases; never rename one.
- Colour is never the only signal. See `docs/design.md`.
- **Every palette value is pinned by a WCAG contrast test.** Adding a role or
  changing a surface means `PaletteTests` has to pass first — the previous
  "contrast-checked" claim was documentation, not enforcement, and the Day theme
  had been failing five pairs the whole time.
- **The page base is `.moonBackground(_:)`, never `.background(palette.bg)`.**
  One gradient, described once.
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
| `docs/testflight.md` | Release readiness and what shipped |
| `docs/app-store-connect.md` | The one-off App Store Connect setup (done) |
| `docs/next-features.md` | NFC and Apple Watch — scope, open questions, what needs the user |

## One client family at a time

The app has a single selected household. **Switching it, adding one, and adding a
baby all live in Settings**, not on Tonight — Tonight is for logging, and a mode
change does not belong next to the buttons pressed forty times a night. The
client-family picker must stay at the **root** of the Settings stack; see the
constraint in `docs/design.md`.
