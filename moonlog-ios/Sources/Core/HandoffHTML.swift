import Foundation

/// The keepsake handoff: the same night as `Handoff.text`, laid out to be read.
///
/// The plain-text version exists to be pasted into Messages at 6am. This one is
/// what gets sent to the family afterwards — so it is a document, with the numbers
/// up front and the entries underneath.
///
/// Three constraints shape it, all deliberate:
///
/// - **Self-contained.** No external stylesheet, font, script or image. The page is
///   forwarded, saved to Files and opened offline months later, and anything fetched
///   over the network would be missing by then — or would tell a third party when
///   the parents opened it.
/// - **Responsive.** They will open it on a phone, so the layout is fluid and the
///   stat tiles reflow rather than assuming a page width.
/// - **Pure.** Same rule as the rest of `MoonlogCore`: value types in, `String` out,
///   no `Date.now`. It takes the same arguments as `Handoff.text` and derives its
///   numbers from the same `Totals.compute`, so the two documents cannot disagree.
public enum HandoffHTML {

    public static func render(
        babies: [HandoffBaby],
        shift: ShiftWindow,
        caregiver: String?,
        note: String?,
        events allEvents: [EventSnapshot],
        sessions: [SleepSnapshot],
        unit: VolumeUnit,
        timeZone: TimeZone,
        asOf now: Date
    ) -> String {
        // Clipped exactly as the text version clips, so a back-dated record is
        // excluded from both lists and both counts rather than one of each.
        let events = shift.interval(asOf: now)
            .map { window in allEvents.filter { window.contains($0.at) } } ?? []

        var body = ""
        body += headerHTML(
            babies: babies, shift: shift, caregiver: caregiver, timeZone: timeZone)
        body += noteHTML(note, caregiver: caregiver)

        for baby in babies {
            let totals = Totals.compute(
                events: allEvents, sessions: sessions, forBaby: baby.id,
                shift: shift, asOf: now)
            body += babyHTML(
                baby, totals: totals, events: events, sessions: sessions,
                shift: shift, unit: unit, timeZone: timeZone, now: now,
                namesBaby: babies.count > 1)
        }

        // Records logged against a baby the roster cannot name — a `Baby` deleted
        // out from under its history, or a relationship still in flight from sync.
        // They were logged for somebody, so they must not vanish from the page the
        // family keeps just because the name has.
        body += unattributedHTML(
            babies: babies, events: events, sessions: sessions,
            shift: shift, unit: unit, timeZone: timeZone, now: now)

        let household = Totals.household(events: allEvents, shift: shift, asOf: now)
        if !household.isEmpty {
            body += """
            <section class="card"><h2>Pumping</h2><p class="line">\
            \(esc(Fmt.amountTotal(ml: household.pumpedMl, unit: unit))) over \
            \(household.pumpSessions) session\(household.pumpSessions == 1 ? "" : "s").</p>\
            </section>
            """
        }

        body += footerHTML(caregiver: caregiver)
        return document(title: documentTitle(babies: babies, shift: shift, timeZone: timeZone),
                        body: body)
    }

    // MARK: - Shell

