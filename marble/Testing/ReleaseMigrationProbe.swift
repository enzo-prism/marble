#if targetEnvironment(simulator)
import Foundation
import SwiftData

/// Release-simulator acceptance only. Nothing is compiled into device builds.
/// A fresh context must actually read the retained user rows before producing proof.
@MainActor
enum ReleaseMigrationProbe {
    static func writeIfRequested(container: ModelContainer) throws {
        guard let token = ProcessInfo.processInfo.environment["MARBLE_MIGRATION_PROBE"],
              UUID(uuidString: token) != nil,
              !container.configurations.isEmpty,
              container.configurations.allSatisfy({ !$0.isStoredInMemoryOnly && $0.url.standardizedFileURL == PersistenceController.storeURL.standardizedFileURL })
        else { return }
        let context = ModelContext(container)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let exerciseName = "Migration exercise " + token
        guard let exercise = exercises.first(where: { $0.name == exerciseName }),
              let session = sessions.first(where: { $0.id == UUID(uuidString: token) }),
              let endedAt = session.endedAt else { return }
        let record: [String: Any] = [
            "token": token,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "store_path": PersistenceController.storeURL.path,
            "exercise_id": exercise.id.uuidString.replacingOccurrences(of: "-", with: ""),
            "exercise_name": exercise.name,
            "session_id": session.id.uuidString.replacingOccurrences(of: "-", with: ""),
            "session_title": session.title,
            "session_notes": session.notes ?? "",
            "session_started_at": session.startedAt.timeIntervalSinceReferenceDate,
            "session_ended_at": endedAt.timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try data.write(to: PersistenceController.storeURL.deletingLastPathComponent()
            .appendingPathComponent("migration-probe.json"), options: .atomic)
    }
}
#endif
