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

    /// `-moonlogTab summary|settings` — selects that tab on launch, so each screen
    /// can be rendered and screenshotted without driving the UI.
    static var requestedTab: String? {
        UserDefaults.standard.string(forKey: "moonlogTab")
    }

    /// `-moonlogOpenSheet feed|diaper|note` — opens that sheet on appear.
    ///
    /// No `sleep`: the tile toggles now, so there is no new-sleep sheet to open.
    /// Correcting one is `-moonlogEditFirst` on a sleep row.
    static func requestedSheet(for babyID: UUID?) -> LogSheet? {
        guard let babyID,
              let name = UserDefaults.standard.string(forKey: "moonlogOpenSheet")
        else { return nil }
        switch name {
        case "feed": return .feed(babyID: babyID)
        case "diaper": return .diaper(babyID: babyID)
        case "note": return .note(babyID: babyID)
        case "pump": return .extra(kind: .pump, babyID: nil)
        case "medication": return .extra(kind: .medication, babyID: babyID)
        case "weight": return .extra(kind: .measurement, babyID: babyID)
        default: return nil
        }
    }

    /// `-moonlogEditFirst YES` — opens the edit sheet for the newest record, which
    /// is the only way to see the delete row and the wrong-twin control rendered.
    static var editsFirstRecord: Bool {
        UserDefaults.standard.bool(forKey: "moonlogEditFirst")
    }

    /// `-moonlogShiftHours end|correct` — presents the shift-hours sheet, the one
    /// surface a launch argument is the only way to reach without tapping a menu.
    static var requestedShiftHours: ShiftHoursSheet.Purpose? {
        switch UserDefaults.standard.string(forKey: "moonlogShiftHours") {
        case "end": return .end
        case "correct": return .correct
        default: return nil
        }
    }

    /// `-moonlogDumpHandoff YES` — writes the keepsake page into the app's Documents
    /// directory on appear, so the real rendered output can be pulled off the
    /// simulator and looked at in a browser. Composing it in a test would only prove
    /// the string; this proves what the parents actually open.
    static var wantsHandoffDump: Bool {
        UserDefaults.standard.bool(forKey: "moonlogDumpHandoff")
    }

    /// `-moonlogSettingsSheet family|baby` — presents one of the surfaces
    /// that moved off Tonight and Summary into Settings. Without this they are
    /// only reachable by tapping, which is what `-moonlogShiftHours` exists to fix.
    static var requestedSettingsSheet: String? {
        UserDefaults.standard.string(forKey: "moonlogSettingsSheet")
    }

    /// `-moonlogDemoWrite YES` — performs one real write through the app's own path
    /// on appear, so the confirmation banner and its Undo can be screenshotted.
    /// Deliberately the real `write`, not a faked banner: the thing worth seeing is
    /// that the path produces one.
    static var wantsDemoWrite: Bool {
        UserDefaults.standard.bool(forKey: "moonlogDemoWrite")
    }

    /// `-moonlogResetStore YES` — empties the store before seeding.
    ///
    /// The UI test target needs it: the seed deliberately fires only into an empty
    /// store, so without a reset the second test in a run inherits whatever the
    /// first one logged, and a suite whose tests are order-dependent is worse than
    /// no suite. Also gated on `isRequested`, so it can only ever run in a seeded
    /// launch and can never be the thing that empties a real night.
    static var wantsStoreReset: Bool {
        UserDefaults.standard.bool(forKey: "moonlogResetStore")
    }

    /// `-moonlogStillGlyphs YES` — freezes the tile's sun and moon on their resting
    /// frame.
    ///
    /// Not a preference and not about looks: **a `repeatForever` animation means the
    /// app never reports itself idle**, and XCUITest waits for idle before it can
    /// take the hierarchy snapshot a compound query needs. With the glyphs moving,
    /// `testTurningOnAskBeforeMakesTheTileConfirm` — which asks
    /// `app.buttons.containing(.staticText, identifier: "Mia is asleep")` — went
    /// from about ten seconds to **eighteen minutes**, and took the whole suite from
    /// four minutes to twenty-two. A suite that slow is a suite nobody runs, which
    /// is the same as not having one.
    ///
    /// So the motion is not exercised by the reachability suite. That is the
    /// deliberate trade: the glyph is decorative, the controls under it are not, and
    /// no query in the suite is about whether a ray moved.
    static var wantsStillGlyphs: Bool {
        UserDefaults.standard.bool(forKey: "moonlogStillGlyphs")
    }

    /// The other half of the reset, and it has to run before anything reads a
    /// preference — so it is called from `MoonlogApp.init`, not from
    /// `seedIfNeeded`, whose position in static-initialisation order is not
    /// something to depend on.
    ///
    /// Without this the suite is order-dependent in the worst way: a test that
    /// turns on "Ask before" leaves it on, and a later test that taps a tile gets a
    /// dialog it never asked for and fails somewhere unrelated. Every `moonlog.`
    /// key goes, which is what a fresh install actually looks like.
    static func resetPreferencesIfRequested() {
        guard isRequested, wantsStoreReset else { return }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("moonlog.") {
            defaults.removeObject(forKey: key)
        }
    }

    @MainActor
    static func seedIfNeeded(_ container: ModelContainer) {
        guard isRequested else { return }
        let context = ModelContext(container)
        if wantsStoreReset {
            // `Family` cascades to babies, shifts, and through those to every
            // record; note tags hang off the family too. Deleting the roots is
            // enough, and asking for the whole graph would be a second place for
            // the delete rules to be described.
            for family in (try? context.fetch(FetchDescriptor<Family>())) ?? [] {
                context.delete(family)
            }
            try? context.save()
        }
        guard (try? context.fetch(FetchDescriptor<Family>()))?.isEmpty ?? false else { return }

        let now = Date()
        let calendar = Calendar.current
        // A shift that started at 10pm and is still running.
        let shiftStart = calendar.date(byAdding: .hour, value: -5, to: now) ?? now
        let birth = calendar.date(byAdding: .day, value: -5, to: now) ?? now

        let family = Family(name: "Nguyen")
        family.volumeUnitRaw = VolumeUnit.oz.rawValue
        // All three on, so the opt-in kinds are reachable in a screenshot run.
        // They are off by default in a real family.
        family.setOptionalKinds(EventKind.optional)
        for (i, label) in ["Spit-up", "Fussy", "Jaundice", "Swaddled", "Skin-to-skin"].enumerated() {
            let tag = NoteTagPreset(label: label, sortOrder: i)
            tag.family = family
            context.insert(tag)
        }
        let mia = Baby(name: "Mia", birthAt: birth, sortOrder: 0, accent: .gold)
        let leo = Baby(name: "Leo", birthAt: birth, sortOrder: 1, accent: .sage)
        mia.family = family
        leo.family = family

        let shift = Shift(startedAt: shiftStart, caregiver: "Cat")
        // So the keepsake page's note section is reachable in a screenshot run.
        shift.parentNote = """
            A settled night overall. Mia took a while to go down after the 9pm feed \
            but slept solidly once she did — I kept her swaddled and she seemed \
            comfortable.

            Leo fed well both times and is taking the bottle more easily than \
            earlier in the week. Nappies all looked normal.

            Everything's in the log below if you want the detail. Sleep well.
            """
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

        // Two closed shifts from previous nights, so History has something in it.
        for nightsAgo in 1...2 {
            guard let start = calendar.date(byAdding: .day, value: -nightsAgo, to: shiftStart),
                  let end = calendar.date(byAdding: .hour, value: 8, to: start)
            else { continue }
            let past = Shift(startedAt: start, endedAt: end, caregiver: "Cat")
            past.attach(to: family)
            context.insert(past)

            for (offset, baby) in [(90, mia), (150, leo), (300, mia)] {
                let feed = LogEvent(
                    kind: .feed, at: start.addingTimeInterval(Double(offset) * 60))
                feed.feedMethodRaw = FeedMethod.bottleFormula.rawValue
                feed.amountMl = 60
                feed.attach(to: past, baby: baby)
                context.insert(feed)
            }
            let sleep = SleepSession(
                startAt: start.addingTimeInterval(3600),
                endAt: start.addingTimeInterval(3600 * 4))
            sleep.attach(to: past, baby: mia)
            context.insert(sleep)
        }

        // Mia asleep now; Leo woke a little while ago. The state twins actually
        // spend most of the night in, and the reason the layout shows both.
        let miaAsleep = SleepSession(startAt: minutesAgo(83))
        miaAsleep.attach(to: shift, baby: mia)
        context.insert(miaAsleep)

        let leoEarlier = SleepSession(startAt: minutesAgo(195), endAt: minutesAgo(58))
        leoEarlier.attach(to: shift, baby: leo)
        context.insert(leoEarlier)

        // A second household, so the client-family picker in Settings has more
        // than one row to render. It carries no shift: between visits is the
        // normal state for a family you are not with tonight, and it is what the
        // picker will most often be switching *to*.
        let other = Family(name: "Okafor")
        other.volumeUnitRaw = VolumeUnit.ml.rawValue
        let ada = Baby(
            name: "Ada",
            birthAt: calendar.date(byAdding: .day, value: -19, to: now) ?? now,
            sortOrder: 0,
            accent: .lilac)
        ada.family = other
        context.insert(other)
        context.insert(ada)

        try? context.save()
    }
}
#endif
