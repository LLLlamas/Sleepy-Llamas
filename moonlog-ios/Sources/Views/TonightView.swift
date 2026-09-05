import SwiftUI
import SwiftData
import MoonlogCore

/// The screen the whole app exists for: what happened, what is happening, and the
/// three buttons you need at 3am.
///
/// Layout is **adaptive**. One baby renders a single status block; two or more
/// render a card each, both states visible at once with per-baby actions, over one
/// shared timeline. There is deliberately no "active baby" selector — a mode you
/// can set wrong is the main hazard twins introduce.
struct TonightView: View {
    let family: Family
    let shift: Shift

    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var modelContext

    @State private var sheet: LogSheet?

    var body: some View {
        // Ticks every 30s, matching the web version's clock. Cheap, and it keeps
        // the sleep timers and "x ago" labels honest without a manual Timer.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let babies = family.activeBabies

        return ScrollView {
            VStack(spacing: 14) {
                ForEach(babies) { baby in
                    BabyStatusCard(
                        baby: presentation(for: baby, now: now),
                        now: now,
                        dueSoonHours: 3,
                        onFeed: { sheet = .feed(babyID: baby.id) },
                        onDiaper: { sheet = .diaper(babyID: baby.id) },
                        onToggleSleep: { sheet = .sleep(babyID: baby.id) }
                    )
                }

                TimelineSection(
                    entries: timelineEntries(now: now),
                    timeZone: timeZone,
                    babyNames: Dictionary(
                        uniqueKeysWithValues: babies.map { ($0.id, $0.name) }),
                    babyAccents: Dictionary(
                        uniqueKeysWithValues: babies.map { ($0.id, $0.accent) })
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(palette.bg)
        .sheet(item: $sheet) { which in
            Text("\(which.title) — coming next")
                .presentationDetents([.medium])
        }
    }

    // MARK: - Derivation

    private var timeZone: TimeZone {
        TimeZone(identifier: shift.timeZoneIdentifier) ?? .current
    }

    private func presentation(for baby: Baby, now: Date) -> BabyPresentation {
        let sessions = (shift.sleepSessions ?? []).compactMap(\.snapshot)
        let open = SleepMath.openSession(in: sessions, forBaby: baby.id)

        let events = (shift.events ?? []).filter { $0.babyIDRaw == baby.id }
        let lastFeed = events.filter { $0.kind == .feed }.map(\.at).max()
        let lastDiaper = events.filter { $0.kind == .diaper }.map(\.at).max()

        // Explicitly ignore a future-dated feed when deciding "overdue". The web
        // version let a mis-tapped PM entry produce a negative age, which silently
        // suppressed this warning for the rest of the night.
        let feedIsDue: Bool = {
            guard let last = lastFeed else { return false }
            let elapsed = now.timeIntervalSince(last)
            guard elapsed >= 0 else { return false }
            return elapsed >= 3 * 3600
        }()

        return BabyPresentation(
            id: baby.id,
            name: baby.name,
            accent: baby.accent,
            dayOfLife: DayOfLife.calendarDay(
                birthAt: baby.birthAt, forShift: shift.window, calendar: family.calendar),
            isAsleep: open != nil,
            asleepSince: open?.startAt,
            lastFeedAt: lastFeed,
            lastDiaperAt: lastDiaper,
            feedIsDue: feedIsDue
        )
    }

    private func timelineEntries(now: Date) -> [TimelineEntry] {
        var entries: [TimelineEntry] = (shift.events ?? []).map { event in
            TimelineEntry(
                id: event.id,
                at: event.at,
                babyID: event.babyIDRaw,
                icon: event.kind.icon,
                title: event.timelineTitle,
                detail: event.timelineDetail)
        }

        for session in shift.sleepSessions ?? [] {
            let ended = session.endAt
            entries.append(
                TimelineEntry(
                    id: session.id,
                    at: session.startAt,
                    babyID: session.babyIDRaw,
                    icon: "moon.zzz.fill",
                    title: "Asleep",
                    detail: ended.map {
                        Fmt.duration($0.timeIntervalSince(session.startAt))
                    } ?? "still asleep"))
        }

        return entries.sorted { $0.at > $1.at }
    }
}

// MARK: - Sheet routing

enum LogSheet: Identifiable, Equatable {
    case feed(babyID: UUID)
    case diaper(babyID: UUID)
    case sleep(babyID: UUID)
    case note(babyID: UUID)

    var id: String {
        switch self {
        case .feed(let b): return "feed-\(b)"
        case .diaper(let b): return "diaper-\(b)"
        case .sleep(let b): return "sleep-\(b)"
        case .note(let b): return "note-\(b)"
        }
    }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .diaper: return "Diaper"
        case .sleep: return "Sleep"
        case .note: return "Note"
        }
    }
}

// MARK: - Display helpers

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
            if let seconds = feedDurationSeconds, seconds > 0 {
                parts.append(Fmt.duration(TimeInterval(seconds)))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .diaper:
            return stoolColor?.rawValue.capitalized
        case .note:
            return text
        }
    }
}
