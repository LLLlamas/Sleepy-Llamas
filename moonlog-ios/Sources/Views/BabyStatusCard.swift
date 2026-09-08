import SwiftUI
import MoonlogCore

/// Already-computed state for one card. Keeps the view free of domain logic and
/// previewable without a store.
struct BabyPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let accent: BabyAccent
    let dayOfLife: Int
    let asleepSince: Date?
    /// When they last woke — the end of their most recent sleep. `nil` when they
    /// have not slept this shift, in which case nothing is claimed about how long
    /// they have been up. Only meaningful while `asleepSince` is `nil`.
    let awakeSince: Date?
    /// Both ends of the most recent *finished* sleep, which the awake tile names.
    /// `nil` before this baby has slept at all — the tile then says nothing rather
    /// than naming a span it does not have.
    let lastSleep: SleepSpan?
    let lastFeedAt: Date?
    let lastDiaperAt: Date?

    var isAsleep: Bool { asleepSince != nil }

    /// A finished sleep, both ends known. A separate type rather than a tuple so it
    /// can carry `Equatable` into `BabyPresentation` without spelling it out.
    struct SleepSpan: Equatable {
        let startAt: Date
        let endAt: Date
    }

    /// The instant the current state began, whichever state that is.
    var stateSince: Date? { asleepSince ?? awakeSince }

    /// Whether the feed is overdue as of `now`. Computed here rather than baked in,
    /// so the value can refresh on the clock without invalidating the whole screen.
    ///
    /// A future-dated feed (reachable only via sync from a device with a skewed
    /// clock) counts as overdue rather than as "just fed" — treating it as recent is
    /// what silently suppressed this warning in the web version.
    func feedIsDue(now: Date, after interval: TimeInterval = 3 * 3600) -> Bool {
        guard let lastFeedAt else { return false }
        let elapsed = now.timeIntervalSince(lastFeedAt)
        return elapsed < 0 || elapsed >= interval
    }
}

/// One baby's live state plus their actions. With twins these stack, so both
/// states are visible at once and neither set of buttons can act on the wrong baby.
struct BabyStatusCard: View {
    let baby: BabyPresentation
    /// The shift's zone, not the device's. Every other clock on this screen is
    /// rendered in it, and a family in another timezone would otherwise get a
    /// status line disagreeing with the timeline row directly beneath it.
    let timeZone: TimeZone

    /// A write is in flight for this baby; actions are inert until it lands.
    var isBusy: Bool
    var onFeed: () -> Void
    var onDiaper: () -> Void
    var onToggleSleep: () -> Void
    var onNote: () -> Void
    var onEditBaby: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accentColor: Color { baby.accent.color(for: theme) }

    /// **The tile is the baby's colour, in both states.** It used to be sage for
    /// asleep and gold for awake — the same two colours on every card — so with
    /// twins the two tiles could swap hues without changing which baby was which,
    /// and hue said nothing about whose card you were looking at.
    ///
    /// Now hue is identity and the *depth of the fill* is the state. That is a
    /// deliberate demotion of colour as a state signal, and it is only defensible
    /// because state was never carried by colour alone here: the glyph is a moon or
    /// a sun, the sentence reads "Mia is asleep" in words, and the trailing edge
    /// says two different things — a running counter while asleep, the last sleep's
    /// range while awake. Colour remains the third signal, as
    /// `docs/design.md` requires — it has simply changed what it is third *for*.
    private var stateColor: Color { accentColor }

