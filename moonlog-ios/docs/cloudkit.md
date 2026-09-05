# CloudKit

Sync is to the user's own private database. All constraints below were **verified by
probe on this machine**, not taken from documentation.

## The launch-crash trap

> Requesting a CloudKit-backed store without the iCloud entitlement **does not
> throw.** `ModelContainer(for:configurations:)` returns successfully, and CloudKit
> then traps asynchronously on a background queue inside
> `PFCloudKitContainerProvider containerWithIdentifier:`. The app dies a moment
> after launch with `EXC_BREAKPOINT` / SIGTRAP and no catchable error.

A `do/catch` around the initialiser cannot see this. We hit it for real.

So the app **must not request CloudKit unless the entitlement is present**, which is
what `MOONLOG_CLOUDKIT` in `project.yml` gates.

**Flip the flag at the same time as adding the capability in Xcode.** One without
the other either crashes at launch (flag on, capability off) or silently never syncs
(capability on, flag off).

A runtime probe is not possible: `SecTaskCopyValueForEntitlement` is not public on
iOS, and the `ubiquityIdentityToken` proxy keys off the iCloud *Documents*
entitlement, so it reports false for a CloudKit-only build and would disable sync
forever.

## Verified schema constraints

| Rule | Verdict | Evidence |
|---|---|---|
| `@Attribute(.unique)` / `#Unique` | **Rejected** | "CloudKit integration does not support unique constraints" |
| Relationships must be optional | **Required** | store refuses to load otherwise |
| Relationships must *have* an inverse | **Required** | but need not be *declared* — inference works |
| Non-optional attribute needs a default | **Required, and it must be INLINE** | a value assigned in `init` is not enough; only a property initialiser populates `Schema.Attribute.defaultValue` |
| `.deny` delete rule | **Rejected** | "The following relationships are configured with unsupported delete rules" |
| `.cascade` delete rule | **Accepted** | loads fine — but not atomic across devices, so tolerate a transiently `nil` parent |

Note the last row contradicts the comment in
`The-Llamas-Cookbook/ios-native/Sources/App/LlamasCookbookApp.swift`, which says
cascade is rejected. It is not.

`SchemaCloudKitCompatibilityTests` asserts every one of these mechanically, so a
future property that CloudKit cannot mirror fails a test instead of surfacing months
later as a store that silently refuses to open. It has been mutation-verified.

## Consequences baked into the design

- No uniqueness → identity is an app-minted `UUID`, deduplicated explicitly.
- No `.deny` → a baby is archived, never deleted, enforced in `CareStore`.
- Sync can produce **two open sleep sessions for one baby** and no schema constraint
  can prevent it. `SleepReconciler` repairs this deterministically, so two devices
  reconciling the same set reach the same answer instead of fighting.

## Irreversible, decide before the first TestFlight build

- **Field-level encryption.** An encrypted field must be *newly introduced* — an
  existing field can never be converted — and encrypted fields cannot be indexed.
  Recommendation: encrypt `Baby.name`, `Family.name`, `Shift.caregiver`,
  `LogEvent.text`, `LogEvent.tempF`. Leave timestamps, enums and ids in the clear so
  trends stay queryable.
- **The schema is additive-only in production.** No renames, no deletions, no type
  changes. Adopt `@Attribute(originalName:)` if a Swift property ever needs renaming.

## Also required for sync to work

- iCloud capability with a CloudKit container.
- **Background Modes → Remote notifications.** Without it, SwiftData never receives
  the silent pushes that drive incoming sync, and it presents as "sync only works
  when I open the app".
