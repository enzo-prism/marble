import SwiftUI
import SwiftData

@main
struct MarbleApp: App {
    private let modelContainer: ModelContainer

    init() {
        TestHooks.applyGlobalSettings()
        modelContainer = PersistenceController.makeContainer(useInMemory: TestHooks.useInMemoryStore)
        let context = ModelContext(modelContainer)
        SeedData.seedIfNeeded(in: context)
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("Seed data save failed: \(error)")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
