import SwiftUI
import MoonlogCore

struct FeedSheet: View {
    let baby: BabyPresentation
    let shift: ShiftWindow
    let unit: VolumeUnit
    let onSave: (FeedEntry) -> Void

    @State private var at = Date()
    @State private var method: FeedMethod = .breast
    @State private var leftMinutes = 0
    @State private var rightMinutes = 0
    @State private var amountMl: Double = 0
    @State private var bottleMinutes = 0

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    /// Something must have been entered — an empty feed record helps nobody.
    private var hasContent: Bool {
        method.isBottle ? (amountMl > 0 || bottleMinutes > 0) : (leftMinutes + rightMinutes > 0)
    }

    var body: some View {
        LogSheetChrome(
            title: "Feed",
            babyName: baby.name,
            accent: baby.accent.color(for: theme),
            at: $at,
            shift: shift,
            saveEnabled: hasContent,
            onSave: save
        ) {
            Section("How") {
                Picker("Method", selection: $method) {
                    Text("Breast").tag(FeedMethod.breast)
                    Text("Breastmilk").tag(FeedMethod.bottleBreastmilk)
                    Text("Formula").tag(FeedMethod.bottleFormula)
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
