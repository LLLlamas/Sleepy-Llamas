import SwiftUI
import SwiftData
import MoonlogCore

/// What it takes to take a write back, run if Undo is tapped.
///
/// A write returning `nil` cannot be undone, and no Undo is offered rather than
/// one that quietly does nothing.
typealias Undo = @Sendable (CareStore) async throws -> Void

/// What happened, what is happening, and the three buttons you need at 3am.
///
/// Layout is adaptive: one baby renders a single block, two or more render a card
/// each over one shared timeline. No active-baby selector — see `docs/design.md`.
struct TonightView: View {
    let family: Family
    let shift: Shift

    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var modelContext
    @Environment(\.careStore) private var store
    @Environment(\.confirmations) private var confirmations

    @State private var sheet: LogSheet?
    @State private var editingBaby: Baby?
    @State private var confirmation: String?
    /// Only the newest confirmation may clear itself. Without this an older write's
    /// two-second timer wipes a newer write's banner — and since the banner is the
    /// only feedback that a write landed, that makes the user log it again.
    @State private var confirmationToken = 0
    @State private var saveError: String?
    /// Babies with a write in flight. The sleep toggle is the most-pressed control
    /// in the app and the card cannot update until the actor round-trip lands, so
    /// without this a second tap immediately closes the session that just opened —
    /// leaving a ~20ms sleep and a card reading "Awake".
    @State private var busy: Set<UUID> = []
    /// Cleared with the banner. Non-nil is what puts an Undo button on it.
    @State private var pendingUndo: Undo?
    /// Bumped after every write. See the note in `body` — this is what re-derives
    /// the screen, and it used to be an accident.
    @State private var refreshToken = 0
    @State private var reminders: [UUID: Date] = [:]
    @State private var remindersLoaded = false
    @State private var reminderWarning: String?
    @Environment(\.scenePhase) private var scenePhase
    /// Non-nil presents the shift-hours sheet, for correcting the start or ending.
    @State private var hoursSheet: ShiftHoursSheet.Purpose?
    /// Non-nil presents the "are you sure" for whichever action asked for one. One
    /// dialog for all of them rather than one per call site — the question and the
    /// button label come off `ConfirmableAction`, so a new confirmable action does
    /// not mean a new alert to keep in step.
    @State private var pendingConfirm: ConfirmPrompt?

