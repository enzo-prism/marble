import UIKit

/// Centralized haptic confirmations for the core logging loop.
/// Generators fire outside the SwiftUI view lifecycle so feedback still
/// plays when the triggering view dismisses in the same frame.
enum MarbleHaptics {
    static func success() {
        guard !TestHooks.isUITesting else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A richer confirmation for personal-record sets: the success chime
    /// paired with a heavy impact so beating a PR feels distinct from a
    /// routine save.
    static func celebrate() {
        guard !TestHooks.isUITesting else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
    }

    static func warning() {
        guard !TestHooks.isUITesting else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func lightImpact() {
        guard !TestHooks.isUITesting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
