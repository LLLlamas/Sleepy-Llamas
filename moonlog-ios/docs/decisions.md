# Decision log

Newest first. Each entry records what was decided, why, and what would reverse it.

---

## Confirmations are per action, and most of them default to off
**2026-09-06**

A setting for whether an action asks before it happens, as a list of toggles under
"Ask before" in Settings — `ConfirmableAction` (five cases) plus `ConfirmPreferences`,
an `@Observable` object in the environment alongside `careStore`.

**Per action rather than one global switch.** A single "confirm destructive actions"
toggle forces one answer onto two different questions. Ending a shift cannot be
undone; the sleep toggle is pressed forty times a night and *can* be undone. Anyone
setting a global switch is choosing which of those to get wrong.

**Undo is what picks the defaults.** Four of the five return a reversing write and
leave an Undo on the banner for six seconds, and an Undo you already have beats a
dialog you have to read — so `toggleSleep` and `moveRecord` start off, and only the
irreversible ending and the two deletes start on. The cost of an unnecessary
confirmation is not zero: at 3am it trains the thumb to dismiss dialogs without
reading them, which is how the one that mattered gets tapped through.

**One key per action, not one encoded set.** `moonlog.confirm.<case>`, read with
`object(forKey:)` and not `bool(forKey:)`. `bool` returns `false` for a key nobody
has written, which is indistinguishable from a user who switched it off — every
default of `true` would have shipped as `false`. A CSV of the on-set, which is what
`Family.optionalKindsRaw` does, has the matching flaw one level up: a case added
later is absent from every stored string and reads as off for existing installs.

**The gate wraps the call site; it is not inside `perform`.** The delete
confirmation belongs to `LogSheetChrome`, which owns the sheet the delete is pressed
in and which five log sheets inherit at once. Gating deletes in `perform` as well
would put two dialogs on top of each other.

**A dialog is raised by whichever view owns the control.** The end-shift
confirmation was first written in `TonightView`, gating `ShiftHoursSheet`'s `onSave`
callback. That callback runs while the sheet is still presented and `dismiss()` is
the next line, so the dialog would have been handed across a view that is going away
— and a confirmation that fails to appear is an end-shift that silently does nothing.
Moving it into the sheet fixed it, and then the same reading found the same bug in
"Wrong baby?", whose menu also dismisses on choosing; that one would only have bitten
someone who switched it on, since it defaults off. Both now live in the sheet.
`TonightView.confirming` is left for controls actually on Tonight, which is just the
sleep toggle. Same family of bug as the `navigationDestination` in a `Section`, and
found by reasoning about the ordering — the suite stayed green throughout.

**They are alerts, and this is the second bug the screenshots found.** Written as
`confirmationDialog`, the end-shift confirmation rendered as a *popover* — tail
pointing at the sheet's grabber, floating over Tonight, obscuring the sheet's own
Cancel — and iOS drops the cancel action in a popover presentation. So "this cannot
be undone" offered one red button and no visible way out. Checking the rest found the
app's **pre-existing** delete confirmation had shipped with exactly that flaw, in
every log sheet, since it was written. All five are alerts now: centred, modal, both
buttons, every time.

Opening a log sheet is deliberately not on the list. A sheet is a form, not a
question, and a form you can cancel already is its own confirmation.

*Reverses if:* the list grows past about six rows, at which point "Ask before"
stops being a setting anyone reads and wants grouping or a sensible-defaults reset.

---

## The status tile says when the state started, awake as well as asleep
**2026-09-06**

`Fmt.clockAmPm` ("3:42am") next to the existing `shortClock` ("3:42a"), a new
`SleepMath.lastWake(in:forBaby:)`, and `awakeSince` on `BabyPresentation`.

The tile already named a time, but only while asleep — awake said "Tap to log a
sleep you missed" and nothing about when being awake began. That was the more useful
half: "she has been up since 4:20" is what decides whether to try a feed. There is no
awake session to read, since awake is the absence of an open sleep, so the answer is
the latest `endAt` across the closed sessions. `nil` when the baby has not slept yet,
and the tile then says nothing rather than naming the shift's start as if it were a
wake.

