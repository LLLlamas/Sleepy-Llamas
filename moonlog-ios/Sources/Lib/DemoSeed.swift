#if DEBUG
import Foundation
import SwiftData
import MoonlogCore

/// Seeds a realistic twin night so the UI can be exercised and screenshotted
/// before onboarding exists.
///
/// Gated behind a launch argument rather than "seed when empty", so it can never
/// fire during real use: an empty store is a legitimate first-run state.
///   xcrun simctl launch <device> com.sleepyllamas.moonlog -moonlogSeedDemo YES
enum DemoSeed {

    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "moonlogSeedDemo")
    }

    @MainActor
    static func seedIfNeeded(_ container: ModelContainer) {
        guard isRequested else { return }
        let context = ModelContext(container)
        guard (try? context.fetch(FetchDescriptor<Family>()))?.isEmpty ?? false else { return }

        let now = Date()
        let calendar = Calendar.current
        // A shift that started at 10pm and is still running.
        let shiftStart = calendar.date(byAdding: .hour, value: -5, to: now) ?? now
        let birth = calendar.date(byAdding: .day, value: -5, to: now) ?? now

        let family = Family(name: "Nguyen")
        family.volumeUnitRaw = VolumeUnit.oz.rawValue
        let mia = Baby(name: "Mia", birthAt: birth, sortOrder: 0, accent: .gold)
        let leo = Baby(name: "Leo", birthAt: birth, sortOrder: 1, accent: .sage)
        mia.family = family
        leo.family = family

        let shift = Shift(startedAt: shiftStart, caregiver: "Cat")
        shift.attach(to: family)

        context.insert(family)
        context.insert(mia)
        context.insert(leo)
        context.insert(shift)

        func minutesAgo(_ m: Int) -> Date {
            calendar.date(byAdding: .minute, value: -m, to: now) ?? now
        }

        func log(
            _ kind: EventKind, _ baby: Baby, _ minutes: Int,
            configure: (LogEvent) -> Void = { _ in }
        ) {
            let event = LogEvent(kind: kind, at: minutesAgo(minutes))
            configure(event)
            event.attach(to: shift, baby: baby)
            context.insert(event)
        }

        log(.feed, mia, 245) { $0.feedMethodRaw = FeedMethod.breast.rawValue
                               $0.leftSeconds = 480; $0.rightSeconds = 360 }
        log(.diaper, mia, 238) { $0.diaperContentsRaw = DiaperContents.both.rawValue
                                 $0.stoolColorRaw = StoolColor.transitional.rawValue }
        log(.feed, leo, 230) { $0.feedMethodRaw = FeedMethod.bottleFormula.rawValue
                               $0.amountMl = 60
                               $0.feedDurationSeconds = 600 }
        log(.diaper, leo, 205) { $0.diaperContentsRaw = DiaperContents.wet.rawValue }
        log(.note, mia, 150) { $0.text = "Spit-up after the feed, settled with swaddle" }
        log(.feed, mia, 95) { $0.feedMethodRaw = FeedMethod.breast.rawValue
                              $0.rightSeconds = 900 }
        log(.feed, leo, 42) { $0.feedMethodRaw = FeedMethod.bottleBreastmilk.rawValue
                              $0.amountMl = 75
                              $0.feedDurationSeconds = 720 }
        log(.diaper, leo, 35) { $0.diaperContentsRaw = DiaperContents.dirty.rawValue
                                $0.stoolColorRaw = StoolColor.yellow.rawValue }

        // Mia asleep now; Leo woke a little while ago. The state twins actually
        // spend most of the night in, and the reason the layout shows both.
        let miaAsleep = SleepSession(startAt: minutesAgo(83))
        miaAsleep.attach(to: shift, baby: mia)
        context.insert(miaAsleep)

        let leoEarlier = SleepSession(startAt: minutesAgo(195), endAt: minutesAgo(58))
        leoEarlier.attach(to: shift, baby: leo)
        context.insert(leoEarlier)

        try? context.save()
    }
}
#endif
