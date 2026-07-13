import Foundation
import SwiftData
import XCTest
@testable import marble

@MainActor
final class SprintGoalMigrationTests: XCTestCase {
    func testV3StoreMigratesToV4WithoutChangingExistingTrainingData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marble-sprint-goal-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Marble.store")
        let exerciseID = UUID()
        let entryID = UUID()

        try autoreleasepool {
            let schema = Schema(versionedSchema: MarbleSchemaV3.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let exercise = Exercise(
                id: exerciseID,
                name: "Legacy 150m Sprint",
                category: .run,
                preferredDistanceUnit: .meters,
                metrics: .distanceAndDurationRequired,
                defaultRestSeconds: 180
            )
            context.insert(exercise)
            context.insert(SetEntry(
                id: entryID,
                exercise: exercise,
                performedAt: Date(timeIntervalSince1970: 1_700_000_000),
                distance: 150,
                durationSeconds: 20,
                restAfterSeconds: 180
            ))
            context.insert(SprintPrescription(
                exerciseID: exerciseID,
                distance: 150,
                repetitionCount: 4,
                targetLowerSeconds: 19,
                targetUpperSeconds: 21
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: MarbleSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: MarbleMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.id), [exerciseID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetEntry>()).map(\.id), [entryID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintPrescription>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)
    }
}
