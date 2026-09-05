# Getting to TestFlight

Status as of 2026-09-05. Signing and encryption are done; these are what remain.

## Hard blockers — the upload is rejected without them

| # | What | Who | Notes |
|---|---|---|---|
| 1 | **App icon** | me | There is no asset catalog at all. App Store Connect rejects an upload with no icon. Needs a 1024×1024 and an `AppIcon` set wired via `ASSETCATALOG_COMPILER_APPICON_NAME`. |
| 2 | **`PrivacyInfo.xcprivacy`** | me | Apple has auto-rejected submissions without a privacy manifest since 2024-05-01. Must declare required-reason API use. Moonlog's is short — no analytics, no third-party servers, data stays in the user's own iCloud. |
| 3 | **App Store Connect record** | **you** | An app record for `com.sleepyllamas.moonlog` under team `GYFN949Q5E`. Nothing can be uploaded until it exists. |

## Functional blockers — it would upload, but could not be used

| # | What | Who |
|---|---|---|
| 4 | **Onboarding** — add a family and a baby | me |
| 5 | **Start shift** — currently a placeholder, so a cold start dead-ends | me |

Without these the app installs and shows "No family yet". Everything else is
reachable only through the debug seed.

## Should do before a real night, not strictly blocking

| # | What | Who |
|---|---|---|
| 6 | Export-compliance declaration (`ITSAppUsesNonExemptEncryption`) | me — otherwise App Store Connect asks on every single upload. CloudKit field encryption uses Apple's own crypto, which is exempt. |
| 7 | Edit / delete from the timeline | me — a mis-logged entry currently cannot be corrected. |
| 8 | Family settings — volume unit, optional kinds, note tags | me — all three are modelled but reachable only via the demo seed. |

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
