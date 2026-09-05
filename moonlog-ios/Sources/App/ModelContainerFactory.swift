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

    /// Whether this build carries the iCloud container entitlement.
    ///
    /// This gate is **load-bearing, not belt-and-braces.** Asking SwiftData for a
    /// CloudKit-backed store without the entitlement does not throw: the
    /// `ModelContainer` initialiser returns *successfully* and CloudKit then traps
    /// asynchronously on a background queue inside
    /// `PFCloudKitContainerProvider containerWithIdentifier:`. A do/catch around
    /// the initialiser cannot see it, so the app dies a moment after launch with a
    /// SIGTRAP and no catchable error. Verified by crashing in exactly that way.
    ///
    /// It is a compile-time flag rather than a runtime probe because the entitlement
    /// APIs (`SecTaskCopyValueForEntitlement`) are not public on iOS, and the
    /// available proxies — `ubiquityIdentityToken` — key off the iCloud *Documents*
    /// entitlement, so they would report false for a CloudKit-only build and
    /// silently disable sync forever.
    ///
    /// **Flip `MOONLOG_CLOUDKIT` in `project.yml` at the same time as adding the
    /// iCloud capability in Xcode.** Turning on one without the other either
    /// crashes at launch (flag on, capability off) or silently never syncs
    /// (capability on, flag off).
    static var hasCloudKitEntitlement: Bool {
        #if MOONLOG_CLOUDKIT
        return true
        #else
        return false
        #endif
    }

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
            // Still worth catching: iCloud storage being full is reported here.
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
