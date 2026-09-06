# Getting to TestFlight

**A first build shipped to TestFlight on 2026-09-05** — version 0.1.0, build
1788644622, signed `Apple Distribution: Lorenzo Llamas (GYFN949Q5E)` against the
explicit `com.sleepyllamas.moonlog` App Store profile. The pipeline works end to
end; everything below is about what the app still needs, not about shipping it.

Note what that build can and cannot do: it is **local-only** (no CloudKit — see
`docs/cloudkit.md`), and a logged entry **cannot be edited or deleted**. It is a
look-and-feel build, not one to run a real shift on.

## Hard blockers — the upload is rejected without them

| # | What | Who | Notes |
|---|---|---|---|
| 1 | ~~App icon~~ | **done** | Crescent reused from the PWA, opaque RGB (an alpha channel is rejected). Verified compiled into `Assets.car`. |
| 2 | ~~`PrivacyInfo.xcprivacy`~~ | **done** | Verified present in the built bundle. |
| 3 | ~~App Store Connect record~~ | **done** | Created 2026-09-05; build uploaded through it. |

## Functional blockers — it would upload, but could not be used

| # | What | Who |
|---|---|---|
| 4 | ~~Onboarding~~ | **done** |
| 5 | ~~Start shift / end shift / add baby~~ | **done** |

A cold start now walks: create family + first baby + unit → start shift → log →
end shift. "End shift" is in Tonight's overflow menu; add-baby moved to Settings ›
Babies, along with the client-family switcher — see `docs/decisions.md`.

## Should do before a real night, not strictly blocking

| # | What | Who |
|---|---|---|
| 6 | ~~Export compliance~~ | **done** — `ITSAppUsesNonExemptEncryption` declared. |
| 7 | Edit / delete from the timeline | me — a mis-logged entry still cannot be corrected. **The one I would want before a real night.** |
| 8 | ~~Family settings~~ | **done** — Settings tab covers the client family, babies, past nights, Deep Night, volume unit, optional kinds, note tags and storage mode. |
| 9 | ~~History and a shareable handoff~~ | **done** — past nights are their own screen under Settings › Past nights, reachable during a shift as well as after one, and each carries the handoff to share. |

## Deliberately still off

- **CloudKit sync — deferred, not pending.** The app runs local-only, which avoids
  the launch-crash trap entirely (`docs/cloudkit.md`). Schema encryption is already
  correct for the day it is switched on.

  An earlier version of this section called that "the main data-safety gap" on the
  grounds that there was "no backup or export of any kind". That was wrong: the
  store sits in `Library/Application Support` with nothing excluding it, so the
  phone's own backup carries it and a replaced phone restores it. The real
  remaining gap is narrower — deleting the app, and having no *re-importable*
  export of your own history. The handoff, text or keepsake, is a document for the
  parents rather than something the app can read back.
- **NFC.** Backlog. Needs the entitlement on the App ID and has no UI yet.

## Shipped — 0.1.0 (1788666101), the first build safe to work a shift on

Archived and **uploaded 2026-09-05**. Verified on the exact archive that was
packaged:

| Check | Result |
|---|---|
| Debug-only markers in the Release binary | **0** — all six launch-argument hooks compiled out |
| Release build warnings | none *at the time* — see the correction below |
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / `1788666101` |
| `ITSAppUsesNonExemptEncryption` | `false`, so export compliance never prompts |
| iCloud / CloudKit entitlement | **absent** — local-only, as decided, so the launch-crash trap cannot fire |

Unlike build 1788644622, this one carries no demo seed and is safe to run a real
shift on.

**Correction, 2026-09-06.** A Release build now emits four warnings, and they are
not new to today's work — `FeedEntry`, `DiaperEntry`, `NoteEntry` and `ExtraEntry`
declare `Sendable` conformance at the bottom of `TonightView.swift`, away from the
structs themselves, which Swift 6 will make an error. The "none" above was true when
it was written and is no longer a claim to rely on. Not fixed, because moving four
conformances is not a change to make in the same pass as a feature; it is on the
list in `docs/status.md`.

### How it was uploaded, for next time

Not through Organizer. `xcodebuild -exportArchive` with `destination: upload` in the
export options does the same thing from the command line and authenticates with the
same Xcode account session, so cloud-managed distribution signing works exactly as
it does in the GUI — no App Store Connect API key is needed, and there is none on
this machine.

```bash
xcodebuild -exportArchive \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/<day>/<name>.xcarchive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath /tmp/export -allowProvisioningUpdates
```

`ExportOptions.plist` needs `method: app-store-connect`, `destination: upload`,
`teamID: GYFN949Q5E`, and — load-bearing —
**`manageAppVersionAndBuildNumber: false`**. Left true, Xcode rewrites the build
number and breaks the Unix-timestamp scheme `stamp-build.sh` depends on.

With `destination: upload` no `.ipa` is left on disk, so verify the archive's own
binary rather than looking for an export.

## The archive ritual

```bash
cd moonlog-ios
./scripts/archive.sh    # stamps, archives, and verifies no debug code shipped
```

Then Xcode → Window → Organizer → Archives → Distribute App → App Store Connect.
Xcode creates the distribution certificate and profile on first archive.

**The 0.1.0 build shipped on 2026-09-05 contains the debug demo seed.** DEBUG was
defined in the Release configuration, so `#if DEBUG` code compiled in. Fixed by
moving `SWIFT_ACTIVE_COMPILATION_CONDITIONS` to per-configuration, and
`scripts/archive.sh` now fails the archive if any debug marker survives. Any future
build is clean; that one is not, which is another reason not to run a real shift on
it.

The build number is a Unix timestamp so it always increases, which App Store Connect
requires. **Do not use `agvtool`** — see `scripts/stamp-build.sh` for why it does not
work on this project.