    /// Pinned by `PaletteTests` across every accent, theme and state — do not
    /// substitute an opacity. See `BabyAccent.wash(for:asleep:)`.
    private var stateWash: Color { baby.accent.wash(for: theme, asleep: baby.isAsleep) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // Only these two labels depend on the clock. Ticking here rather than
            // around the whole screen means the timeline — every row, every
            // formatted time — re-renders on writes, not every 30 seconds.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    status(now: context.date)
                    lastSeen(now: context.date)
                }
            }
            actions
        }
        .padding(16)
        .cardSurface(palette)
    }

    // A visible chevron, not a long-press — see `docs/design.md`.
    private var header: some View {
        Button(action: { Haptics.tap(); onEditBaby() }) {
            HStack {
                BabyChip(name: baby.name, accent: baby.accent)
                Spacer()
                // Day N used to sit here. It answers a question nobody asks
                // mid-shift, and the header is the one line that carries the
                // baby's identity — `BabyPresentation.dayOfLife` stays because the
                // handoff document still names it.
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.faint)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(baby.name). Edit name, birth date and colour.")
    }

    // **The tile toggles, at the time you tapped it.** It is the biggest target on
    // the card and the one thing done most often at 3am, so it takes no
    // configuration at all — the same write the Wake/Sleep button below makes.
    //
    // It used to open the adjust-sleep sheet instead, which meant the largest
    // control on the screen asked a question rather than answering one. Getting the
    // time right afterwards is the rarer job and now lives where the record is: tap
    // the sleep row in tonight's timeline.
    //
    // Ported from the PWA's sleep tile, which is the one piece of that design worth
    // keeping literally: a bordered, tinted block reading "Mia is asleep" is legible
    // across a dark room in a way a coloured word in a row is not. Its copy is
    // correct again now that the gesture matches — the web tile said "tap when Mia
    // wakes" precisely because tapping it toggled.
    private func status(now: Date) -> some View {
        Button(action: {
            guard !isBusy else { return }
            Haptics.tap()
            onToggleSleep()
        }) {
            statusContent(now: now)
        }
        // Not `.plain`: it fades its label while pressed, and on a block this size
        // the fade reads as the tile breaking rather than as a press. The tap is
        // already answered by a haptic and by the tile changing state, so nothing
        // is lost by taking the dimming away.
        .buttonStyle(UntouchedButton())
        .disabled(isBusy)
        .accessibilityLabel(accessibleStatus(now: now))
        .accessibilityHint(baby.isAsleep ? "Wake \(baby.name)" : "Put \(baby.name) to sleep")
    }

    private func statusContent(now: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous)
        // The tightest line on the card, and it now carries a clock on both sides
        // of the state. At accessibility sizes the glyph, a wrapped name and a pair
        // of times cannot share a row, so it stacks the way `lastSeen` and the
        // action row already do.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            StatusGlyph(asleep: baby.isAsleep, tint: stateColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(baby.name) is \(baby.isAsleep ? "asleep" : "awake")")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .font(.caption)
                    // `soft`, not `faint`, and the fills depend on it. `faint` was
                    // the binding constraint on how deep either fill could go, and
                    // the fill had to be deep enough to still look like this baby's
                    // colour. Moving one line to the next role up bought that room —
                    // and it is a line read at 3am, so it is the better call anyway.
                    .foregroundStyle(palette.soft)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            sleepTimes(now: now)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stateWash, in: shape)
        // Two points, not one: the tint is the third signal here, behind the name
        // in the copy and the icon, and a hairline would disappear against the
        // wash it sits on.
        .overlay(shape.stroke(stateColor, lineWidth: 2))
        .contentShape(shape)
    }

    /// "Since 3:42am · tap to wake" — when this state began, then what the tap does.
    ///
    /// The hint names the state the tap moves *to*, and uses the same two words as
    /// the button below it. Copy that describes the wrong gesture is worse than no
    /// copy, and this line has already been wrong once in the other direction.
    ///
    /// The time sits on this line rather than trailing the state sentence above it,
    /// which is where it was first put. Appended there it wrapped, and it wrapped
    /// *inside* the parenthetical — "(since" ending one line and "10:12am)" alone on
    /// the next — because the tile also carries times on its trailing edge, in both
    /// states now, and any name longer than "Mia" makes it worse. The state stays
    /// one short bold line; the clock time is the supporting fact.
    ///
    /// Both states carry the time now. Awake used to say nothing about when it
    /// started, which was the more useful of the two — "she has been up since 4:20"
    /// is what decides whether to try a feed.
    private var subtitle: String {
        let hint = baby.isAsleep ? "tap to wake" : "tap to sleep"
        guard let since = baby.stateSince else {
            // Before this baby has slept, there is no honest answer. Say nothing
            // rather than name the shift's start as though it were a wake.
            return hint.prefix(1).uppercased() + hint.dropFirst()
        }
        return "Since \(Fmt.clockAmPm(since, timeZone: timeZone)) · \(hint)"
    }

    /// The trailing edge of the tile: when this sleep started and how long it has
    /// run, or — once they are up — the sleep they just had.
    ///
    /// It used to be the elapsed counter alone, which meant that the moment a baby
    /// woke the tile forgot the sleep entirely and the only record of it was a row
    /// further down the screen. "3:42a–4:22a" is the answer to the question asked
    /// straight after a wake, and it is the one the next feed is timed against.
    ///
    /// `shortClock` for the finished range and `clockAmPm` for the single start:
    /// two "am"s inside one range is more letters than the tightest line on the card
    /// can spare, and the start time on its own is read across a dark room.
    @ViewBuilder
    private func sleepTimes(now: Date) -> some View {
        let alignment: HorizontalAlignment = dynamicTypeSize.isAccessibilitySize
            ? .leading : .trailing
        if let since = baby.asleepSince {
            VStack(alignment: alignment, spacing: 1) {
                Text(Fmt.clockAmPm(since, timeZone: timeZone))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.soft)
                // Monospaced so the number doesn't jitter as digit widths change.
                Text(Fmt.ago(since, now: now))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(stateColor)
            }
            .lineLimit(1)
            .layoutPriority(1)
        } else if let last = baby.lastSleep {
            Text("\(Fmt.shortClock(last.startAt, timeZone: timeZone))–"
                + Fmt.shortClock(last.endAt, timeZone: timeZone))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette.soft)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// VoiceOver gets the elapsed time as well as the clock time. The spoken
    /// "asleep for 40m" answers the question the doula is actually asking faster
    /// than "asleep since 3:42am" does, so it leads — but the tile now shows both,
    /// and a label that names less than the screen does is its own bug.
    ///
    /// `clockAmPm` rather than the `shortClock` the awake tile prints: "3:42a" is a
    /// column-width economy, and VoiceOver reads the bare letter aloud.
    private func accessibleStatus(now: Date) -> String {
        if let since = baby.asleepSince {
            return "\(baby.name) asleep for \(Fmt.ago(since, now: now)), "
                + "since \(Fmt.clockAmPm(since, timeZone: timeZone))"
        }
        let awake: String
        if let woke = baby.awakeSince {
            awake = "\(baby.name) awake for \(Fmt.ago(woke, now: now))"
        } else {
            awake = "\(baby.name) awake"
        }
        guard let last = baby.lastSleep else { return awake }
        return awake + ". Last slept \(Fmt.clockAmPm(last.startAt, timeZone: timeZone)) "
            + "to \(Fmt.clockAmPm(last.endAt, timeZone: timeZone))"
    }

    private func lastSeen(now: Date) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            // The glyph changes as well as the colour when a feed is due —
            // `docs/design.md`: colour is never the only signal. It was the only
            // signal here, on the one chip that decides the next action.
            chip("drop.fill", baby.lastFeedAt, now: now,
                 empty: "no feed yet", label: "Last feed", warn: baby.feedIsDue(now: now))
            chip(CareGlyph.diaper, baby.lastDiaperAt, now: now,
                 empty: "no change yet", label: "Last diaper", warn: false)
            Spacer()
        }
    }

    private func chip(
        _ icon: String, _ at: Date?, now: Date, empty: String, label: String, warn: Bool
    ) -> some View {
        HStack(spacing: 5) {
            CareGlyph(
                warn ? "exclamationmark.triangle.fill" : icon,
                size: 11, relativeTo: .caption2)
            Text((at.map { Fmt.ago($0, now: now) } ?? empty) + (warn ? " · due" : ""))
                .font(.caption.monospacedDigit())
        }
        // `soft`, not `faint`, when it is not warning: these two lines are what
        // decide the next action, and they were the palest text on the card.
        .foregroundStyle(warn ? palette.warn : palette.soft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): " + (at.map { Fmt.ago($0, now: now) + " ago" } ?? empty) + (warn ? ", due" : ""))
    }

    /// Four, not three. `onNote` was declared here and passed in from `TonightView`
    /// from the day the card was written, and never called — so the note sheet, the
    /// note tags in Settings, the temperature field and the fever badge were all
    /// built, tested and unreachable, and shipped that way. The comment on
    /// `extraButtons` already said "the card's four controls".
    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            action("Feed", "drop.fill", onFeed)
            action("Diaper", CareGlyph.diaper, onDiaper)
            action("Note", "text.bubble.fill", onNote)
            // Tinted by the state the button moves *to*, matching its label —
            // "Wake" is gold, "Sleep" is sage, whichever state you are in now.
            action(
                baby.isAsleep ? "Wake" : "Sleep",
                baby.isAsleep ? "sun.max.fill" : "moon.zzz.fill",
                onToggleSleep, tint: baby.isAsleep ? palette.awake : palette.sleep)
        }
    }

    private func action(
        _ title: String, _ icon: String, _ run: @escaping () -> Void, tint: Color? = nil
    ) -> some View {
        Button(action: {
            guard !isBusy else { return }
            Haptics.tap()
            run()
        }) {
            VStack(spacing: 4) {
                CareGlyph(icon)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(minHeight: MoonLayout.tapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle((tint ?? palette.ink).opacity(isBusy ? 0.4 : 1))
        .background(palette.chip, in: RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: MoonLayout.controlCorner, style: .continuous))
        .disabled(isBusy)
        .accessibilityLabel("\(title) for \(baby.name)")
    }
}

/// A `ButtonStyle` that hands its label straight back.
///
/// `.plain` still dims what it wraps while the finger is down. On the status tile —
/// a bordered block most of the card wide — that dimming reads as a rendering fault
/// rather than as feedback, which is why it is gone. Only the tile uses this: the
/// action row keeps `.plain`, where a small control fading under a thumb is the
/// expected thing.
private struct UntouchedButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The moon and the sun, drawn rather than set in SF Symbols.
///
/// The ask was for the z's and the rays to keep moving *independently* — of each
/// other and of the tile. `moon.zzz.fill` and `sun.max.fill` are each one glyph, so
/// every symbol effect this deployment target has moves the whole thing at once: it
/// can shake the moon, it cannot send the z's up on their own. Shapes can.
///
/// Two kinds of motion, deliberately. A continuous drift that says the tile is live,
/// and a one-shot shake-and-swell fired by `asleep` actually changing. Both are
/// small: this is read at 3am in a dark nursery, and the glyph is one of the three
/// signals — glyph, words, colour — that say which state the baby is in, so it never
/// fades out of legibility and never passes through the other shape on the way.
private struct StatusGlyph: View {
    let asleep: Bool
    let tint: Color

    /// The drift is decoration, so it is the first thing to go.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sized off `.title3` — the size the SF Symbol it replaces was set in.
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 26

    var body: some View {
        Group {
            if asleep {
                MoonGlyph(side: side, tint: tint, still: reduceMotion)
            } else {
                SunGlyph(side: side, tint: tint, still: reduceMotion)
            }
        }
        .frame(width: side, height: side)
        // Fires on the state change, never on a timer. Reduce Motion collapses the
        // sequence to a single phase, which leaves the animator nowhere to go.
        .phaseAnimator(reduceMotion ? [0] : [0, 1, 2, 3], trigger: asleep) { glyph, phase in
            glyph
                .rotationEffect(.degrees(shake(phase)))
                .scaleEffect(swell(phase))
        } animation: { _ in .spring(response: 0.17, dampingFraction: 0.55) }
    }

    private func shake(_ phase: Int) -> Double {
        switch phase {
        case 1: return -7
        case 2: return 5
        default: return 0
        }
    }

    private func swell(_ phase: Int) -> Double {
        switch phase {
        case 1: return 1.12
        case 2: return 1.05
        default: return 1
        }
    }
}

/// A crescent with three z's climbing away from it.
///
/// Its own view rather than a branch inside `StatusGlyph`, because the drift starts
/// from `onAppear`: a repeating animation only attaches when the value it watches
/// changes, and swapping sun for moon inserts a fresh view whose `onAppear` runs.
/// One `@State` shared across both would leave whichever glyph appeared second
/// sitting perfectly still.
private struct MoonGlyph: View {
    let side: CGFloat
    let tint: Color
    let still: Bool

    @State private var drifting = false

    var body: some View {
        ZStack {
            Crescent()
                .fill(tint, style: FillStyle(eoFill: true))
                .frame(width: side * 0.78, height: side * 0.78)
                .offset(x: -side * 0.10, y: side * 0.08)

            // The z's are the decoration and the crescent is the signal, which is
            // why only the z's fade: at the top of each climb they are gone and the
            // moon is not, so "asleep" is legible on every frame. Staggered by a
            // delay each, so the three climb as a train rather than in lockstep.
            ForEach(0..<3, id: \.self) { i in
                let step = Double(i)
                Text("z")
                    .font(.system(
                        size: side * (0.17 + 0.05 * step), weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .offset(
                        x: side * (0.15 + 0.10 * step) + (drifting ? side * 0.09 : 0),
                        y: -side * (0.03 + 0.15 * step) - (drifting ? side * 0.13 : 0))
                    .opacity(drifting ? 0 : 1)
                    .animation(
                        still
                            ? nil
                            : .easeOut(duration: 2.6)
                                .repeatForever(autoreverses: false)
                                .delay(step * 0.85),
                        value: drifting)
            }
        }
        // Under Reduce Motion `drifting` never leaves `false`, which is also the
        // resting frame: three z's stepping up off a full moon.
        .onAppear { drifting = !still }
    }
}

/// A disc with eight rays turning slowly around it.
///
/// One ray's pitch per cycle — 45° of eight — so the turn closes on itself and the
/// restart is invisible. Nine seconds for that 45° is about five degrees a second:
/// enough that the tile is alive, little enough that it is not something to watch.
private struct SunGlyph: View {
    let side: CGFloat
    let tint: Color
    let still: Bool

    @State private var turning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: side * 0.46, height: side * 0.46)

            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: side * 0.07, height: side * 0.16)
                        .offset(y: -side * 0.38)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }
            .rotationEffect(.degrees(turning ? 45 : 0))
            .animation(
                still ? nil : .linear(duration: 9).repeatForever(autoreverses: false),
                value: turning)
        }
        .onAppear { turning = !still }
    }
}

/// A disc with a second disc punched out of it. The overlap is only a hole when the
/// fill is even-odd, so `FillStyle(eoFill: true)` at the call site is load-bearing —
/// without it this draws a plain circle.
private struct Crescent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addPath(
            Path(ellipseIn: rect.offsetBy(dx: rect.width * 0.32, dy: -rect.height * 0.13)))
        return path
    }
}
