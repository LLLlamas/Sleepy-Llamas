import SwiftUI
import MoonlogCore

struct FeedSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    let unit: VolumeUnit
    let editing: FeedEntry?
    /// This baby's most recent feed, for "Same as last". `nil` on the first feed of
    /// the shift and while editing, where "last" would mean the record itself.
    let lastFeed: FeedEntry?
    let onSave: (FeedEntry) async throws -> Void
    var onDelete: (() -> Void)?
    /// Forwarded to the chrome; set only when editing.
    var reassignment: Reassignment?

    @State private var at: Date
    @State private var method: FeedMethod
    @State private var leftMinutes: Int
    @State private var rightMinutes: Int
    @State private var amountMl: Double
    @State private var bottleMinutes: Int

    init(
        baby: BabyPresentation,
        shift: ShiftWindow,
        unit: VolumeUnit,
        editing: FeedEntry? = nil,
        lastFeed: FeedEntry? = nil,
        reassignment: Reassignment? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (FeedEntry) async throws -> Void
    ) {
        self.baby = baby
        self.shift = shift
        self.lastFeed = editing == nil ? lastFeed : nil
        self.unit = unit
        self.editing = editing
        self.onDelete = onDelete
        self.reassignment = reassignment
        self.onSave = onSave
        _at = State(initialValue: editing?.at ?? Date())
        _method = State(initialValue: editing?.method ?? .breast)
        _leftMinutes = State(initialValue: (editing?.leftSeconds ?? 0) / 60)
        _rightMinutes = State(initialValue: (editing?.rightSeconds ?? 0) / 60)
        _amountMl = State(initialValue: editing?.amountMl ?? 0)
        _bottleMinutes = State(initialValue: (editing?.bottleSeconds ?? 0) / 60)
    }

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    var body: some View {
        LogSheetChrome(
            title: editing == nil ? "Feed" : "Edit feed",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $at,
            shift: shift,
            reassignment: reassignment,
            // No gate. A feed used to need a volume or a time at the breast before
            // it could be saved, on the grounds that an empty record helps nobody —
            // but the record was never empty: "she fed at the breast at 3:12" is the
            // fact that drives "last fed" and the overdue warning, and it is the one
            // you have when a baby unlatches and goes back down before you have
            // touched the phone. Refusing it lost the whole feed to save a detail.
            // `Handoff.warmFeed` already renders a bare "breast".
            saveEnabled: true,
            onSave: save,
            onDelete: onDelete
        ) {
            // The night's most repeated action is the same bottle again, and typing
            // it out four times is four chances to mis-set a stepper in the dark.
            // Deliberately not a prefill: an amount nobody chose would still reach
            // the parents' handoff as a measured fact, so the fields stay empty
            // until this is tapped. The time is never copied — that is the one
            // thing the doula has already set on the way in.
            if let parts = lastFeedParts {
                Section {
                    Button {
                        Haptics.tap()
                        applyLastFeed()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline)
                                .foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Same as last")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.ink)
                                Text(parts.joined(separator: " \u{00B7} "))
                                    .font(.caption)
                                    .foregroundStyle(palette.soft)
                            }
                            Spacer()
                        }
                        .frame(minHeight: MoonLayout.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feed.sameAsLast")
                    .accessibilityLabel(
                        "Repeat last feed, \(parts.joined(separator: ", "))")
                }
            }

            Section("How") {
                Picker("Method", selection: $method) {
                    Text("Breast").tag(FeedMethod.breast)
                    Text("Breastmilk").tag(FeedMethod.bottleBreastmilk)
                    Text("Formula").tag(FeedMethod.bottleFormula)
                    // Only shown for a record that already carries it — a value
                    // from a newer build must survive an edit rather than being
                    // silently rewritten to breast.
                    if editing?.method == .unknown { Text("Unrecorded").tag(FeedMethod.unknown) }
                }
                .pickerStyle(.segmented)
            }

            if method.isBottle {
                Section("Bottle") {
                    AmountField(unit: unit, ml: $amountMl)
                    MinutesField(label: "Duration", minutes: $bottleMinutes, step: 5)
                }
            } else {
                // Each side separately: one feed commonly uses both, and a single
                // combined figure cannot express that.
                Section("Time at breast") {
                    MinutesField(label: "Left", minutes: $leftMinutes, step: 5)
                    MinutesField(label: "Right", minutes: $rightMinutes, step: 5)
                }
            }
        }
    }

    /// What "same as last" would actually write, in pieces so the row can join them
    /// with a separator and VoiceOver can hear them as a sentence.
    ///
    /// The words are `Handoff.warmFeed`'s — "bottle, formula", "both sides" — because
    /// this row and the parents' handoff describe the same feed, and two spellings of
    /// one night is how the parents end up asking which one is right. `warmFeed`
    /// itself is internal to Core and takes an `EventSnapshot`, so it cannot be
    /// called from here.
    ///
    /// `nil` also for an `unknown` method: there is nothing to repeat, and setting it
    /// would select a tag the picker only offers while editing, leaving the segmented
    /// control with nothing lit.
    private var lastFeedParts: [String]? {
        guard let last = lastFeed else { return nil }
        var parts: [String] = []
        switch last.method {
        case .breast:
            let left = last.leftSeconds ?? 0
            let right = last.rightSeconds ?? 0
            if left > 0 && right > 0 {
                parts.append("both sides")
                parts.append("left \(Fmt.duration(TimeInterval(left))), "
                    + "right \(Fmt.duration(TimeInterval(right)))")
            } else if left > 0 {
                parts.append("left breast")
                parts.append(Fmt.duration(TimeInterval(left)))
            } else if right > 0 {
                parts.append("right breast")
                parts.append(Fmt.duration(TimeInterval(right)))
            } else {
                parts.append("breast")
            }
        case .bottleBreastmilk, .bottleFormula:
            if let ml = last.amountMl, ml > 0 {
                parts.append(Fmt.amount(ml: ml, unit: unit))
            }
            parts.append(last.method == .bottleFormula ? "bottle, formula" : "bottle, breastmilk")
            if let seconds = last.bottleSeconds, seconds > 0 {
                parts.append(Fmt.duration(TimeInterval(seconds)))
            }
        case .unknown:
            return nil
        }
        return parts
    }

    /// Everything but the time. A repeat is about what the baby took, not when.
    private func applyLastFeed() {
        guard let last = lastFeed else { return }
        method = last.method
        amountMl = last.amountMl ?? 0
        bottleMinutes = (last.bottleSeconds ?? 0) / 60
        leftMinutes = (last.leftSeconds ?? 0) / 60
        rightMinutes = (last.rightSeconds ?? 0) / 60
    }

    private func save() async throws {
        try await onSave(
            FeedEntry(
                at: at,
                method: method,
                amountMl: method.isBottle && amountMl > 0 ? amountMl : nil,
                bottleSeconds: method.isBottle && bottleMinutes > 0 ? bottleMinutes * 60 : nil,
                leftSeconds: !method.isBottle && leftMinutes > 0 ? leftMinutes * 60 : nil,
                rightSeconds: !method.isBottle && rightMinutes > 0 ? rightMinutes * 60 : nil))
    }
}

struct FeedEntry: Sendable {
    let at: Date
    let method: FeedMethod
    let amountMl: Double?
    let bottleSeconds: Int?
    let leftSeconds: Int?
    let rightSeconds: Int?
}
