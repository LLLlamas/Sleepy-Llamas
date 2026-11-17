import Foundation
import Observation
import MoonlogCore

/// One editor's ordered write stream. Cancelling a debounce cannot revoke an
/// actor call already submitted, so every later value waits for that call before
/// choosing its optimistic base. The actor separately rejects another editor's
/// changes; serialization alone cannot prevent a stale whole-draft replacement.
@MainActor @Observable
final class DayReportDraftWriter {
    struct Request {
        let entered: DayReportDraft
        let generation: UInt64
    }
    struct ReadTicket {
        let generation: UInt64
        let entered: DayReportDraft
        let hadUnsavedChanges: Bool
    }

    private(set) var base: DayReportDraft?
    private(set) var pendingWrites = 0
    private(set) var committedGeneration: UInt64 = 0
    private(set) var editGeneration: UInt64 = 0
    private(set) var conflicted = false
    private var requestGeneration: UInt64 = 0
    private var tail: Task<DayReportState, Error>?

    init(base: DayReportDraft? = nil) { self.base = base?.normalized }

    var hasPendingWrites: Bool { pendingWrites > 0 }
    func needsSave(_ draft: DayReportDraft) -> Bool {
        guard let base else { return false }
        return base != draft.normalized
    }
    func edited() {
        editGeneration &+= 1
        // A revert to the saved base may enqueue no replacement write. It still
        // invalidates a captured older request that has not entered this queue.
        requestGeneration &+= 1
    }

    /// Capture synchronously beside the entered value, before creating any Task.
    /// A later user revert is a newer request even when its text equals old data.
    func request(for entered: DayReportDraft) -> Request {
        requestGeneration &+= 1
        return Request(entered: entered, generation: requestGeneration)
    }
    func readTicket(for draft: DayReportDraft) -> ReadTicket {
        ReadTicket(generation: editGeneration, entered: draft.normalized,
                   hadUnsavedChanges: needsSave(draft) || hasPendingWrites || conflicted)
    }
    func canReplaceEnteredDraft(_ ticket: ReadTicket, current: DayReportDraft) -> Bool {
        !ticket.hadUnsavedChanges && ticket.generation == editGeneration && ticket.entered == current.normalized
    }

    /// Used only for a clean load or an explicit user-confirmed reload. A dirty
    /// editor never silently adopts someone else's base and overwrites its notes.
    func adoptSavedDraft(_ draft: DayReportDraft) {
        requestGeneration &+= 1
        editGeneration &+= 1
        base = draft.normalized
        conflicted = false
    }
    func flagConflict() { conflicted = true }

    func waitForPendingWrites() async { _ = try? await tail?.value }

    func save(_ request: Request,
              using write: @escaping @MainActor (DayReportDraft, DayReportDraft) async throws -> DayReportState) async throws -> DayReportState {
        guard request.generation == requestGeneration else { throw CancellationError() }
        let previous = tail
        pendingWrites += 1
        let operation = Task { @MainActor [self] in
            // A cancelled caller still needs an already-submitted write to finish.
            // Later writes must observe its result even if that caller disappeared.
            _ = try? await previous?.value
            defer { pendingWrites -= 1 }
            guard request.generation == requestGeneration else { throw CancellationError() }
            guard let expected = base else { throw DayReportError.draftConflict }
            do {
                let result = try await write(request.entered, expected)
                base = result.draft.normalized
                committedGeneration &+= 1
                conflicted = false
                return result
            } catch {
                if error as? DayReportError == .draftConflict { conflicted = true }
                throw error
            }
        }
        tail = operation
        do {
            let result = try await operation.value
            guard request.generation == requestGeneration else { throw CancellationError() }
            return result
        } catch {
            // An obsolete callback must not overwrite newer UI state or surface
            // an old failure after the latest request has already succeeded.
            guard request.generation == requestGeneration else { throw CancellationError() }
            throw error
        }
    }
}
