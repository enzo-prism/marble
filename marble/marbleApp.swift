import SwiftUI
import SwiftData

@main
struct MarbleApp: App {
    private let modelContainer: ModelContainer

    init() {
        TestHooks.applyGlobalSettings()
        modelContainer = PersistenceController.makeContainer(useInMemory: TestHooks.useInMemoryStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
