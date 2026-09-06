import SwiftUI
import MoonlogCore

struct FeedSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    let unit: VolumeUnit
    let editing: FeedEntry?
    let onSave: (FeedEntry) -> Void
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
        reassignment: Reassignment? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (FeedEntry) -> Void
    ) {
        self.baby = baby
        self.shift = shift
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

    /// Something must have been entered — an empty feed record helps nobody.
    private var hasContent: Bool {
        switch method {
        case .bottleBreastmilk, .bottleFormula: return amountMl > 0 || bottleMinutes > 0
        case .breast: return leftMinutes + rightMinutes > 0
        // An unrecorded method is already saved; editing its time alone is valid.
        case .unknown: return true
        }
    }

    var body: some View {
        LogSheetChrome(
            title: editing == nil ? "Feed" : "Edit feed",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $at,
            shift: shift,
            reassignment: reassignment,
            saveEnabled: hasContent,
            onSave: save,
            onDelete: onDelete
        ) {
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
                    MinutesField(label: "Duration", minutes: $bottleMinutes)
                }
            } else {
                // Each side separately: one feed commonly uses both, and a single
                // combined figure cannot express that.
                Section("Time at breast") {
                    MinutesField(label: "Left", minutes: $leftMinutes)
                    MinutesField(label: "Right", minutes: $rightMinutes)
                }
            }
        }
    }

    private func save() {
        onSave(
            FeedEntry(
                at: at,
                method: method,
                amountMl: method.isBottle && amountMl > 0 ? amountMl : nil,
                bottleSeconds: method.isBottle && bottleMinutes > 0 ? bottleMinutes * 60 : nil,
                leftSeconds: !method.isBottle && leftMinutes > 0 ? leftMinutes * 60 : nil,
                rightSeconds: !method.isBottle && rightMinutes > 0 ? rightMinutes * 60 : nil))
    }
}

struct FeedEntry {
    let at: Date
    let method: FeedMethod
    let amountMl: Double?
    let bottleSeconds: Int?
    let leftSeconds: Int?
    let rightSeconds: Int?
}
