import Foundation

/// Holds workout text that should open the Typed Workout sheet once the
/// Import hub is on screen. Written by the Review Workout Text/File intents
/// and consumed by `ImportView` so the paste never lives in a URL or a
/// background commit.
@MainActor
enum PendingTextImport {
    private(set) static var hasPending = false
    private static var text: String?

    static func stage(_ text: String) {
        self.text = text
        hasPending = true
    }

    /// `nil` when nothing was staged. An empty string still means "open the
    /// editor" (Shortcuts can send a blank parameter).
    static func consume() -> String? {
        guard hasPending else { return nil }
        hasPending = false
        let value = text
        text = nil
        return value ?? ""
    }
}

extension Notification.Name {
    static let marbleOpenTextImport = Notification.Name("marbleOpenTextImport")
}
