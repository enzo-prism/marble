import SwiftUI
import SwiftData

@main
struct MarbleApp: App {
    @State private var modelContainer: ModelContainer?
    @State private var storageFailure: PersistenceOpenFailure?

    init() {
        TestHooks.applyGlobalSettings()
        // FIRST, and before the model container exists: `SeedData` writes
        // `didSeedMarbleData` during first-run seeding, so the onboarding gate
        // must snapshot that flag while it still answers "did this app run
        // before?" rather than "has this launch seeded yet?". Reading it later
        // races the seeding below (and the `.task` seeding in `body`, which
        // SwiftUI does not order against `ContentView`'s own `.task`).
        OnboardingGate.captureLaunchState()
        // Must run before anything reads the shared suite. Effectively a no-op
        // now that the suite is `.standard` again (see `SharedDefaults.suite`),
        // but it still stamps the migration flag and is the one hook if these
        // keys ever move stores.
        SharedDefaults.migrateIfNeeded()
        // No-op under UI testing; tips floating over the UI break flows + audits.
        MarbleTips.configure()
        let opened: ModelContainer?
        do {
            #if DEBUG
            if TestHooks.isUITesting, ProcessInfo.processInfo.environment["MARBLE_TEST_STORAGE_FAILURE"] == "1" {
                throw NSError(domain: NSPOSIXErrorDomain, code: 13)
            }
            #endif
            opened = try PersistenceController.openContainer(useInMemory: TestHooks.useInMemoryStore)
        } catch {
            opened = nil
            AppIntentsSupport.storageFailure = PersistenceOpenFailure.classify(error)
            _storageFailure = State(initialValue: PersistenceOpenFailure.classify(error))
        }
        _modelContainer = State(initialValue: opened)
        // Registers the container with `AppDependencyManager` (what the intents
        // inject through `@Dependency`) as well as with `AppIntentsSupport`'s own
        // accessor, which the Spotlight index and entity queries use.
        if let opened { AppIntentsSupport.register(container: opened) }
        if let opened, TestHooks.isUITesting || TestHooks.seedDemoFixtures {
            // UI tests and demo recordings rely on fixtures existing before the first frame.
            Self.seed(container: opened)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                .modelContainer(modelContainer)
                .task {
                    // First-launch seeding stays off the launch critical path.
                    guard !TestHooks.isUITesting, !TestHooks.seedDemoFixtures else { return }
                    Self.seed(container: modelContainer)
                }
            } else {
                PersistenceUnavailableView(failure: storageFailure ?? .unknown, retry: retryStorage)
                    .preferredColorScheme(TestHooks.forcedColorScheme)
            }
        }
    }

    private func retryStorage() {
        do {
            let opened = try PersistenceController.openContainer(useInMemory: TestHooks.useInMemoryStore)
            AppIntentsSupport.register(container: opened)
            if TestHooks.isUITesting || TestHooks.seedDemoFixtures { Self.seed(container: opened) }
            storageFailure = nil
            modelContainer = opened
        } catch {
            storageFailure = PersistenceOpenFailure.classify(error)
            AppIntentsSupport.storageFailure = storageFailure
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
