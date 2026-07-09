import Foundation
import SwiftUI

struct QuickLogContext: Equatable {
    var title: String
    var source: String
}

@Observable
final class QuickLogCoordinator {
    var isPresentingAddSet = false
    var prefillDate: Date = AppEnvironment.now
    var prefillExerciseID: UUID?
    var workoutSessionID: UUID?
    var context: QuickLogContext?

    func open(
        prefillDate: Date = AppEnvironment.now,
        prefillExerciseID: UUID? = nil,
        workoutSessionID: UUID? = nil,
        context: QuickLogContext? = nil
    ) {
        self.prefillDate = prefillDate
        self.prefillExerciseID = prefillExerciseID
        self.workoutSessionID = workoutSessionID
        self.context = context
        isPresentingAddSet = true
    }

    func clearPresentationContext() {
        prefillExerciseID = nil
        workoutSessionID = nil
        context = nil
    }
}
