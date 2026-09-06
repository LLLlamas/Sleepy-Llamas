import SwiftUI
import MoonlogCore

/// The opt-in kinds — pumping, a medication, a weight — share one entry, because
/// each is a time plus one or two fields.
struct ExtraEntry {
    let at: Date
    let pumpedMl: Double?
    let medicationName: String?
    let doseText: String?
    let weightGrams: Double?
}

/// The way in for the three kinds Settings can enable.
///
/// They could be switched on and then logged by nothing: there was no create path
/// and no edit path, and their timeline rows were deliberately inert because the
/// only sheet they could have routed to was the note sheet, which would have
/// written note fields onto a record that never renders them.
///
/// One sheet rather than three: the chrome call is identical and only the middle
/// section differs.
struct ExtraSheet: View {
    let kind: EventKind
    /// `nil` for a pump, which is about the mother and carries no baby.
    let baby: BabyPresentation?
    let shift: ShiftWindow
    let unit: VolumeUnit
    let editing: ExtraEntry?
    var onDelete: (() -> Void)?
    var reassignment: Reassignment?
    let onSave: (ExtraEntry) -> Void

    @State private var at: Date
    @State private var pumpedMl: Double
    @State private var medicationName: String
    @State private var doseText: String
    @State private var weightGrams: Double

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    init(
        kind: EventKind,
        baby: BabyPresentation?,
        shift: ShiftWindow,
        unit: VolumeUnit,
        editing: ExtraEntry? = nil,
        reassignment: Reassignment? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (ExtraEntry) -> Void
    ) {
        self.kind = kind
        self.baby = baby
        self.shift = shift
        self.unit = unit
        self.editing = editing
        self.reassignment = reassignment
        self.onDelete = onDelete
        self.onSave = onSave
        _at = State(initialValue: editing?.at ?? Date())
        _pumpedMl = State(initialValue: editing?.pumpedMl ?? 0)
        _medicationName = State(initialValue: editing?.medicationName ?? "")
        _doseText = State(initialValue: editing?.doseText ?? "")
        _weightGrams = State(initialValue: editing?.weightGrams ?? 0)
    }

    /// An empty record helps nobody, and the parents read every line.
    private var hasContent: Bool {
        switch kind {
        case .pump: return pumpedMl > 0
        case .medication:
            return !medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .measurement: return weightGrams > 0
        default: return false
        }
    }

    var body: some View {
        LogSheetChrome(
            title: editing == nil ? kind.noun : "Edit \(kind.noun.lowercased())",
            babyName: baby?.name,
            accent: baby?.accent.color(for: theme) ?? palette.accent,
            at: $at,
            shift: shift,
            reassignment: reassignment,
            saveEnabled: hasContent,
            onSave: { onSave(entry) },
            onDelete: onDelete
        ) {
            switch kind {
            case .pump:
                Section("Pumped") {
                    AmountField(unit: unit, ml: $pumpedMl)
                }
            case .medication:
                Section("Given") {
                    TextField("Name", text: $medicationName)
                        .textInputAutocapitalization(.words)
                    TextField("Dose", text: $doseText)
                }
            case .measurement:
                Section("Weighed") {
                    WeightField(unit: unit, grams: $weightGrams)
                }
            default:
                EmptyView()
            }
        }
    }

    /// Only this kind's own fields are carried. The store writes the payload
    /// wholesale, so sending a stale value from another kind would persist it.
    private var entry: ExtraEntry {
        let name = medicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dose = doseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtraEntry(
            at: at,
            pumpedMl: kind == .pump ? pumpedMl : nil,
            medicationName: kind == .medication && !name.isEmpty ? name : nil,
            doseText: kind == .medication && !dose.isEmpty ? dose : nil,
            weightGrams: kind == .measurement ? weightGrams : nil)
    }
}
