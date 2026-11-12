import Foundation

/// A saved Health workout and its effort attachment are separate durable commits.
/// Never replay the first commit when only the second failed or the phone locked.
@MainActor
final class HealthExportTransaction {
    nonisolated struct Checkpoint: Codable, Equatable {
        var workoutSaved = false
        var complete = false
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func checkpoint(for identifier: String) -> Checkpoint {
        guard let data = defaults.data(forKey: key(identifier)),
              let value = try? JSONDecoder().decode(Checkpoint.self, from: data) else { return Checkpoint() }
        return value
    }

    func run<Workout>(identifier: String,
        lookup: @MainActor () async throws -> Workout?,
        create: @MainActor () async throws -> Workout?,
        attachEffort: @MainActor (Workout) async throws -> Void
    ) async -> Bool {
        var state = checkpoint(for: identifier)
        if state.complete { return true }
        do {
            var workout = try await lookup()
            if workout != nil {
                state.workoutSaved = true
                persist(state, for: identifier)
            } else if !state.workoutSaved {
                workout = try await create()
                // HealthKit may save successfully but return nil while locked.
                state.workoutSaved = true
                persist(state, for: identifier)
            }
            guard let workout else { return false }
            try await attachEffort(workout)
            state.complete = true
            persist(state, for: identifier)
            return true
        } catch {
            // The saved-workout checkpoint deliberately survives attachment errors.
            return false
        }
    }

    private func key(_ identifier: String) -> String { "marble.health.export.\(identifier)" }
    private func persist(_ value: Checkpoint, for identifier: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key(identifier))
    }
}
