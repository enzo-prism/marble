import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(useInMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            SetEntry.self,
            SupplementType.self,
            SupplementEntry.self
        ])

        let configuration: ModelConfiguration
        if useInMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            if TestHooks.resetDatabase {
                try? FileManager.default.removeItem(at: storeURL)
            }
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("Marble", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Marble.store")
    }
}
