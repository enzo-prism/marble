import Combine
import Foundation
import SwiftUI

struct QuickLogContext: Equatable {
    var title: String
    var source: String
}

final class QuickLogCoordinator: ObservableObject {
    @Published var isPresentingAddSet = false
    @Published var prefillDate: Date = AppEnvironment.now
    @Published var prefillExerciseID: UUID?
    @Published var context: QuickLogContext?

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
