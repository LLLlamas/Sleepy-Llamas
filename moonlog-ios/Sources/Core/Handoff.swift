import Foundation

/// One baby, as the handoff needs to name them.
public struct HandoffBaby: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let dayOfLife: Int
    /// Discharged, but their history did not go anywhere. Only `roster` reads this;
    /// once a baby is in the roster the rest of the handoff treats them like any
    /// other. Defaulted, so a caller that has no notion of archiving is unaffected.
    public let isArchived: Bool

    public init(id: UUID, name: String, dayOfLife: Int, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.dayOfLife = dayOfLife
        self.isArchived = isArchived
    }
}

/// The two facts the roster rule needs about a baby. `Baby` — the SwiftData model
/// — conforms in the app, so the Summary cards and the handoff apply one rule
/// instead of two copies of it, which is how the cards came to disagree with the
/// document in the first place.
public protocol RosterMember {
    var id: UUID { get }
    var isArchived: Bool { get }
}

extension HandoffBaby: RosterMember {}

/// The night, written out for the parents.
///
/// Lives in Core, and is a pure function of value types, for two reasons: it is the
/// app's actual output and deserves tests, and it must render the same numbers the
/// Summary screen shows — both go through `Totals.compute`.
///
/// The register is deliberately different from the UI's. The interface uses chips
/// and abbreviations because a tired doula scans it; this is prose because the
/// parents read it over coffee. "left breast", not "Breast L".
///
/// The shape is a **short sequential letter**: who and when at the top, a line of
/// greeting, then each baby's night in a fixed order — feeds, diapers, sleep,
/// medication and weight, notes — and a sign-off. Fixed order matters more than it
/// looks: the parents read one of these every morning, and a document whose
/// sections move around has to be re-read rather than scanned.
public enum Handoff {

    /// Who the night is written about: everyone currently on the family's roster,
    /// plus anyone this shift actually logged something for. Composing from the
    /// active babies alone meant archiving a baby mid-shift silently erased
    /// everything already logged against them from the parents' document.
    ///
    /// An archived baby with nothing logged stays out — an empty section for a
    /// discharged baby is noise on a page read at 6am. Input order is preserved, so
    /// the caller sorts once (by `sortOrder`) and this never reshuffles the cards.
    public static func roster<Member: RosterMember>(
        _ babies: [Member], loggedFor logged: Set<UUID>
    ) -> [Member] {
        babies.filter { !$0.isArchived || logged.contains($0.id) }
    }