**A second clock format rather than changing the one that existed.** `shortClock`'s
single letter is a column-width economy that earns nothing in a sentence, but it is
pasted into eight places in the plain-text and keepsake handoffs, which the parents
read — so it was left alone and both now share one hour-12 computation, pinned by
`FormattersTests` at midnight and noon.

**The time sits on the tile's second line, not trailing the state sentence.** It was
put on the state line first, as "Mia is asleep (since 10:12am)", and the screenshot
showed it wrapping *inside* the parenthetical — "(since" ending one line and
"10:12am)" alone on the next. The asleep tile is the tight one, because it is the
only state carrying the elapsed badge on its trailing edge, and any name longer than
"Mia" makes it worse. The state stays one short bold line.

*Reverses if:* the elapsed badge goes away, which is what makes the first line tight.

---

## One client family at a time, chosen in Settings
**2026-09-06**

The doula works one household a shift, so the app assumes one and the switcher moved to
Settings' first section. `RootView` loses `familyMenu`, `familyBinding`, the
`addingFamily` state and the `.topBarLeading` toolbar item; `SettingsView` now takes a
`FamilyRoster` value (`current`, `all`, `select`, `create`) and its signature is
`SettingsView(roster:onError:)`. "Add baby" moved with it. The sections read Client
family, Babies, Past nights, the per-family preferences, note tags, Appearance, Data —
who this is, who is in it, what has already happened, then settings proper.

What the superseded entry got right is the only reason this was not a free move. The
switcher's label was doing a second job: standing answer to "whose night am I logging?"
Deleting the control without replacing that answer would have traded a convenience for
the exact mis-logging risk the placement existed to prevent. `NightHeader` gives the
answer now. `docs/design.md` carries the rest of the placement rules, including why the
picker has to stay at the root of the Settings stack.

Selection itself is unchanged. `moonlog.currentFamilyID` is still owned and resolved in
`RootView` and `FamilySelection.resolve` was not touched — the picker can only offer a
family that exists, but the stale-id fallback still has to survive one being deleted.

*Supersedes* "The client-family switcher is on Tonight, not in Settings" (2026-09-05).

*Reverses if:* the doula ever covers two households in one night, at which point
switching becomes a mid-shift act again.

---

## The maroon is lifted forward, and "contrast-checked" is now a test
**2026-09-06**

Two problems with the palette, and only one of them was visible.

The invisible one: the values were ported from the PWA's `tokens.css` and these documents
called them contrast-checked. Nothing had checked them. Measured at WCAG AA the Day theme
failed five pairs, so Day's `faint` `7e5c61`→`6f5056`, `sleep` `3f7d68`→`2f6753`,
`sleepFaint` `e1f0e9`→`e4f1eb` and `stop` `b8324a`→`a82a42`. The decision is what
replaced the claim rather than the corrections: three tests in `PaletteTests`, so the
palette is measured on every run and a colour added to it cannot be looked at until it
passes. `docs/design.md` records which pairs failed and by how much.

The visible one: the identity read as near-black on a phone. `bg`→`raised` is a
six-thousandths luminance step, which a bright monitor flatters and an OLED panel in a
dark nursery does not. The surfaces above `bg` are lifted toward maroon, and a new role
`bgLift` carries the maroon at the top of the page — a role rather than an inline
gradient stop, precisely so the contrast test covers text drawn on it.

Night and Deep Night `bg` did not move, and that is the decision inside the decision: it
is the brand anchor, the PWA's `theme-color`, and the value every screenshot of this app
so far was taken against. Day's `bg` moved one step warmer, because a cream page cannot
be made more maroon by lifting only what sits on top of it.

---

## The clock is the largest thing on Tonight
**2026-09-06**

