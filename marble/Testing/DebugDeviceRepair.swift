#if DEBUG
import Foundation
import SwiftData

/// A narrowly guarded model-layer repair for a developer-created empty session.
/// Requires explicit UUID and creation time in the launch environment; normal
/// launches and all Release builds have no repair behavior.
@MainActor
enum DebugDeviceRepair {
    static func applyIfRequested(in context: ModelContext) {
        let environment = ProcessInfo.processInfo.environment
        guard !TestHooks.isUITesting, Bundle.main.bundleIdentifier == "Prism.marble",
              let text = environment["MARBLE_REPAIR_EMPTY_SESSION_ID"], let id = UUID(uuidString: text),
              let timestamp = environment["MARBLE_REPAIR_EMPTY_SESSION_CREATED_AT"] else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: timestamp) else { return }
        guard UserDefaults.standard.string(forKey: NativeWorkoutController.sessionKey) != id.uuidString else {
            print("Empty-session repair refused: live Health tracking owns this session.")
            return
        }
        do {
            let removed = try removeEmptySession(id: id, expectedCreatedAt: date, in: context)
            print(removed ? "Removed the exact empty developer-test session." : "Empty-session repair made no change.")
        } catch { print("Empty-session repair failed; existing data was preserved: \(error)") }
    }

    @discardableResult
    static func removeEmptySession(id: UUID, expectedCreatedAt: Date, in context: ModelContext) throws -> Bool {
        guard let session = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first,
              session.entries.isEmpty,
              abs(session.createdAt.timeIntervalSince(expectedCreatedAt)) < 0.001,
              abs(session.startedAt.timeIntervalSince(expectedCreatedAt)) < 0.001 else { return false }
        context.delete(session)
        do { try context.save(); return true }
        catch { context.rollback(); throw error }
    }
}
#endif
