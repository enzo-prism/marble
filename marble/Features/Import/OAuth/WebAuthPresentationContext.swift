import UIKit
import AuthenticationServices

/// Supplies the window an `ASWebAuthenticationSession` anchors to. Shared by OAuth-based
/// import connectors (Strava today).
@MainActor
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { !$0.windows.isEmpty }
        return scene?.windows.first ?? ASPresentationAnchor()
    }
}