    /// Wraps the body in a complete, standalone document.
    ///
    /// The stylesheet is inline for the self-containment reason above. It is written
    /// mobile-first — the parents open this on a phone — and the tiles are the only
    /// thing that reflows, via `auto-fit`, so there are no breakpoints to maintain.
    private static func document(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(title))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>
        """
    }

    private static let stylesheet = """
    /* Day palette, copied from the app's tokens. It is a COPY, not a shared
       source: `Palette` lives in the app target and this file is in Core, which
       cannot import it. The two diverged on 2026-09-06, when the app's Day
       `faint`, `sleep` and `stop` were darkened to hold AA against `chip` and
       `raised2` — surfaces this document does not have. Every pair used here was
       measured at WCAG 2.1 and holds: faint on bg 5.48:1, faint on raised 5.65:1,
       sleep on bg 4.53:1, soft on bg 7.24:1, accent on bg 6.13:1. Re-measure
       before changing one; `PaletteTests` does not cover this file. */
    :root {
      --bg: #fdf6f4; --raised: #fffaf8; --ink: #2a1418; --soft: #6b4a4f;
      --faint: #7e5c61; --line: rgba(61,15,23,0.12); --accent: #a83246;
      --accent-deep: #6b1a28; --accent-faint: #f7e6e2; --sleep: #3f7d68;
    }
    /* The Night palette, for a phone in dark mode at 6am. */
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #1a0a0e; --raised: #241016; --ink: #f7ece9; --soft: #d9bcbd;
        --faint: #bb979c; --line: #3f2129; --accent: #d9a96b;
        --accent-deep: #bd8748; --accent-faint: #3a2a1d; --sleep: #8fb8a8;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; background: var(--bg); color: var(--ink);
      font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      -webkit-text-size-adjust: 100%;
    }
    main { max-width: 40rem; margin: 0 auto; padding: 2rem 1.15rem 3rem; }
    /* Fraunces is the intended face for this document, but no font file is bundled
       and nothing may be fetched, so a serif stack carries the brand moments. */
    h1, h2, .sig, .tile-value {
      font-family: ui-serif, Georgia, "Times New Roman", serif; font-weight: 600;
    }
    header { margin-bottom: 1.75rem; }
    .eyebrow {
      margin: 0 0 .3rem; color: var(--accent); font-size: .82rem;
      font-weight: 600; letter-spacing: .07em; text-transform: uppercase;
    }
    h1 { margin: 0; font-size: 2rem; line-height: 1.15; }
    .span { margin: .3rem 0 0; color: var(--soft); font-size: .95rem; }
    .note {
      background: var(--accent-faint); border-radius: 16px;
      padding: 1.1rem 1.25rem; margin-bottom: 1.5rem;
    }
    .note-body p { margin: 0 0 .7rem; }
    .note-body p:last-child { margin-bottom: 0; }
    .signoff { margin: .8rem 0 0; color: var(--accent-deep); font-size: .92rem; }
    .card {
      background: var(--raised); border: 1px solid var(--line); border-radius: 16px;
      padding: 1.25rem; margin-bottom: 1.25rem;
    }
    .baby { display: flex; align-items: baseline; gap: .6rem; margin-bottom: 1rem; }
    h2 { margin: 0; font-size: 1.4rem; }
    .day {
      color: var(--accent); font-size: .8rem; font-weight: 600;
      letter-spacing: .05em; text-transform: uppercase;
    }
    /* Sleep leads full width — it is the headline number and carries the longest
       caption — with feeds and diapers paired underneath. `auto-fit` was tried and
       left a hole: three tiles in two columns means the third sits alone beside an
       empty cell. Wider than a phone, all three fit in a row. */
    .tiles {
      display: grid; gap: .6rem; margin-bottom: 1rem;
      grid-template-columns: 1fr 1fr;
    }
    .tile:first-child { grid-column: 1 / -1; }
    @media (min-width: 34rem) {
      .tiles { grid-template-columns: repeat(3, 1fr); }
      .tile:first-child { grid-column: auto; }
    }
    .tile {
      background: var(--bg); border: 1px solid var(--line);
      border-radius: 12px; padding: .7rem .8rem;
    }
    .tile-label {
      margin: 0; color: var(--faint); font-size: .72rem;
      font-weight: 600; letter-spacing: .06em; text-transform: uppercase;
    }
    .tile-value { margin: .15rem 0 .1rem; font-size: 1.3rem; }
    .tile-sub { margin: 0; color: var(--soft); font-size: .8rem; }
    .still {
      margin: 0 0 1rem; padding: .55rem .75rem; border-radius: 10px;
      background: var(--bg); border-left: 3px solid var(--sleep);
      color: var(--sleep); font-size: .92rem; font-weight: 600;
    }
    h3 {
      margin: 1.15rem 0 .5rem; font-size: .78rem; color: var(--faint);
      font-weight: 700; letter-spacing: .07em; text-transform: uppercase;
    }
    .entries { list-style: none; margin: 0; padding: 0; }
    .entries li {
      display: flex; gap: .8rem; padding: .42rem 0;
      border-top: 1px solid var(--line);
    }
    .entries li:first-child { border-top: 0; }
    /* Tabular figures so the times form a column instead of shimmering. */
    .t {
      flex: 0 0 4.4rem; color: var(--faint); font-size: .9rem;
      font-variant-numeric: tabular-nums;
    }
    .d { flex: 1; }
    .line { margin: .5rem 0 0; color: var(--soft); font-size: .93rem; }
    .line strong { color: var(--ink); }
    .empty { margin: 0; color: var(--faint); font-size: .93rem; }
    footer {
      margin-top: 2rem; padding-top: 1.25rem; border-top: 1px solid var(--line);
      color: var(--soft);
    }
    footer p { margin: 0; }
    .sig { margin-top: .2rem; color: var(--accent); font-size: 1.1rem; }
    /* Save to PDF goes through print. Keep it on white, and never split a baby's
       card across two pages. */
    @media print {
      :root {
        --bg: #ffffff; --raised: #ffffff; --ink: #1c1116; --soft: #4a3a3e;
        --faint: #6b5a5e; --line: #d8ccc9; --accent-faint: #f7f0ee;
      }
      body { font-size: 11.5pt; }
      main { max-width: none; padding: 0; }
      .card, .note { break-inside: avoid; page-break-inside: avoid; }
    }
    """

    // MARK: - Sections

    private static func documentTitle(
        babies: [HandoffBaby], shift: ShiftWindow, timeZone: TimeZone
    ) -> String {
        let who = babies.map(\.name).joined(separator: " & ")
        let night = Fmt.nightOf(shift.startedAt, timeZone: timeZone)
        return who.isEmpty ? night : "\(who) · \(night)"
    }

    private static func headerHTML(
        babies: [HandoffBaby], shift: ShiftWindow, caregiver: String?, timeZone: TimeZone
    ) -> String {
        let who = babies.map(\.name).joined(separator: " & ")
        let from = Fmt.clock(shift.startedAt, timeZone: timeZone)
        let to = shift.endedAt.map { Fmt.clock($0, timeZone: timeZone) }
        // An open shift is a night still in progress; say so rather than printing a
        // dash, because this page can legitimately be shared mid-shift.
        let span = to.map { "\(from) – \($0)" } ?? "from \(from) · still in progress"
        var out = """
        <header>
          <p class="eyebrow">\(esc(Fmt.nightOf(shift.startedAt, timeZone: timeZone)))</p>
          <h1>\(esc(who.isEmpty ? "The night" : who))</h1>
          <p class="span">\(esc(span))</p>
        """
        if let caregiver, !caregiver.isEmpty {
            out += "<p class=\"span\">Cared for by \(esc(caregiver))</p>"
        }
        return out + "</header>"
    }

    /// The doula's own sentences. First, because it is the part written *to* the
    /// parents — the rest of the page is the record it refers to.
    private static func noteHTML(_ note: String?, caregiver: String?) -> String {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "" }
        let signed = caregiver.map { "<p class=\"signoff\">— \(esc($0))</p>" } ?? ""
        return """
        <section class="note"><div class="note-body">\(paragraphs(note))</div>\(signed)</section>
        """
    }

    private static func babyHTML(
        _ baby: HandoffBaby,
        totals: ShiftTotals,
        events: [EventSnapshot],
        sessions: [SleepSnapshot],
        shift: ShiftWindow,
        unit: VolumeUnit,
        timeZone: TimeZone,
        now: Date,
        namesBaby: Bool
    ) -> String {
        var out = "<section class=\"card\">"
        // A single baby is already named in the page title, but the day of life is
        // not — and it is on the handoff precisely because the parents track it.
        out += namesBaby
            ? """
            <div class="baby"><h2>\(esc(baby.name))</h2>\
            <span class="day">Day \(baby.dayOfLife)</span></div>
            """
            : "<div class=\"baby\"><span class=\"day\">Day \(baby.dayOfLife)</span></div>"

        // Three tiles, because these are the three questions actually asked.
        let sleepValue = totals.stretches > 0 ? Fmt.spanned(totals.sleepSeconds) : "none"
        let sleepSub = totals.stretches > 0
            ? "\(totals.stretches) stretch\(totals.stretches == 1 ? "" : "es")"
                + (totals.longestStretchSeconds > 0
                    ? ", longest \(Fmt.spanned(totals.longestStretchSeconds))" : "")
            : "none logged"
        let feedSub = totals.feedMl > 0
            ? "\(Fmt.amountTotal(ml: totals.feedMl, unit: unit)) by bottle" : "&nbsp;"
        let diaperSub = totals.diapers > 0
            ? "\(totals.wet) wet, \(totals.dirty) dirty" : "&nbsp;"
        out += """
        <div class="tiles">
          \(tile("Sleep", esc(sleepValue), esc(sleepSub)))
          \(tile("Feeds", "\(totals.feeds)", feedSub == "&nbsp;" ? feedSub : esc(feedSub)))
          \(tile("Diapers", "\(totals.diapers)", diaperSub == "&nbsp;" ? diaperSub : esc(diaperSub)))
        </div>
        """

        if let open = SleepMath.openSession(in: sessions, forBaby: baby.id) {
            // The single fact a parent most wants at 6am.
            out += """
            <p class="still">Still asleep, since \
            \(esc(Fmt.clock(open.startAt, timeZone: timeZone))).</p>
            """
        }

        let feeds = events
            .filter { $0.babyID == baby.id && $0.kind == .feed }
            .sorted { $0.at < $1.at }
        out += entryList(
            "Feeds", feeds.map {
                (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.warmFeed($0, unit: unit))
            }, emptyText: "None logged.")

        if !totals.stoolProgression.isEmpty {
            out += """
            <p class="line"><strong>Stool</strong> \
            \(esc(totals.stoolProgression.map(Fmt.stool).joined(separator: " → ")))</p>
            """
        }

        let meds = events
            .filter { $0.babyID == baby.id && $0.kind == .medication }
            .sorted { $0.at < $1.at }
        if !meds.isEmpty {
            out += entryList(
                "Medication",
                meds.map {
                    (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.medicationDetail($0))
                },
                emptyText: nil)
        }
        // The latest weight in the shift, as the text version reports it — listing
        // every measurement would put a blank row on the page for one taken without
        // a number attached.
        if let grams = totals.latestWeightGrams {
            out += """
            <p class="line"><strong>Weight</strong> \
            \(esc(Fmt.weight(grams: grams, unit: unit)))</p>
            """
        }

        let notes = events
            .filter { $0.babyID == baby.id && $0.kind == .note }
            .sorted { $0.at < $1.at }
        if !notes.isEmpty {
            out += entryList(
                "Notes",
                // Shared phrasing: this used to read `note.text` alone, so a note
                // logged as a tag and nothing else arrived as a bare timestamp.
                notes.map {
                    (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.noteDetail($0))
                },
                emptyText: nil)
        }

        return out + "</section>"
    }

    private static func footerHTML(caregiver: String?) -> String {
        if let caregiver, !caregiver.isEmpty {
            return """
            <footer><p>With care,</p><p class="sig">\(esc(caregiver)) 🌙</p></footer>
            """
        }
        return "<footer><p class=\"sig\">🌙 Logged with Moonlog</p></footer>"
    }

    private static func unattributedHTML(
        babies: [HandoffBaby],
        events: [EventSnapshot],
        sessions: [SleepSnapshot],
        shift: ShiftWindow,
        unit: VolumeUnit,
        timeZone: TimeZone,
        now: Date
    ) -> String {
        let named = Set(babies.map(\.id))
        // `EventSnapshot.noBaby` is deliberately not an orphan: a pump carries no
        // baby by design and is reported as a household total below.
        let orphanEvents = events
            .filter { !named.contains($0.babyID) && $0.babyID != EventSnapshot.noBaby }
            .sorted { $0.at < $1.at }
        // Clipped like everywhere else, so a session contributing no time inside the
        // window is not announced as a record.
        let orphanSleep = sessions
            .filter { !named.contains($0.babyID) }
            .map { ($0, SleepMath.seconds(of: $0, clippedTo: shift, asOf: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.0.startAt < $1.0.startAt }
        guard !orphanEvents.isEmpty || !orphanSleep.isEmpty else { return "" }

        var rows = orphanEvents.map {
            (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.strayLine($0, unit: unit))
        }
        rows += orphanSleep.map {
            (Fmt.shortClock($0.0.startAt, timeZone: timeZone),
             "asleep \(Fmt.spanned($0.1))")
        }
        return """
        <section class="card"><h2>Not matched to a baby</h2>\
        \(entryList("\(rows.count) record\(rows.count == 1 ? "" : "s")", rows, emptyText: nil))\
        </section>
        """
    }

    // MARK: - Fragments

    private static func tile(_ label: String, _ value: String, _ sub: String) -> String {
        """
        <div class="tile"><p class="tile-label">\(label)</p>\
        <p class="tile-value">\(value)</p><p class="tile-sub">\(sub)</p></div>
        """
    }

    private static func entryList(
        _ heading: String, _ rows: [(String, String)], emptyText: String?
    ) -> String {
        guard !rows.isEmpty else {
            guard let emptyText else { return "" }
            return "<h3>\(esc(heading))</h3><p class=\"empty\">\(esc(emptyText))</p>"
        }
        let items = rows.map { time, detail in
            "<li><span class=\"t\">\(esc(time))</span><span class=\"d\">\(esc(detail))</span></li>"
        }.joined()
        return "<h3>\(esc(heading))</h3><ul class=\"entries\">\(items)</ul>"
    }

    /// Blank-line-separated blocks become paragraphs; single newlines become breaks.
    /// The doula typed it in a text field, so the shape they gave it is meaningful.
    private static func paragraphs(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>" + esc($0).replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
            .joined()
    }

    /// Every interpolated value goes through this. Names, notes and medications are
    /// free text typed by a person, and an unescaped `&` or `<` would silently
    /// swallow the rest of the page.
    private static func esc(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for character in raw {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }
}
