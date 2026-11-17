import SwiftUI
import MoonlogCore

/// A saved draft, an explicitly reviewed snapshot, and optional receipt on this
/// phone are separate stages. Nothing here claims a message was delivered.
struct DayReportView: View {
    private let shiftID: UUID
    private let familyName: String
    private let startedAt: Date
    private let timeZoneIdentifier: String
    @State private var shiftOpen: Bool

    init(family: Family, shift: Shift) {
        self.shiftID = shift.id
        self.familyName = family.name
        self.startedAt = shift.startedAt
        self.timeZoneIdentifier = shift.timeZoneIdentifier
        _shiftOpen = State(initialValue: shift.isOpen)
    }
    @Environment(\.careStore) private var store
    @Environment(\.palette) private var palette
    @State private var state: DayReportState?
    @State private var draft = DayReportDraft()
    @State private var facts: DayReportComposer.Facts?
    @State private var reviewed = false
    @State private var busy = false
    @State private var error: String?
    @State private var showingReceipt = false
    @State private var draftSaveTask: Task<Void, Never>?
    @FocusState private var editingField: String?

    private var dirty: Bool { state.map { $0.draft.normalized != draft.normalized } ?? false }
    private var current: DayReportPublication? {
        guard !dirty, let facts else { return nil }
        return state?.currentPublication(for: facts.fingerprint)
    }

    private var temporaryStorage: Bool {
        if case .inMemory = ModelContainerFactory.mode { return true }
        return false
    }
    private var draftStatus: String {
        if dirty { return error == nil ? "Saving draft… " : "Draft not saved yet. " }
        return temporaryStorage ? "Draft retained for this session only. " : "Draft saved on this phone. "
    }

