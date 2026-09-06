import XCTest
@testable import Moonlog

/// Which actions ask before they act.
///
/// The failure this guards against is quiet in exactly the way that matters: a
/// confirmation that stops appearing is invisible until the night it was needed,
/// and one that appears where it should not trains the thumb to dismiss dialogs
/// unread. Neither shows up in a screenshot.
@MainActor
final class ConfirmPreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "moonlog.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults

    /// **The bug this exists to prevent.** Reading with `bool(forKey:)` returns
    /// `false` for a key nobody has written, which is indistinguishable from a user
    /// who turned it off — so every action defaulting to *on* would silently ship
    /// defaulting to off. A fresh install must confirm the irreversible ones.
    func testFreshInstallUsesEachActionsOwnDefault() {
        let prefs = ConfirmPreferences(defaults: defaults)
        XCTAssertTrue(prefs.confirms(.endShift))
        XCTAssertTrue(prefs.confirms(.deleteRecord))
        XCTAssertTrue(prefs.confirms(.deleteNoteTag))
        XCTAssertFalse(prefs.confirms(.toggleSleep))
        XCTAssertFalse(prefs.confirms(.moveRecord))
    }

    /// Ending a shift is the only action on the list with no Undo, so it is the one
    /// that must never quietly default to firing on a single tap.
    func testTheIrreversibleActionDefaultsToAsking() {
        XCTAssertTrue(ConfirmableAction.endShift.confirmsByDefault)
        XCTAssertFalse(ConfirmableAction.endShift.question("").isEmpty)
    }

    // MARK: - Round trip

    func testASetSurvivesANewInstance() {
        let first = ConfirmPreferences(defaults: defaults)
        first.setConfirms(true, for: .toggleSleep)
        first.setConfirms(false, for: .endShift)

        let second = ConfirmPreferences(defaults: defaults)
        XCTAssertTrue(second.confirms(.toggleSleep), "an opt-in must persist")
        XCTAssertFalse(second.confirms(.endShift), "an opt-out must persist")
    }

    /// Turning one off must not disturb another. A single encoded set is what makes
    /// this go wrong, which is why there is a key per action.
    func testActionsAreIndependent() {
        let prefs = ConfirmPreferences(defaults: defaults)
        prefs.setConfirms(false, for: .deleteRecord)
        XCTAssertFalse(prefs.confirms(.deleteRecord))
        XCTAssertTrue(prefs.confirms(.endShift))
        XCTAssertTrue(prefs.confirms(.deleteNoteTag))
    }

    /// Storing off as `false` rather than as an absent key: the difference is the
    /// whole reason `object(forKey:)` is used on the way in.
    func testSwitchingOffAndBackOnLandsWhereItStarted() {
        let prefs = ConfirmPreferences(defaults: defaults)
        prefs.setConfirms(false, for: .endShift)
        XCTAssertFalse(ConfirmPreferences(defaults: defaults).confirms(.endShift))
        prefs.setConfirms(true, for: .endShift)
        XCTAssertTrue(ConfirmPreferences(defaults: defaults).confirms(.endShift))
    }

    // MARK: - Keys and copy

    /// The keys are the storage format. Renaming one silently resets that setting
    /// for everyone who had already changed it.
    func testStorageKeysAreStableAndDistinct() {
        XCTAssertEqual(ConfirmableAction.endShift.storageKey, "moonlog.confirm.endShift")
        XCTAssertEqual(
            ConfirmableAction.deleteRecord.storageKey, "moonlog.confirm.deleteRecord")
        let keys = Set(ConfirmableAction.allCases.map(\.storageKey))
        XCTAssertEqual(keys.count, ConfirmableAction.allCases.count)
    }

    /// Every action reaches Settings with something to render, and the dialog it
    /// raises has a verb on its button rather than "OK".
    func testEveryActionCarriesItsCopy() {
        for action in ConfirmableAction.allCases {
            XCTAssertFalse(action.label.isEmpty, "\(action) has no Settings label")
            XCTAssertFalse(action.note.isEmpty, "\(action) has no note")
            XCTAssertFalse(action.verb.isEmpty, "\(action) has no button verb")
            XCTAssertFalse(
                action.question("Mia").isEmpty, "\(action) has no dialog question")
            XCTAssertNotEqual(action.verb, "OK")
        }
    }
}