    public static func text(
        babies: [HandoffBaby],
        shift: ShiftWindow,
        caregiver: String?,
        events allEvents: [EventSnapshot],
        sessions: [SleepSnapshot],
        unit: VolumeUnit,
        timeZone: TimeZone,
        asOf now: Date
    ) -> String {
        var lines: [String] = []
        let end = shift.endedAt ?? now
        // Clipped once, here, so every list below agrees with the totals above it.
        // Back-dating outside the shift is allowed by design, and the counts have
        // always excluded it — the lists used not to.
        let events = shift.interval(asOf: now)
            .map { window in allEvents.filter { window.contains($0.at) } } ?? []

        lines.append(
            header(babies: babies, shift: shift, end: end, timeZone: timeZone))
        if let caregiver, !caregiver.isEmpty {
            lines.append("Cared for by \(caregiver)")
        }
        // The letter's opening. One line here, two paragraphs on the keepsake page:
        // this one is pasted into Messages, where anything longer is scrolled past
        // to reach the numbers.
        lines.append("")
        lines.append(greeting(babies: babies, shift: shift))

        for baby in babies {
            let totals = Totals.compute(
                events: allEvents, sessions: sessions, forBaby: baby.id,
                shift: shift, asOf: now)
            lines.append("")
            if babies.count > 1 {
                lines.append("— \(baby.name) · Day \(baby.dayOfLife) —")
                lines.append("")
            }
            // A blank line between blocks: pasted into Messages at 6am, an
            // unbroken wall of text is not read.
            lines.append(contentsOf: feedBlock(baby, totals, events, unit, timeZone))
            lines.append("")
            lines.append(contentsOf: diaperBlock(baby, totals, events, timeZone))
            lines.append("")
            lines.append(contentsOf: sleepBlock(baby, totals, sessions, shift, now, timeZone))
            let extras = extrasBlock(baby, totals, events, unit, timeZone)
            if !extras.isEmpty {
                lines.append("")
                lines.append(contentsOf: extras)
            }
            let notes = noteBlock(baby, events, timeZone)
            if !notes.isEmpty {
                lines.append("")
                lines.append(contentsOf: notes)
            }
        }

        // Records logged against a baby who is nowhere in the roster — a `Baby`
        // deleted out from under its history, or a relationship that never arrived
        // from sync. They were logged for somebody, so they must not vanish from the
        // parents' page just because the name has. Roster-independent, like the
        // household total below it.
        let stray = unattributedBlock(
            babies, events, sessions, shift, now, unit, timeZone)
        if !stray.isEmpty {
            lines.append("")
            lines.append(contentsOf: stray)
        }

        let household = Totals.household(events: allEvents, shift: shift, asOf: now)
        if !household.isEmpty {
            lines.append("")
            lines.append("🫙  Pumped · \(pumpSummary(household, unit: unit))")
            for (time, amount) in pumpRows(events, unit: unit, timeZone: timeZone) {
                lines.append("     \(time)  \(amount)")
            }
        }

        lines.append("")
        if let caregiver, !caregiver.isEmpty {
            lines.append("With care,")
            lines.append("\(caregiver) 🌙")
        } else {
            lines.append("🌙 logged with Moonlog")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Blocks

    private static func header(
        babies: [HandoffBaby], shift: ShiftWindow, end: Date, timeZone: TimeZone
    ) -> String {
        // An open shift must not read as a finished one. The PWA framed this as
        // "summary through <time>" and that honesty was dropped in the port.
        let line = shift.isOpen
            ? "Shift started \(Fmt.clock(shift.startedAt, timeZone: timeZone)) · "
                + "summary through \(Fmt.clock(end, timeZone: timeZone)) · "
                + onWatch(shift, end: end)
            : "Shift \(Fmt.clock(shift.startedAt, timeZone: timeZone)) → "
                + "\(Fmt.clock(end, timeZone: timeZone)) · \(onWatch(shift, end: end))"
        // The date written out rather than abbreviated. "Fri, Sep 4" is the register
        // of a list of past nights; this is the first line of a letter about one.
        return """
        🌙 \(title(babies))
        \(Fmt.longDate(shift.startedAt, timeZone: timeZone))
        \(line)
        """
    }

    /// "Mia's night · Day 6" / "Mia & Leo's night". The day of life only rides on
    /// the title when there is one baby to own it; with twins each block carries
    /// its own, because they are not always the same number.
    static func title(_ babies: [HandoffBaby]) -> String {
        let names = babies.map(\.name)
        switch names.count {
        case 0: return "The night"
        case 1: return "\(names[0])'s night · Day \(babies[0].dayOfLife)"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head) & \(names[names.count - 1])'s night"
        }
    }

    /// The line that turns a table of counts into a letter. Shared, so the keepsake
    /// page opens with the same sentence the 6am message did.
    ///
    /// "Good morning" is only true of a finished night. This page can legitimately
    /// be shared at 1am, mid-shift, and greeting the parents with the wrong time of
    /// day is the sort of small wrongness that makes a document feel generated.
    static func greeting(babies: [HandoffBaby], shift: ShiftWindow) -> String {
        let names = babies.map(\.name)
        let whose: String
        switch names.count {
        case 0: whose = "the night"
        case 1: whose = "\(names[0])'s night"
        default:
            let head = names.dropLast().joined(separator: ", ")
            whose = "\(head) & \(names[names.count - 1])'s night"
        }
        return shift.isOpen
            ? "Here is \(whose) so far, just as it happened."
            : "Good morning. Here is \(whose), just as it happened."
    }

    /// How long the doula was on watch. An open shift has not finished, so it says
    /// "so far" rather than reporting a total that is still growing.
    static func onWatch(_ shift: ShiftWindow, end: Date) -> String {
        Fmt.paddedDuration(end.timeIntervalSince(shift.startedAt))
            + (shift.isOpen ? " so far" : " on watch")
    }

    /// "No feeds logged this shift." A whole sentence, because an empty section on a
    /// page the family keeps reads as something missing unless it says plainly that
    /// there was nothing to record.
    static func nothingLogged(_ what: String) -> String {
        "No \(what) logged this shift."
    }

    private static func feedBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals,
        _ events: [EventSnapshot], _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        var out = ["🍼  Feeds · \(totals.feeds)"
            + (feedSummary(totals, unit: unit).map { "  (\($0))" } ?? "")]
        let feeds = events
            .filter { $0.babyID == baby.id && $0.kind == .feed }
            .sorted { $0.at < $1.at }
        for feed in feeds {
            out.append("     \(Fmt.shortClock(feed.at, timeZone: timeZone))  "
                + warmFeed(feed, unit: unit))
        }
        if feeds.isEmpty { out.append("     \(nothingLogged("feeds"))") }
        return out
    }

