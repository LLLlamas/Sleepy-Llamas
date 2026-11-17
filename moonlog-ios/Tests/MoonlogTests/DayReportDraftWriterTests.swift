import XCTest
import MoonlogCore
@testable import Moonlog

@MainActor
final class DayReportDraftWriterTests: XCTestCase {
    private let original = DayReportDraft(caregiverName: "Cat", summary: "A")

    func testRevertingWhileSubmittedSaveIsPendingRestoresLastEnteredValue() async throws {
        let writer = DayReportDraftWriter(base: original)
        var stored = DayReportState(draft: original)
        var entered = original
        entered.summary = "B"
        var firstStarted: CheckedContinuation<Void, Never>?
        var releaseFirst: CheckedContinuation<Void, Never>?
        var calls: [String] = []
        let firstRequest = writer.request(for: entered)
        let first = Task { @MainActor in
            try await writer.save(firstRequest) { value, expected in
                calls.append(value.summary)
                firstStarted?.resume()
                await withCheckedContinuation { releaseFirst = $0 }
                XCTAssertEqual(expected, stored.draft)
                stored.draft = value
                return stored
            }
        }
        await withCheckedContinuation { continuation in
            firstStarted = continuation
            if !calls.isEmpty { firstStarted?.resume(); firstStarted = nil }
        }
        XCTAssertTrue(writer.hasPendingWrites)
        // Relative to the old UI baseline A this looks clean, but B is submitted.
        XCTAssertFalse(writer.needsSave(original))
        let restoredRequest = writer.request(for: original)
        let restored = Task { @MainActor in
            try await writer.save(restoredRequest) { value, expected in
                calls.append(value.summary)
                XCTAssertEqual(expected.summary, "B", "the queue must use the completed predecessor's base")
                XCTAssertEqual(expected, stored.draft)
                stored.draft = value
                return stored
            }
        }
        // The old caller can be cancelled after actor submission; its write still
        // finishes and must not become the final disk value after the later revert.
        first.cancel()
        releaseFirst?.resume()
        do { _ = try await first.value; XCTFail("superseded callback returned stale state") }
        catch is CancellationError { }
        _ = try await restored.value
        XCTAssertEqual(calls, ["B", "A"])
        XCTAssertEqual(stored.draft, original)
        XCTAssertFalse(writer.hasPendingWrites)
    }

    func testRefreshTicketDoesNotBecomeCleanWhenAutosaveCompletesDuringRead() async throws {
        let writer = DayReportDraftWriter(base: original)
        var changed = original
        changed.summary = "B"
        writer.edited()
        let ticket = writer.readTicket(for: changed)
        XCTAssertFalse(writer.canReplaceEnteredDraft(ticket, current: changed))
        _ = try await writer.save(writer.request(for: changed)) { value, _ in DayReportState(draft: value) }
        XCTAssertFalse(writer.needsSave(changed))
        // An older read captured A. Checking today's dirty flag would now allow
        // replacing B with A; the captured read ticket must keep B instead.
        XCTAssertFalse(writer.canReplaceEnteredDraft(ticket, current: changed))
    }

    func testTypingAfterCleanReadStartsInvalidatesItsReplacementTicket() {
        let writer = DayReportDraftWriter(base: original)
        let ticket = writer.readTicket(for: original)
        XCTAssertTrue(writer.canReplaceEnteredDraft(ticket, current: original))
        writer.edited()
        XCTAssertFalse(writer.canReplaceEnteredDraft(ticket, current: original), "even typing then reverting must invalidate the older read")
    }

    func testLateOldExitRequestCannotOverwriteNewerCommittedValue() async throws {
        let writer = DayReportDraftWriter(base: original)
        let oldExitRequest = writer.request(for: original)
        var newer = original
        newer.summary = "The newer B"
        let newerRequest = writer.request(for: newer)
        _ = try await writer.save(newerRequest) { value, _ in DayReportState(draft: value) }
        var staleWriteRan = false
        do {
            _ = try await writer.save(oldExitRequest) { value, _ in
                staleWriteRan = true
                return DayReportState(draft: value)
            }
            XCTFail("late old exit request was accepted")
        } catch is CancellationError { }
        XCTAssertFalse(staleWriteRan)
        XCTAssertEqual(writer.base, newer)
        // An ordinary user revert is a NEW intent and must remain possible.
        _ = try await writer.save(writer.request(for: original)) { value, expected in
            XCTAssertEqual(expected, newer)
            return DayReportState(draft: value)
        }
        XCTAssertEqual(writer.base, original)
    }

    func testRevertToSavedBaseInvalidatesCapturedRequestWithoutReplacementSave() async throws {
        let writer = DayReportDraftWriter(base: original)
        var changed = original
        changed.summary = "B"
        writer.edited()
        let capturedB = writer.request(for: changed)
        writer.edited() // User reverts to A; no save is needed or pending.
        XCTAssertFalse(writer.needsSave(original))
        XCTAssertFalse(writer.hasPendingWrites)
        var oldWriteRan = false
        do {
            _ = try await writer.save(capturedB) { value, _ in
                oldWriteRan = true
                return DayReportState(draft: value)
            }
            XCTFail("captured B survived a later edit back to saved A")
        } catch is CancellationError { }
        XCTAssertFalse(oldWriteRan)
        XCTAssertEqual(writer.base, original)
    }

    func testExplicitReloadInvalidatesEarlierCapturedRequestsImmediately() async throws {
        let writer = DayReportDraftWriter(base: original)
        let oldRequest = writer.request(for: original)
        var loaded = original
        loaded.summary = "Freshly reloaded notes"
        writer.adoptSavedDraft(loaded)
        var staleWriteRan = false
        do {
            _ = try await writer.save(oldRequest) { value, _ in
                staleWriteRan = true
                return DayReportState(draft: value)
            }
            XCTFail("old request survived explicit reload")
        } catch is CancellationError { }
        XCTAssertFalse(staleWriteRan)
        XCTAssertEqual(writer.base, loaded)
    }

    func testConflictDoesNotRebaseAndSilentlyOverwriteAnotherEditor() async throws {
        let writer = DayReportDraftWriter(base: original)
        var target = original
        target.summary = "My unsaved observations"
        do {
            _ = try await writer.save(writer.request(for: target)) { _, expected in
                XCTAssertEqual(expected, self.original)
                throw DayReportError.draftConflict
            }
            XCTFail("write conflict hidden")
        } catch { XCTAssertEqual(error as? DayReportError, .draftConflict) }
        XCTAssertTrue(writer.conflicted)
        XCTAssertEqual(writer.base, original)
        XCTAssertFalse(writer.hasPendingWrites)
        // Reload is explicit; accepting another editor's base clears the conflict.
        var other = original
        other.eveningNotes = "Their new handoff note"
        writer.adoptSavedDraft(other)
        XCTAssertFalse(writer.conflicted)
        XCTAssertEqual(writer.base, other)
    }
}
