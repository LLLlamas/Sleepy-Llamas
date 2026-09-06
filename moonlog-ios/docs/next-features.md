# Next features: NFC tags and a Watch app

Scoping, not a plan of record. **Neither feature is started** — there is no NFC code
and no watchOS target. Both sit behind everything in `docs/status.md`'s ordered list,
which is mostly about not losing or misreporting data; these two are about making a
correct app faster to use.

What follows is what someone would need to know before starting: what the codebase
already carries, what it does not, what only the user can do, and the questions that
have to be answered before any of it is worth writing. Where a claim is a guess, it
says so.

---

# NFC tags

The shape is: a sticker on the changing table, a sticker on the bassinet, tap the
phone against one and the entry is logged without hunting for a button in the dark.

## What already exists

More than you would expect. The data model was built for this from the start.

- **`EventSource`** (`Sources/Core/Snapshots.swift`) has `manual` and
  `nfcTag = "nfc-tag"`. Its docstring already states the rule the UI will have to
  honour: *"A tag scan never writes silently, but recording the source makes a
  mis-scan traceable."*
- **`LogEvent` carries the provenance**: `sourceRaw` (defaulting to `manual`) and
  `sourceTagToken: String?`, a free-text token identifying which physical tag was
  read.
- **`CareStore.logEvent` already takes `source: EventSource = .manual`**, and its
  `configure:` closure is where `sourceTagToken` would be set. A tag-sourced event can
  be written today with no change to the writer and no change to the schema.
- **Undo preserves it.** `EventRestoration` carries `source` and `sourceTagToken`, and
  `restoreEvent` puts the original record back rather than logging a lookalike —
  precisely so an undone-and-restored scan does not become a manual entry.
  `CareStoreTests` asserts this, with the comment "the source is what makes a mis-scan
  traceable".
- **`TagBinding`** (`Sources/Models/CareRecords.swift`) is a full `@Model`:
  `tagToken`, `label`, `actionRaw`, `targetBabyIDRaw`, and a `family` relationship
  cascading from `Family.tagBindings`. It is in `ModelContainerFactory.schema` and in
  the seven-model set that `SchemaCloudKitCompatibilityTests` pins by name — so it
  already syncs, and already satisfies the CloudKit constraints.
- **`TagAction`**: `toggle-sleep`, `log-feed`, `log-diaper`.
- **The time rules are in the right place.** `CareStore.rejectFuture` and
  `requireOverlap` sit in the actor, and the comment above them names "an NFC tap" as
  exactly the kind of non-sheet caller they exist for. A scan cannot log into the
  future or outside the shift, without the feature having to remember to check.

## What is missing

Everything above the model layer. Nothing imports Core NFC; `TagBinding` is
referenced only by the schema list, the `Family` relationship and the schema test.
Nothing creates, reads, edits or deletes one, and `CareStore` has no tag-binding
methods at all.

Concretely absent:

- A reader session, and if tags are to carry app-minted tokens, an NDEF **write**
  session too. Two different APIs with two different failure modes.
- A binding editor — Settings has sections for volume unit, optional kinds and note
  tags, and nothing for tags.
- A scan entry point on Tonight.
- **The mapping from `TagAction` to a `CareStore` call, which is the actual design
  problem.** `toggleSleep(shiftID:babyID:at:)` takes exactly what a `toggle-sleep`
  binding holds, so that case is clean. The other two are not: a diaper logged with no
  contents is a diaper of unknown contents (`DiaperContents.unknown` exists, so this is
  at least expressible), but **a feed logged with no method and no amount contributes
  0 ml to the night's totals and appears in the handoff as a feed of nothing**. The
  handoff goes to the parents. That is the question to settle before writing any code.
- **`TagBinding.targetBabyIDRaw` has no relationship beside it.** Elsewhere the
  denormalised-id idiom always pairs a raw id with a real relationship kept in step by
  `attach` — here the raw id stands alone, so nothing prevents a binding naming a baby
  from another family, or one that has since been archived. A scan against a stale
  binding needs a defined behaviour, and "log it against a baby who is not in this
  shift" is not it.
- **`TagAction` has no `unknown` case**, so `TagBinding.action` falls back to
  `.logDiaper` for any raw value it does not recognise. See the CloudKit note below.

## What the user must do

| # | What | Where | Why |
|---|---|---|---|
| 1 | Add **NFC Tag Reading** to the App ID | Developer portal → Identifiers → `com.sleepyllamas.moonlog`, or Xcode's capability editor | Nothing is testable on device without it. Already listed in `docs/status.md`. |
| 2 | Regenerate the provisioning profile afterwards | Automatic signing usually handles it | The entitlement is baked into the profile at issue time. |
| 3 | Buy tags | — | NTAG21x stickers are the usual choice for iPhone read/write. Which type matters if tokens are to be *written*; for read-only UID binding, almost anything works. |

Two build-configuration notes, one verified and one not:

