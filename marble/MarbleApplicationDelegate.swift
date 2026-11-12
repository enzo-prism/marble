import UIKit

@MainActor
final class MarbleApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // A HealthKit recovery launch may stay backgrounded. Reconnect before
        // waiting for a SwiftUI view to appear, without replacing SwiftUI's
        // scene configuration or scene delegate.
        if !TestHooks.isUITesting, !TestHooks.isXCTestProcess {
            Task { await NativeWorkoutController.shared.recover() }
        }
        return true
    }
}
