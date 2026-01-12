import Combine
import Foundation
import SwiftUI

final class QuickLogCoordinator: ObservableObject {
    @Published var isPresentingAddSet = false
    @Published var prefillDate: Date = Date()

    func open(prefillDate: Date = Date()) {
        self.prefillDate = prefillDate
        isPresentingAddSet = true
    }
}