`NightHeader` is new at the top of Tonight and answers two questions at once: what time
is it, and whose night is this. The first is the question behind every log this app takes
— "when did that happen, relative to now" — and the PWA answered it in a 19-pixel line
beside the wordmark. The second was being answered by the switcher that has just moved to
Settings.

It ticks on its own `TimelineView(.periodic(by: 30))`, a subtree rather than the screen.
The rule that the rest of Tonight re-renders on writes and not on the clock is unchanged,
and this is what keeping it costs: a live clock has to be its own island. The layout is
in `docs/design.md`.

---

## The baby's status is a tinted tile, and the port stops at the copy
**2026-09-06**

`BabyStatusCard.statusContent` is the PWA's sleep tile — a bordered, state-tinted block
reading "Mia is asleep" — because a tinted block is legible across a dark room in a way a
coloured word in a row is not.

The subtitle is where the port deliberately stops. The web tile said "tap when Mia wakes"
because tapping it toggled. Tapping this one opens the adjust-sleep sheet, so it says
"tap to adjust". Carrying the words over with the layout, when the gesture underneath has
changed, ships a promise the app does not keep. The behaviour is what did not change here:
the Wake/Sleep button is still the toggle.

`BabyStatusCard` took a `timeZone` parameter in the same change. It would otherwise have
formatted its one time in `.current` while every other clock on the screen reads the
shift's zone.

---

## Past nights are their own screen, reachable during the shift
**2026-09-06**

`HistoryView` is pushed from Settings, and `SummaryView` is now strictly the running
shift's totals.

Worth recording because it was made for a bug rather than for tidiness. `PastNightsSection`
only rendered in Summary's *no open shift* branch, so from the moment a shift started
until it ended, last night was unreachable — and mid-shift is exactly when "how long did
she go last night?" gets asked. Splitting the two screens along now-versus-before makes
that structural instead of a branch someone has to remember to check.

---

## `navigationDestination` goes on the `Form`, not inside the `Section`
**2026-09-06**

Declared inside the `Section` whose row triggers it, the push to `HistoryView` landed on a
blank screen: a `navigationDestination` inside a lazy container is not registered until
that row has been built. It is declared on the `Form`.

Recorded as a decision rather than a fix because it is the rule for every push added from
a `Form` or a `List` from here on. Nothing in the suite would have caught it — there are
no view-layer tests and no UI test target — and it was found by screenshotting the pushed
screen and seeing nothing on it.

---

## No JSON export, and the caregiver is named once

**2026-09-05**

Both were on the next list and both came off it after the user weighed them.

The caregiver is one person every night — the doula this app is built for. The
field is already `@AppStorage("moonlog.lastCaregiver")`, typed once and pre-filled
from then on, and `Shift.caregiver` is the snapshot taken when the shift started so
past handoffs keep saying what they said. Building an editor for a value that never
changes would be work spent on a screen nobody opens twice.

The JSON export was proposed as the thing that would make history restorable
without CloudKit. It came off for the same reason CloudKit did: the store persists
across launches and is carried by the phone's own backup, so the loss case it
guarded against is already covered. What remains uncovered is deleting the app
itself, which no export prevents either unless it has been run recently.

*Reverses if:* a second caregiver ever works these shifts, or history has to move
between devices without a full device restore.

## CloudKit deferred; the phone's own backup already covers the loss case
**2026-09-05**

Sync was ranked first on the strength of a claim that turns out to be wrong: that a
lost phone means a lost year of nights. It does not. `ModelConfiguration` is opened
without a `url:`, so the store sits at `Library/Application Support/default.store` —
confirmed on a running simulator — and nothing in `Sources/` excludes it from backup.
That directory is carried by iCloud Backup and by an encrypted Finder backup, so a
broken, lost or replaced phone restores it with the rest of the device.

