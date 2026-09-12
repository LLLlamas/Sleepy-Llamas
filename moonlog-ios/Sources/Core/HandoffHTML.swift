import Foundation

/// The keepsake handoff: the same night as `Handoff.text`, laid out to be read.
///
/// The plain-text version exists to be pasted into Messages at 6am. This one is
/// what gets sent to the family afterwards — so it is a **letter**: a header naming
/// the night, two paragraphs written to the parents, then each baby's night in the
/// same fixed order the text uses, then a closing line. The numbers are in the
/// middle, where a document puts its evidence, not at the top where a dashboard
/// puts its metrics.
///
/// Three constraints shape it, all deliberate:
///
/// - **Self-contained.** No external stylesheet, font, script or image. The page is
///   forwarded, saved to Files and opened offline months later, and anything fetched
///   over the network would be missing by then — or would tell a third party when
///   the parents opened it. Every icon is inline SVG for the same reason.
/// - **Responsive.** They will open it on a phone, so the layout is fluid and the
///   stat tiles reflow rather than assuming a page width.
/// - **Pure.** Same rule as the rest of `MoonlogCore`: value types in, `String` out,
///   no `Date.now`. It takes the same arguments as `Handoff.text` and derives its
///   numbers from the same `Totals.compute` and its words from the same helpers on
///   `Handoff`, so the two documents cannot disagree.
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
            babies: babies, shift: shift, caregiver: caregiver,
            timeZone: timeZone, now: now)
        body += letterHTML(babies: babies, shift: shift, note: note, caregiver: caregiver)

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
            <section class="card">\
            \(sectionHead("Pumping", tag: nil, pip: nil))\
            <p class="line">\(esc(Handoff.pumpSummary(household, unit: unit))).</p>\
            \(entryList(Handoff.pumpRows(events, unit: unit, timeZone: timeZone),
                        emptyText: nil))\
            </section>
            """
        }

        body += footerHTML()
        return document(title: documentTitle(babies: babies, shift: shift, timeZone: timeZone),
                        body: body)
    }

    // MARK: - Shell

    /// Wraps the body in a complete, standalone document.
    ///
    /// The stylesheet is inline for the self-containment reason above. It is written
    /// mobile-first — the parents open this on a phone — and the tiles are the only
    /// thing that reflows, so there are no breakpoints to maintain beyond one.
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
       `raised2` — surfaces this document does not have.

       Every pair below carries text or an icon and was measured at WCAG 2.1:
       faint on bg 5.48:1, faint on raised 5.65:1, soft on bg 7.24:1, soft on
       raised 7.46:1, soft on panel 6.39:1, accent on bg 6.13:1, sleep on bg
       4.53:1, sleep-ink on panel 5.23:1, accent-deep on panel 9.63:1. The icon
       colours only have to clear 3:1 as graphical objects and do: rose on bg
       4.68:1, gold-ink on bg 3.96:1. On the header's tinted ground, measured
       against the gradient with both radial washes composited over it (#e5c7bb):
       accent-deep 7.33:1, soft 4.86:1, ink 10.91:1.

       `--gold` is the one colour with no contrast obligation: it is only ever a
       hairline rule, and every rule sits beside a heading that says the same
       thing in words. Anything that carries meaning uses `--gold-ink`.
       Re-measure before changing one; `PaletteTests` does not cover this file. */
    :root {
      --bg: #fdf6f4; --raised: #fffaf8; --ink: #2a1418; --soft: #6b4a4f;
      --faint: #7e5c61; --line: rgba(61,15,23,0.12); --accent: #a83246;
      --accent-deep: #6b1a28; --accent-faint: #f7e6e2; --sleep: #3f7d68;
      --sleep-ink: #35695a; --gold: #c79a5e; --gold-soft: #d9a96b;
      --gold-ink: #9a7536; --rose: #b0506a; --diaper-ink: #6b1a28;
      --head-a: #f3e0db; --head-b: #f8eae5; --head-c: #fffaf8;
      --wash-gold: rgba(199,154,94,0.16); --wash-rose: rgba(176,80,106,0.12);
    }
    /* The Night palette, for a phone in dark mode at 6am. Measured the same way:
       soft on panel 7.77:1, sleep-ink on panel 6.27:1, accent-deep on panel
       4.40:1 — which is why the diaper emphasis uses `--gold-ink` (6.43:1) at
       night rather than accent-deep. On the header composite (#512d32): ink
       10.24:1, soft 6.71:1, accent 5.55:1. Icons: rose on bg 7.37:1. */
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #1a0a0e; --raised: #241016; --ink: #f7ece9; --soft: #d9bcbd;
        --faint: #bb979c; --line: #3f2129; --accent: #d9a96b;
        --accent-deep: #bd8748; --accent-faint: #3a2a1d; --sleep: #8fb8a8;
        --sleep-ink: #8fb8a8; --gold: #d9a96b; --gold-soft: #e6c08c;
        --gold-ink: #d9a96b; --rose: #d98a9c; --diaper-ink: #d9a96b;
        --head-a: #301722; --head-b: #26121a; --head-c: #241016;
        --wash-gold: rgba(217,169,107,0.10); --wash-rose: rgba(176,80,106,0.14);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; background: var(--bg); color: var(--ink);
      font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      -webkit-text-size-adjust: 100%;
    }
    main { max-width: 40rem; margin: 0 auto; padding: 1.5rem 1.15rem 3rem; }
    /* Fraunces is the intended face for this document, but no font file is bundled
       and nothing may be fetched, so a serif stack carries the brand moments. */
    h1, h2, .tile-value, .letter p, .keepsake, .datestamp {
      font-family: ui-serif, Georgia, "Times New Roman", serif;
    }
    h1, h2, .tile-value { font-weight: 600; }

    /* ---- The header, which is the keepsake part of the keepsake ---- */
    .almanac {
      position: relative; overflow: hidden; border-radius: 22px;
      border: 1px solid var(--line); padding: 2rem 1.5rem 1.6rem;
      background:
        radial-gradient(120% 90% at 78% 8%, var(--wash-gold) 0%, transparent 46%),
        radial-gradient(140% 120% at 18% 0%, var(--wash-rose) 0%, transparent 42%),
        linear-gradient(180deg, var(--head-a) 0%, var(--head-b) 52%, var(--head-c) 100%);
    }
    /* The inset gold line that makes it read as a card rather than a banner. */
    .almanac::before {
      content: ""; position: absolute; inset: 9px; pointer-events: none;
      border: 1px solid var(--gold); opacity: .45; border-radius: 15px;
    }
    /* Stars as real elements, not an image — nothing may be fetched, and a data
       URI would not survive a print stylesheet that drops backgrounds. */
    .stars { position: absolute; inset: 0; pointer-events: none; }
    .star {
      position: absolute; width: 3px; height: 3px; border-radius: 50%;
      background: var(--gold); opacity: .55;
    }
    .star.sm { width: 2px; height: 2px; opacity: .4; }
    .star.lg { width: 4px; height: 4px; opacity: .5; }
    .crest {
      position: relative; display: flex; align-items: center; gap: .5rem;
      color: var(--accent-deep); font-size: .72rem; font-weight: 600;
      letter-spacing: .16em; text-transform: uppercase;
    }
    .crest svg { width: 22px; height: 22px; flex: none; }
    h1 { position: relative; margin: .9rem 0 .15rem; font-size: 2rem; line-height: 1.15; }
    .datestamp { position: relative; margin: 0 0 1rem; color: var(--soft); font-size: 1rem; }
    .shift-line {
      position: relative; display: flex; flex-wrap: wrap; gap: .35rem .9rem;
      align-items: baseline; padding-top: .9rem; border-top: 1px solid var(--line);
      color: var(--soft); font-size: .88rem;
    }
    .shift-line .who { font-weight: 600; color: var(--ink); }
    .shift-line .len { margin-left: auto; color: var(--accent-deep); font-weight: 600; }

    /* ---- The letter ---- */
    .letter { margin: 1.6rem .15rem 1.75rem; }
    .letter p { margin: 0 0 .7rem; font-size: 1.05rem; }
    .letter .lede { color: var(--gold-ink); }
    .signoff, .letter-sign {
      margin: .9rem 0 0; color: var(--soft); font-style: italic; font-size: .95rem;
    }
    .signoff .name, .letter-sign .name {
      display: block; color: var(--accent-deep); font-style: normal; font-weight: 600;
    }
    .note {
      background: var(--accent-faint); border-radius: 16px;
      padding: 1.1rem 1.25rem; margin: 1.1rem 0 0;
    }
    .note-body p { margin: 0 0 .7rem; }
    .note-body p:last-child { margin-bottom: 0; }
    .note .signoff { margin-top: .8rem; }

    /* ---- A baby's night ---- */
    .card {
      background: var(--raised); border: 1px solid var(--line); border-radius: 16px;
      padding: 1.25rem; margin-bottom: 1.25rem;
    }
    .baby { display: flex; align-items: baseline; gap: .6rem; margin-bottom: 1rem; }
    h2 { margin: 0; font-size: 1.35rem; }
    .day {
      color: var(--accent); font-size: .8rem; font-weight: 600;
      letter-spacing: .05em; text-transform: uppercase;
    }
    /* Four tiles in two columns: sleep, feeds, diapers and — new here — notes,
       which the page counted for nobody before. An even grid replaces the old
       full-width first tile, which existed only because three tiles in two
       columns left the third alone beside an empty cell. */
    .tiles { display: grid; gap: .6rem; margin-bottom: 1rem; grid-template-columns: 1fr 1fr; }
    @media (min-width: 34rem) { .tiles { grid-template-columns: repeat(4, 1fr); } }
    .tile {
      position: relative; background: var(--bg); border: 1px solid var(--line);
      border-top: 3px solid var(--faint); border-radius: 12px; padding: .7rem .8rem;
    }
    /* Hue is a second signal only. Every tile also names itself and carries an
       icon of the same shape as its section heading below. */
    .tile-sleep { border-top-color: var(--sleep-ink); }
    .tile-feeds { border-top-color: var(--rose); }
    .tile-diapers { border-top-color: var(--gold-ink); }
    .tile-notes { border-top-color: var(--faint); }
    .tile-ico { position: absolute; top: .6rem; right: .65rem; width: 17px; height: 17px; }
    .tile-sleep .tile-ico { color: var(--sleep-ink); }
    .tile-feeds .tile-ico { color: var(--rose); }
    .tile-diapers .tile-ico { color: var(--gold-ink); }
    .tile-notes .tile-ico { color: var(--faint); }
    .tile-label {
      margin: 0 1.6rem .1rem 0; color: var(--faint); font-size: .72rem;
      font-weight: 600; letter-spacing: .06em; text-transform: uppercase;
    }
    .tile-value { margin: .15rem 0 .1rem; font-size: 1.3rem; }
    .tile-sub { margin: 0; color: var(--soft); font-size: .8rem; }
    .still {
      margin: .6rem 0 0; padding: .55rem .75rem; border-radius: 10px;
      background: var(--bg); border-left: 3px solid var(--sleep);
      color: var(--sleep); font-size: .92rem; font-weight: 600;
    }

    /* ---- Section headings: name, gold rule, count ---- */
    /* A heading, a gold rule filling what is left of the line, and a short count
       on the right. It wraps rather than overflowing: the tag does not shrink, and
       the longest heading here is five words on a 375px phone. (Nothing in this
       stylesheet may quote a heading verbatim — the keepsake's tests assert that
       a section's title is absent from a page that has no such section, and a
       comment mentioning it counts.) */
    .section-head {
      display: flex; flex-wrap: wrap; align-items: baseline;
      gap: .35rem .7rem; margin: 1.4rem 0 .6rem;
    }
    .section-head h2 { font-size: 1.1rem; }
    .rule {
      flex: 1 1 1.5rem; height: 1px; align-self: center; opacity: .85;
      background: linear-gradient(90deg, transparent 0%, var(--gold) 22%,
        var(--gold-soft) 55%, var(--gold) 80%, transparent 100%);
    }
    .tag { color: var(--faint); font-size: .78rem; white-space: nowrap; }
    .pip {
      display: inline-block; width: 7px; height: 7px; border-radius: 50%;
      margin-right: .35rem; vertical-align: middle; background: var(--faint);
    }
    .pip-feeds { background: var(--rose); }
    .pip-diapers { background: var(--gold-ink); }
    .pip-sleep { background: var(--sleep-ink); }

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
    .pills { display: flex; flex-wrap: wrap; gap: .4rem; margin: 0; }
    .pill {
      background: var(--accent-faint); border: 1px solid var(--line);
      border-radius: 999px; padding: .3rem .75rem;
      color: var(--soft); font-size: .82rem;
    }
    .pill strong { color: var(--sleep-ink); }
    .pill-diaper strong { color: var(--diaper-ink); }
    .line { margin: .5rem 0 0; color: var(--soft); font-size: .93rem; }
    .line strong { color: var(--ink); }
    /* A whole sentence, set in italic, because a bare "None" on a page the family
       keeps reads as a section that failed to render. */
    .empty { margin: 0; color: var(--faint); font-size: .93rem; font-style: italic; }

    /* ---- The close ---- */
    .closer { margin-top: 2.25rem; text-align: center; color: var(--soft); }
    .goldrule {
      height: 1px; border: 0; margin: 0 0 1.1rem;
      background: linear-gradient(90deg, transparent 0%, var(--gold) 28%,
        var(--gold-soft) 50%, var(--gold) 72%, transparent 100%);
    }
    .keepsake { margin: 0 0 .9rem; font-style: italic; font-size: 1rem; }
    .gen {
      display: inline-flex; align-items: center; gap: .4rem; margin: 0;
      font-size: .76rem; letter-spacing: .04em; color: var(--faint);
    }
    .gen svg { width: 15px; height: 15px; }

    /* Save to PDF goes through print. Keep it on white, never split a baby's card
       across two pages, and — the part that was missing — tell the browser to
       print the colours. Without `print-color-adjust: exact` every gold rule, tile
       border and tinted card is dropped, and the keepsake prints as grey lines. */
    @media print {
      @page { margin: 14mm; }
      :root {
        --bg: #ffffff; --raised: #ffffff; --ink: #1c1116; --soft: #4a3a3e;
        --faint: #6b5a5e; --line: #d8ccc9; --accent-faint: #f7f0ee;
        --sleep: #35695a; --sleep-ink: #35695a; --rose: #99435b;
        --gold-ink: #8a6a33; --diaper-ink: #6b1a28;
        --head-a: #f7f0ee; --head-b: #fbf7f5; --head-c: #ffffff;
      }
      body { font-size: 11.5pt; }
      main { max-width: none; padding: 0; }
      /* A baby's card is a page tall now that it carries its stretches and its
         notes, so it is allowed to break — `break-inside: avoid` on it left half a
         sheet blank and would have chopped a long night anyway. What must not
         break is a block small enough to fit: the header, the letter, the tile
         row, a single entry, and a heading that would otherwise end a page with
         its list overleaf. */
      .almanac, .note, .letter, .tiles, .pills { break-inside: avoid; page-break-inside: avoid; }
      .entries li, .baby { break-inside: avoid; }
      .section-head, .baby { break-after: avoid; page-break-after: avoid; }
      .card { break-before: auto; }
      * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    }
    """

    // MARK: - Inline art
    //
    // Every icon is drawn here rather than fetched, for the self-containment rule
    // above, and every one of them sits beside a word — they are reinforcement for
    // the colour, never the label itself.

    private static let moonPath =
        "M20 14.2A8.2 8.2 0 1 1 10.6 4a6.4 6.4 0 0 0 9.4 10.2z"

    private static func icon(_ paths: [String], class className: String = "") -> String {
        let body = paths.map {
            "<path d=\"\($0)\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\" "
                + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        }.joined()
        let attr = className.isEmpty ? "" : " class=\"\(className)\""
        return "<svg\(attr) viewBox=\"0 0 24 24\" aria-hidden=\"true\">" + body + "</svg>"
    }

    private static func tileIcon(_ kind: String) -> String {
        switch kind {
        case "sleep": return icon([moonPath], class: "tile-ico")
        case "feeds": return icon(
            ["M9.5 3h5M10 3v2.2c0 .6-.25 1.18-.7 1.6L8 8.3C7.36 8.9 7 9.74 7 10.62V19a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-8.38c0-.88-.36-1.72-1-2.32l-1.3-1.5A2.2 2.2 0 0 1 16 5.2V3",
             "M7 12.5h10"], class: "tile-ico")
        case "diapers": return icon(
            ["M3 6h18v3c0 5-3.8 9-9 9S3 14 3 9V6z",
             "M3 9c3 0 5 1.6 9 1.6S18 9 21 9"], class: "tile-ico")
        default: return icon(
            ["M6 3h8l4 4v14H6V3z", "M13 3v5h5", "M8.5 12.5h7M8.5 16h7"],
            class: "tile-ico")
        }
    }

    // MARK: - Sections

    private static func documentTitle(
        babies: [HandoffBaby], shift: ShiftWindow, timeZone: TimeZone
    ) -> String {
        let who = babies.map(\.name).joined(separator: " & ")
        let night = Fmt.nightOf(shift.startedAt, timeZone: timeZone)
        return who.isEmpty ? night : "\(who) · \(night)"
    }

    /// The night's own front page: the crest, who it is about, the date written out,
    /// and how long the doula was there. `<h1>` is the names and nothing else — the
    /// title of a keepsake is a name, and a reader scanning a folder of these needs
    /// them to line up.
    private static func headerHTML(
        babies: [HandoffBaby], shift: ShiftWindow, caregiver: String?,
        timeZone: TimeZone, now: Date
    ) -> String {
        let who = babies.map(\.name).joined(separator: " & ")
        let end = shift.endedAt ?? now
        let from = Fmt.clock(shift.startedAt, timeZone: timeZone)
        let to = shift.endedAt.map { Fmt.clock($0, timeZone: timeZone) }
        // An open shift is a night still in progress; say so rather than printing a
        // dash, because this page can legitimately be shared mid-shift.
        let span = to.map { "\(from) – \($0)" } ?? "from \(from) · still in progress"
        let stars = [
            ("sm", 18, 8), ("", 40, 24), ("lg", 14, 46), ("sm", 54, 62),
            ("", 26, 88), ("sm", 66, 34), ("", 10, 72), ("lg", 78, 13),
        ].map { size, top, left in
            "<span class=\"star \(size)\" style=\"top:\(top)px;left:\(left)%\"></span>"
        }.joined()

        var out = """
        <header class="almanac">
          <div class="stars" aria-hidden="true">\(stars)</div>
          <p class="crest">\(icon([moonPath]))Moonlog · Sleepy Llamas</p>
          <h1>\(esc(who.isEmpty ? "The night" : who))</h1>
          <p class="datestamp">\(esc(Fmt.longDate(shift.startedAt, timeZone: timeZone)))</p>
          <p class="shift-line"><span class="who">\(esc(span))</span>
        """
        if let caregiver, !caregiver.isEmpty {
            out += "<span>Cared for by \(esc(caregiver))</span>"
        }
        out += "<span class=\"len\">\(esc(Handoff.onWatch(shift, end: end)))</span></p>"
        return out + "</header>"
    }

    /// The part written *to* the parents, above the record it refers to. The single
    /// biggest difference between a keepsake and a data dump, and it costs two
    /// string literals.
    ///
    /// The first sentence is `Handoff.greeting`, so the page opens with the same
    /// words the 6am message did. The doula's own note, when she wrote one, sits
    /// inside the letter rather than above it — it is the middle of what she is
    /// saying, not a preface to it.
    private static func letterHTML(
        babies: [HandoffBaby], shift: ShiftWindow, note: String?, caregiver: String?
    ) -> String {
        var out = """
        <section class="letter">\
        <p><span class="lede">☽</span> \(esc(Handoff.greeting(babies: babies, shift: shift)))</p>\
        <p>Everything below was written down as the night went: the feeds, the changes, \
        the stretches of sleep, and anything worth remembering. Pour the coffee and \
        read it slowly — the night was watched over.</p>
        """
        let body = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if body.isEmpty {
            // Nothing of her own to say, so the fixed prose carries the signature.
            out += signOff(caregiver, class: "letter-sign")
        } else {
            // Her words are signed where they end. One sign-off on a page, never
            // two: the letter above her note is the frame, and repeating the name a
            // few lines apart reads as a template rather than a letter.
            out += """
            <section class="note"><div class="note-body">\(paragraphs(body))</div>\
            \(signOff(caregiver, class: "signoff"))</section>
            """
        }
        return out + "</section>"
    }

    /// "With care, / — Cat", or nothing at all when the shift records no caregiver.
    /// The PWA hid an empty name with `.name:empty` and left "With care," dangling
    /// over it; there is no templating language here to work around, so the whole
    /// block simply does not render.
    private static func signOff(_ caregiver: String?, class className: String) -> String {
        guard let caregiver, !caregiver.isEmpty else { return "" }
        return "<p class=\"\(className)\">With care,<span class=\"name\">— "
            + esc(caregiver) + "</span></p>"
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
            <span class="day">Day \(baby.dayOfLife)</span><span class="rule"></span></div>
            """
            : """
            <div class="baby"><span class="day">Day \(baby.dayOfLife)</span>\
            <span class="rule"></span></div>
            """

        // Four tiles, because these are the four questions actually asked. Notes
        // were counted for the doula on the Summary screen and for nobody here.
        let sleepValue = totals.stretches > 0 ? Fmt.spanned(totals.sleepSeconds) : "none"
        let feedSub = Handoff.feedSummary(totals, unit: unit)
        out += """
        <div class="tiles">
          \(tile("sleep", "Sleep", esc(sleepValue), Handoff.sleepStretches(totals)))
          \(tile("feeds", "Feeds", "\(totals.feeds)", feedSub))
          \(tile("diapers", "Diapers", "\(totals.diapers)", Handoff.diaperSplit(totals)))
          \(tile("notes", "Notes", "\(totals.notes)",
                 totals.notes > 0 ? "worth keeping" : nil))
        </div>
        """

        let feeds = events
            .filter { $0.babyID == baby.id && $0.kind == .feed }
            .sorted { $0.at < $1.at }
        // The tag is a count and nothing more. The volume belongs to the tile above,
        // where it has room to wrap; here it is one line beside a heading.
        out += sectionHead(
            "Feeds", tag: feeds.isEmpty ? nil : "\(totals.feeds) in all", pip: "feeds")
        out += entryList(
            feeds.map {
                (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.warmFeed($0, unit: unit))
            }, emptyText: Handoff.nothingLogged("feeds"))

        // The count and the colour first — that is the shape of the night, and it
        // was for a long time all this section had. The rows underneath are the
        // record: a change with no time on it cannot be placed against a feed, and
        // this page is what the family hands to their pediatrician.
        let changes = events
            .filter { $0.babyID == baby.id && $0.kind == .diaper }
            .sorted { $0.at < $1.at }
        out += sectionHead("Diapers", tag: Handoff.diaperSplit(totals), pip: "diapers")
        if totals.diapers > 0 {
            var pills = ["<span class=\"pill pill-diaper\"><strong>\(totals.diapers)</strong> "
                + "change\(totals.diapers == 1 ? "" : "s") in all</span>"]
            if let colours = Handoff.diaperColours(totals, in: events, forBaby: baby.id) {
                pills.append("<span class=\"pill\">\(esc(colours))</span>")
            }
            out += "<p class=\"pills\">\(pills.joined())</p>"
        }
        out += entryList(
            changes.map {
                (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.diaperDetail($0))
            }, emptyText: Handoff.nothingLogged("diapers"))

        out += sectionHead(
            "Sleep",
            tag: totals.stretches > 0
                ? "\(totals.stretches) stretch\(totals.stretches == 1 ? "" : "es")" : nil,
            pip: "sleep")
        if totals.stretches > 0 {
            out += "<p class=\"pills\"><span class=\"pill\"><strong>"
                + esc(Fmt.spanned(totals.sleepSeconds)) + "</strong> asleep</span>"
            // One stretch is its own longest, and the pill would print the same
            // number twice — the same rule `Handoff.sleepStretches` applies.
            if totals.stretches > 1 && totals.longestStretchSeconds > 0 {
                let longest = Fmt.spanned(totals.longestStretchSeconds)
                out += "<span class=\"pill\">longest <strong>\(esc(longest))</strong></span>"
            }
            out += "</p>"
        }
        if let open = SleepMath.openSession(in: sessions, forBaby: baby.id) {
            // The single fact a parent most wants at 6am. It sits inside the sleep
            // section and above the stretches, exactly where the text handoff puts
            // it — it used to float above the feeds, which is where the eye looks
            // last. Same words as the text; only the casing and the full stop
            // belong to the page.
            let phrase = Handoff.stillAsleep(open, timeZone: timeZone)
            out += "<p class=\"still\">"
                + esc(phrase.prefix(1).uppercased() + phrase.dropFirst()) + ".</p>"
        }
        // The stretches themselves — content the port never had. A parent reading at
        // 6am wants to see the night's shape, not only what it summed to.
        out += entryList(
            Handoff.sleepRows(
                sessions, forBaby: baby.id, clippedTo: shift, asOf: now,
                timeZone: timeZone),
            emptyText: Handoff.nothingLogged("sleep"))

        let meds = events
            .filter { $0.babyID == baby.id && $0.kind == .medication }
            .sorted { $0.at < $1.at }
        if !meds.isEmpty {
            out += sectionHead("Medication", tag: "\(meds.count) given", pip: "meds")
            out += entryList(
                meds.map {
                    (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.medicationDetail($0))
                },
                emptyText: nil)
        }
        // Each weighing with the time it was taken, latest last — the same shape the
        // text version prints, and for the same reason the heading carries no value:
        // with one weighing it would be the row below it, minus its time.
        // `Handoff.weightRows` drops a measurement saved without a number, which
        // would otherwise be a blank row.
        let weights = Handoff.weightRows(baby, events, unit, timeZone)
        if !weights.isEmpty {
            out += sectionHead(
                "Weight", tag: weights.count > 1 ? "\(weights.count) taken" : nil,
                pip: nil)
            out += entryList(weights, emptyText: nil)
        }

        let notes = events
            .filter { $0.babyID == baby.id && $0.kind == .note }
            .sorted { $0.at < $1.at }
        if !notes.isEmpty {
            out += sectionHead("Notes", tag: "\(notes.count) noted", pip: "notes")
            out += entryList(
                // Shared phrasing: this used to read `note.text` alone, so a note
                // logged as a tag and nothing else arrived as a bare timestamp.
                notes.map {
                    (Fmt.shortClock($0.at, timeZone: timeZone), Handoff.noteDetail($0))
                },
                emptyText: nil)
        }

        return out + "</section>"
    }

    /// The closing line. The signature is at the top, where a letter puts it after
    /// the greeting; this is the page's last word to a family that will open it
    /// again in a year.
    private static func footerHTML() -> String {
        """
        <footer class="closer">
        <hr class="goldrule" aria-hidden="true">
        <p class="keepsake">Rest easy — the night is logged and the morning is yours.</p>
        <p class="gen">\(icon([moonPath]))Logged with Moonlog · Sleepy Llamas</p>
        </footer>
        """
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
        <section class="card">\
        \(sectionHead("Not matched to a baby",
                      tag: "\(rows.count) record\(rows.count == 1 ? "" : "s")", pip: nil))\
        \(entryList(rows, emptyText: nil))</section>
        """
    }

    // MARK: - Fragments

    /// A heading, a gold hairline filling what is left of the line, and the count on
    /// the right. The pip is a second signal on a tag that already says the number
    /// in words, never the signal itself.
    private static func sectionHead(_ title: String, tag: String?, pip: String?) -> String {
        var out = "<div class=\"section-head\"><h2>\(esc(title))</h2>"
        out += "<span class=\"rule\"></span>"
        if let tag, !tag.isEmpty {
            let dot = pip.map { "<span class=\"pip pip-\($0)\"></span>" } ?? ""
            out += "<span class=\"tag\">\(dot)\(esc(tag))</span>"
        }
        return out + "</div>"
    }

    private static func tile(
        _ kind: String, _ label: String, _ value: String, _ sub: String?
    ) -> String {
        // `&nbsp;` rather than an empty paragraph: the tiles are a grid row and an
        // absent third line makes one tile shorter than the rest.
        let subText = sub.map(esc) ?? "&nbsp;"
        return """
        <div class="tile tile-\(kind)">\(tileIcon(kind))<p class="tile-label">\(label)</p>\
        <p class="tile-value">\(value)</p><p class="tile-sub">\(subText)</p></div>
        """
    }

    private static func entryList(
        _ rows: [(String, String)], emptyText: String?
    ) -> String {
        guard !rows.isEmpty else {
            guard let emptyText else { return "" }
            return "<p class=\"empty\">\(esc(emptyText))</p>"
        }
        let items = rows.map { time, detail in
            "<li><span class=\"t\">\(esc(time))</span><span class=\"d\">\(esc(detail))</span></li>"
        }.joined()
        return "<ul class=\"entries\">\(items)</ul>"
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
    /// swallow the rest of the page. It is also why the page uses literal `·`, `—`
    /// and `→` rather than the HTML entities for them: the document is UTF-8, and
    /// every `&` that survives to the output is one this escaper put there.
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
