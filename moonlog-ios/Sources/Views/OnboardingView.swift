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
    @State private var isCreating = false

    @Environment(\.palette) private var palette

    private var trimmedFamily: String { familyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBaby: String { babyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool {
        !trimmedFamily.isEmpty && !trimmedBaby.isEmpty && birthAt <= Date() && !isCreating
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
                Picker("Bottle measurement", selection: $unit) {
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
                // `isCreating` matters: a second tap creates a second Family.
                // That is no longer a trap door — the family menu on Tonight can
                // reach it — but there is still no in-app delete.
                Button("Create") {
                    guard !isCreating else { return }
                    isCreating = true
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
    /// Seeded on appear, not at construction. This view is the root whenever no
    /// shift is open, so a `Date()` captured here survives backgrounding — open the
    /// app at 21:50, start the shift at 22:35, and it would record 21:50.
    @State private var startedAt = Date()
    @State private var isStarting = false

    @Environment(\.palette) private var palette

    private var isFuture: Bool { startedAt.isMeaningfullyInFuture }

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
                    guard !isStarting else { return }
                    isStarting = true
                    onStart(
                        startedAt,
                        caregiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil : caregiver)
                }
                .disabled(isFuture || isStarting)
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(palette.raised)
        }
        .scrollContentBackground(.hidden)
        .background(palette.bg)
        .onAppear { startedAt = Date() }
    }
}

/// Adding a twin later, from the Tonight toolbar.
struct AddBabySheet: View {
    let familyName: String
    let onAdd: (String, Date) -> Void

    @State private var name = ""
    @State private var birthAt = Date()
    @State private var isAdding = false

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
                    // Two taps produce two identical babies. The timeline then
                    // splits one infant's night across two cards.
                    Button("Add") {
                        guard !isAdding else { return }
                        isAdding = true
                        onAdd(trimmed, birthAt)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || isAdding)
                }
            }
        }
        .tint(palette.accent)
    }
}

/// Taking on another client household, from the family menu on Tonight.
///
/// Not `OnboardingView` in a sheet: onboarding is the first-run screen, it has no
/// way out, and its copy welcomes someone who has already been welcomed. The
/// fields are the same, and both paths call the same three writes in `RootView`.
struct AddFamilySheet: View {
    let onAdd: (String, String, Date, VolumeUnit) -> Void

    @State private var familyName = ""
    @State private var babyName = ""
    @State private var birthAt = Date()
    @State private var unit: VolumeUnit = .oz
    @State private var isAdding = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    private var trimmedFamily: String { familyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBaby: String { babyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool {
        !trimmedFamily.isEmpty && !trimmedBaby.isEmpty && birthAt <= Date() && !isAdding
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Family") {
                    TextField("Household name", text: $familyName)
                        .textInputAutocapitalization(.words)
                    Picker("Bottle measurement", selection: $unit) {
                        ForEach(VolumeUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                .listRowBackground(palette.raised)

                // A baby is required here for the same reason it is at first run:
                // a household with none opens on an empty Tonight with nothing to
                // log against.
                Section("Baby") {
                    TextField("Name", text: $babyName)
                        .textInputAutocapitalization(.words)
                    DatePicker("Born", selection: $birthAt, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                }
                .listRowBackground(palette.raised)
            }
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle("Add family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Two taps produce two identical households, as on the
                    // onboarding form.
                    Button("Add") {
                        guard !isAdding else { return }
                        isAdding = true
                        onAdd(trimmedFamily, trimmedBaby, birthAt, unit)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .tint(palette.accent)
    }
}
