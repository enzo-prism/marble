import Foundation
import SwiftData

@Observable
final class PersistenceIssueCenter {
    static let shared = PersistenceIssueCenter()

    var message: String?

    func report(_ error: Error) {
        message = "Marble couldn't save your latest change. Nothing partial was kept. \(error.localizedDescription)"
    }
}

extension ModelContext {
    /// Saves pending changes, rolling back to the last saved state on failure so
    /// the context never carries half-applied mutations.
    @discardableResult
    func saveOrRollback() -> Bool {
        do {
            try save()
            return true
        } catch {
            #if DEBUG
            print("ModelContext save failed, rolling back: \(error)")
            #endif
            rollback()
            PersistenceIssueCenter.shared.report(error)
            return false
        }
    }
}
