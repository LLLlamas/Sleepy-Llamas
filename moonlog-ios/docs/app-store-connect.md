# Creating the App Store Connect record

The one remaining blocker on a TestFlight upload, and the only one that cannot be
done from the command line. About ten minutes.

Facts you will need:

| Field | Value |
|---|---|
| Bundle ID | `com.sleepyllamas.moonlog` |
| Team | `GYFN949Q5E` (same team as The-Llamas-Cookbook) |
| Device display name | Moonlog |
| Current version | 0.1.0 |

---

## Step 1 — Register the explicit App ID

**Do this first.** Signing currently resolves through a *wildcard* profile
(`iOS Team Provisioning Profile: *`), which means no explicit App ID exists yet —
and App Store Connect's Bundle ID dropdown only lists explicit ones. Skip this and
step 2 has nothing to select.

1. [developer.apple.com/account](https://developer.apple.com/account) →
   **Certificates, Identifiers & Profiles** → **Identifiers** → **+**
2. **App IDs** → Continue → **App** → Continue
3. Description: `Moonlog`
4. Bundle ID: select **Explicit**, enter `com.sleepyllamas.moonlog`
5. **Capabilities: leave everything off for now.** iCloud and NFC come later, with
   the code that needs them — see `docs/cloudkit.md` for why enabling iCloud early
   crashes the app at launch.
6. Continue → Register

## Step 2 — Create the app record

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+**
   → **New App**
2. **Platforms:** iOS
3. **Name:** app names are unique across the entire App Store, so plain "Moonlog"
   may be taken. If it is rejected, use something like `Moonlog — Night Log`. This
   name is **separate** from the name on the device, which stays "Moonlog" via
   `CFBundleDisplayName` — so a longer store name costs nothing.
4. **Primary Language:** English (U.S.)
5. **Bundle ID:** `com.sleepyllamas.moonlog` — the one registered in step 1
6. **SKU:** any internal string, never shown to anyone. `moonlog-ios` is fine.
7. **User Access:** Full Access
8. Create

## Step 3 — Archive and upload

```bash
cd moonlog-ios
./scripts/stamp-build.sh    # stamps the build number AND regenerates the project
open Moonlog.xcodeproj
```

In Xcode: select **Any iOS Device** as the destination → **Product → Archive** →
**Distribute App** → **App Store Connect** → **Upload**.

> **If an archive does not appear in Organizer**, it was almost certainly built with
> a custom `-archivePath`. Organizer only reads
> `~/Library/Developer/Xcode/Archives/<YYYY-MM-DD>/`. Copy the `.xcarchive` into
> today's folder there and reopen Organizer — it scans on load. Archiving from
> Xcode's own Product → Archive always lands in the right place.

Xcode creates the *distribution* certificate and profile itself at this point. Only
a development certificate exists today; that is expected and nothing to fix in
advance.

## Step 4 — TestFlight

1. App Store Connect → your app → **TestFlight**
2. The build appears after processing (a few minutes; you get an email)
3. **Internal Testing** → add yourself as a tester

Internal testing needs **no Beta App Review** and no App Privacy answers, so this is
the fast path to the phone. Both are required only for *external* testers and for
App Store submission.

Export compliance will not prompt — `ITSAppUsesNonExemptEncryption` is already
declared `NO` in the build.

---

## Gotchas worth knowing

- **Build numbers must always increase.** `CURRENT_PROJECT_VERSION` is a Unix
  timestamp for exactly this reason. Use `./scripts/stamp-build.sh`, which stamps
  `project.yml` and regenerates in the right order. **`agvtool` does not work here**
  — it writes into the generated `.xcodeproj` (discarded on the next regenerate) and
  fails with `Cannot find "Moonlog.xcodeproj/../YES"` because our Info.plist is
  generated rather than a file on disk.
- **A build cannot be deleted, only expired.** An accidental upload burns that
  timestamp; the next one is simply higher, so it does not matter much.
- **Do not enable iCloud on the App ID yet.** The app requests CloudKit only when
  `MOONLOG_CLOUDKIT` is set, and the two must be turned on together.