    var body: some View {
        // Deliberately NOT wrapped in a periodic TimelineView. Nothing on this
        // screen except the two labels inside each card depends on the clock, and
        // ticking the whole view rebuilt every timeline row — every formatted time,
        // every string — 2,880 times a night for values that change ~40 times.
        // The cards own their own tick; everything else re-renders on writes.
        //
        // `refreshToken` is read here deliberately. `CareStore` is a `@ModelActor`
        // writing through its own context, so the main context's relationship
        // arrays — `shift.events`, `shift.sleepSessions` — are a merge behind, and
        // nothing else on this screen forces the re-read. Until this existed the
        // job was done by accident: the confirmation banner's `@State` happened to
        // mutate about two seconds after every write. Deleting the banner would
        // have silently stopped the timeline updating after a log.
        let data = Tonight(
            family: family, shift: shift, now: Date(), generation: refreshToken, reminders: reminders)
        content(data)
            .navigationTitle(shift.careContext == .day ? "Nanny Log" : "Moonlog")
            .task(id: refreshToken) {
                reminders = await FeedReminders.pending()
                remindersLoaded = true
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { reminders = await FeedReminders.pending(); remindersLoaded = true }
                }
            }
            #if DEBUG
            // Test affordances, never reachable in a real run — same rationale as
            // DemoSeed.
            .task { sheet = sheet ?? demoSheet(data) }
            .task { hoursSheet = hoursSheet ?? DemoSeed.requestedShiftHours }
            .task {
                guard DemoSeed.wantsDemoWrite, let baby = data.babies.first else { return }
                write(baby, "Feed logged") { store in
                    let id = try await store.logEvent(
                        kind: .feed, at: Date(), shiftID: shift.id, babyID: baby.id
                    ) { $0.amountMl = 60 }
                    return { try await $0.deleteEvent(id) }
                }
            }
            #endif
    }

    private func content(_ data: Tonight) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                NightHeader(familyName: family.name, timeZone: data.timeZone)
                if let warning = reminderWarning {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Reminder not set", systemImage: "bell.slash.fill")
                            .font(.headline).foregroundStyle(palette.warn)
                        Text(warning).font(.footnote).foregroundStyle(palette.ink)
                            .accessibilityIdentifier("reminder.warning")
                        Button("Dismiss reminder notice") { reminderWarning = nil }
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().cardSurface(palette)
                }

                ForEach(data.babies) { presentation in
                    BabyStatusCard(
                        baby: presentation,
                        timeZone: data.timeZone,
                        isBusy: busy.contains(presentation.id),
                        onFeed: { sheet = .feed(babyID: presentation.id) },
                        onDiaper: { sheet = .diaper(babyID: presentation.id) },
                        onToggleSleep: { toggleSleep(presentation) },
                        onNote: { sheet = .note(babyID: presentation.id) },
                        onEditBaby: { editingBaby = data.model(for: presentation.id) }
                    )
                }

                TimelineSection(
                    entries: data.timeline,
                    timeZone: data.timeZone,
                    names: data.names,
                    accents: data.accents,
                    title: shift.careContext == .day ? "Today" : "Tonight",
                    onEdit: { sheet = $0 })
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // Clears the floating tab bar, which overlays the scroll content.
            .padding(.bottom, MoonLayout.tabBarClearance)
        }
        .moonBackground(palette)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    extraButtons(data)
                    earlierSleepButtons(data)
                    Button("Shift times", systemImage: "clock.arrow.circlepath") {
                        hoursSheet = .correct
                    }
                    Divider()
                    Button("End shift", systemImage: "moon.stars", role: .destructive) {
                        hoursSheet = .end
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                // Named, because an SF Symbol alone leaves VoiceOver reading
                // "ellipsis.circle" and leaves the suite guessing at bar indices.
                .accessibilityLabel("More")
            }
        }
        .sheet(item: $hoursSheet) { purpose in
            ShiftHoursSheet(
                purpose: purpose,
                window: shift.window,
                asleep: data.babies.filter(\.isAsleep).map(\.name),
                plannedEnd: shift.plannedEndAt
            ) { startedAt, endedAt in
                endShift(startedAt: startedAt, endedAt: endedAt)
            }
            .presentationDetents([.medium, .large])
        }
        // Bottom, not top: the banner now carries a tappable Undo, which has to be
        // in reach of the thumb already holding the phone — and at the top it sat
        // over the very card it was naming, for the six seconds Undo stays up.
        .overlay(alignment: .bottom) { confirmationBanner }
        // An `alert`, for the reason spelled out in `ShiftHoursSheet` — a
        // confirmation dialog loses its cancel button when it presents as a popover.
        .alert(
            pendingConfirm?.title ?? "",
            isPresented: Binding(
                get: { pendingConfirm != nil },
                set: { if !$0 { pendingConfirm = nil } }),
            presenting: pendingConfirm
        ) { prompt in
            Button(prompt.verb, role: prompt.action.isDestructive ? .destructive : nil) {
                Haptics.commit()
                pendingConfirm = nil
                prompt.run()
            }
            Button("Cancel", role: .cancel) { pendingConfirm = nil }
        } message: { prompt in
            if let message = prompt.message { Text(message) }
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .sheet(item: $sheet) { which in
            logSheet(which, data: data)
        }
        .sheet(item: $editingBaby) { baby in
            BabyDetailSheet(
                name: baby.name, accent: baby.accent, birthAt: baby.birthAt
            ) { name, accent, birthAt in
                // Through the store, not the view's context: writing the model
                // directly skipped `updateBaby`'s trim and empty-name guard, and the
                // `try?` meant a failed save still rendered the new name.
                let wasNamed = baby.name
                let woreAccent = baby.accent
                let wasBorn = baby.birthAt
                let id = baby.id
                perform("\(name) updated") { store in
                    try await store.updateBaby(
                        id, name: name, accent: accent, birthAt: birthAt)
                    return {
                        try await $0.updateBaby(
                            id, name: wasNamed, accent: woreAccent, birthAt: wasBorn)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Logging

private extension TonightView {

    @ViewBuilder
    func logSheet(_ which: LogSheet, data: Tonight) -> some View {
        switch which {
        case .editEvent(let id, _):
            editEventSheet(id: id, data: data)
        case .extra(let kind, let babyID):
            newExtraSheet(kind: kind, babyID: babyID, data: data)
        default:
            coreSheet(which, data: data)
        }
    }

    /// The four a thumb reaches for, all of which name a baby.
    @ViewBuilder
    func coreSheet(_ which: LogSheet, data: Tonight) -> some View {
        if let baby = data.babies.first(where: { $0.id == which.babyID }) {  // swiftlint:disable:this all
            switch which {
            case .feed:
                FeedSheet(
                    baby: baby, shift: shift.window, unit: family.volumeUnit,
                    lastFeed: data.lastFeedEntry[baby.id]
                ) {
                    try await logNew(.feed, baby: baby, $0)
                }
            case .diaper:
                DiaperSheet(baby: baby, shift: shift.window) {
                    try await logNew(.diaper, baby: baby, $0)
                }
            case .note:
                NoteSheet(baby: baby, shift: shift.window, presetTags: presetTags) {
                    try await logNew(.note, baby: baby, $0, said: "Note saved")
                }
            case .editSleep(let id, _):
                editSleepSheet(id: id, baby: baby)
            case .pastSleep:
                pastSleepSheet(baby: baby)

            case .extra, .editEvent:
                // Routed before this switch; both can open without a baby.
                EmptyView()
            }
        } else {
            // The baby vanished between tapping and presenting — archived, or a
            // relationship transiently nil during sync. Presenting nothing would
            // leave an empty sheet with no way out.
            Color.clear.onAppear { sheet = nil }
        }
    }

    #if DEBUG
    /// Which sheet a screenshot run asked for. Editing resolves to the newest
    /// record, since its id is not knowable from a launch argument.
    func demoSheet(_ data: Tonight) -> LogSheet? {
        if DemoSeed.editsFirstRecord,
           let newest = shift.liveEvents.max(by: { $0.at < $1.at }) {
            return .editEvent(id: newest.id, babyID: newest.babyIDRaw)
        }
        return DemoSeed.requestedSheet(for: data.babies.first?.id)
    }
    #endif

    /// A pump is about the mother, so it is the one sheet that opens with no baby.
    @ViewBuilder
    func newExtraSheet(kind: EventKind, babyID: UUID?, data: Tonight) -> some View {
        let baby = babyID.flatMap { id in data.babies.first(where: { $0.id == id }) }
        if kind.attachesToBaby && baby == nil {
            Color.clear.onAppear { sheet = nil }
        } else {
            ExtraSheet(
                kind: kind, baby: baby, shift: shift.window, unit: family.volumeUnit
            ) {
                try await logNew(kind, baby: baby, $0)
            }
        }
    }

    /// The tile toggles at the moment it is tapped, so a sleep that ended while
    /// both hands were full had no route at all: you had to toggle a false state
    /// and then correct it from the timeline.
    ///
    /// Flat per baby, not a submenu, for the reason `extraButtons` is flat.
    @ViewBuilder
    func earlierSleepButtons(_ data: Tonight) -> some View {
        if data.babies.count == 1, let only = data.babies.first {
            Button("Log earlier sleep", systemImage: "moon.zzz.fill") {
                sheet = .pastSleep(babyID: only.id)
            }
        } else {
            ForEach(data.babies) { baby in
                Button("Log earlier sleep — \(baby.name)", systemImage: "moon.zzz.fill") {
                    sheet = .pastSleep(babyID: baby.id)
                }
            }
        }
    }

    /// The opt-in kinds live in this menu rather than on the cards. The card's four
    /// controls are the ones a thumb needs at 3am; a fifth and sixth would crowd
    /// them for records that are logged once a night at most.
    @ViewBuilder
    func extraButtons(_ data: Tonight) -> some View {
        ForEach(EventKind.optional.filter { family.enabledKinds.contains($0) }, id: \.self) {
            kind in
            if !kind.attachesToBaby {
                Button("Log \(kind.noun.lowercased())", systemImage: kind.icon) {
                    sheet = .extra(kind: kind, babyID: nil)
                }
            } else if data.babies.count == 1, let only = data.babies.first {
                Button("Log \(kind.noun.lowercased())", systemImage: kind.icon) {
                    sheet = .extra(kind: kind, babyID: only.id)
                }
            } else {
                // Flat, not a submenu. Three levels deep in the dark — ellipsis,
                // then the kind, then the twin — to log one dose of vitamin D.
                ForEach(data.babies) { baby in
                    Button(
                        "Log \(kind.noun.lowercased()) — \(baby.name)",
                        systemImage: kind.icon
                    ) {
                        sheet = .extra(kind: kind, babyID: baby.id)
                    }
                }
            }
        }
    }

    /// Correcting a logged event. The same sheets serve create and edit, seeded
    /// from the stored record — a mis-logged feed was previously permanent.
    @ViewBuilder
    func editEventSheet(id: UUID, data: Tonight) -> some View {
        if let event = shift.liveEvents.first(where: { $0.id == id }) {
            // From the record, not the sheet request: a pump has no baby to pass in.
            let baby = event.babyIDRaw.flatMap { babyID in
                data.babies.first(where: { $0.id == babyID })
            }
            // Read before the write, not inside it: afterwards these would be the
            // values we just saved, and Undo would restore nothing.
            let reminderWas = data.reminders[id]
            let kind = event.kind
            let feedBefore = seededFeedEntry(event, reminderAt: reminderWas)
            let diaperBefore = event.diaperEntry
            let noteBefore = event.noteEntry
            let extraBefore = event.extraEntry
            let restoration = event.restoration
            let loggedAt = event.at
            let zone = shiftTimeZone
            let babyID = baby?.id
            let babyName = baby?.name
            let delete: () -> Void = {
                write(baby, "Entry deleted") { store in
                    try await store.deleteEvent(id)
                    // Unconditional: whatever alarm this record had goes with it.
                    // A pending notification for a deleted feed points at nothing.
                    await FeedReminders.cancel(id)
                    guard let restoration else { return nil }
                    return { store in
                        try await store.restoreEvent(restoration)
                        guard let fireAt = reminderWas, let babyID, let babyName
                        else { return }
                        // `restoreEvent` brings the record back under its original
                        // id, which is the identifier the reminder was filed under —
                        // so the alarm comes back to the same record, not a
                        // lookalike. `try?` for the same reason as an edit's undo:
                        // if that time has now passed there is nothing to restore.
                        try? await FeedReminders.schedule(
                            eventID: id, babyID: babyID, babyName: babyName,
                            feedAt: loggedAt,
                            afterMinutes: Self.minutes(from: loggedAt, to: fireAt),
                            timeZone: zone)
                    }
                }
            }
            let move = reassignment(
                of: id, from: baby, loggedAt: loggedAt, reminderWas: reminderWas,
                data: data)

            switch (kind, baby) {
            case (.feed, let baby?):
                if remindersLoaded {
                FeedSheet(
                    baby: baby, shift: shift.window, unit: family.volumeUnit,
                    editing: feedBefore, reassignment: move, onDelete: delete
                ) {
                    try await saveEdit(id, baby: baby, "Feed", from: feedBefore, to: $0,
                                       reminderWas: reminderWas)
                }
                } else { ProgressView("Loading reminder…") }
            case (.diaper, let baby?):
                DiaperSheet(
                    baby: baby, shift: shift.window,
                    editing: diaperBefore, reassignment: move, onDelete: delete
                ) {
                    try await saveEdit(id, baby: baby, "Diaper", from: diaperBefore, to: $0)
                }
            case (.note, let baby?):
                NoteSheet(
                    baby: baby, shift: shift.window, presetTags: presetTags,
                    editing: noteBefore, reassignment: move, onDelete: delete
                ) {
                    try await saveEdit(id, baby: baby, "Note", from: noteBefore, to: $0)
                }
            case (.pump, _), (.medication, _), (.measurement, _):
                ExtraSheet(
                    kind: kind, baby: baby, shift: shift.window, unit: family.volumeUnit,
                    editing: extraBefore, reassignment: move, onDelete: delete
                ) {
                    try await saveEdit(id, baby: baby, kind.noun, from: extraBefore, to: $0)
                }
            default:
                // A feed, diaper or note with no baby: its sheet is built around
                // naming one, so it stays readable in the timeline but not editable.
                Color.clear.onAppear { sheet = nil }
            }
        } else {
            Color.clear.onAppear { sheet = nil }
        }
    }

    /// `event.feedEntry` reads the record, and the record knows nothing about a
    /// reminder — the notification centre is the only place one exists. The edit
    /// sheet seeds its picker from this entry, so without the offset put back here
    /// it would open reading "off" for a feed that has a reminder pending, and
    /// saving would silently cancel it.
    func seededFeedEntry(_ event: LogEvent, reminderAt: Date?) -> FeedEntry {
        var entry = event.feedEntry
        entry.reminderMinutes = reminderAt.map { Self.minutes(from: event.at, to: $0) } ?? 0
        return entry
    }

    /// The wrong-twin remedy this app is named for. `nil` in a one-baby family,
    /// where there is nowhere to move a record to.
    func reassignment(
        of id: UUID, from baby: BabyPresentation?, loggedAt: Date, reminderWas: Date?,
        data: Tonight
    ) -> Reassignment? {
        // A pump belongs to no baby, so there is nothing to have got wrong.
        guard let baby else { return nil }
        let others = data.babies.filter { $0.id != baby.id }
        guard !others.isEmpty else { return nil }
        let zone = shiftTimeZone
        let wasMinutes = reminderWas.map { Self.minutes(from: loggedAt, to: $0) }
        return Reassignment(
            targets: others.map { ReassignTarget(id: $0.id, name: $0.name) }
        ) { targetID in
            guard let target = data.babies.first(where: { $0.id == targetID }) else { return }
            let from = baby.id
            let fromName = baby.name
            let toName = target.name
            // The "are you sure" for this is raised by `LogSheetChrome`, which owns
            // the menu it is chosen from. See the note on `endShift`.
            write(target, "Moved to \(target.name)") { store in
                try await store.reassignEvent(id, toBaby: targetID)
                // The reminder moves with the record — same identifier, so this
                // rewrites the pending request's title and thread rather than adding
                // a second one. A notification naming the twin this feed no longer
                // belongs to is worse than no notification: it sends her to the
                // wrong cot, which is the exact mistake this menu exists to correct.
                await Self.moveReminder(
                    id, to: targetID, named: toName, feedAt: loggedAt,
                    afterMinutes: wasMinutes, timeZone: zone)
                return { store in
                    try await store.reassignEvent(id, toBaby: from)
                    await Self.moveReminder(
                        id, to: from, named: fromName, feedAt: loggedAt,
                        afterMinutes: wasMinutes, timeZone: zone)
                }
            }
        }
    }

    /// Re-files a pending reminder under a different baby, or gives up on it.
    ///
    /// Not `try` — a move must not be blocked, and must not be left un-undoable, by
    /// an alarm. But it must not survive misaddressed either, so a failure cancels
    /// rather than leaves the old title in place. Both realistic failures land on
    /// the right end state anyway: the fire time having passed means there was
    /// nothing left to deliver, and notifications being off means nothing was
    /// pending to begin with.
    static func moveReminder(
        _ eventID: UUID, to babyID: UUID?, named babyName: String?,
        feedAt: Date, afterMinutes: Int?, timeZone: TimeZone
    ) async {
        guard let afterMinutes, let babyID, let babyName else {
            await FeedReminders.cancel(eventID)
            return
        }
        do {
            try await FeedReminders.schedule(
                eventID: eventID, babyID: babyID, babyName: babyName,
                feedAt: feedAt, afterMinutes: afterMinutes, timeZone: timeZone)
        } catch {
            await FeedReminders.cancel(eventID)
        }
    }

    @ViewBuilder
    func editSleepSheet(id: UUID, baby: BabyPresentation) -> some View {
        if let session = shift.liveSleepSessions.first(where: { $0.id == id }) {
            // Captured before the write, for the same reason as an event's payload.
            let before = SleepEntry(startAt: session.startAt, endAt: session.endAt)
            let shiftID = shift.id
            let babyID = baby.id
            SleepSheet(
                baby: baby, shift: shift.window,
                editing: before,
                onDelete: {
                    write(baby, "Sleep deleted") { store in
                        try await store.deleteSleepSession(id)
                        return {
                            try await $0.restoreSleepSession(
                                id: id, shiftID: shiftID, babyID: babyID,
                                startAt: before.startAt, endAt: before.endAt)
                        }
                    }
                }
            ) { entry in
                try await writeAwaitingSave(baby, "Sleep updated") { store in
                    try await store.updateSleepSession(
                        id, startAt: entry.startAt, endAt: entry.endAt)
                    return {
                        try await $0.updateSleepSession(
                            id, startAt: before.startAt, endAt: before.endAt)
                    }
                }
            }
        } else {
            Color.clear.onAppear { sheet = nil }
        }
    }

    /// Manual entry for a sleep nobody was free to log at the time — the one thing
    /// the tile's toggle cannot record, since toggling now would misdate it and
    /// then need correcting.
    ///
    /// It ends where the baby's current state began: at the start of the sleep she
    /// is in now, or at this moment if she is awake. Touching is safe — the
    /// reconciler merges on starts within two minutes and truncates only a real
    /// overlap — and `recordCompletedSleep` refuses anything closer.
    func pastSleepSheet(baby: BabyPresentation) -> some View {
        let until = baby.asleepSince ?? Date()
        return SleepSheet(
            baby: baby, shift: shift.window,
            earlier: until.addingTimeInterval(-3600), until: until
        ) { entry in
            // `.earlier` never leaves the wake time open, so this is total.
            guard let endAt = entry.endAt else { return }
            try await writeAwaitingSave(baby, "Earlier sleep logged") { store in
                let id = try await store.recordCompletedSleep(
                    shiftID: shift.id, babyID: baby.id,
                    startAt: entry.startAt, endAt: endAt)
                // It did not exist a moment ago, so removing it is the state before.
                return { try await $0.deleteSleepSession(id) }
            }
        }
    }

    var presetTags: [String] {
        let saved = (family.noteTags ?? []).sorted { $0.sortOrder < $1.sortOrder }.map(\.label)
        let day = shift.careContext == .day ? ["Play", "Outing", "Comfort", "Supplies"] : []
        return day + saved.filter { !day.contains($0) }
    }

    /// Both times come from the sheet, never from the clock. Correcting the start
    /// and ending are one write path because ending is the last chance to fix the
    /// start, and the two are read off the same two pickers.
    ///
    /// The "are you sure" for ending lives inside `ShiftHoursSheet`, on the button
    /// that commits — not here. Raising it here would mean setting a dialog while
    /// the sheet that triggered it is still presented and then dismissing out from
    /// under it, and a confirmation that fails to appear is an end-shift that
    /// silently does nothing.
    func endShift(startedAt: Date, endedAt: Date?) {
        let shiftID = shift.id
        let wasStartedAt = shift.startedAt
        let movedStart = startedAt != wasStartedAt
        let reminderIDs = shift.liveEvents.filter { $0.kind == .feed }.map(\.id)
        perform(endedAt == nil ? "Shift times updated" : "Shift ended") { store in
            // Two writes, not one: `endShift` is the call that means "the doula is
            // leaving", and it is the one that refuses an already-closed shift.
            // If the second fails the corrected start still stands — which is the
            // right way round, since that correction was independently true.
            if movedStart {
                try await store.updateShift(shiftID, startedAt: startedAt)
            }
            guard let endedAt else {
                guard movedStart else { return nil }
                return { try await $0.updateShift(shiftID, startedAt: wasStartedAt) }
            }
            try await store.endShift(shiftID, endedAt: endedAt)
            for id in reminderIDs { await FeedReminders.cancel(id) }
            // No Undo: `updateShift` will not reopen a closed shift, because
            // `close(at:)` is the only thing keeping `isOpen` honest.
            return nil
        }
    }

    func toggleSleep(_ baby: BabyPresentation) {
        guard !busy.contains(baby.id) else { return }
        // `SleepToggle` reports only an id, so reopening needs the start the session
        // already had. The card knew it before the tap; afterwards nobody does.
        let wasAsleepSince = baby.asleepSince
        // The question names the change rather than asking it: "Mia is asleep" as an
        // alert title reads as a statement of fact, which is the wrong thing to put
        // above a button that changes it. The verb matches the direction for the same
        // reason — "Change" under "Wake Mia?" makes you re-read the title.
        //
        // The message is how long the state being ended has run, which is the fact
        // that decides the answer. Absent before this baby has slept, exactly as on
        // the card, rather than a length nobody knows.
        let question = baby.isAsleep ? "Wake \(baby.name)?" : "\(baby.name) to sleep?"
        let elapsed = baby.stateSince.map {
            "\(baby.name) has been \(baby.isAsleep ? "asleep" : "awake") "
                + "for \(Fmt.ago($0, now: Date()))."
        }
        confirming(
            .toggleSleep, question,
            verb: baby.isAsleep ? "Wake" : "Sleep",
            message: elapsed
        ) {
            write(baby, baby.isAsleep ? "\(baby.name) awake" : "\(baby.name) asleep") { store in
                switch try await store.toggleSleep(
                    shiftID: shift.id, babyID: baby.id, at: Date()) {
                case .opened(let id):
                    // It began a moment ago, so removing it is exactly the state before.
                    return { try await $0.deleteSleepSession(id) }
                case .closed(let id):
                    guard let wasAsleepSince else { return nil }
                    return {
                        try await $0.updateSleepSession(id, startAt: wasAsleepSince, endAt: nil)
                    }
                }
            }
        }
    }

    /// Every write reports which baby it landed on, so a mis-tap on the wrong twin
    /// is caught now rather than in the morning handoff.
    /// Logging anything. The Undo is the same for every kind: the record did not
    /// exist a moment ago, so removing it is exactly the state before.
    struct ReminderPlan {
        let babyID: UUID
        let babyName: String
        let minutes: Int
        let zone: TimeZone
    }

    func reminderPlan<E: LogEntry>(_ entry: E, baby: BabyPresentation?) -> ReminderPlan? {
        guard let feed = entry as? FeedEntry, feed.reminderMinutes > 0, let baby else { return nil }
        return ReminderPlan(babyID: baby.id, babyName: baby.name,
                            minutes: feed.reminderMinutes, zone: shiftTimeZone)
    }

    /// Reminder failure never turns a durable feed save into a failed sheet save.
    func scheduleReminder(_ id: UUID, _ plan: ReminderPlan, feedAt: Date) async {
        do {
            try await FeedReminders.schedule(eventID: id, babyID: plan.babyID,
                babyName: plan.babyName, feedAt: feedAt, afterMinutes: plan.minutes,
                timeZone: plan.zone)
        } catch {
            // Never leave the old alarm at a time or baby that was just corrected.
            await FeedReminders.cancel(id)
            reminderWarning = "The feed was saved. Its reminder was not set. Check notification settings and choose a future reminder time."
        }
    }

    func logNew<E: LogEntry>(
        _ kind: EventKind, baby: BabyPresentation?, _ entry: E, said: String? = nil
    ) async throws {
        let plan = reminderPlan(entry, baby: baby)
        try await writeAwaitingSave(baby, said ?? "\(kind.noun) logged") { store in
            let id = try await store.logEvent(
                kind: kind, at: entry.at, shiftID: shift.id, babyID: baby?.id
            ) { entry.apply(to: $0) }
            if let plan { await scheduleReminder(id, plan, feedAt: entry.at) }
            return { store in
                try await store.deleteEvent(id)
                await FeedReminders.cancel(id)
            }
        }
    }

    func saveEdit<E: LogEntry>(
        _ id: UUID, baby: BabyPresentation?, _ noun: String, from before: E, to entry: E,
        reminderWas: Date? = nil
    ) async throws {
        let plan = reminderPlan(entry, baby: baby)
        let babyID = baby?.id
        let babyName = baby?.name
        let zone = shiftTimeZone
        let wasMinutes = reminderWas.map { Self.minutes(from: before.at, to: $0) }
        try await writeAwaitingSave(baby, "\(noun) updated") { store in
            try await store.updateEvent(id, at: entry.at) { entry.apply(to: $0) }
            if let plan { await scheduleReminder(id, plan, feedAt: entry.at) }
            else { await FeedReminders.cancel(id) }
            return { store in
                try await store.updateEvent(id, at: before.at) { before.apply(to: $0) }
                await Self.moveReminder(id, to: babyID, named: babyName,
                    feedAt: before.at, afterMinutes: wasMinutes, timeZone: zone)
            }
        }
    }

    static func minutes(from feedAt: Date, to fireAt: Date) -> Int {
        Int((fireAt.timeIntervalSince(feedAt) / 60).rounded())
    }

    var shiftTimeZone: TimeZone { .current }

    /// Sheets await this result so errors leave their entered values available to retry.
    func writeAwaitingSave(
        _ baby: BabyPresentation?,
        _ success: String,
        _ action: @escaping (CareStore) async throws -> Undo?
    ) async throws {
        guard let store else { throw EntrySaveError.unavailable }
        let undo = try await action(store)
        refreshToken &+= 1
        Haptics.success()
        show(baby.map { success.contains($0.name) ? success : "\(success) · \($0.name)" } ?? success,
             undo: undo)
    }

    /// `nil` only for a pump, which is about the mother and names nobody.
    func write(
        _ baby: BabyPresentation?,
        _ success: String,
        _ action: @escaping (CareStore) async throws -> Undo?
    ) {
        guard let baby else {
            perform(success, action)
            return
        }
        perform(
            success.contains(baby.name) ? success : "\(success) · \(baby.name)",
            busyFor: baby.id,
            action)
    }

    /// Asks first, or does not, according to Settings.
    ///
    /// Wraps the call rather than living inside `perform`, because most confirmable
    /// actions are not raised from this screen at all — deleting and moving a record
    /// belong to `LogSheetChrome` and ending a shift to `ShiftHoursSheet`, each of
    /// which owns the control being pressed and, crucially, is a sheet that dismisses
    /// on the way out. Only the sleep toggle is pressed on Tonight itself, so only it
    /// comes through here. The machinery is general because the next one might.
    func confirming(
        _ action: ConfirmableAction,
        _ subject: String,
        verb: String? = nil,
        message: String? = nil,
        _ body: @escaping () -> Void
    ) {
        guard confirms(action) else { return body() }
        Haptics.warn()
        pendingConfirm = ConfirmPrompt(
            action: action,
            title: action.question(subject),
            verb: verb ?? action.verb,
            message: message,
            run: body)
    }

    func confirms(_ action: ConfirmableAction) -> Bool {
        confirmations?.confirms(action) ?? action.confirmsByDefault
    }

    /// The one path every write takes. Failures surface as an alert — a care log
    /// that silently drops an entry is worse than one that stops.
    func perform(
        _ success: String,
        busyFor babyID: UUID? = nil,
        _ action: @escaping (CareStore) async throws -> Undo?
    ) {
        guard let store else {
            // Silently returning would dismiss the sheet and drop the entry with no
            // banner and no alert — total, invisible data loss.
            saveError = "The data store is unavailable. Nothing was saved."
            return
        }
        if let babyID { busy.insert(babyID) }
        Task {
            defer { if let babyID { busy.remove(babyID) } }
            do {
                let undo = try await action(store)
                Haptics.success()
                refreshToken &+= 1
                show(success, undo: undo)
                // The card reads through the main context, which is a merge behind
                // the actor's own, so it still shows the state from before for a
                // moment. Holding the per-baby lock across that gap is what stops a
                // second tap from closing the session the first one just opened.
                try? await Task.sleep(for: .seconds(2))
            } catch {
                Haptics.warn()
                saveError = "\(error)"
            }
        }
    }

    /// An undoable write holds the banner longer. Two seconds is enough to read a
    /// confirmation and not nearly enough to notice a wrong-twin tap and act on it.
    func show(_ text: String, undo: Undo?) {
        confirmationToken &+= 1
        let token = confirmationToken
        confirmation = text
        pendingUndo = undo
        Task {
            try? await Task.sleep(for: .seconds(undo == nil ? 2 : 6))
            // Only the newest confirmation may clear itself.
            guard confirmationToken == token else { return }
            confirmation = nil
            pendingUndo = nil
        }
    }

    func runUndo() {
        guard let store, let undo = pendingUndo else { return }
        confirmation = nil
        pendingUndo = nil
        Task {
            do {
                try await undo(store)
                Haptics.commit()
                refreshToken &+= 1
                show("Undone", undo: nil)
            } catch {
                Haptics.warn()
                saveError = "\(error)"
            }
        }
    }

    @ViewBuilder
    var confirmationBanner: some View {
        if let confirmation {
            HStack(spacing: 14) {
                Text(confirmation)
                    .font(.subheadline.weight(.medium))
                if pendingUndo != nil {
                    // Underlined, because colour is never the only signal that
                    // something can be tapped. See `docs/design.md`.
                    // Padded and shape-clipped, not bare text: the hit region of
                    // a plain-styled `Text` is the glyph bounds, so the app's one
                    // six-second recovery from a wrong-twin tap had a target about
                    // 44×20pt — under both Apple's floor and this app's own 56.
                    Button("Undo") { runUndo() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .underline()
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .contentShape(.rect)
                }
            }
            .foregroundStyle(palette.accentInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .background(palette.accent, in: Capsule())
            .shadow(color: palette.backdrop, radius: 8, y: 2)
            // Clears the floating tab bar, which this would otherwise sit under.
            .padding(.bottom, MoonLayout.tabBarClearance + 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Derived state

/// Everything the screen needs, derived from the shift's records.
///
/// Bucketed by baby id rather than asking each baby to filter the whole event list,
/// which would be O(babies × events). Rebuilt when the records change — the screen
/// no longer ticks; only the live labels inside each card do.
private struct Tonight {
    /// Held only so the value changes when `refreshToken` does. See `body`.
    let generation: Int
    let reminders: [UUID: Date]
    let timeZone: TimeZone
    let babies: [BabyPresentation]
    let timeline: [TimelineEntry]
    let names: [UUID: String]
    let accents: [UUID: BabyAccent]
    /// The values of each baby's most recent feed, for the sheet's "Same as last".
    /// Held per baby, not per household: twins rarely take the same bottle.
    let lastFeedEntry: [UUID: FeedEntry]
    private let models: [UUID: Baby]

    func model(for id: UUID) -> Baby? { models[id] }

    init(family: Family, shift: Shift, now: Date, generation: Int, reminders: [UUID: Date]) {
        self.reminders = reminders
        self.generation = generation
        // The device's zone, not the shift's recorded one. The recorded zone is
        // whatever the phone was in when the client family was added, and there is
        // no editor for it — so a family added away from home leaves the header
        // clock reading an hour off the status bar, and a doula who reads the app
        // clock and then writes that time on a bottle has no way to notice. Night
        // boundaries and day-of-life still run on the family's zone
        // (`Family.calendar`); this is display only. Past nights in History keep
        // their recorded zone, which is the right thing for a night already worked.
        self.timeZone = .current

        let roster = family.activeBabies
        var models: [UUID: Baby] = [:]
        var names: [UUID: String] = [:]
        var accents: [UUID: BabyAccent] = [:]
        var lastFeed: [UUID: Date] = [:]
        var lastFeedEntry: [UUID: FeedEntry] = [:]
        var lastDiaper: [UUID: Date] = [:]
        var nextReminder: [UUID: Date] = [:]
        var reminderFeed: [UUID: Date] = [:]
        var snapshots: [SleepSnapshot] = []

        models.reserveCapacity(roster.count)
        for baby in roster {
            models[baby.id] = baby
            names[baby.id] = baby.name
            accents[baby.id] = baby.accent
        }

        let unit = family.volumeUnit
        let events = shift.liveEvents
        let sessions = shift.liveSleepSessions

        for event in events {
            guard let babyID = event.babyIDRaw else { continue }
            switch event.kind {
            case .feed:
                if let due = reminders[event.id], due < nextReminder[babyID] ?? .distantFuture {
                    nextReminder[babyID] = due
                    reminderFeed[babyID] = event.at
                }
                if event.at > lastFeed[babyID] ?? .distantPast {
                    lastFeed[babyID] = event.at
                    lastFeedEntry[babyID] = event.feedEntry
                }
            case .diaper:
                if event.at > lastDiaper[babyID] ?? .distantPast { lastDiaper[babyID] = event.at }
            case .note, .pump, .medication, .measurement:
                break
            }
        }

        // All of them, not just the open ones: "awake since" is the end of the last
        // closed session, so the closed ones are no longer discardable here.
        for session in sessions {
            if let snapshot = session.snapshot { snapshots.append(snapshot) }
        }

        self.timeline = ShiftTimeline.entries(
            for: shift, unit: unit, now: now, editable: true)
        self.names = names
        self.accents = accents
        self.lastFeedEntry = lastFeedEntry
        self.models = models

        let calendar = family.calendar
        self.babies = roster.map { baby in
            BabyPresentation(
                id: baby.id,
                name: baby.name,
                accent: baby.accent,
                dayOfLife: DayOfLife.calendarDay(
                    birthAt: baby.birthAt, forShift: shift.window, calendar: calendar),
                // Through Core, which breaks an equal-start tie on id so every
                // device resolves a synced duplicate the same way.
                asleepSince: SleepMath.openSession(in: snapshots, forBaby: baby.id)?.startAt,
                awakeSince: SleepMath.lastWake(in: snapshots, forBaby: baby.id),
                lastFeedAt: lastFeed[baby.id],
                lastDiaperAt: lastDiaper[baby.id],
                feedReminderAt: nextReminder[baby.id], reminderFeedAt: reminderFeed[baby.id])
        }
    }

}

// MARK: - Sheet routing

/// A question waiting to be answered, and what to do if it is answered yes.
///
/// Carries the work rather than an enum the dialog switches on, so the gate can sit
/// at the call site — where the captured payload for the Undo already is — instead
/// of every confirmable write having to be reconstructible from a case.
struct ConfirmPrompt: Identifiable {
    let id = UUID()
    let action: ConfirmableAction
    let title: String
    /// Defaults to the action's own verb. Overridden where one action has two
    /// directions — waking and settling are the same toggle and want opposite words.
    let verb: String
    /// A title-only alert reads thin next to the others, and the fact worth putting
    /// under this particular question is how long the state being ended has run.
    let message: String?
    let run: () -> Void
}

enum LogSheet: Identifiable, Equatable {
    case feed(babyID: UUID), diaper(babyID: UUID), note(babyID: UUID)
    /// One of the kinds Settings can enable. `pump` is about the mother, which is
    /// why the baby here — and on `editEvent` — is optional.
    case extra(kind: EventKind, babyID: UUID?)
    /// Correcting an existing record. Carries the record id as well as the baby.
    case editEvent(id: UUID, babyID: UUID?)
    case editSleep(id: UUID, babyID: UUID)
    /// A finished sleep nobody was free to log at the time.
    case pastSleep(babyID: UUID)

    var babyID: UUID? {
        switch self {
        case .feed(let id), .diaper(let id), .note(let id), .pastSleep(let id): return id
        case .editSleep(_, let babyID): return babyID
        case .extra(_, let babyID), .editEvent(_, let babyID): return babyID
        }
    }

    /// Distinct per record, so tapping a different row re-presents rather than
    /// reusing the previous sheet's state.
    var id: String {
        switch self {
        case .editEvent(let id, _): return "event-\(id)"
        case .editSleep(let id, _): return "sleep-\(id)"
        case .extra(let kind, let babyID):
            return "\(kind.rawValue)-\(babyID?.uuidString ?? "household")"
        default: return "\(title)-\(babyID?.uuidString ?? "")"
        }
    }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .diaper: return "Diaper"
        case .editSleep: return "Sleep"
        case .pastSleep: return "Earlier sleep"
        case .note: return "Note"
        case .extra(let kind, _): return kind.noun
        case .editEvent: return "Edit"
        }
    }
}

// MARK: - Display

extension EventKind {
    /// What a confirmation and a sheet title call it.
    var noun: String {
        switch self {
        case .feed: return "Feed"
        case .diaper: return "Diaper"
        case .note: return "Note"
        case .pump: return "Pumping"
        case .medication: return "Medication"
        case .measurement: return "Weight"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "drop.fill"
        // Not an SF Symbol — see `CareGlyph`. Apple has no nappy, and the stack of
        // squares that stood in for one reads as "duplicate".
        case .diaper: return CareGlyph.diaper
        case .note: return "text.bubble.fill"
        case .pump: return "waveform.path"
        case .medication: return "pills.fill"
        case .measurement: return "scalemass.fill"
        }
    }
}

/// Every log entry is a time plus a payload it knows how to write. That is what
/// lets one function log any kind, and one function save an edit to any kind
/// together with the reversal Undo needs.
protocol LogEntry: Sendable {
    var at: Date { get }
    func apply(to event: LogEvent)
}

extension FeedEntry: LogEntry { func apply(to event: LogEvent) { event.apply(self) } }
extension DiaperEntry: LogEntry { func apply(to event: LogEvent) { event.apply(self) } }
extension NoteEntry: LogEntry { func apply(to event: LogEvent) { event.apply(self) } }
extension ExtraEntry: LogEntry { func apply(to event: LogEvent) { event.apply(self) } }

// Each payload is written in exactly one place. It used to appear twice per kind
// — once for logging, once for editing — which is how an edited feed could keep a
// field the new entry had cleared.
extension LogEvent {
    func apply(_ entry: FeedEntry) {
        feedMethodRaw = entry.method.rawValue
        amountMl = entry.amountMl
        feedDurationSeconds = entry.bottleSeconds
        leftSeconds = entry.leftSeconds
        rightSeconds = entry.rightSeconds
    }

    func apply(_ entry: DiaperEntry) {
        diaperContentsRaw = entry.contents.rawValue
        // Written through exactly as the sheet holds it, `nil` included. It used to
        // be cleared whenever the contents stopped counting as dirty, because the
        // colour swatches only appeared for dirty and a colour picked and then
        // corrected away sat invisible in view state and rode into the handoff as
        // meconium on a wet diaper. The swatches are on every diaper now, so
        // nothing can be stranded — and clearing on contents would instead throw
        // away a colour the doula can see and deliberately chose.
        stoolColorRaw = entry.stool?.rawValue
    }

    func apply(_ entry: NoteEntry) {
        text = entry.text.isEmpty ? nil : entry.text
        tagsRaw = entry.tags.isEmpty ? nil : entry.tags.joined(separator: ",")
        tempF = entry.tempF
    }

    func apply(_ entry: ExtraEntry) {
        pumpedMl = entry.pumpedMl
        medicationName = entry.medicationName
        doseText = entry.doseText
        weightGrams = entry.weightGrams
    }

    var extraEntry: ExtraEntry {
        ExtraEntry(
            at: at, pumpedMl: pumpedMl, medicationName: medicationName,
            doseText: doseText, weightGrams: weightGrams)
    }

    var feedEntry: FeedEntry {
        FeedEntry(
            at: at, method: feedMethod ?? .breast, amountMl: amountMl,
            bottleSeconds: feedDurationSeconds,
            leftSeconds: leftSeconds, rightSeconds: rightSeconds)
    }

    var diaperEntry: DiaperEntry {
        DiaperEntry(at: at, contents: diaperContents ?? .wet, stool: stoolColor)
    }

    var noteEntry: NoteEntry {
        NoteEntry(at: at, text: text ?? "", tags: tags, tempF: tempF)
    }

    func timelineTitle(unit: VolumeUnit) -> String {
        switch kind {
        case .feed: return feedMethod.map(Fmt.feedMethod) ?? "Feed"
        case .diaper: return diaperContents.map(Fmt.diaperRecord) ?? "Diaper"
        case .note: return "Note"
        case .pump: return "Pumped"
        case .medication: return "Medication"
        case .measurement: return "Weight"
        }
    }

    /// How long this feed ran, or `nil` for one that recorded no time.
    ///
    /// **By method, never by adding the three fields up.** A bottle's length is
    /// `feedDurationSeconds`; a breast feed's is the two sides added, because they
    /// are consecutive and not concurrent. That is the same either/or
    /// `Handoff.warmFeed` and `timelineDetail` below already answer with, and the
    /// flat model holds all three columns whatever the method is — summing them
    /// would give the trailing edge of a row a length its own subtitle disagrees
    /// with. A missing method reads as breast, as it does in `warmFeed`.
    var feedSeconds: Int? {
        guard kind == .feed else { return nil }
        if feedMethod?.isBottle == true { return feedDurationSeconds }
        guard leftSeconds != nil || rightSeconds != nil else { return nil }
        return (leftSeconds ?? 0) + (rightSeconds ?? 0)
    }

    /// When this record finished, or `nil` for one that took no time.
    ///
    /// Only a feed has a length: `at` is when it started — the sheet pairs a "Time"
    /// with a "Duration" — so a twenty-minute bottle ran from `at` to twenty minutes
    /// later, and the row prints both clocks the way a sleep does. Nothing else on
    /// the timeline is a stretch: a diaper, a note, a weighing and a pump are all
    /// instants, and a range on one of them would be invented.
    var timelineEndAt: Date? {
        guard let seconds = feedSeconds, seconds > 0 else { return nil }
        return at.addingTimeInterval(TimeInterval(seconds))
    }

    func timelineDetail(unit: VolumeUnit) -> String? {
        switch kind {
        case .feed:
            var parts: [String] = []
            if let ml = amountMl { parts.append(Fmt.amount(ml: ml, unit: unit)) }
            if let sides = Fmt.sides(left: leftSeconds, right: rightSeconds) {
                parts.append(sides)
            } else if let s = feedDurationSeconds, s > 0 {
                parts.append(Fmt.duration(TimeInterval(s)))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .diaper:
            return stoolColor?.rawValue.capitalized
        case .note:
            return text
        case .pump:
            return pumpedMl.map { Fmt.amount(ml: $0, unit: unit) }
        case .medication:
            return [medicationName, doseText].compactMap { $0 }.joined(separator: " · ")
        case .measurement:
            return weightGrams.map { Fmt.weight(grams: $0, unit: unit) }
        }
    }
}