- **Verified**: `INFOPLIST_KEY_NFCReaderUsageDescription` *is* a real build setting in
  the installed Xcode, so the usage string (the prompt shown when a scan starts) can go
  straight into `project.yml` alongside the other `INFOPLIST_KEY_*` values. No
  `Info.plist` migration needed for this one.
- **Not verified**: the NFC entitlement itself. It is written into the entitlements
  file, keyed on formats (NDEF and/or TAG) — I have not checked the exact key or values
  against this SDK, and did not want to write a plausible-looking string into a
  document. Let the portal and Xcode generate it, then read the file. It will live in
  the same hand-written entitlements file CloudKit needs; see `docs/cloudkit.md`.

Core NFC is device-only — there is no reader in the simulator — so this feature has no
meaningful unit-test story above the mapping layer. Test the `TagAction` → `CareStore`
routing without a scanner, and accept that the session handling gets exercised by hand.

## Not in scope: background reading

`docs/decisions.md`, 2026-09-05, dropped it for v1 on two independent grounds: it
cannot log silently (iOS always shows a notification to tap, and a locked phone must be
unlocked first, so the delta over "open app, tap Scan" is small), and the
`apple-app-site-association` file cannot be served from our URL, which was probed live
and 404s. Nothing here reopens that. Everything above assumes foreground scanning.

## Open questions, before any code

1. **What does a `log-feed` tap actually record?** A feed with no amount is a lie in
   the totals; a feed that opens a prefilled sheet is honest but is barely faster than
   the button already on screen. Possible answers: restrict v1 bindings to
   `toggle-sleep` and `log-diaper`; or have a feed tap open the sheet with the baby
   preselected. Both are defensible; guessing is not.
2. **Confirm or write?** `EventSource`'s own docstring says a scan never writes
   silently. If every scan opens a sheet, what is the feature buying? Answer this and
   the previous question together — they are the same question.
3. **UID or written token?** `TagBinding.tagToken`'s docstring says "Hardware UID hex
   (v1) or an app-minted token written into the tag's URL. Generic so both schemes can
   coexist." Coexisting is a nice property of the storage; it is not a reason to build
   both. Reading a UID needs a read session and no tag preparation; writing a token
   needs an NDEF write flow and a tag that is not locked.
4. **One tag per baby per action, or one tag read in the context of the selected
   baby?** With twins the first means four stickers for two actions and a wrong-sticker
   failure mode; the second means a wrong-selection failure mode. The app's named
   failure mode is already the wrong-twin tap.
5. **How is a mis-scan repaired?** `CareStore.reassignEvent` exists, its docstring
   calls it the remedy for a wrong-twin tap, and nothing calls it (`docs/status.md`,
   known issue 3). NFC multiplies exactly that mistake. Make the remedy reachable
   before adding a faster way to make the mistake.

## CloudKit impact

- `TagBinding` is already in the schema and already syncs, so bindings created on one
  phone appear on another with no migration. Nothing to do.
- **Adding a `TagAction` case is additive on the wire and therefore safe — but an
  older build reads the unknown raw value as `.logDiaper`.** A tag meaning "feed"
  would log a diaper on a phone that has not updated. If more actions are likely, add
  an `unknown` case *now*: it is a schema-visible change, and free only until the
  schema reaches production.
- `tagToken` is unencrypted (right — it may need to be matched on) and not unique
  (CloudKit forbids unique constraints). Two devices binding the same physical tag
  concurrently therefore produce two bindings, and whatever resolves a scan must
  tolerate that, the same way everything else here deduplicates explicitly.
- If a scan ever needs a new field on `LogEvent` — a "needs review" flag for an
  unconfirmed tap, say — add it before the first production sync. Afterwards the schema
  is additive-only and a field can never be removed.

## Rough order of work

1. Make `reassignEvent` reachable. Small, independent, and a prerequisite for
   deserving the feature.
2. Answer questions 1–4 above. Nothing below survives a different answer.
3. Portal capability, usage-description build setting, entitlements file.
4. `CareStore` tag-binding CRUD, with tests, and the `TagAction` → call mapping. No UI
   yet, but no scanner needed to test it either.