    var body: some View {
        Form {
            if temporaryStorage {
                Section {
                    Label("Temporary storage — this session only", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(palette.stop)
                    Text("Drafts, revisions and optional receipts can be lost when the app closes. Share a copy, and check Storage in Settings before relying on this phone to retain the handoff.")
                }.listRowBackground(palette.raised)
            }
            Section {
                Text(familyName).font(.headline)
                Text("Day care · \(Fmt.longDate(startedAt, timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .gmt))")
                Text(shiftOpen ? "Draft — shift still running" : "Shift ended — ready for review")
                    .font(.footnote).foregroundStyle(palette.soft)
            }
            .listRowBackground(palette.raised)
            if state != nil {
                Section {
                    TextField("Caregiver name", text: $draft.caregiverName)
                        .textContentType(.name).focused($editingField, equals: "report.caregiver").accessibilityIdentifier("report.caregiver")
                    narrativeField("Today's summary", text: $draft.summary, identifier: "report.summary")
                    narrativeField("Handoff notes / what helped", text: $draft.eveningNotes, identifier: "report.notes")
                    narrativeField("Questions / supplies to follow up", text: $draft.questions, identifier: "report.questions")
                    Button(busy ? "Saving…" : "Save draft") { saveDraft() }
                        .disabled(busy || !dirty).accessibilityIdentifier("report.saveDraft")
                } header: { Text("Your editable observations") }
                footer: { Text(draftStatus + "These notes do not change the recorded feed, diaper or sleep entries. Each note can contain up to 2,000 characters.") }
                .listRowBackground(palette.raised)

                Section {
                    NavigationLink {
                        ScrollView {
                            Text(facts?.text ?? "Care log unavailable")
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        .moonBackground(palette).navigationTitle("Review care log")
                    } label: { Label("Review names, hours and care log", systemImage: "list.bullet.clipboard") }
                    .accessibilityIdentifier("report.reviewFacts")
                    Button("Refresh care log") { load() }.disabled(busy)
                    Toggle("I reviewed the notes and care log", isOn: $reviewed)
                        .accessibilityIdentifier("report.reviewed")
                    Button(busy ? "Saving…" : "Publish reviewed report") { publish() }
                        .disabled(busy || dirty || !reviewed || shiftOpen || draft.caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("report.publish")
                } header: { Text("Review before sharing") }
                footer: { Text(shiftOpen
                    ? "You can save a draft now. End the shift before publishing the final coverage window."
                    : "Publishing freezes this revision on this phone. It does not send it. Later edits require a new review and revision.") }
                .listRowBackground(palette.raised)

                if let current {
                    Section {
                        NavigationLink {
                            PublishedDayReportView(publication: current, receipts: state?.acknowledgements(for: current) ?? [])
                        } label: { Label("Open & share revision \(current.version)", systemImage: "doc.text") }
                        .accessibilityIdentifier("report.openPublished")
                        Text((temporaryStorage ? "Published for this session only" : "Published locally") + " · revision \(current.version)")
                            .accessibilityIdentifier("report.publishedStatus")
                        Button("Optional parent receipt on this phone") { showingReceipt = true }
                            .accessibilityIdentifier("report.optionalReceipt")
                        if let receipts = state?.acknowledgements(for: current), !receipts.isEmpty {
                            Text("\(receipts.count) optional in-person receipt\(receipts.count == 1 ? "" : "s") recorded for this revision.")
                                .font(.footnote)
                        }
                    } header: { Text("Current reviewed copy") }
                    footer: { Text("Parent receipt is optional. You can share and finish handoff without recording one. A typed name on this phone is not authenticated identity or consent to care decisions.") }
                    .listRowBackground(palette.raised)
                } else if state?.latestPublication != nil {
                    Section {
                        Label("Draft or care log changed — review and publish a new revision.", systemImage: "pencil.circle")
                    }.listRowBackground(palette.raised)
                }
                if let publications = state?.publications, !publications.isEmpty {
                    Section("Saved revisions") {
                        ForEach(publications.reversed()) { publication in
                            NavigationLink("Revision \(publication.version) · \(publication.publishedAt.formatted(date: .abbreviated, time: .shortened))") {
                                PublishedDayReportView(publication: publication,
                                                       receipts: state?.acknowledgements(for: publication) ?? [])
                            }
                        }
                    }.listRowBackground(palette.raised)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(palette.stop)
                    Button(state == nil ? "Retry loading" : "Refresh care log and retry") { load() }
                }.listRowBackground(palette.raised)
            }
        }
        .disabled(busy)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden).moonBackground(palette)
        .navigationTitle("End-of-day report").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingField = nil }.accessibilityIdentifier("report.doneEditing")
            }
        }
        .task { load() }
        .onChange(of: draft) { _, _ in
            reviewed = false
            scheduleDraftSave()
        }
        .onDisappear {
            draftSaveTask?.cancel()
            if dirty { persistDraftOnExit() }
        }
        .sheet(isPresented: $showingReceipt) {
            if let current {
                ParentReceiptSheet(publication: current) { name, note in
                    guard let store else { throw EntrySaveError.unavailable }
                    let result = try await store.acknowledgeDayReport(shiftID, publicationID: current.id,
                                                                    version: current.version, parentName: name,
                                                                    note: note, at: Date())
                    state = result
                }
            }
        }
    }

    private func narrativeField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(palette.soft)
            TextField(title, text: text, axis: .vertical).lineLimit(3...7)
                .focused($editingField, equals: identifier).accessibilityIdentifier(identifier)
        }
    }

    private func load() {
        guard !busy else { return }
        guard let store else { error = "The data store is unavailable. Nothing was changed."; return }
        busy = true
        Task { @MainActor in
            do {
                let snapshot = try await store.dayReportSnapshot(shiftID)
                // A tab switch can refresh facts without discarding entered text.
                if !dirty { draft = snapshot.state.draft }
                state = snapshot.state
                facts = snapshot.facts
                shiftOpen = snapshot.isOpen
                reviewed = false; error = nil
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    /// Writes still go through the actor. A short debounce avoids a durable save
    /// for every keystroke; leaving this screen flushes the latest entered values.
    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        guard dirty, let store else { return }
        let entered = draft
        draftSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
                try Task.checkCancellation()
                let saved = try await store.saveDayReportDraft(shiftID, draft: entered)
                if draft == entered { state = saved; error = nil }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func persistDraftOnExit() {
        guard let store else { return }
        let entered = draft
        Task { @MainActor in
            do { state = try await store.saveDayReportDraft(shiftID, draft: entered) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func saveDraft() {
        draftSaveTask?.cancel()
        perform { store in
            let saved = try await store.saveDayReportDraft(shiftID, draft: draft)
            state = saved; draft = saved.draft
            let snapshot = try await store.dayReportSnapshot(shiftID)
            facts = snapshot.facts; shiftOpen = snapshot.isOpen
            reviewed = false
        }
    }

    private func publish() {
        guard let fingerprint = facts?.fingerprint else { return }
        perform { store in
            state = try await store.publishDayReport(shiftID, reviewedFingerprint: fingerprint,
                                                      reviewedDraft: draft, at: Date())
            let snapshot = try await store.dayReportSnapshot(shiftID)
            facts = snapshot.facts; shiftOpen = snapshot.isOpen
            reviewed = false
        }
    }

    private func perform(_ action: @escaping @MainActor (CareStore) async throws -> Void) {
        guard !busy else { return }
        guard let store else { error = "The data store is unavailable. Nothing was saved."; return }
        busy = true; error = nil
        Task { @MainActor in
            do { try await action(store) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct PublishedDayReportView: View {
    let publication: DayReportPublication
    let receipts: [DayReportAcknowledgement]
    @Environment(\.palette) private var palette
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if case .inMemory = ModelContainerFactory.mode {
                    Label("Temporary storage: share a copy before closing the app.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(palette.stop)
                }
                Text("Revision \(publication.version)").font(.title2).accessibilityIdentifier("report.revisionTitle")
                Text("Published on this phone \(publication.publishedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                Text(publication.plainText).textSelection(.enabled)
                ForEach(receipts) { receipt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Optional in-person receipt · \(receipt.parentName)").font(.headline)
                        Text(receipt.acknowledgedAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                        if !receipt.note.isEmpty { Text("Parent note: \(receipt.note)") }
                        Text("Recorded on the caregiver's phone; name not authenticated. Receipt of this revision only, not care consent.").font(.caption)
                    }.padding().cardSurface(palette)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .moonBackground(palette).navigationTitle("Reviewed report")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: publication.plainText) { Label("Share text copy", systemImage: "text.alignleft") }
                    ShareLink(item: HandoffPage(filename: "Nanny Log revision \(publication.version).html", html: publication.html),
                              preview: SharePreview("Nanny Log revision \(publication.version)")) {
                        Label("Share designed page", systemImage: "doc.richtext")
                    }
                    Button("Copy report") { UIPasteboard.general.string = publication.plainText }
                } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("report.share")
            }
        }
    }
}

private struct ParentReceiptSheet: View {
    let publication: DayReportPublication
    let onSave: (String, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var name = ""
    @State private var note = ""
    @State private var received = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var editingField: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Optional receipt of revision \(publication.version)")
                    Text(publication.publishedAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                    DisclosureGroup("Read this report revision") { Text(publication.plainText).textSelection(.enabled) }
                    Text("Hand this phone to the parent. This records their receipt of this report only; it is not approval of care decisions. Their typed name is not authenticated.")
                    TextField("Parent name", text: $name).focused($editingField, equals: "name").accessibilityIdentifier("report.parentName")
                    TextField("Parent note or question (optional)", text: $note, axis: .vertical).lineLimit(3...6)
                        .focused($editingField, equals: "note").accessibilityIdentifier("report.parentNote")
                    Toggle("I received this report revision", isOn: $received).accessibilityIdentifier("report.received")
                    Button(busy ? "Saving…" : "Record optional receipt") {
                        busy = true; error = nil
                        Task { @MainActor in
                            do { try await onSave(name, note); dismiss() }
                            catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }.disabled(busy || !received || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("report.saveReceipt")
                }.listRowBackground(palette.raised)
                if let error { Section { Text(error).foregroundStyle(palette.stop) }.listRowBackground(palette.raised) }
            }.disabled(busy).scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).moonBackground(palette)
                .navigationTitle("Optional parent receipt").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { editingField = nil }.accessibilityIdentifier("report.receiptDoneEditing")
                    }
                }
        }.interactiveDismissDisabled(busy).tint(palette.accent)
    }
}