    /// What the feeds added up to, hedged. A total is a sum of estimates a doula
    /// read off a bottle in the dark, and "about" is the honest register for it —
    /// the PWA said "about 12 oz" and the port dropped the word.
    ///
    /// Breast time is reported beside it rather than folded in: a night of two
    /// bottles and forty minutes at the breast is not four ounces of feeding, and
    /// the volume alone made those nights look thin.
    static func feedSummary(_ totals: ShiftTotals, unit: VolumeUnit) -> String? {
        var parts: [String] = []
        if totals.feedMl > 0 {
            parts.append("about \(Fmt.amountTotal(ml: totals.feedMl, unit: unit)) by bottle")
        }
        if totals.breastSeconds > 0 {
            parts.append("\(Fmt.spanned(totals.breastSeconds)) at the breast")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Prose, not chips. "left breast — 18 min" reads; "Breast L · 18m" does not.
    ///
    /// Internal rather than private so `HandoffHTML` describes a feed with exactly
    /// these words. Two documents about the same night that phrase it differently
    /// is how the parents end up asking which one is right.
    static func warmFeed(_ feed: EventSnapshot, unit: VolumeUnit) -> String {
        var method = "feed"
        // One dash, then commas. A bottle with an amount and a duration used to
        // join on the dash as well — "bottle, breastmilk — 3 oz — 20m" — which put
        // two of them in a line meant to read as a sentence.
        var details: [String] = []
        switch feed.feedMethod {
        case .breast, .none:
            let left = feed.leftSeconds ?? 0
            let right = feed.rightSeconds ?? 0
            if left > 0 && right > 0 {
                method = "both sides"
                details.append("left \(Fmt.duration(TimeInterval(left)))")
                details.append("right \(Fmt.duration(TimeInterval(right)))")
            } else if left > 0 {
                method = "left breast"
                details.append(Fmt.duration(TimeInterval(left)))
            } else if right > 0 {
                method = "right breast"
                details.append(Fmt.duration(TimeInterval(right)))
            } else {
                method = "breast"
            }
        case .bottleBreastmilk, .bottleFormula:
            method = feed.feedMethod == .bottleFormula
                ? "bottle, formula" : "bottle, breastmilk"
            if let ml = feed.amountMl, ml > 0 {
                details.append(Fmt.amount(ml: ml, unit: unit))
            }
            if let s = feed.feedDurationSeconds, s > 0 {
                details.append(Fmt.duration(TimeInterval(s)))
            }
        case .unknown:
            break
        }
        return details.isEmpty ? method : "\(method) — \(details.joined(separator: ", "))"
    }

    /// What a note actually says. Shared with `HandoffHTML` so the keepsake page and
    /// the plain text describe one note identically — the keepsake used to drop the
    /// tags, which meant a note logged as "Spit-up" and nothing else reached the
    /// parents as a timestamp with no words next to it.
    static func noteDetail(_ note: EventSnapshot) -> String {
        var pieces: [String] = []
        if let text = note.text, !text.isEmpty { pieces.append(text) }
        if !note.noteTags.isEmpty { pieces.append(note.noteTags.joined(separator: ", ")) }
        if let temp = note.tempF {
            pieces.append(String(format: "%.1f°F", temp)
                + (temp >= ShiftTotals.feverThresholdF ? " — tell the parents" : ""))
        }
        return pieces.isEmpty ? "note" : pieces.joined(separator: " · ")
    }

    /// Shared for the same reason. The `filter` is load-bearing: `compactMap` alone
    /// keeps an empty string, which renders as a dangling separator.
    static func medicationDetail(_ event: EventSnapshot) -> String {
        let what = [event.medicationName, event.doseText]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return what.isEmpty ? "given" : what
    }

    private static func diaperBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals, _ events: [EventSnapshot],
        _ timeZone: TimeZone
    ) -> [String] {
        var out = ["🧷  Diapers · \(totals.diapers)"
            + (diaperSplit(totals).map { "  (\($0))" } ?? "")]
        if let colours = diaperColours(totals, in: events, forBaby: baby.id) {
            out.append("     \(colours)")
        }
        // A row per change, like every other section. This was a count and a colour
        // on purpose — "eight rows of wet" was not thought to be the shape of the
        // night — but the record is what the family and their pediatrician are
        // handed, and a change with no time on it cannot be placed against a feed.
        let changes = events
            .filter { $0.babyID == baby.id && $0.kind == .diaper }
            .sorted { $0.at < $1.at }
        for change in changes {
            out.append("     \(Fmt.shortClock(change.at, timeZone: timeZone))  "
                + diaperDetail(change))
        }
        if changes.isEmpty { out.append("     \(nothingLogged("diapers"))") }
        return out
    }

    /// "3 wet, 2 dirty". `nil` when there were no changes at all, so the count line
    /// does not trail an empty bracket.
    static func diaperSplit(_ totals: ShiftTotals) -> String? {
        totals.diapers > 0 ? "\(totals.wet) wet, \(totals.dirty) dirty" : nil
    }

    /// The word in front of a colour progression: **"Stool"** when a dirty diaper
    /// contributed one of those colours, **"Colour"** when they only came from wet
    /// ones.
    ///
    /// `ShiftTotals.stoolProgression` collects a colour from *any* diaper that
    /// carries one, and since the diaper sheet started offering the swatches for a
    /// wet change too, a legal record is `contents: .wet` with a colour against it.
    /// A fixed "Stool" label then reports stool on a night that had none — which is
    /// the one thing on this line the parents and the pediatrician are actually
    /// reading it for.
    ///
    /// Public because the Summary screen labels the same progression and must not
    /// answer differently from the handoff. Pass it the **same** events and baby the
    /// totals were computed from; that is what makes the two agree by construction
    /// rather than by inspection. `nil` for `babyID` asks about every baby at once.
    public static func diaperColourLabel(
        in events: [EventSnapshot], forBaby babyID: UUID? = nil
    ) -> String {
        let fromStool = events.contains {
            $0.kind == .diaper && $0.stoolColor != nil
                && (babyID == nil || $0.babyID == babyID)
                && ($0.diaperContents ?? .unknown).countsAsDirty
        }
        return fromStool ? "Stool" : "Colour"
    }

    /// One change, named as a record rather than as a state — "wet diaper", with the
    /// colour when there is one. Shared by the text, the keepsake page and the
    /// stray-record list, so a change is described in one voice wherever it appears.
    static func diaperDetail(_ event: EventSnapshot) -> String {
        // `Fmt.diaperRecord(.unknown)` is already the word "Diaper"; appending the
        // noun to it would read "diaper diaper". The colour rides along because a
        // wet change can now carry one.
        let colour = event.stoolColor.map { " — \(Fmt.stool($0).lowercased())" } ?? ""
        return Fmt.diaperRecord(event.diaperContents ?? .unknown).lowercased() + colour
    }

    /// That label with the progression behind it — the marker the parents and the
    /// pediatrician are watching. `nil` when no colour was recorded at all.
    static func diaperColours(
        _ totals: ShiftTotals, in events: [EventSnapshot], forBaby babyID: UUID
    ) -> String? {
        guard !totals.stoolProgression.isEmpty else { return nil }
        let progression = totals.stoolProgression.map(Fmt.stool).joined(separator: " → ")
        return "\(diaperColourLabel(in: events, forBaby: babyID)): \(progression)"
    }

    private static func sleepBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals, _ sessions: [SleepSnapshot],
        _ shift: ShiftWindow, _ now: Date, _ timeZone: TimeZone
    ) -> [String] {
        var out = ["😴  Sleep · \(sleepSummary(totals))"]
        // The single fact a parent most wants at 6am, and it leads: the stretches
        // below it end with the same session, so putting it underneath them read as
        // a repetition rather than as the answer.
        if let open = SleepMath.openSession(in: sessions, forBaby: baby.id) {
            out.append("     \(stillAsleep(open, timeZone: timeZone))")
        }
        // The stretches themselves, not only what they added up to. Sleep was the
        // one section giving a total where feeds and notes gave a sequence, and a
        // parent asking "when did she go down?" had nothing to read.
        for (start, rest) in sleepRows(
            sessions, forBaby: baby.id, clippedTo: shift, asOf: now, timeZone: timeZone
        ) {
            out.append("     \(start)  \(rest)")
        }
        return out
    }

