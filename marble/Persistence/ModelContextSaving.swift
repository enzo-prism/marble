import Foundation
import SwiftData

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
            return false
        }
    }
}
