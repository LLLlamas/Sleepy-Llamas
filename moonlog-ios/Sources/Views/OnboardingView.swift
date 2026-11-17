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
                    // Says where, not just "later" — twins are the normal case
                    // for this user, so the second baby is the expected next act
                    // and the route to it was never signposted.
                    Text("Set up the family you're caring for. A second baby, and "
                         + "more families, go in Settings whenever you need them.")
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
                // That is no longer a trap door — Settings › Client family can
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
        .moonBackground(palette)
        .navigationTitle("Welcome")
    }
}

/// Between visits there is no open shift — a normal state, not an error. Start and
/// end times are set or confirmed by the doula, never read off the clock.
///
/// Both ends are asked for here because the hours are booked in advance: the doula
/// knows at 10pm that she leaves at 6. The end is a **plan**, not the record —
/// `ShiftHoursSheet` still decides what actually gets written when she leaves — so
/// unlike the start it is allowed to be in the future, and has to be.
///
/// The roster sits on this screen against `CLAUDE.md`'s "adding a baby lives in
/// Settings", deliberately and at the user's request. That rule is about Tonight,
/// the logging screen: a mode change does not belong beside buttons pressed forty
/// times a night. This screen is the opposite — it is the setup that happens once,
/// before any logging, and arriving to find a twin missing is exactly when the
/// second card is needed. Settings keeps its copy; this is a second route, not a move.
struct StartShiftView: View {
    let familyName: String
    var shiftWindow: ShiftWindowDefault? = nil
    var timeZoneIdentifier: String = TimeZone.current.identifier
    /// Who is on the roster right now, in card order. Read for display only — the
    /// names answer "is the second twin here yet" without a trip to Settings.
    let babyNames: [String]
    let onAddBaby: (String, Date) -> Void
    let onStart: (Date, Date, String?, CareContext) async throws -> Void

    @AppStorage("moonlog.lastCareContext") private var careContextRaw = CareContext.night.rawValue
    @State private var startError: String?

    @AppStorage("moonlog.lastCaregiver") private var caregiver = ""
    /// Seeded on appear, not at construction. This view is the root whenever no
    /// shift is open, so a `Date()` captured here survives backgrounding — open the
    /// app at 21:50, start the shift at 22:35, and it would record 21:50.
    @State private var startedAt = Date()
    /// The booked end, seeded the same way and for the same reason. Eight hours is
    /// the shape of a night shift and the number is wrong on any given night, which
    /// is why it is a picker and not a constant.
    @State private var plannedEndAt = Date().addingTimeInterval(Self.defaultLength)
    @State private var addingBaby = false
    @State private var isStarting = false

    @Environment(\.palette) private var palette

    /// Eight hours. A suggestion the doula overrides, never a recorded length.
    private static let defaultLength: TimeInterval = 8 * 60 * 60

    private var isFuture: Bool { startedAt.isMeaningfullyInFuture }
    /// The end is *expected* to be in the future, so the only thing wrong with it is
    /// being before the start. `CareStore.startShift` enforces the same rule.
    private var endsBeforeStart: Bool { plannedEndAt < startedAt }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text(careContextRaw == CareContext.day.rawValue ? "☀️" : "🌙").font(.system(size: 34))
                    Text(familyName).font(.headline).foregroundStyle(palette.ink)
                    Text("No shift running").font(.footnote).foregroundStyle(palette.faint)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section("Care context") {
                Picker("Care context", selection: $careContextRaw) {
                    Text("Night care").tag(CareContext.night.rawValue)
                    Text("Day care · Nanny Log").tag(CareContext.day.rawValue)
                }
                .accessibilityIdentifier("shift.careContext")
                Text("Choose the work you're recording. Times and appearance stay under your control.")
                    .font(.footnote).foregroundStyle(palette.faint)
            }
            .listRowBackground(palette.raised)

            Section("Shift") {
                if let window = shiftWindow {
                    Button("Use usual family hours") {
                        let now = Date()
                        let calendar = MoonClock(timeZoneIdentifier: timeZoneIdentifier).calendar
                        startedAt = ShiftDefaults.suggestedStart(window, now: now, calendar: calendar) ?? now
                        plannedEndAt = ShiftDefaults.suggestedEnd(window, after: startedAt, calendar: calendar)
                    }
                    .accessibilityIdentifier("shift.usualHours")
                    Text("A suggestion to review, in \(timeZoneIdentifier). Starting a shift records only the times you confirm.")
                        .font(.footnote).foregroundStyle(palette.faint)
                }
                DatePicker("Start", selection: $startedAt,
                           displayedComponents: [.date, .hourAndMinute])
                if isFuture {
                    Advisory("That's in the future")
                }
                DatePicker("End", selection: $plannedEndAt,
                           displayedComponents: [.date, .hourAndMinute])
                if endsBeforeStart {
                    Advisory("That's before the shift starts")
                }
                TextField("Caregiver (optional)", text: $caregiver)
                    .textInputAutocapitalization(.words)
            }
            .listRowBackground(palette.raised)

            Section("Babies") {
                ForEach(babyNames, id: \.self) { name in
                    Text(name).foregroundStyle(palette.ink)
                }
                Button {
                    addingBaby = true
                } label: {
                    Label("Add baby", systemImage: "plus.circle.fill")
                }
                // The label's *contents* are what a plain button hit-tests, so the
                // row answered at the width of the words. See `CLAUDE.md`.
                .contentShape(Rectangle())
            }
            .listRowBackground(palette.raised)

        }
        .scrollContentBackground(.hidden)
        .moonBackground(palette)
        .safeAreaInset(edge: .bottom) {
            Button {
                guard !isStarting else { return }
                isStarting = true
                Task {
                    defer { isStarting = false }
                    do {
                        try await onStart(startedAt, plannedEndAt,
                            caregiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caregiver,
                            CareContext(rawValue: careContextRaw) ?? .night)
                    } catch { startError = error.localizedDescription }
                }
            } label: {
                Text(isStarting ? "Starting…" : "Start shift")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: MoonLayout.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFuture || endsBeforeStart || isStarting)
            .padding().background(.bar)
        }
        .onAppear {
            let now = Date()
            let calendar = MoonClock(timeZoneIdentifier: timeZoneIdentifier).calendar
            // Default hours prefill a visible, editable plan, never a recorded shift.
            startedAt = now
            plannedEndAt = shiftWindow.map {
                ShiftDefaults.suggestedEnd($0, after: now, calendar: calendar)
            } ?? now.addingTimeInterval(Self.defaultLength)
        }
        .environment(\.timeZone, TimeZone(identifier: timeZoneIdentifier) ?? .current)
        .alert("Couldn't start shift", isPresented: Binding(
            get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button("OK", role: .cancel) { startError = nil }
        } message: { Text(startError ?? "") }
        .sheet(isPresented: $addingBaby) {
            AddBabySheet(familyName: familyName, onAdd: onAddBaby)
                .presentationDetents([.medium])
        }
    }
}

/// Adding a twin later, from Settings › Babies.
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
            .moonBackground(palette)
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

/// Taking on another client household, from Settings › Client family.
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
            .moonBackground(palette)
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