    /// "3h 10m over 2 stretches · longest 2h 10m".
    static func sleepSummary(_ totals: ShiftTotals) -> String {
        guard let stretches = sleepStretches(totals) else { return "none logged" }
        return "\(Fmt.spanned(totals.sleepSeconds)) over \(stretches)"
    }

    /// The tail of that line on its own, for the stat tile whose value is already
    /// the total. `nil` when nobody slept. The longest stretch is left off when
    /// there was only one, where it is the same number twice.
    static func sleepStretches(_ totals: ShiftTotals) -> String? {
        guard totals.stretches > 0 else { return nil }
        var out = "\(totals.stretches) stretch\(totals.stretches == 1 ? "" : "es")"
        if totals.stretches > 1 && totals.longestStretchSeconds > 0 {
            out += " · longest \(Fmt.spanned(totals.longestStretchSeconds))"
        }
        return out
    }

    /// One row per stretch: the time it began, then where it went.
    ///
    /// The times are the **clipped** ones, like every other figure in the document —
    /// a stretch that began before the doula arrived is reported from the moment she
    /// was there to watch it, so the rows add up to the total printed above them.
    static func sleepRows(
        _ sessions: [SleepSnapshot], forBaby babyID: UUID,
        clippedTo shift: ShiftWindow, asOf now: Date, timeZone: TimeZone
    ) -> [(String, String)] {
        SleepMath.stretches(of: sessions, forBaby: babyID, clippedTo: shift, asOf: now)
            .map {
                (Fmt.shortClock($0.start, timeZone: timeZone),
                 sleepTail($0, endLabel: Fmt.shortClock($0.end, timeZone: timeZone)))
            }
    }