What CloudKit adds on top of that is narrower than it looked: surviving deletion of the
app itself on a working phone, more than one device writing the same records, and
continuous sync rather than nightly-when-locked-and-charging. Against that sits the
launch-crash trap — requesting a CloudKit store without the entitlement kills the app on
a background queue with no catchable error, and this app has already died that way once.
For one doula with one phone, whose per-shift summary is sent to the family anyway, that
is a large amount of launch risk for a narrow gain.

Deferred, not cancelled. `docs/cloudkit.md` keeps the whole checklist, every verified
constraint and every trap, because none of it stopped being true. What is honestly still
open is that a handoff — text or keepsake — is a document for the parents, not something
this app can read back: if a phone is lost and never restored, the families keep their
summaries and the doula loses her own history. A re-importable export is the cheap thing
that closes that, and it is not built.

*Reverses if:* a Watch app writes records directly rather than handing them to the
phone, or a second device is added at all — at which point sync stops being a
convenience and becomes a correctness requirement.

---

## The keepsake handoff is responsive HTML, shared as a file
**2026-09-05**

`Handoff.text` exists to be pasted into Messages at 6am. The document the family keeps
afterwards is a different job, so `HandoffHTML` renders the same night as a page, from
the same records and the same `Totals.compute`.

Self-contained is a requirement rather than a preference: no external stylesheet, font,
script or image. The page is forwarded, saved to Files and opened offline months later,
so anything fetched over the network is either missing by then or is a request that
tells a third party the exact moment the parents opened it. Hence an inline stylesheet.
It is written mobile-first for the plain reason that they read it on a phone, straight
out of Messages — the stat tiles reflow with `auto-fit` and there are no breakpoints to
maintain.

It ships as a `Transferable` **file** — `HandoffPage` in
`Sources/Views/ShiftDetailView.swift`, a `DataRepresentation(exportedContentType: .html)`
with a suggested filename — and not as a `String`. `ShareLink` on a string pastes raw
markup into the message body. As a file the parents get something they can open, keep,
forward and print.

