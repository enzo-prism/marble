#if DEBUG
import AppIntents
import SwiftData

/// Known app-side data for out-of-process tests, following Apple's test-only
/// intent pattern. Never included in Release or discoverable in system UI.
struct PrepareWorkoutIntentTests: AppIntent {
    static let title: LocalizedStringResource = "Prepare Workout Intent Tests"
    static let isDiscoverable = false
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard Bundle.main.object(forInfoDictionaryKey: "MarbleBundleSuffix") as? String == ".validation" else {
            throw WorkoutIntentFailure(message: "Only available in the isolated validation app.")
        }
        UserDefaults.standard.set(true, forKey: "marble.validation.persistentIntentStore")
        let container = try PersistenceController.openContainer(useInMemory: false)
        AppIntentsSupport.register(container: container)
        let context = container.mainContext
        // This dedicated store contains integration fixtures only. Do not reset
        // either the validation journal or the public app's store.
        for entry in try context.fetch(FetchDescriptor<SetEntry>()) { context.delete(entry) }
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) { context.delete(session) }
        try context.save()
        SeedData.seedExercises(in: context)
        try context.save()
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        guard let bench = exercises.first(where: { $0.name == "Bench Press" }),
              let sprint = exercises.first(where: { $0.name == "Sprint" }) else {
            throw WorkoutIntentFailure(message: "Missing intent test exercises.")
        }
        let values = ["bench": bench.id.uuidString, "sprint": sprint.id.uuidString]
        let data = try JSONEncoder().encode(values)
        return .result(value: String(decoding: data, as: UTF8.self))
    }
}
#endif
