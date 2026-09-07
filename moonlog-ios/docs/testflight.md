# TestFlight

The pipeline works end to end. This is the ritual and the build history, not a list
of things still to do — that lives in `docs/status.md`.

## The archive ritual

```bash
cd moonlog-ios
./scripts/archive.sh    # stamps, archives, and REFUSES a build with debug code in it
```

It stamps `project.yml` (the source of truth — **never `agvtool`**, see
`scripts/stamp-build.sh`), archives where Organizer can see it, and greps the Release
binary for debug-only markers. **Every new `#if DEBUG` launch hook has to be added to
that grep**, or it ships unguarded and the archive still reports clean. No test can
catch that; only the binary can be asked.

Run the reachability suite before archiving. `docs/status.md` says why.

## Uploading

Not through Organizer. `xcodebuild -exportArchive` with `destination: upload` does
the same thing from the command line and authenticates with the same Xcode account
session, so cloud-managed distribution signing works exactly as it does in the GUI —
**no App Store Connect API key is needed**, and there is none on this machine.

```bash
xcodebuild -exportArchive \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/<day>/<name>.xcarchive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath /tmp/export -allowProvisioningUpdates
```

`ExportOptions.plist` needs `method: app-store-connect`, `destination: upload`,
`teamID: GYFN949Q5E`, and — load-bearing — **`manageAppVersionAndBuildNumber:
false`**. Left true, Xcode rewrites the build number and breaks the Unix-timestamp
scheme `stamp-build.sh` depends on. The build number is a Unix timestamp so it always
increases, which App Store Connect requires.

With `destination: upload` no `.ipa` is left on disk, so verify the archive's own
binary rather than looking for an export.

## What every build is checked for

| Check | Expected |
|---|---|
| Debug-only markers in the Release binary | **0** — every launch-argument hook compiled out |
| Release build warnings | none |
| `ITSAppUsesNonExemptEncryption` | `false`, so export compliance never prompts |
| iCloud / CloudKit entitlement | **absent** — local-only, so the launch-crash trap cannot fire |

## Build history

All 0.1.0. Newest first.

| Build | Date | What it added |
|---|---|---|
| 1788793916 | 09-07 | Erase everything and start over (ships in Release — the only other way back to a first run is deleting the app, which loses the TestFlight build). Rename or remove a client family; reorder babies and put a removed one back. **Save moved to the bottom of every log sheet.** A feed logs on its time alone. **Past nights actually opens** — it pushed a dead destination in every earlier build. |
| 1788733948 | 09-06 | **The Note button, which did not exist in any earlier build** — `BabyStatusCard` declared `onNote`, `TonightView` passed a closure, and the row rendered three controls, so notes, note tags, temperature and the fever badge were unreachable. Appearance as Follow phone / Night / Deep Night. Feed minutes step by 5. Edit a birth date; remove a baby. Summary keeps the night just ended. |
| 1788712279 | 09-06 | The maroon gradient and night header; the switcher moved into Settings; History as its own screen; the tile's "since" on both states; "Ask before"; **every confirmation converted from `confirmationDialog` to `alert`** — the old ones presented as popovers with no Cancel. Tile toggles on tap, tinted by the baby's colour. (1788708510, same day, carries only the first three.) |
| 1788666101 | 09-05 | **The first build safe to work a real shift on.** No demo seed, no debug hooks. |
| 1788644622 | 09-05 | First upload. **Contains the demo seed** — `DEBUG` was defined in the Release configuration. Do not run a shift on it. That is why `archive.sh` greps the binary now. |
