import Combine
import Foundation
import SwiftUI

final class QuickLogCoordinator: ObservableObject {
    @Published var isPresentingAddSet = false
    @Published var prefillDate: Date = AppEnvironment.now
    @Published var prefillExerciseID: UUID?

    func open(prefillDate: Date = AppEnvironment.now, prefillExerciseID: UUID? = nil) {
        self.prefillDate = prefillDate
        self.prefillExerciseID = prefillExerciseID
        isPresentingAddSet = true
    }
}