No PDF renderer was written and none is needed: the page carries a print stylesheet
(white ground, and no baby's card split across a page break), and Save to PDF goes
through print, so a PDF costs nothing beyond CSS that already had to exist.

Fraunces is still the intended face for this document and is still not bundled, and
nothing may be fetched, so `ui-serif, Georgia, "Times New Roman", serif` carries the
brand moments — the same compromise recorded further down for the app itself, and a
smaller one on a page than on a screen.

*Reverses if:* a font file is bundled, or the family needs something one self-contained
HTML file cannot express.

---

## The parents' note lives on the `Shift`, encrypted, and stays editable
**2026-09-05**

The doula's own sentences to the family are `Shift.parentNote`: one optional `String` on
the shift, written through `CareStore.setShiftNote`, which trims and stores `nil` for an
empty result so a whitespace note cannot render an empty block on the keepsake page. It
belongs to the shift rather than to a `LogEvent` because it is about the night as a
whole, and it is the one part of the handoff that is composed rather than logged — so it
stays editable after the shift has ended, from both Summary and a past night's detail.

It carried `@Attribute(.allowsCloudEncryption)` from the moment it was introduced,
because that is the only moment it can: an existing field can never be converted
to an encrypted one, so a note that shipped in the clear would stay in the clear for the
life of the schema, and this is free text about somebody's newborn. The pinned set in
`Tests/MoonlogTests/SchemaCloudKitCompatibilityTests.swift` was updated deliberately in
the same change. That test exists precisely so a new sensitive field cannot arrive
unencrypted by omission.

*Reverses if:* nothing cheap. Once the schema reaches production this is one of the
decisions that cannot be taken back.

---

## One phrasing per fact, shared between the two handoff documents
**2026-09-05**

A review read the keepsake page against the plain text for the same night and found five
places where they described it differently. The page dropped unattributed records
entirely; it dropped a note's tags, so a note logged as "Spit-up" and nothing else
reached the parents as a timestamp with no words beside it; it lost the day of life when
the family had one baby; it phrased a medication differently and leaked a dangling
separator when the dose was an empty string; and it took the weight from somewhere other
than where the text took it.

Individually these are small. Together they are two accounts of one night with no way
for the family to tell which is the record, which is the exact failure the whole area
exists to avoid.

The fix was not to re-check the renderers against each other, which only holds until the
next change. `Handoff.warmFeed`, `noteDetail`, `medicationDetail` and `strayLine` became
internal rather than private, and `HandoffHTML` now calls them. Both documents already
derived their numbers from `Totals.compute`; now they derive their words from one place
too. The rule for anything added later: **a fact that appears in both documents is
phrased in exactly one place.**

The 14 string-exact tests over `Handoff.text` are what made the extraction safe. They
assert the actual words of a feed, a note and a stray record, and they passed unchanged,
which is the evidence that moving the helpers changed nothing the doula has already read
at 6am. The keepsake's own tests assert on meaningful substrings instead of a golden
file, so a CSS tweak cannot train anyone to re-bless a diff without reading it.

*Reverses if:* the two documents ever need to say one fact differently on purpose — in
which case the difference belongs in one function with a parameter, not in two
renderers.

---

## `StoreWrite` for the screens whose only job on failure is to say so
**2026-09-05**

`RootView` and `SettingsView` had each grown the same six lines: unwrap the optional
store, spawn a `Task`, `try await` the write, put the error into an alert. Adding the
note to the parents would have made four copies. `Sources/Lib/StoreWrite.swift` is that
shape written once — a `@MainActor enum` with a single `run(_:onError:_:)`.

The line count is not the point. The failure path is: a care log that silently drops a
write is worse than one that stops and says so, so no caller gets to leave the `catch`
empty, and a missing store is reported in words rather than returned into silence.

`TonightView` deliberately keeps its own path. It also owns the confirmation banner, the
per-baby busy lock and Undo — its `perform` returns the action that reverses the write —
and none of that belongs in a helper the other four screens would then have to opt out
of. A shared abstraction that one caller has to work around is worse than two paths that
are honest about doing different jobs.

*Reverses if:* a second screen needs Undo, at which point the two paths should be merged
rather than the Tonight one copied.

---

## Time rules live in `CareStore`, with a minute of slack for clock skew
**2026-09-05**

Future-blocking and the shift-overlap check used to exist only in `LogSheetChrome`, so
they held for a thumb on a sheet and for nothing else. Anything that is not a view —
the sleep reconciler, an NFC tap, a future import — wrote straight past them.
`rejectFuture(_:)` and `requireOverlap(startAt:endAt:with:)` are the actor's now, and
every mutating entry point calls them. The sheets keep their advisories, but as a
courtesy to the thumb rather than as the enforcement. `CLAUDE.md` already said
invariants belong in the actor; this makes that true for time as well as for identity.

The tolerance is 60 seconds, the same figure as `Date.isMeaningfullyInFuture` in Core,
so a sheet and the store can never disagree about what counts as the future. Two
synced devices do not agree on the second, and a tap on the trailing one should not be
refused. Twelve hours out — the web version's actual bug, which suppressed the
overdue-feed warning for the rest of the night — still is.

`futureTimestamp` and `outsideShift` arrive with a `CustomStringConvertible`
conformance on `CareStoreError`. Every alert in the app renders `"\(error)"`, so
`LocalizedError` alone would have shown a tired reader "futureTimestamp" at 3am.

---

## Undo is a compensating write, not `UndoManager`
**2026-09-05**

Every write action returns an `Undo?` — a `@Sendable (CareStore) async throws -> Void`
naming the call that reverses it. Returning `nil` means the write cannot be taken
back, and the banner then offers no Undo button rather than one that quietly does
nothing.

`UndoManager` was never really on the table. Nothing in the project wires
`context.undoManager`, and the writes do not happen on the context the view holds:
`CareStore` is a `@ModelActor` with its own. An undo stack on the main context would
have nothing recorded on it. A compensating call also stays in the store's own
vocabulary — `deleteEvent`, `reassignEvent`, `updateShift` — so undoing obeys the
same invariants the original write did, instead of rewinding the object graph
underneath them.

The banner holds six seconds when there is something to undo and two when there is
not. Two seconds is enough to read a confirmation and nowhere near enough to notice a
wrong-twin tap and act on it.

*Reverses if:* undo ever needs to span more than one step, which a single closure
cannot express.

---

## Undo restores the record, not a lookalike
**2026-09-05**

A deleted entry could have been undone by logging an equivalent one. It is not.
`LogEvent.restoration` captures an `EventRestoration` — a `Sendable` value type, so it
crosses the actor boundary and outlives the model object — and `restoreEvent(_:)`
re-inserts under the original `id`, `createdAt` and source. Re-logging would mint a
fresh id, breaking anything already pointing at the old one, reset `createdAt`, and
drop `sourceTagToken`, which is what makes a mis-scan traceable later.

Sleep needed `restoreSleepSession(id:shiftID:babyID:startAt:endAt:)` of its own rather
than reusing `recordSleep`: when a session is already open, `recordSleep` corrects
*that* one instead of inserting, so undoing a deleted closed session would have
dragged a live one backwards in time and rewritten a sleep nobody touched.

Both restores return early when the id is already present, so a double-tap on Undo
cannot produce two copies. Idempotence is the cheap half; keeping the identity is the
point.

---

## The re-read is named, not inherited from the banner
**2026-09-05**

`TonightView` now bumps a `refreshToken` after every write and reads it in `body` via
`Tonight(..., generation:)`. Before that, the screen re-derived itself because the
confirmation banner's `@State` happened to mutate about two seconds after each write —
so deleting the banner, or shortening it, would have silently stopped the timeline
updating after a log. A dependency that nobody can see is one that a later change
removes by accident.

The remote case is deliberately left unsolved rather than guessed at: a merge arriving
from another device bumps nothing, and it cannot be tested until the iCloud capability
exists. It is named in `docs/architecture.md` so it is a known gap rather than a
surprise.

---

## One sheet for all three opt-in kinds
**2026-09-05**

Pumping, a medication and a weight are each a time plus one or two fields, and each
would have made the same `LogSheetChrome` call with a different middle section. One
`ExtraSheet` and one `ExtraEntry` cover all three. Until it existed they could be
switched on in Settings and then logged by nothing: there was no create path, and
their timeline rows were deliberately inert because the only sheet they could have
routed to was the note sheet, which would have written note fields onto a record that
never renders them.

`ExtraEntry` carries only the kind's own fields, because the store writes the payload
wholesale and a stale value from another kind would persist. Logging a pump also
needed `CareStore.logEvent` to take a `UUID?`, gated by `requiredBaby(_:for:)` — the
signature was the last thing standing between "pump carries no baby" as a design and
as a fact. And `ShiftTimeline` no longer gates the edit route on `EventKind.core`, so
every kind is correctable, a pump routing with a nil baby rather than staying inert.

*Reverses if:* one of the three grows a form of its own, at which point sharing the
sheet costs more than it saves.

---

## The opt-in kinds live in Tonight's menu, not on the baby cards
**2026-09-05**

The card's four controls — feed, diaper, sleep, note — are the set a thumb finds in
the dark without reading the labels. A fifth and a sixth would crowd them for records
logged once a night at most. The extras go in Tonight's toolbar menu instead, which
also gives pumping somewhere sensible to live: it belongs to no baby, so a control on
a baby's card would have been a lie. A kind that does attach to a baby expands into a
name picker only when the family has more than one.

---

## A sheet for the shift's own hours, replacing the end-shift dialog
**2026-09-05**

Ending a shift was a confirmation dialog that took the clock. Tapping it half an hour
after actually leaving widened the window by half an hour — and since the totals and
the handoff clip to that window, it credited the parents with sleep nobody watched.
`ShiftHoursSheet` puts both times on pickers. Now is pre-filled, because it is right
most nights, and editable, because the night it is wrong is the night it matters.

The same sheet corrects a running shift's start, since ending is the last chance to
fix it and both come off the same two pickers. Ending while a baby is asleep names
who, rather than counting them: their sleep stays in the record either way, and the
session is deliberately left open.

`updateShift` will not reopen a closed shift. `close(at:)` is the only thing keeping
`isOpen` honest and there is no `reopen()` to pair with it, which is also why ending a
shift is the one write on this screen that offers no Undo. Narrowing a window is
refused outright when it would strand an already-logged sleep session outside it.

---

## The client-family switcher is on Tonight, not in Settings
**2026-09-05**

*Superseded 2026-09-06 by "One client family at a time, chosen in Settings."* The
mis-logging risk below is real and still guarded; only the control moved.

Tonight is the screen the doula is on all night, so the switcher sits on its leading
toolbar and its label doubles as a standing answer to "whose night am I logging?" The
mistake it guards against is logging a feed against the wrong household; Settings, two
taps away and rarely open, would not prevent that. It is a `Picker`, so the current
family carries a checkmark — colour is never the only signal.

The selection persists in `@AppStorage("moonlog.currentFamilyID")` as a string, since
`@AppStorage` cannot hold a `UUID`, and resolves through
`FamilySelection.resolve(storedID:among:)` — its own testable type, because the
difference between falling back to the oldest active family and returning nothing is
the difference between the wrong household's night and an empty screen. Tonight and
Summary carry `.id(family.id)` so a half-filled sheet cannot survive a switch still
holding the previous family's baby id.

---

## Volume unit is per family; breast feeds carry a duration per side
**2026-09-05**

Households mark bottles differently, so `Family.volumeUnit` decides display and
entry (oz or ml) while storage stays canonical millilitres. The handoff then reads
the way that family expects. Weight follows the same unit system — a household
working in ounces gets pounds and ounces, not grams.

`FeedMethod` collapsed from `breastLeft`/`breastRight` to a single `breast`, with
`leftSeconds` and `rightSeconds` on the event. One feed commonly uses both sides,
and the old shape could not express that without logging two feeds. A single-sided
feed simply leaves the other nil.

*Free to do now* — a CloudKit raw value can never be renamed after a production
deploy, so this had to happen before the first TestFlight build or not at all.

---

## Pumping, medication and weight are optional event kinds
**2026-09-05**

Added to `EventKind` but **off by default**, enabled per family via
`Family.enabledKinds` / `setOptionalKinds(_:)`. The three core kinds stay in the thumb row; nobody pays for
a feature they do not use.

`pump` is about the mother, so it carries **no baby** — `attachesToBaby` is false
and totals count it for the shift regardless of whose figures are being computed.

Note tags become a `NoteTagPreset` model rather than a fixed list, so the user
defines their own. A model rather than a stored array because SwiftData persists
`[String]` as an opaque Codable blob that CloudKit merges last-writer-wins — two
devices adding a tag concurrently would silently lose one.

## Five baby accents, defined per theme, not as palette roles
**2026-09-05**

Accents were originally `--accent` / `--sleep` / `--warn`. In the Day theme that
made "gold" resolve to maroon, sitting almost on top of "rose" — twins were
distinguishable at night and barely so by day. Each accent now carries its own
per-theme value.

A sixth, "clay", was tried and dropped: in a warm maroon palette a terracotta is
inescapably close to gold, and the contrast test caught it in all three themes. Two
colours a tired person can confuse are worse than one fewer option.

*Reverses if:* someone needs more than five babies in one family, which would mean
finding hues that survive the distinctness test rather than reusing roles.

---

## SF for the interface, Fraunces only for brand moments
**2026-09-05**

A deliberate departure from the PWA's brand type. SF is engineered for glanceability
at small sizes in low light and gives `.monospacedDigit()` free — a sleep timer in a
proportional face jitters as digit widths change, and it is re-read all night.
Fraunces stays on the wordmark and the exported keepsake handoff, where a display
serif earns its place.

*Reverses if:* the app stops feeling like Sleepy Llamas. Cheap to change.

---

## No PWA importer; the PWA is frozen
**2026-09-05**

The PWA only ever held test data, so the native app starts clean. The 17 audit
findings against it become a specification of defects not to reintroduce, not a work
list. `legacyID` columns were removed while it was still free — a CloudKit field
cannot be deleted after the schema is promoted to production.

---

## Clip sleep sessions to the shift window; never auto-close them
**2026-09-05**

A shift ends by leaving the baby with the parents, often still asleep. So the
session stays open and honest — "asleep since 5:40, still asleep when I left" — and
totals clip to the shift window instead.

One rule replaces three fixes: it stops an archived shift's total growing forever,
stops a back-dated entry crediting one shift with another's hours, and preserves the
true record. Also means ending a shift does not open a replacement.

*Supersedes* an earlier plan to close the session and start a fresh shift, which was
written before the workflow was understood.

---

## Day of life uses the clinical convention (birth day = Day 1)
**2026-09-05**

The PWA counts completed 24-hour blocks, so it calls a ten-hour-old baby "Day 0" and
rolls over at the birth *minute*. Neither matches how a pediatrician counts, and the
minute-rollover means the same handoff reports a different Day N depending on when
it is copied. There is a shift-pinned overload so the number is stable for a shift.

*Made without an explicit answer from the user* — flagged, and a one-constant change.

---

## `LogEvent` is one flat model, not three and not a class hierarchy
**2026-09-05**

- Three models cannot be paged: `FetchDescriptor.fetchLimit` is per-type, so a
  merged timeline would mean loading every event of all three kinds to show 50 rows.
- `@Model` inheritance needs iOS 26 and has reported crashes at the inheritance +
  optional-relationships intersection, which CloudKit mandates.
- `#Predicate` cannot compare enum properties at all, so raw `String` columns are
  needed regardless — and reaching through `.rawValue` inside the macro
  *hard-crashes uncatchably*.

Cost: the schema cannot enforce "a feed has a method". Bought back with a payload
projection and tests. CloudKit could not have enforced it either.

---

## CloudKit behind a compile flag, not a runtime probe
**2026-09-05**

Requesting a CloudKit store without the entitlement does not throw — it traps
asynchronously and kills the app. A runtime check is impossible on iOS
(`SecTaskCopyValueForEntitlement` is not public; `ubiquityIdentityToken` keys off a
different entitlement). See `docs/cloudkit.md`.

---

## Target iOS 18, not 26
**2026-09-05**

Everything v1 needs is available at 18 — SwiftData, `#Index`, CloudKit mirroring,
Core NFC, Live Activities — and it keeps older devices in play. Only AlarmKit
(feed-due alarms) needs 26, and it is last in the order and will be `@available`-gated.

---

## Background NFC dropped for v1
**2026-09-05**

Two independent reasons:

1. It cannot log silently. iOS always shows a notification the user must tap, and a
   locked phone must be unlocked first. The real delta versus "open app, tap Scan"
   is small.
2. The `apple-app-site-association` file cannot live at our URL. It must be served
   from the **domain root**, and `LLLlamas.github.io/.well-known/...` is served by a
   different repository — probed live, it 404s. Nothing in this repo can appear
   there.

In-app tag reading and writing need no web infrastructure and are still planned.

*Reverses if:* a custom domain is bought and `.well-known/` served from a host that
controls headers.

---

## iOS work lives on a branch, not a separate repo
**2026-09-05**

`deploy.yml` only triggers on pushes to `main`, so an unmerged branch is invisible to
CI. Chosen over a separate repository so TestFlight builds come straight off this
branch. The one hole is `workflow_dispatch`, which can target any ref — hence the
discipline in `CLAUDE.md`.
