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

    @State private var sheet: LogSheet?
    @State private var editingBaby: Baby?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(Tonight(family: family, shift: shift, now: context.date))
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
                        onToggleSleep: { sheet = .sleep(babyID: presentation.id) },
                        onEditBaby: { editingBaby = data.model(for: presentation.id) }
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
        .sheet(item: $sheet) { which in
            Text("\(which.title) — coming next").presentationDetents([.medium])
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

        let events = shift.events ?? []
        let sessions = shift.sleepSessions ?? []
        timeline.reserveCapacity(events.count + sessions.count)

        for event in events {
            timeline.append(
                TimelineEntry(
                    id: event.id, at: event.at, babyID: event.babyIDRaw,
                    icon: event.kind.icon, title: event.timelineTitle,
                    detail: event.timelineDetail))

            guard let babyID = event.babyIDRaw else { continue }
            switch event.kind {
            case .feed:
                if event.at > lastFeed[babyID] ?? .distantPast { lastFeed[babyID] = event.at }
            case .diaper:
                if event.at > lastDiaper[babyID] ?? .distantPast { lastDiaper[babyID] = event.at }
            case .note:
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
        }
    }
}

extension LogEvent {
    var timelineTitle: String {
        switch kind {
        case .feed: return feedMethod.map(Fmt.feedMethod) ?? "Feed"
        case .diaper: return diaperContents.map(Fmt.diaper) ?? "Diaper"
        case .note: return "Note"
        }
    }

    var timelineDetail: String? {
        switch kind {
        case .feed:
            var parts: [String] = []
            if let ml = amountMl { parts.append(Fmt.amount(ml: ml, unit: .ml)) }
            if let s = feedDurationSeconds, s > 0 { parts.append(Fmt.duration(TimeInterval(s))) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .diaper:
            return stoolColor?.rawValue.capitalized
        case .note:
            return text
        }
    }
}
