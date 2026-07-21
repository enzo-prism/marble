import SwiftUI
import SwiftData

@main
struct MarbleApp: App {
    private let modelContainer: ModelContainer

    init() {
        TestHooks.applyGlobalSettings()
        // Must run before anything reads the shared suite. Effectively a no-op
        // now that the suite is `.standard` again (see `SharedDefaults.suite`),
        // but it still stamps the migration flag and is the one hook if these
        // keys ever move stores.
        SharedDefaults.migrateIfNeeded()
        // No-op under UI testing; tips floating over the UI break flows + audits.
        MarbleTips.configure()
        modelContainer = PersistenceController.makeContainer(useInMemory: TestHooks.useInMemoryStore)
        AppIntentsSupport.container = modelContainer
        if TestHooks.isUITesting {
            // UI tests rely on fixtures existing before the first frame.
            Self.seed(container: modelContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .task {
                    // First-launch seeding stays off the launch critical path.
                    guard !TestHooks.isUITesting else { return }
                    Self.seed(container: modelContainer)
                }
        }
    }

    private static func seed(container: ModelContainer) {
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
