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
            NoteTagPreset.self,
            TagBinding.self,
        ])
    }

    /// Surfaced in Settings, so a misconfiguration is visible rather than silent.
    enum Mode: Equatable {
        case syncing
        case localOnly(reason: String)
        case inMemory(reason: String)
    }

    private(set) static var mode: Mode = .localOnly(reason: "not yet opened")

    /// **Load-bearing.** Requesting a CloudKit store without the entitlement does
    /// not throw — `ModelContainer` init succeeds and CloudKit then traps on a
    /// background queue, killing the app with no catchable error.
    ///
    /// A compile flag, not a runtime probe: the entitlement APIs are not public on
    /// iOS. Flip `MOONLOG_CLOUDKIT` in `project.yml` at the same time as adding the
    /// capability in Xcode, never one without the other. See `docs/cloudkit.md`.
    static var hasCloudKitEntitlement: Bool {
        #if MOONLOG_CLOUDKIT
        return true
        #else
        return false
        #endif
    }

    /// Degrades rather than crashes, and degrades to **local on-disk** rather than
    /// in-memory — a CloudKit problem should cost sync, never the night's logs.
    @MainActor
    static func make(syncEnabled: Bool = true) -> ModelContainer {
        let schema = self.schema

        guard syncEnabled, hasCloudKitEntitlement else {
            let why = syncEnabled
                ? "no iCloud entitlement in this build"
                : "sync disabled in settings"
            logger.notice("Opening local store: \(why)")
            mode = .localOnly(reason: why)
            return openLocal(schema: schema)
        }

        do {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            let container = try ModelContainer(for: schema, configurations: config)
            mode = .syncing
            return container
        } catch {
            // iCloud storage being full is reported here.
            logger.error("CloudKit store unavailable, using local only: \(error)")
            mode = .localOnly(reason: "\(error)")
            return openLocal(schema: schema)
        }
    }

    @MainActor
    private static func openLocal(schema: Schema) -> ModelContainer {
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            // Last resort: launching with visible breakage beats crashing at 3am.
            logger.fault("Local store failed to open, falling back to memory: \(error)")
            mode = .inMemory(reason: "\(error)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // Force-try is safe: the schema is fully defaulted, so in-memory opens.
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }
}
