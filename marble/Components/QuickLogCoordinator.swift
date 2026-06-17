import Combine
import Foundation
import SwiftUI

final class QuickLogCoordinator: ObservableObject {
    @Published var isPresentingAddSet = false
    @Published var prefillDate: Date = AppEnvironment.now
    @Published var prefillExerciseID: UUID?
    /// Bumped whenever a set is successfully logged. ContentView observes it with
    /// `.sensoryFeedback(.success,)` so the haptic outlives the dismissing sheet.
    @Published var setLoggedFeedbackTrigger = 0

    func open(prefillDate: Date = AppEnvironment.now, prefillExerciseID: UUID? = nil) {
        self.prefillDate = prefillDate
        self.prefillExerciseID = prefillExerciseID
        isPresentingAddSet = true
    }

    func notifySetLogged() {
        setLoggedFeedbackTrigger += 1
    }
}
