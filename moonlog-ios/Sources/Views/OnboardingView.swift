import SwiftUI
import MoonlogCore

/// First run: a family, one baby, and the unit that family reads bottles in.
///
/// Deliberately asks for a household name rather than assuming one baby lives
/// alone — every query, export and handoff is scoped to a family, and retrofitting
/// that later would mean a migration.
struct OnboardingView: View {
    let onCreate: (String, String, Date, VolumeUnit) -> Void

    @State private var familyName = ""
    @State private var babyName = ""
    @State private var birthAt = Date()
    @State private var unit: VolumeUnit = .oz

    @Environment(\.palette) private var palette

    private var trimmedFamily: String { familyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBaby: String { babyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool {
        !trimmedFamily.isEmpty && !trimmedBaby.isEmpty && birthAt <= Date()
    }

    var body: some View {
        Form {
            Section {
                // One row, not two — two rows draw a separator between them.
                VStack(spacing: 10) {
                    Text("🌙").font(.system(size: 34))
                    Text("Set up the family you're caring for. You can add a second "
                         + "baby, and more families, later.")
                        .font(.footnote)
                        .foregroundStyle(palette.faint)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section("Family") {
                TextField("Household name", text: $familyName)
                    .textInputAutocapitalization(.words)
                Picker("Bottles in", selection: $unit) {
                    ForEach(VolumeUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            .listRowBackground(palette.raised)

            Section("Baby") {
                TextField("Name", text: $babyName)
                    .textInputAutocapitalization(.words)
                DatePicker("Born", selection: $birthAt, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
            }
            .listRowBackground(palette.raised)

            Section {
                Button("Create") {
                    onCreate(trimmedFamily, trimmedBaby, birthAt, unit)
                }
                .disabled(!canCreate)
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(palette.raised)
        }
        .scrollContentBackground(.hidden)
        .background(palette.bg)
        .navigationTitle("Welcome")
    }
}

/// Between visits there is no open shift — a normal state, not an error. Start and
/// end times are set or confirmed by the doula, never read off the clock.
struct StartShiftView: View {
    let familyName: String
    let onStart: (Date, String?) -> Void

    @AppStorage("moonlog.lastCaregiver") private var caregiver = ""
    @State private var startedAt = Date()

    @Environment(\.palette) private var palette

    private var isFuture: Bool { startedAt > Date().addingTimeInterval(60) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text("🌙").font(.system(size: 34))
                    Text(familyName).font(.headline).foregroundStyle(palette.ink)
                    Text("No shift running").font(.footnote).foregroundStyle(palette.faint)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section("Shift") {
                DatePicker("Started", selection: $startedAt,
                           displayedComponents: [.date, .hourAndMinute])
                if isFuture {
                    Label("That's in the future", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.stop)
                        .font(.footnote)
                }
                TextField("Caregiver (optional)", text: $caregiver)
                    .textInputAutocapitalization(.words)
            }
            .listRowBackground(palette.raised)

            Section {
                Button("Start shift") {
                    onStart(
                        startedAt,
                        caregiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil : caregiver)
                }
                .disabled(isFuture)
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(palette.raised)
        }
        .scrollContentBackground(.hidden)
        .background(palette.bg)
    }
}

/// Adding a twin later, from the Tonight toolbar.
struct AddBabySheet: View {
    let familyName: String
    let onAdd: (String, Date) -> Void

    @State private var name = ""
    @State private var birthAt = Date()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section(familyName) {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                    DatePicker("Born", selection: $birthAt, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                }
                .listRowBackground(palette.raised)
            }
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle("Add baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(trimmed, birthAt); dismiss() }
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .tint(palette.accent)
    }
}
