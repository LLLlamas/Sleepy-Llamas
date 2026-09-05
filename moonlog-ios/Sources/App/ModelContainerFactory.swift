import Foundation
import SwiftData
import OSLog

enum ModelContainerFactory {

    static let logger = Logger(subsystem: "com.sleepyllamas.moonlog", category: "data")

    static let cloudKitContainerID = "iCloud.com.sleepyllamas.moonlog"

    static var schema: Schema {
        Schema([
            Family.self,
            Baby.self,
            Shift.self,
            LogEvent.self,
            SleepSession.self,
            TagBinding.self,
        ])
    }

    /// How the store actually opened. Surfaced in Settings so a misconfiguration is
    /// visible rather than silent — the Cookbook's equivalent failure presents as
    /// "no recipes yet" with new records vanishing on relaunch.
    enum Mode: Equatable {
        case syncing
        case localOnly(reason: String)
        case inMemory(reason: String)
    }

    private(set) static var mode: Mode = .localOnly(reason: "not yet opened")

    /// Opens the store, degrading rather than crashing.
    ///
    /// The ladder matters. A launch crash mid-shift is itself a data-loss event, and
    /// `ModelContainer` can fail outright when the user's iCloud storage is full —
    /// so a CloudKit failure must not take the app down. But it must also not fall
    /// straight to in-memory, which loses the night's logs silently. Local on-disk
    /// keeps every record and costs only sync.
    @MainActor
    static func make(syncEnabled: Bool = true) -> ModelContainer {
        let schema = self.schema

        if syncEnabled {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            do {
                let container = try ModelContainer(for: schema, configurations: config)
                mode = .syncing
                return container
            } catch {
                // Expected until the iCloud capability and container exist; also
                // hit when iCloud storage is full.
                logger.error("CloudKit store unavailable, using local only: \(error)")
                mode = .localOnly(reason: "\(error)")
            }
        } else {
            mode = .localOnly(reason: "sync disabled in settings")
        }

        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            // Last resort so the app still launches and the failure is visible in
            // the UI rather than as a crash on a customer's phone at 3am.
            logger.fault("Local store failed to open, falling back to memory: \(error)")
            mode = .inMemory(reason: "\(error)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // Safe to force-try: the schema is fully defaulted, so in-memory
            // always opens.
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }
}