    /// Where a stretch went, given the time it began: when the baby woke and how
    /// long it lasted, or that it has not ended yet.
    ///
    /// The caller supplies the wake time already formatted, because the two
    /// documents and the timeline set a clock differently and only the *sentence*
    /// is shared. An open session has no end to print — "so far" is the same
    /// honesty the header applies to an open shift.
    public static func sleepTail(_ stretch: SleepStretch, endLabel: String) -> String {
        let length = Fmt.spanned(stretch.seconds)
        return stretch.isOpen
            ? "still asleep · \(length) so far"
            : "→ \(endLabel) · \(length)"
    }

    /// Lower-cased and unpunctuated, because the two documents set it differently —
    /// a bullet in the text, a callout on the page. The words are shared; only the
    /// casing is the renderer's.
    static func stillAsleep(_ session: SleepSnapshot, timeZone: TimeZone) -> String {
        "still asleep, since \(Fmt.clock(session.startAt, timeZone: timeZone))"
    }

    /// One row per session, oldest first. `events` is the clipped list and
    /// `Totals.household` clips to the same window, so the rows and the total above
    /// them count the same sessions.
    static func pumpRows(
        _ events: [EventSnapshot], unit: VolumeUnit, timeZone: TimeZone
    ) -> [(String, String)] {
        events
            .filter { $0.kind == .pump }
            .sorted { $0.at < $1.at }
            .map {
                (Fmt.shortClock($0.at, timeZone: timeZone),
                 Fmt.amount(ml: $0.pumpedMl ?? 0, unit: unit))
            }
    }

    static func pumpSummary(_ household: HouseholdTotals, unit: VolumeUnit) -> String {
        "\(Fmt.amountTotal(ml: household.pumpedMl, unit: unit)) over "
            + "\(household.pumpSessions) session\(household.pumpSessions == 1 ? "" : "s")"
    }

    /// Medication and weight, when the family logs them. Previously computed and
    /// then rendered nowhere, so a dose given at 2am never reached the parents.
    private static func extrasBlock(
        _ baby: HandoffBaby, _ totals: ShiftTotals,
        _ events: [EventSnapshot], _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        var out: [String] = []
        let meds = events
            .filter { $0.babyID == baby.id && $0.kind == .medication }
            .sorted { $0.at < $1.at }
        if !meds.isEmpty {
            out.append("💊  Medication · \(meds.count)")
            for med in meds {
                out.append("     \(Fmt.shortClock(med.at, timeZone: timeZone))  "
                    + medicationDetail(med))
            }
        }
        // The rows carry the value, so the heading does not: with one weighing —
        // which is the usual number — a heading naming the latest was the row
        // underneath it printed twice, once without its time.
        let weights = weightRows(baby, events, unit, timeZone)
        if !weights.isEmpty {
            out.append("⚖️  Weight" + (weights.count > 1 ? " · \(weights.count) taken" : ""))
            for (time, reading) in weights {
                out.append("     \(time)  \(reading)")
            }
        }
        return out
    }

