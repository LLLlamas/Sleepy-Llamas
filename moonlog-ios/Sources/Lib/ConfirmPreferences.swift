import Foundation
import Observation

/// The actions a second tap can be demanded before.
///
/// Deliberately not every button in the app. A confirmation is only worth its
/// interruption where the action is either **hard to take back** or **easy to fire
/// by mistake**, and at 3am in a dark room an unnecessary one is not neutral — it
/// trains the thumb to dismiss dialogs without reading them, which is exactly how
/// the one that mattered gets tapped through.
///
/// Opening a log sheet is not here. A sheet is a form, not a question, and a form
/// you can cancel already is its own confirmation.
enum ConfirmableAction: String, CaseIterable, Identifiable, Sendable {
    /// The only one on this list that cannot be undone.
    case endShift
    case deleteRecord
    case toggleSleep
    case moveRecord
    case deleteNoteTag

    var id: String { rawValue }

    /// One `UserDefaults` key per action rather than one encoded set, so a case
    /// added later falls back to its own default instead of being read as "off" by
    /// every install that stored the set before it existed.
    var storageKey: String { "moonlog.confirm.\(rawValue)" }

    /// **Undo is what sets these defaults.** Every action here except ending a shift
    /// returns a reversing write and puts an Undo button on the banner for six
    /// seconds, and an Undo you already have beats a dialog you have to read. So the
    /// two that default on are the irreversible one and the destructive one; the
    /// rest start out of the way and can be switched on by anyone who wants them.
    var confirmsByDefault: Bool {
        switch self {
        case .endShift, .deleteRecord, .deleteNoteTag: return true
        case .toggleSleep, .moveRecord: return false
        }
    }

    /// The Settings row.
    var label: String {
        switch self {
        case .endShift: return "Ending the shift"
        case .deleteRecord: return "Deleting a record"
        case .toggleSleep: return "Wake and sleep"
        case .moveRecord: return "Moving a record to the other baby"
        case .deleteNoteTag: return "Deleting a note tag"
        }
    }

    /// The Settings row's second line — why you might want this one on or off.
    var note: String {
        switch self {
        case .endShift: return "Cannot be undone."
        case .deleteRecord: return "Undoable for six seconds."
        case .toggleSleep: return "The most-pressed button in the app."
        case .moveRecord: return "Undoable for six seconds."
        case .deleteNoteTag: return "Cannot be undone."
        }
    }

    /// The question itself. Titles a dialog, so it names the consequence rather than
    /// asking "Are you sure?", which tells nobody anything.
    func question(_ subject: String) -> String {
        switch self {
        case .endShift: return "End the shift?"
        case .deleteRecord: return "Delete this \(subject)?"
        case .toggleSleep: return subject
        case .moveRecord: return "Move this record to \(subject)?"
        case .deleteNoteTag: return "Delete the \(subject) tag?"
        }
    }

    /// The confirming button's own label. A dialog whose buttons read "OK / Cancel"
    /// makes you re-read the title to know which one you want.
    var verb: String {
        switch self {
        case .endShift: return "End shift"
        case .deleteRecord, .deleteNoteTag: return "Delete"
        case .toggleSleep: return "Change"
        case .moveRecord: return "Move"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .deleteRecord, .deleteNoteTag, .endShift: return true
        case .toggleSleep, .moveRecord: return false
        }
    }
}

/// Which actions ask first. Read by the screens that perform them, written by
/// Settings.
///
/// An object rather than a scatter of `@AppStorage` declarations because five
/// actions across four screens is twenty key strings, and a typo in one of them
/// creates a second setting that silently never matches the toggle. It holds the
/// values in memory so `@Observable` can see a change; `UserDefaults` is the
/// durable copy, written through on every set.
@MainActor
@Observable
final class ConfirmPreferences {
    private var values: [ConfirmableAction: Bool]
    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults` is injectable so tests get a scratch suite rather than dirtying
    /// the one the simulator persists between runs.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [ConfirmableAction: Bool] = [:]
        for action in ConfirmableAction.allCases {
            // `object(forKey:)`, not `bool(forKey:)` — the latter returns `false` for
            // an absent key, which is indistinguishable from a user who turned it
            // off, and would quietly drop every default that is `true`.
            loaded[action] = defaults.object(forKey: action.storageKey) as? Bool
                ?? action.confirmsByDefault
        }
        self.values = loaded
    }

    func confirms(_ action: ConfirmableAction) -> Bool {
        values[action] ?? action.confirmsByDefault
    }

    func setConfirms(_ confirms: Bool, for action: ConfirmableAction) {
        values[action] = confirms
        defaults.set(confirms, forKey: action.storageKey)
    }
}