5. The binding editor in Settings — which is what makes step 4 reachable at all. This
   project has shipped built-but-unreachable code three times (`Totals.compute`, the
   Note button, the handoff's Copy/Share); the pattern is to finish a path, not a
   layer.
6. The read session and the scan entry point on Tonight.
7. Writing tokens to tags, only if question 3 lands there.

---

# Apple Watch app

The wrist is where a night-logging app wants to be: a sleep toggle without taking the
phone out of a pocket in a dark room.

## What already exists

Nothing watch-specific — `project.yml` declares four targets and every one is
`platform: iOS`. What exists is the *reason this is cheap*:

**`MoonlogCore` is already the shareable half.** Every file in `Sources/Core/` imports
`Foundation` and nothing else — verified, not assumed. No SwiftData, no SwiftUI, no
`Date.now`. Day bucketing, day-of-life, totals, sleep math, the reconciler, the
handoff text and every value type cross a target boundary without ceremony because they
were built to.

**The persistence half is not shareable as it stands.** `CareStore` is a `@ModelActor`
in the app target, over `@Model` types in the app target. Putting it on the watch means
a second store on the watch, which is the question below, not a detail.

**One concrete unknown right at the start**: `MoonlogCore` is declared
`platform: iOS`, and a watchOS target cannot link an iOS framework. XcodeGen 2.46 ships
`SupportedDestinations` presets that include `watchOS`, so a multi-destination framework
is very likely the route — **I have not tried it in this project.** The fallback has
in-house precedent: `Our-Fitness` compiles individual pure-Foundation domain files
directly into its watch target rather than sharing a framework, with a comment on each
that the file must stay dependency-free or it drags the rest of the domain onto the
wrist. Either way, this is a half-hour experiment that decides the shape of everything
else, so do it first.

## What it would need

- **A new target in `project.yml`**: `type: application`, `platform: watchOS`,
  `TARGETED_DEVICE_FAMILY: "4"`, `SKIP_INSTALL: "YES"`, its own bundle identifier
  (`com.sleepyllamas.moonlog.watchkitapp` by convention), and
  `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` pointing back at the phone app —
  that key is confirmed present in the installed Xcode's build settings, so it needs no
  `Info.plist` file.
- **Its own asset catalog with its own AppIcon set.** A watchOS icon must be declared
  with `"platform": "watchos"` and cannot be borrowed from the phone's catalog.
  `Our-Fitness`'s notes record the failure mode: without it, `actool` writes no
  `CFBundleIconName` and the upload is rejected with altool error 90713 **after** a
  full archive has already run.
- **Its own provisioning profile**, and its own entitlements file if it talks to
  CloudKit directly.
- **A decision about what belongs on a watch face-sized screen.** The sleep toggle is
  the most-pressed control in the app and the obvious candidate. The merged timeline is
  not. Diaper is plausible; feed carries an amount and a method and probably is not.

## The open question that decides everything

**Does the watch write to its own store, or hand off to the phone?**

*A — the watch owns a store.* Its own SwiftData container, mirrored through the same
CloudKit container. Works with the phone in another room. The costs are real: the model
layer and a writer have to exist on the watch, CloudKit membership has to include it,
and sync stops being a backup and becomes a **correctness requirement** — including the
two-open-sleep-sessions conflict class, on a device that may be offline for hours.
`SleepReconciler` exists precisely for that and is already tested, which is the single
biggest argument that this is viable. Against it: I have **not** verified that SwiftData
+ CloudKit mirroring behaves on watchOS the way it does on iOS, and would not start here
without checking.

*B — the watch is a thin client.* The phone owns the store; the watch sends intents
over WatchConnectivity and renders what it is told. In-house precedent exists:
`OurFitnessWatch` is exactly this shape, with a shared wire-format file compiled into
both targets. The costs: writes fail or queue when the phone is out of range, and a
second wire format has to be maintained.

**What decides it is a fact I do not have**: whether the doula has the phone on her in
the room, or leaves it on a surface. If the phone is always in a pocket, B is smaller,
safer and does not touch CloudKit at all. If the point is to leave the phone behind, only
A delivers it. Nothing else should be built until that is answered.

## CloudKit impact

- **Option A** uses the same container and the same schema — no new fields. But it makes
  the gap described in `docs/cloudkit.md` ("Before switching it on") load-bearing: a
  write from the watch is a change arriving from another device, and Tonight has no
  trigger for that today. The watch app would ship with the phone screen not updating
  until it was touched.
- **Option B** has no schema impact whatsoever. The watch/phone wire format is version-
  locked to a paired install, so it is not subject to the additive-only rule the way
  CloudKit fields are.
- If per-device provenance is ever wanted — "logged from the watch" — that is a new
  `EventSource` case. Additive and safe, and unlike `TagAction` the fallback is benign:
  an older build reads it as `.manual`, which understates rather than misfiles.

## Rough order of work

1. Answer the write-versus-handoff question.
2. Prove `MoonlogCore` builds for watchOS (`supportedDestinations`, or file-by-file
   inclusion as `Our-Fitness` does). Cheap, and it determines how much is shared.
3. Skeleton target, icon set, signing — and **archive once before writing any feature
   code**, to flush out the 90713-class rejections that only appear after a full archive.
4. One action end to end: the sleep toggle, reaching whichever writer option 1 chose.
   Then stop and use it for a night before adding the second.
5. Complications, Live Activities and feed-due alarms are out of scope here. AlarmKit
   needs iOS 26 and is already last in the order behind an `@available` gate.

## What I do not know

Stated plainly, because these are the parts that would otherwise read as if they had
been checked:

- Whether SwiftData's CloudKit mirroring works on watchOS as it does on iOS.
- Whether `supportedDestinations: [iOS, watchOS]` on `MoonlogCore` generates cleanly in
  XcodeGen 2.46 and links from a watch target — only that the preset directory exists.
- What the watch app should show when there is no open shift, which is most of the time.
- Whether a watchOS app that only ever writes needs its own CloudKit entitlement or can
  ride the phone's — that follows from option A versus B, and I have not checked the
  entitlement side of A.
