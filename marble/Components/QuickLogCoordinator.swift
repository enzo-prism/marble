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
    var context: QuickLogContext?

    func open(
        prefillDate: Date = AppEnvironment.now,
        prefillExerciseID: UUID? = nil,
        context: QuickLogContext? = nil
    ) {
        self.prefillDate = prefillDate
        self.prefillExerciseID = prefillExerciseID
        self.context = context
        isPresentingAddSet = true
    }

    func clearPresentationContext() {
        prefillExerciseID = nil
        context = nil
    }
}
