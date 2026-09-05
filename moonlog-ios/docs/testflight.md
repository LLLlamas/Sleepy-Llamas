# Getting to TestFlight

Status as of 2026-09-05. Signing and encryption are done; these are what remain.

## Hard blockers — the upload is rejected without them

| # | What | Who | Notes |
|---|---|---|---|
| 1 | ~~App icon~~ | **done** | Crescent reused from the PWA, opaque RGB (an alpha channel is rejected). Verified compiled into `Assets.car`. |
| 2 | ~~`PrivacyInfo.xcprivacy`~~ | **done** | Verified present in the built bundle. |
| 3 | **App Store Connect record** | **you — the only remaining blocker** | An app record for `com.sleepyllamas.moonlog` under team `GYFN949Q5E`. Nothing can be uploaded until it exists. |

## Functional blockers — it would upload, but could not be used

| # | What | Who |
|---|---|---|
| 4 | ~~Onboarding~~ | **done** |
| 5 | ~~Start shift / end shift / add baby~~ | **done** |

A cold start now walks: create family + first baby + unit → start shift → log →
end shift. Add-baby and end-shift live in the Tonight toolbar.

## Should do before a real night, not strictly blocking

| # | What | Who |
|---|---|---|
| 6 | ~~Export compliance~~ | **done** — `ITSAppUsesNonExemptEncryption` declared. |
| 7 | Edit / delete from the timeline | me — a mis-logged entry cannot yet be corrected, only the sleep session can. **This is the one I would want before a real night.** |
| 8 | Family settings — optional kinds, note tags | me — the volume unit is now set during onboarding, but the optional event kinds and note tags are still seed-only. |

## Deliberately NOT before the first TestFlight build

- **CloudKit sync.** Needs the iCloud capability, a container, Background Modes →
  Remote notifications, and `MOONLOG_CLOUDKIT` flipped. The app runs local-only
  until then, which is a fine first build and avoids the launch-crash trap
  (`docs/cloudkit.md`). Schema encryption is already correct for when it is enabled.
- **NFC.** Needs the entitlement on the App ID and has no UI yet.

## The archive ritual

```bash
cd moonlog-ios
xcodegen generate
agvtool new-version -all $(date -u +%s)   # MUST be a timestamp; xcodegen resets it
```

Then archive in Xcode (Product → Archive) and upload. Xcode creates the
distribution certificate and profile on first archive.

`CURRENT_PROJECT_VERSION` must be a Unix timestamp — every shipped Cookbook build
uses that scheme, so App Store Connect rejects anything lower.
