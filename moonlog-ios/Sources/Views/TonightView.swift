import SwiftUI
import SwiftData
import MoonlogCore

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

    @State private var sheet: LogSheet?
    @State private var editingBaby: Baby?
    @State private var confirmation: String?
    @State private var saveError: String?
    @State private var addingBaby = false
    @State private var confirmEndShift = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let data = Tonight(family: family, shift: shift, now: context.date)
            content(data)
                #if DEBUG
                // Opens a sheet straight from a launch argument, so each one can be
                // rendered and screenshotted without driving the UI. Same rationale
                // as DemoSeed: a test affordance, never reachable in a real run.
                .task { sheet = sheet ?? DemoSeed.requestedSheet(for: data.babies.first?.id) }
                #endif
        }
    }

    private func content(_ data: Tonight) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(data.babies) { presentation in
                    BabyStatusCard(
                        baby: presentation,
                        now: data.now,
                        onFeed: { sheet = .feed(babyID: presentation.id) },
                        onDiaper: { sheet = .diaper(babyID: presentation.id) },
                        onToggleSleep: { toggleSleep(presentation) },
                        onEditBaby: { editingBaby = data.model(for: presentation.id) },
                        onAdjustSleep: { sheet = .sleep(babyID: presentation.id) }
                    )
                }

                TimelineSection(
                    entries: data.timeline,
                    timeZone: data.timeZone,
                    names: data.names,
                    accents: data.accents)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(palette.bg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add baby", systemImage: "person.badge.plus") { addingBaby = true }
                    Divider()
                    Button("End shift", systemImage: "moon.stars", role: .destructive) {
                        confirmEndShift = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $addingBaby) {
            AddBabySheet(familyName: family.name) { name, birthAt in
                guard let store else { return }
                Task {
                    do {
                        _ = try await store.addBaby(to: family.id, name: name, birthAt: birthAt)
                        confirmation = "\(name) added"
                        try? await Task.sleep(for: .seconds(2))
                        confirmation = nil
                    } catch { saveError = "\(error)" }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmDialogEndShift(
            isPresented: $confirmEndShift,
            asleep: data.babies.filter(\.isAsleep).map(\.name)
        ) {
            guard let store else { return }
            Task {
                do { try await store.endShift(shift.id, endedAt: Date()) }
                catch { saveError = "\(error)" }
            }
        }
        .overlay(alignment: .top) { confirmationBanner }
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
            BabyDetailSheet(name: baby.name, accent: baby.accent) { name, accent in
                baby.name = name
                baby.accentRaw = accent.rawValue
                try? modelContext.save()
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Logging

private extension TonightView {

    @ViewBuilder
    func logSheet(_ which: LogSheet, data: Tonight) -> some View {
        if let baby = data.babies.first(where: { $0.id == which.babyID }) {
            switch which {
            case .feed:
                FeedSheet(baby: baby, shift: shift.window, unit: family.volumeUnit) { entry in
                    write(baby, "Feed logged") { store in
                        try await store.logEvent(
                            kind: .feed, at: entry.at, shiftID: shift.id, babyID: baby.id
                        ) { event in
                            event.feedMethodRaw = entry.method.rawValue
                            event.amountMl = entry.amountMl
                            event.feedDurationSeconds = entry.bottleSeconds
                            event.leftSeconds = entry.leftSeconds
                            event.rightSeconds = entry.rightSeconds
                        }
                    }
                }
            case .diaper:
                DiaperSheet(baby: baby, shift: shift.window) { entry in
                    write(baby, "Diaper logged") { store in
                        try await store.logEvent(
                            kind: .diaper, at: entry.at, shiftID: shift.id, babyID: baby.id
                        ) { event in
                            event.diaperContentsRaw = entry.contents.rawValue
                            event.stoolColorRaw = entry.stool?.rawValue
                        }
                    }
                }
            case .note:
                NoteSheet(baby: baby, shift: shift.window, presetTags: presetTags) { entry in
                    write(baby, "Note saved") { store in
                        try await store.logEvent(
                            kind: .note, at: entry.at, shiftID: shift.id, babyID: baby.id
                        ) { event in
                            event.text = entry.text.isEmpty ? nil : entry.text
                            event.tagsRaw = entry.tags.isEmpty ? nil : entry.tags.joined(separator: ",")
                            event.tempF = entry.tempF
                        }
                    }
                }
            case .sleep:
                SleepSheet(
                    baby: baby, shift: shift.window, openSince: baby.asleepSince
                ) { entry in
                    write(baby, entry.endAt == nil ? "Sleep updated" : "Sleep logged") { store in
                        try await store.recordSleep(
                            shiftID: shift.id, babyID: baby.id,
                            startAt: entry.startAt, endAt: entry.endAt)
                    }
                }
            }
        }
    }

    var presetTags: [String] {
        (family.noteTags ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.label)
    }

    func toggleSleep(_ baby: BabyPresentation) {
        write(baby, baby.isAsleep ? "\(baby.name) awake" : "\(baby.name) asleep") { store in
            try await store.toggleSleep(shiftID: shift.id, babyID: baby.id, at: Date())
        }
    }

    /// Every write reports which baby it landed on, so a mis-tap on the wrong twin
    /// is caught now rather than in the morning handoff. Failures surface as an
    /// alert — a care log that silently drops an entry is worse than one that stops.
    func write(
        _ baby: BabyPresentation,
        _ success: String,
        _ action: @escaping (CareStore) async throws -> Void
    ) {
        guard let store else { return }
        Task {
            do {
                try await action(store)
                confirmation = success.contains(baby.name) ? success : "\(success) · \(baby.name)"
                try? await Task.sleep(for: .seconds(2))
                confirmation = nil
            } catch {
                saveError = "\(error)"
            }
        }
    }

    @ViewBuilder
    var confirmationBanner: some View {
        if let confirmation {
            Text(confirmation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.accentInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.accent, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Derived state

/// Everything the screen needs, built in a **single pass** over the shift's records.
///
/// The obvious shape — asking each baby to filter the shift's events — is O(babies ×
/// events) and re-runs on every 30s tick. Bucketing once by baby id makes it
/// O(events + sessions + babies), with the one unavoidable sort for the timeline.
private struct Tonight {
    let now: Date
    let timeZone: TimeZone
    let babies: [BabyPresentation]
    let timeline: [TimelineEntry]
    let names: [UUID: String]
    let accents: [UUID: BabyAccent]
    private let models: [UUID: Baby]

    func model(for id: UUID) -> Baby? { models[id] }

    init(family: Family, shift: Shift, now: Date) {
        self.now = now
        self.timeZone = TimeZone(identifier: shift.timeZoneIdentifier) ?? .current

        let roster = family.activeBabies
        var models: [UUID: Baby] = [:]
        var names: [UUID: String] = [:]
        var accents: [UUID: BabyAccent] = [:]
        var lastFeed: [UUID: Date] = [:]
        var lastDiaper: [UUID: Date] = [:]
        var openSleep: [UUID: SleepSnapshot] = [:]
        var timeline: [TimelineEntry] = []

        models.reserveCapacity(roster.count)
        for baby in roster {
            models[baby.id] = baby
            names[baby.id] = baby.name
            accents[baby.id] = baby.accent
        }

        let unit = family.volumeUnit
        let events = shift.events ?? []
        let sessions = shift.sleepSessions ?? []
        timeline.reserveCapacity(events.count + sessions.count)

        for event in events {
            timeline.append(
                TimelineEntry(
                    id: event.id, at: event.at, babyID: event.babyIDRaw,
                    icon: event.kind.icon, title: event.timelineTitle(unit: unit),
                    detail: event.timelineDetail(unit: unit)))

            guard let babyID = event.babyIDRaw else { continue }
            switch event.kind {
            case .feed:
                if event.at > lastFeed[babyID] ?? .distantPast { lastFeed[babyID] = event.at }
            case .diaper:
                if event.at > lastDiaper[babyID] ?? .distantPast { lastDiaper[babyID] = event.at }
            case .note, .pump, .medication, .measurement:
                break
            }
        }

        for session in sessions {
            timeline.append(
                TimelineEntry(
                    id: session.id, at: session.startAt, babyID: session.babyIDRaw,
                    icon: "moon.zzz.fill", title: "Asleep",
                    detail: session.endAt.map { Fmt.duration($0.timeIntervalSince(session.startAt)) }
                        ?? "still asleep"))

            guard session.isOpen, let snapshot = session.snapshot else { continue }
            // Earliest start wins, so a duplicate delivered by sync resolves the
            // same way on every device. See `SleepReconciler`.
            if snapshot.startAt < openSleep[snapshot.babyID]?.startAt ?? .distantFuture {
                openSleep[snapshot.babyID] = snapshot
            }
        }

        timeline.sort { $0.at > $1.at }
        self.timeline = timeline
        self.names = names
        self.accents = accents
        self.models = models

        let calendar = family.calendar
        self.babies = roster.map { baby in
            let feedAt = lastFeed[baby.id]
            return BabyPresentation(
                id: baby.id,
                name: baby.name,
                accent: baby.accent,
                dayOfLife: DayOfLife.calendarDay(
                    birthAt: baby.birthAt, forShift: shift.window, calendar: calendar),
                asleepSince: openSleep[baby.id]?.startAt,
                lastFeedAt: feedAt,
                lastDiaperAt: lastDiaper[baby.id],
                // A future-dated entry must not suppress the warning, which is
                // what a negative elapsed time did in the web version.
                feedIsDue: feedAt.map {
                    let elapsed = now.timeIntervalSince($0)
                    return elapsed >= 0 && elapsed >= Self.feedDueAfter
                } ?? false)
        }
    }

    private static let feedDueAfter: TimeInterval = 3 * 3600
}

// MARK: - Sheet routing

enum LogSheet: Identifiable, Equatable {
    case feed(babyID: UUID), diaper(babyID: UUID), sleep(babyID: UUID), note(babyID: UUID)

    var babyID: UUID {
        switch self {
        case .feed(let id), .diaper(let id), .sleep(let id), .note(let id): return id
        }
    }

    var id: String { "\(title)-\(babyID)" }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .diaper: return "Diaper"
        case .sleep: return "Sleep"
        case .note: return "Note"
        }
    }
}

// MARK: - Display

extension EventKind {
    var icon: String {
        switch self {
        case .feed: return "drop.fill"
        case .diaper: return "square.on.square"
        case .note: return "text.bubble.fill"
        case .pump: return "waveform.path"
        case .medication: return "pills.fill"
        case .measurement: return "scalemass.fill"
        }
    }
}

extension LogEvent {
    func timelineTitle(unit: VolumeUnit) -> String {
        switch kind {
        case .feed: return feedMethod.map(Fmt.feedMethod) ?? "Feed"
        case .diaper: return diaperContents.map(Fmt.diaper) ?? "Diaper"
        case .note: return "Note"
        case .pump: return "Pumped"
        case .medication: return "Medication"
        case .measurement: return "Weight"
        }
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
