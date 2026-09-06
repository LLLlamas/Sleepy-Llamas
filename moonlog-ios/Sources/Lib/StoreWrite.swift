import Foundation

/// Running a `CareStore` write from a screen whose only job on failure is to say so.
///
/// `RootView` and `SettingsView` had each grown their own copy of these six lines,
/// and adding the handoff note would have made four. The one thing worth keeping
/// identical is the failure path: a care log that silently drops a write is worse
/// than one that stops, so no caller gets to leave the `catch` empty.
///
/// `TonightView` deliberately does **not** use this. It also owns the confirmation
/// banner, the per-baby busy lock and Undo, none of which belong here.
@MainActor
enum StoreWrite {
    static func run(
        _ store: CareStore?,
        onError: @escaping (String) -> Void,
        _ action: @escaping (CareStore) async throws -> Void
    ) {
        guard let store else {
            onError("The data store is unavailable. Nothing was saved.")
            return
        }
        Task {
            do { try await action(store) } catch { onError("\(error)") }
        }
    }
}