    /// Every weighing with a number on it, oldest first. Shared with the keepsake
    /// page. `events` is the clipped list, so these agree with the heading above
    /// them — `Totals.compute` clips to the same window.
    static func weightRows(
        _ baby: HandoffBaby, _ events: [EventSnapshot],
        _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [(String, String)] {
        events
            .filter { $0.babyID == baby.id && $0.kind == .measurement }
            .sorted { $0.at < $1.at }
            .compactMap { event in
                guard let grams = event.weightGrams else { return nil }
                return (Fmt.shortClock(event.at, timeZone: timeZone),
                        Fmt.weight(grams: grams, unit: unit))
            }
    }

    /// The catch-all for records whose baby the roster does not name. Sleep is
    /// clipped to the shift like everywhere else, so a session that contributed no
    /// time inside the window is not announced as a record.
    ///
    /// `EventSnapshot.noBaby` is deliberately not an orphan: a pump carries no baby
    /// by design and is reported as a household total, not as a lost record.
    private static func unattributedBlock(
        _ babies: [HandoffBaby], _ events: [EventSnapshot], _ sessions: [SleepSnapshot],
        _ shift: ShiftWindow, _ now: Date, _ unit: VolumeUnit, _ timeZone: TimeZone
    ) -> [String] {
        let named = Set(babies.map(\.id))
        let orphanEvents = events
            .filter { !named.contains($0.babyID) && $0.babyID != EventSnapshot.noBaby }
            .sorted { $0.at < $1.at }
        let orphanSleep = sessions
            .filter { !named.contains($0.babyID) }
            .map { ($0, SleepMath.seconds(of: $0, clippedTo: shift, asOf: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.0.startAt < $1.0.startAt }

        let count = orphanEvents.count + orphanSleep.count
        guard count > 0 else { return [] }

        var out = ["❔  Not matched to a baby · \(count) record"
            + (count == 1 ? "" : "s")]
        for event in orphanEvents {
            out.append("     \(Fmt.shortClock(event.at, timeZone: timeZone))  "
                + strayLine(event, unit: unit))
        }
        for (session, seconds) in orphanSleep {
            out.append("     \(Fmt.shortClock(session.startAt, timeZone: timeZone))  "
                + "asleep — \(Fmt.duration(seconds))")
        }
        return out
    }

    /// Terser than the per-baby blocks on purpose: without a name to head them,
    /// these lines have to say what each record was.
    /// Internal so `HandoffHTML` describes a stray record with the same words.
    static func strayLine(_ event: EventSnapshot, unit: VolumeUnit) -> String {
        switch event.kind {
        case .feed:
            return warmFeed(event, unit: unit)
        case .diaper:
            return diaperDetail(event)
        case .note:
            if let text = event.text, !text.isEmpty { return text }
            return event.noteTags.isEmpty ? "note" : event.noteTags.joined(separator: ", ")
        case .medication:
            let what = medicationDetail(event)
            return what == "given" ? "medication given" : "medication — \(what)"
        case .measurement:
            guard let grams = event.weightGrams else { return "measurement" }
            return "weighed \(Fmt.weight(grams: grams, unit: unit))"
        case .pump:
            // Filtered out above; a pump reaching here would carry a real baby id,
            // which no write path produces.
            return "pumped"
        }
    }

    private static func noteBlock(
        _ baby: HandoffBaby, _ events: [EventSnapshot], _ timeZone: TimeZone
    ) -> [String] {
        let notes = events
            .filter { $0.babyID == baby.id && $0.kind == .note }
            .sorted { $0.at < $1.at }
        guard !notes.isEmpty else { return [] }
        var out = ["📝  Notes"]
        for note in notes {
            out.append("     \(Fmt.shortClock(note.at, timeZone: timeZone))  "
                + noteDetail(note))
        }
        return out
    }
}
