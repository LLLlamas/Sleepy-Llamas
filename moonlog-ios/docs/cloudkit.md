# CloudKit

Sync is to the user's own private database. All schema constraints below were
**verified by probe on this machine**, not taken from documentation.

**The code side is finished.** The app already asks for a CloudKit store when — and
only when — the build says the entitlement is there, and degrades visibly rather
than crashing when it is not. What is left is entitlement work in Xcode and the
developer portal that only the user can do, plus one genuine code gap described
under [Before switching it on](#before-switching-it-on).

## What the code already does

`Sources/App/ModelContainerFactory.swift` is the whole gate; nothing else in the app
mentions CloudKit.

- `cloudKitContainerID` is `"iCloud.com.sleepyllamas.moonlog"`. The container created
  in the portal must match that string character for character — one string in three
  places (the Swift constant, the entitlements file, the portal), no drift.
- `hasCloudKitEntitlement` is `#if MOONLOG_CLOUDKIT` and nothing else. It is a
  compile flag rather than a runtime check for the reason in
  [Why there is no runtime probe](#why-there-is-no-runtime-probe).
- `make(syncEnabled:)` opens `ModelConfiguration(schema:cloudKitDatabase:)` with
  `.private(cloudKitContainerID)` only when both the flag and the settings toggle
  allow it. If that initialiser *throws* — a full iCloud account is reported here —
  it logs and falls back to a **local on-disk** store. Deliberately on-disk, not
  in-memory: a CloudKit problem should cost sync, never the night's logs. Only if
  the on-disk store itself refuses to open does it drop to memory, and that is
  logged as a fault and shown in Settings with a warning.
- `Mode` — `.syncing`, `.localOnly(reason:)`, `.inMemory(reason:)` — is surfaced in
  Settings → Data as **Storage** ("iCloud" / "On this device" / "In memory"), so a
  misconfiguration is visible rather than silent. An earlier comment claimed Settings
  showed this before Settings existed; it does now.

> The row directly under it is still `LabeledContent("Sync", value: "Off — this
> device only")` — a hardcoded string, not `Mode`. Once the flag is flipped, Storage
> will read "iCloud" while Sync still reads "Off". Cosmetic, but confusing at exactly
> the moment you are trying to tell whether sync came up. It belongs to whoever next
> touches `SettingsView`, not to this document.

## Switching it on — the checklist

Steps 1–4 are Apple-side and are yours to do. **Step 6 must come last**, because the
flag without the entitlement is the launch crash described below, and the entitlement
without the flag is an app that silently never syncs.

1. **Add the iCloud capability to the App ID.** Xcode → the `Moonlog` target →
   Signing & Capabilities → `+ Capability` → **iCloud**, or the same thing in the
   developer portal under Identifiers → `com.sleepyllamas.moonlog`. Tick the
   **CloudKit** service. (iCloud Documents and Key-value storage are not needed and
   are worth leaving off — see the note about `ubiquityIdentityToken` below.)
2. **Create the container `iCloud.com.sleepyllamas.moonlog`.** Xcode's `+` button in
   the iCloud capability will offer to make one; make sure the identifier is exactly
   that, not the default it proposes from the bundle id. Verify against
   `ModelContainerFactory.cloudKitContainerID`.
3. **Add Background Modes → Remote notifications.** Without it SwiftData never
   receives the silent pushes that drive incoming sync, and it presents as "sync only
   works when I open the app". In a generated project this checkbox needs care — see
   [Where Xcode's checkboxes go to die](#where-xcodes-checkboxes-go-to-die).
4. **Let the provisioning profile be reissued.** The entitlement is baked into a
   profile at issue time, so a profile issued before the capability signs without it
   and CloudKit fails at runtime rather than at build. With automatic signing, the
   device build in `CLAUDE.md` (`-allowProvisioningUpdates`) normally handles this.
   *This is in-house experience from the sibling apps, not something re-probed here.*
5. **Make the entitlement durable in `project.yml`** — next section. Skipping this
   means it works until the next `xcodegen generate` and then quietly stops.
6. **Add `MOONLOG_CLOUDKIT` to both `configs:` entries** of the `Moonlog` target:

   ```yaml
   configs:
     Debug:
       SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG MOONLOG_CLOUDKIT
     Release:
       SWIFT_ACTIVE_COMPILATION_CONDITIONS: MOONLOG_CLOUDKIT
   ```

   **Never in `settings.base`.** Base applies to Release too — that is precisely how
   `DEBUG` leaked into a shipped build and put a fake twin night in TestFlight.
   `scripts/archive.sh` greps the Release binary for `moonlogSeedDemo` /
   `moonlogOpenSheet`, so it guards the `DEBUG` leak specifically and will not object
   to `MOONLOG_CLOUDKIT` being present in Release, which is where it belongs.
7. **`xcodegen generate`, then build to a real device**, then check Settings → Data →
   Storage reads **iCloud**. If it reads "On this device", the container request never
   succeeded and the reason is in the `com.sleepyllamas.moonlog` `data` log category.
   Do not conclude anything from the simulator here.

## Where Xcode's checkboxes go to die

`Moonlog.xcodeproj` is generated and gitignored. Anything Xcode's Signing &
Capabilities editor writes *into the project file* is discarded by the next
`xcodegen generate` — and because that command is run after almost every change,
"it worked yesterday" is the expected symptom.

What survives, and what does not:

| Thing | Survives a regenerate? | Why |
|---|---|---|
| App ID capability, CloudKit container | yes | They live on Apple's servers, not in the repo. |
| A `Moonlog.entitlements` file Xcode writes to disk | yes | It is a real file in the working tree. |
| The `CODE_SIGN_ENTITLEMENTS` setting pointing at it | **no** | Written into the pbxproj. |
| The Background Modes checkbox | **no** (see below) | Written into the pbxproj / a generated plist. |

**Entitlements — the pattern is settled elsewhere in this account.** Both
`Our-Fitness` and `The-Llamas-Cookbook` keep a hand-written `.entitlements` file in
the repo and point at it with a `CODE_SIGN_ENTITLEMENTS` build setting in
`project.yml`, and both carry a comment warning against XcodeGen's `entitlements:`
block, which writes an empty plist over the file on every generate and silently signs
with only the four default keys. Do the same here: keep whatever Xcode writes (or
hand-write it), move it somewhere sensible such as `Resources/Moonlog.entitlements`,
and add to the `Moonlog` target's `settings.base`:

```yaml
CODE_SIGN_ENTITLEMENTS: Resources/Moonlog.entitlements
```

The file needs `com.apple.developer.icloud-container-identifiers` containing
`iCloud.com.sleepyllamas.moonlog` and `com.apple.developer.icloud-services`
containing `CloudKit`.

**Background Modes — unresolved, and I have not verified the fix.** Moonlog builds
with `GENERATE_INFOPLIST_FILE: YES` and has no `Info.plist` in the repo; every plist
value it sets comes from an `INFOPLIST_KEY_*` build setting. I checked the installed
Xcode's build-setting specifications for a key that would carry this, and there is
**no `INFOPLIST_KEY_UIBackgroundModes`** — the list includes
`INFOPLIST_KEY_NFCReaderUsageDescription`, `INFOPLIST_KEY_UIRequiredDeviceCapabilities`
and so on, but nothing for background modes. So the value has to arrive some other
way. Two candidate routes, **neither tried in this project**:

- XcodeGen's target-level `info:` block, which generates a plist at a path you name
  and can carry arbitrary properties including
  `UIBackgroundModes: [remote-notification]`. This interacts with
  `GENERATE_INFOPLIST_FILE`, and how the existing `INFOPLIST_KEY_*` settings merge
  (or fail to merge) once a plist file is in play is exactly the part I have not
  verified.
- A checked-in `Info.plist` referenced by `INFOPLIST_FILE`, which is what both
  sibling apps do — `The-Llamas-Cookbook/ios-native/Resources/AppInfo.plist` carries
  `UIBackgroundModes → remote-notification` for this same reason. It means migrating
  the existing `INFOPLIST_KEY_*` values into the file.

Whichever route is taken, **prove it from the built product**, not from the project
navigator: build, then read `UIBackgroundModes` back out of the `Info.plist` inside
`Moonlog.app`. The failure mode is silent — the app runs, sync appears to work while
you are watching it, and only pulls changes when you open it.

## The launch-crash trap

> Requesting a CloudKit-backed store without the iCloud entitlement **does not
> throw.** `ModelContainer(for:configurations:)` returns successfully, and CloudKit
> then traps asynchronously on a background queue inside
> `PFCloudKitContainerProvider containerWithIdentifier:`. The app dies a moment
> after launch with `EXC_BREAKPOINT` / SIGTRAP and no catchable error.

A `do/catch` around the initialiser cannot see this. We hit it for real, which is why
the `catch` in `ModelContainerFactory.make` reads as if it does nothing useful: it
catches the *other* failures, such as a full iCloud account.

So the app **must not request CloudKit unless the entitlement is present**, which is
exactly what `MOONLOG_CLOUDKIT` gates.

## Why there is no runtime probe

`SecTaskCopyValueForEntitlement` is not public on iOS, so the app cannot ask what it
was signed with. The obvious proxy, `FileManager.ubiquityIdentityToken`, keys off the
iCloud **Documents** entitlement rather than CloudKit — for a CloudKit-only build it
reports `nil`, and using it would disable sync forever on a correctly configured app.
Hence a compile flag, and hence the discipline about flipping it at the same moment as
the capability.

## Before switching it on

**One screen has no way to learn about a change that arrives from another device.**

`TonightView` derives everything it draws from the shift's relationship arrays
(`shift.events`, `shift.sleepSessions`) rather than from a `@Query`. `CareStore` is a
`@ModelActor` writing through its own context, so the main context's copies of those
arrays are a merge behind, and SwiftUI has nothing to observe that reliably changes.

That is handled for **local** writes: `TonightView` holds an explicit
`@State private var refreshToken`, bumps it after every successful write and after
Undo, and reads it in `body` by passing it into `Tonight(generation:)`, whose sole
purpose for that field is to make the derived value differ. Before it existed the job
was being done by accident — the confirmation banner's `@State` happened to mutate
about two seconds after each write — and deleting the banner would have silently
stopped the timeline updating.

**A change arriving from another device bumps nothing.** No local write happens, so
no token changes, so the screen keeps showing what it showed. Summary and History
read through `@Query` and may well behave better, but that has not been checked
either, and Tonight is the screen someone is actually looking at during a shift.

The usual mechanism is Core Data's `NSPersistentStoreRemoteChange` notification —
SwiftData sits on Core Data, so the notification is still what the CloudKit mirroring
machinery posts when it merges a remote transaction. **This is not implemented here
and not verified here.** Nothing in `Sources/` imports `CoreData` today, and no part
of the claim in this paragraph has been tested against this app.

Treat the following as a direction to investigate, not as code to paste:

```swift
// UNVERIFIED SKETCH — not compiled, not run, not tested in this project.
// The notification name, the queue it arrives on, whether the app must set
// NSPersistentStoreRemoteChangeNotificationPostOptionKey when SwiftData owns the
// store description, and whether the main context has already merged by the time it
// fires are ALL open questions.
.onReceive(NotificationCenter.default.publisher(
    for: .NSPersistentStoreRemoteChange)) { _ in
        refreshToken &+= 1
    }
```

Whatever shape it takes, it has to be proved with **two real devices signed into the
same iCloud account**: log a feed on one, watch the other's Tonight screen without
touching it. A simulator pair and a single-device test both pass without exercising
the thing that is broken. Until that test has actually been run, sync is a backup
mechanism, not a live shared view — which is fine, but say so rather than assuming.

## Verified schema constraints

Re-checked against `Sources/Models/` and `Tests/MoonlogTests/SchemaCloudKitCompatibilityTests.swift`.

| Rule | Verdict | Evidence |
|---|---|---|
| `@Attribute(.unique)` / `#Unique` | **Rejected** | "CloudKit integration does not support unique constraints" |
| Relationships must be optional | **Required** | store refuses to load otherwise |
| Relationships must *have* an inverse | **Required** | but need not be *declared* — inference works |
| Non-optional attribute needs a default | **Required, and it must be INLINE** | a value assigned in `init` is not enough; only a property initialiser populates `Schema.Attribute.defaultValue` |
| `.deny` delete rule | **Rejected** | "The following relationships are configured with unsupported delete rules" |
| `.cascade` delete rule | **Accepted** | loads fine — but not atomic across devices, so tolerate a transiently `nil` parent |

The models hold to all six: no `unique` appears anywhere in `Sources/Models/` outside
the comment explaining its absence; every relationship is an optional array declared
`= []` with an explicit inverse; every non-optional attribute carries an inline
default (`var isOpen: Bool = true`, `var startedAt: Date = Date.distantPast`); and the
only delete rules in use are `.cascade` (`Family` → babies, shifts, tagBindings,
noteTags; `Shift` → events, sleepSessions) and `.nullify` (`Baby` → events,
sleepSessions, so deleting a baby cannot destroy logged history — attribution
survives on `babyIDRaw`).

Note the last row contradicts the comment in
`The-Llamas-Cookbook/ios-native/Sources/App/LlamasCookbookApp.swift`, which says
cascade is rejected. It is not.

`SchemaCloudKitCompatibilityTests` asserts most of these mechanically — uniqueness,
optional-or-default, relationship-optional, `.deny`, the exact model set, and the
encrypted-field set. Two rows are **not** covered by a test: that every relationship
*has* an inverse, and that `.cascade` is accepted. The suite exists so that a future
property CloudKit cannot mirror fails a test instead of surfacing months later as a
store that silently refuses to open. It has been mutation-verified.

## Consequences baked into the design

- No uniqueness → identity is an app-minted `UUID`, deduplicated explicitly.
- No `.deny` → a baby is archived, never deleted, enforced in `CareStore`.
- Sync can produce **two open sleep sessions for one baby** and no schema constraint
  can prevent it. `SleepReconciler` repairs this deterministically, so two devices
  reconciling the same set reach the same answer instead of fighting.
- Enum raw values are wire format. `EventKind`, `EventSource`, `StoolColor` and
  `TagAction` have **no `unknown` case**, so a raw value written by a newer build is
  read by an older one as the accessor's fallback — `.note`, `.manual`, `.logDiaper`.
  `FeedMethod` and `DiaperContents` do have one. Worth knowing before adding a case.

## Irreversible, decide before the schema reaches production

- ~~**Field-level encryption**~~ — **applied 2026-09-05.** Nine fields, matching the
  set pinned in the test: `Family.name`, `Baby.name`, `Baby.birthAt`,
  `Shift.caregiver`, `LogEvent.text`, `LogEvent.tempF`, `LogEvent.medicationName`,
  `LogEvent.doseText`, `LogEvent.weightGrams`. `Baby.birthAt` **is** encrypted despite
  being a timestamp — it identifies a child and is never filtered on. Everything
  queried — event times, enums, ids, flags — stays in the clear.

  An encrypted field must be *newly introduced*; an existing one can never be
  converted, and encrypted fields cannot be indexed. A second test asserts that
  nothing the app queries or sorts on is encrypted. Both were mutation-verified.
- **The schema is additive-only in production.** No renames, no deletions, no type
  changes. Adopt `@Attribute(originalName:)` if a Swift property ever needs renaming.
  This bites hardest on anything new — see `docs/next-features.md`, where both NFC and
  the Watch app want fields the schema does not have yet.
