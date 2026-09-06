import SwiftUI

/// How the app decides which theme to wear.
///
/// It used to be a single "Deep Night" toggle, and everything else followed the
/// phone. That meant a doula whose iPhone is in Light appearance — the iOS default,
/// and plenty of people never change it — got the Day theme in a dark nursery:
/// blush at full brightness, over a sleeping newborn. There was no way to say
/// "always dark" except a toggle labelled as something else.
enum AppearancePreference: String, CaseIterable, Identifiable {
    /// Night when the phone is dark, Day when it is light.
    case system
    case night
    case deepNight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Follow phone"
        case .night: return "Night"
        case .deepNight: return "Deep Night"
        }
    }

    /// `nil` for `.system`, which is the one case that must not force a scheme —
    /// forcing it latches the theme on its first value and it never follows again.
    var theme: MoonTheme? {
        switch self {
        case .system: return nil
        case .night: return .night
        case .deepNight: return .deepNight
        }
    }

    /// Reads the stored value, falling back to the retired `moonlog.deepNight`
    /// Bool so someone who had Deep Night on does not silently lose it. Written
    /// only under the new key; the old one is never written again.
    static func stored(raw: String, legacyDeepNight: Bool) -> AppearancePreference {
        if let saved = AppearancePreference(rawValue: raw) { return saved }
        return legacyDeepNight ? .deepNight : .system
    }
}
