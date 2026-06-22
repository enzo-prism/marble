import UIKit
import AuthenticationServices

/// Supplies the window an `ASWebAuthenticationSession` anchors to. Shared by OAuth-based
/// import connectors (Strava today).
@MainActor
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let keyWindow = scene?.windows.first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let window = scene?.windows.first {
            return window
        }
        guard let scene else {
            preconditionFailure("ASWebAuthenticationSession requires an active window scene.")
        }
        return ASPresentationAnchor(windowScene: scene)
    }
}
