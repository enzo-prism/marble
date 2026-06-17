import SwiftUI
import SwiftData

@main
struct MarbleApp: App {
    private let modelContainer: ModelContainer

    init() {
        TestHooks.applyGlobalSettings()
        modelContainer = PersistenceController.makeContainer(useInMemory: TestHooks.useInMemoryStore)
        if TestHooks.useInMemoryStore {
            // UI tests and showcase capture read the UI immediately, so their fixtures
            // must be in place before the first frame.
            Self.seed(in: modelContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .task {
                    // Production seeding is deferred past first render to keep it off the
                    // launch-critical path; @Query views refresh when the save lands.
                    if !TestHooks.useInMemoryStore {
                        Self.seed(in: modelContainer)
                    }
                }
        }
    }

    private static func seed(in container: ModelContainer) {
        let context = ModelContext(container)
        SeedData.seedIfNeeded(in: context)
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("Seed data save failed: \(error)")
            #endif
        }
    }
}
