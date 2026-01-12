import Combine
import Foundation
import SwiftUI

final class QuickLogCoordinator: ObservableObject {
    @Published var isPresentingAddSet = false
    @Published var prefillDate: Date = AppEnvironment.now

    func open(prefillDate: Date = AppEnvironment.now) {
        self.prefillDate = prefillDate
        isPresentingAddSet = true
    }
}
