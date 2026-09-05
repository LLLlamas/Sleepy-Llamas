import CoreGraphics

/// Layout constants that more than one screen depends on.
///
/// `tabBarClearance` in particular is a single physical constraint — the iOS 26 tab
/// bar floats over scroll content — and it had already drifted to two values across
/// three files, so the settings Form clipped its last row while the others did not.
enum MoonLayout {
    static let tabBarClearance: CGFloat = 88
    static let cardCorner: CGFloat = 18
    static let controlCorner: CGFloat = 14
    /// Minimum tap target: one hand, in the dark. Carried over from the PWA's `--tap`.
    static let tapTarget: CGFloat = 56
}
