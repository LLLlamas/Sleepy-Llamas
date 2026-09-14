# TestFlight

The pipeline works end to end. This is the ritual and the build history, not a list
of things still to do — that lives in `docs/status.md`.

## The ritual

```bash
cd moonlog-ios
./scripts/ship.sh            # guards, both suites, archive, upload
./scripts/ship.sh --skip-ui  # skip the ~6-minute reachability suite
./scripts/ship.sh --no-upload
```

One command, in order: it refuses to run off `moonlog-ios` or with anything changed
outside `moonlog-ios/`, runs the unit suite and the reachability suite, then
`archive.sh` and `upload.sh`. Every step prints a line while it works and filters its
own log — a raw `xcodebuild` log must never reach a terminal or an agent's context.
The logs are kept beside the archive.

**It does not write the release note or the commit.** Both are prose; a script
guessing them is worse than a script leaving them.

### archive.sh

Stamps `project.yml` (the source of truth — **never `agvtool`**, see
`scripts/stamp-build.sh`), archives where Organizer can see it, and refuses an
archive that fails any check below. A failed archive is deleted, its log renamed
`.failed.log`, and **`project.yml` is put back** — no build number is burned by a
build that never shipped.

The debug-marker list is **derived from the source**, not maintained by hand: an
`awk` pass collects `"moonlogXxx"` literals inside `#if DEBUG` regions. It used to be
a hard-coded list, and it had already drifted — `moonlogTab` was never added to it.
Adding a new hook now needs no bookkeeping. The derivation must stay non-empty and a
superset of the nine original markers, or the script fails rather than passing
vacuously.

### upload.sh

```bash
./scripts/upload.sh                       # newest archive
./scripts/upload.sh path/to/one.xcarchive
```

Not through Organizer. `xcodebuild -exportArchive` with `destination: upload` does
the same thing from the command line and authenticates with the same Xcode account
session, so cloud-managed distribution signing works exactly as it does in the GUI —
**no App Store Connect API key is needed**, and there is none on this machine. It
refuses an archive with no build log beside it, because that archive was not the one
`archive.sh` checked.

`ExportOptions.plist` needs `method: app-store-connect`, `destination: upload`,
`teamID: GYFN949Q5E`, and — load-bearing — **`manageAppVersionAndBuildNumber:
false`**. Left true, Xcode rewrites the build number and breaks the Unix-timestamp
scheme `stamp-build.sh` depends on. `archive.sh` now catches that before the upload
rather than after, by comparing the archive's `CFBundleVersion` to the stamp.

With `destination: upload` no `.ipa` is left on disk, so verify the archive's own
binary rather than looking for an export.

## What every build is checked for

All four are **enforced by `archive.sh`**, not remembered.

| Check | Expected |
|---|---|
| Debug-only markers in the Release binary **and the embedded `MoonlogCore`** | **0** — every launch-argument hook compiled out |
| Release build warnings | none — matched on the diagnostic shape, so `appintentsmetadataprocessor` chatter does not count |
| `ITSAppUsesNonExemptEncryption` | `false`, so export compliance never prompts |
| iCloud / CloudKit entitlement | **absent** — local-only, so the launch-crash trap cannot fire |

## Where the time actually goes

Measured, so the next person optimising this starts from numbers:

| Step | Wall clock |
|---|---|
| `xcodebuild archive` | **~12 s** |
| Unit suite (224 tests) | **~1 s** of testing |
| Reachability suite (31 tests) | **~5m50s** — the whole cost of a ship |
| Upload + App Store Connect processing | Apple's; no lever here |

The compile is not the bottleneck and never was. The suite is, because every test
launches the app; `--skip-ui` is the only lever and it costs the thing the suite
exists for.

## Build history

All 0.1.0. Newest first.

| Build | Date | What it added |
|---|---|---|
| 1789218659 | 09-12 | **Every logged record carries its time**, and a sleep says start → wake → length rather than a bare duration — on the timeline and in both handoff documents. **Summary carries the full log** under the totals. Diapers, weighings and pump sessions are listed individually where they used to be counts. **Save answers on the whole bar** — it was hit-testing at 38×20pt, the size of the word. The tile's moon and sun drift for a few seconds and then settle instead of moving all night; the moon's resting frame was recomposed. Also the card and diaper glyph work from 09-07. Check: end a night, read the log on Summary and the shared page against each other; tap Save at its left edge. |
| 1788796092 | 09-07 | **The clock at the top of Tonight now matches the status bar** — same minute, same rollover, same zone. Check it against the phone's own clock at a minute boundary. The eyebrow is the family name alone; "on since" is gone. |
| 1788793916 | 09-07 | Erase everything and start over (ships in Release — the only other way back to a first run is deleting the app, which loses the TestFlight build). Rename or remove a client family; reorder babies and put a removed one back. **Save moved to the bottom of every log sheet.** A feed logs on its time alone. **Past nights actually opens** — it pushed a dead destination in every earlier build. |
| 1788733948 | 09-06 | **The Note button, which did not exist in any earlier build** — `BabyStatusCard` declared `onNote`, `TonightView` passed a closure, and the row rendered three controls, so notes, note tags, temperature and the fever badge were unreachable. Appearance as Follow phone / Night / Deep Night. Feed minutes step by 5. Edit a birth date; remove a baby. Summary keeps the night just ended. |
| 1788712279 | 09-06 | The maroon gradient and night header; the switcher moved into Settings; History as its own screen; the tile's "since" on both states; "Ask before"; **every confirmation converted from `confirmationDialog` to `alert`** — the old ones presented as popovers with no Cancel. Tile toggles on tap, tinted by the baby's colour. (1788708510, same day, carries only the first three.) |
| 1788666101 | 09-05 | **The first build safe to work a real shift on.** No demo seed, no debug hooks. |
| 1788644622 | 09-05 | First upload. **Contains the demo seed** — `DEBUG` was defined in the Release configuration. Do not run a shift on it. That is why `archive.sh` greps the binary now. |
