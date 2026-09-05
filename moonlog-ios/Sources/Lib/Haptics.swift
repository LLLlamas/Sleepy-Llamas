import UIKit

/// Real haptics, unlike the PWA — `navigator.vibrate` is ignored by iOS Safari, so
/// the web version's feedback silently did nothing on the device it ran on.
///
/// Feedback matters here beyond polish: a write is async and the card cannot update
/// until it round-trips, so a tap with no response invites a second tap. A haptic
/// lands immediately and tells the user the tap registered.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func commit() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
