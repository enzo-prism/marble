import Foundation
import SwiftData
import XCTest
@testable import marble

/// Guards the V6 "sprint plans" schema bump: `SprintVariant` (multiple
/// tenths-precision plans per exercise) and `SprintRepDetail` (exact time +
/// frozen target per rep). Same invariants `SchemaV5MigrationTests` pins,
/// because V6 is the same change class: purely additive standalone models,
/// raw-UUID references, no stage.
@MainActor
final class SchemaV6MigrationTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marble-schema-v6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("Marble.store")
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Migration plan shape

    func testMigrationPlanHasNoStages() {
        XCTAssertTrue(
            MarbleMigrationPlan.stages.isEmpty,
            "V6 is additive; adding a MigrationStage resurrects the build-35 launch crash"
        )
    }

    func testMigrationPlanDeclaresV6AsTheLatestSchema() {
        let identifiers = MarbleMigrationPlan.schemas.map { $0.versionIdentifier }

        XCTAssertEqual(identifiers.count, 6)
        XCTAssertEqual(identifiers.last, Schema.Version(6, 0, 0))
        XCTAssertEqual(MarbleSchemaV6.versionIdentifier, Schema.Version(6, 0, 0))
    }

    func testSchemaVersionsAreDistinctAndAscending() {
        let identifiers = MarbleMigrationPlan.schemas.map { $0.versionIdentifier }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "Version identifiers must be unique")
        XCTAssertEqual(identifiers, identifiers.sorted(), "Versions must be listed oldest to newest")
    }

    /// V6 is V5 plus exactly the two sprint models. If this fails, something
    /// was removed or retyped and the change is no longer additive.
    func testV6IsV5PlusSprintVariantAndRepDetailOnly() {
        let v5 = MarbleSchemaV5.models.map { String(describing: $0) }
        let v6 = MarbleSchemaV6.models.map { String(describing: $0) }

        XCTAssertEqual(v6.count, v5.count + 2)
        XCTAssertTrue(Set(v5).isSubset(of: Set(v6)), "V6 must not drop or rename any V5 entity")
        XCTAssertEqual(
            Set(v6).subtracting(Set(v5)),
            [String(describing: SprintVariant.self), String(describing: SprintRepDetail.self)]
        )
    }

    // MARK: - Round trip

    func testV6ContainerRoundTripsVariantsAndDetails() throws {
        let exerciseID = UUID()
        let variantID = UUID()
        let entryID = UUID()
        let detailID = UUID()

        try autoreleasepool {
            let container = try makeContainer(versionedSchema: MarbleSchemaV6.self)
            let context = ModelContext(container)
            context.insert(SprintVariant(
                id: variantID,
                exerciseID: exerciseID,
                title: "Speed",
                distance: 60,
                distanceUnit: .meters,
                repetitionCount: 4,
                targetLowerTenths: 85,
                targetUpperTenths: 85,
                lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
            context.insert(SprintRepDetail(
                id: detailID,
                setEntryID: entryID,
                durationTenths: 84,
                targetLowerTenths: 85,
                targetUpperTenths: 85,
                variantID: variantID
            ))
            try context.save()
        }

        let reopened = try makeContainer(versionedSchema: MarbleSchemaV6.self)
        let context = ModelContext(reopened)

        let variant = try XCTUnwrap(try context.fetch(FetchDescriptor<SprintVariant>()).first)
        XCTAssertEqual(variant.id, variantID)
        XCTAssertEqual(variant.title, "Speed")
        XCTAssertEqual(variant.targetLowerTenths, 85)
        XCTAssertEqual(variant.distanceUnit, .meters)

        let detail = try XCTUnwrap(try context.fetch(FetchDescriptor<SprintRepDetail>()).first)
        XCTAssertEqual(detail.id, detailID)
        XCTAssertEqual(detail.setEntryID, entryID)
        XCTAssertEqual(detail.durationTenths, 84)
        XCTAssertEqual(detail.variantID, variantID)
    }

    /// Multiple plans per exercise is the entire point of the new model — the
    /// case the legacy prescription's unique `exerciseID` forbids.
    func testTwoVariantsCanShareOneExercise() throws {
        let exerciseID = UUID()
        let container = try makeContainer(versionedSchema: MarbleSchemaV6.self)
        let context = ModelContext(container)
        context.insert(SprintVariant(
            exerciseID: exerciseID,
            title: "Speed",
            distance: 60,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 85,
            targetUpperTenths: 85
        ))
        context.insert(SprintVariant(
            exerciseID: exerciseID,
            title: "Tempo",
            distance: 150,
            distanceUnit: .meters,
            repetitionCount: 6,
            targetLowerTenths: 200,
            targetUpperTenths: 230
        ))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintVariant>()), 2)
    }

    /// The upgrade path a shipped 2.2 user takes: a populated V5 store opens
    /// as V6 with every row intact, and the new entities are usable at once.
    func testPopulatedV5StoreMigratesToV6WithTrainingDataIntact() throws {
        let exerciseID = UUID()
        let entryID = UUID()
        let prescriptionID = UUID()
        let snapshotID = UUID()
        let bodyMetricID = UUID()

        try autoreleasepool {
            let container = try makeContainer(versionedSchema: MarbleSchemaV5.self, migrating: false)
            let context = ModelContext(container)
            let exercise = Exercise(
                id: exerciseID,
                name: "Sprint",
                category: .run,
                metrics: ExerciseMetricsProfile(weight: .none, reps: .none, distance: .required, durationSeconds: .required),
                defaultRestSeconds: 90
            )
            context.insert(exercise)
            context.insert(SetEntry(
                id: entryID,
                exercise: exercise,
                performedAt: Date(timeIntervalSince1970: 1_699_000_000),
                distance: 150,
                distanceUnit: .meters,
                durationSeconds: 20,
                restAfterSeconds: 90
            ))
            context.insert(SprintPrescription(
                id: prescriptionID,
                exerciseID: exerciseID,
                distance: 150,
                repetitionCount: 4,
                targetLowerSeconds: 19,
                targetUpperSeconds: 21
            ))
            context.insert(SprintGoalSnapshot(
                id: snapshotID,
                setEntryID: entryID,
                exerciseID: exerciseID,
                distance: 150,
                distanceUnit: .meters,
                repetitionNumber: 1,
                repetitionCount: 4,
                targetLowerSeconds: 19,
                targetUpperSeconds: 21
            ))
            context.insert(BodyMetricEntry(
                id: bodyMetricID,
                measuredAt: Date(timeIntervalSince1970: 1_699_500_000),
                weightKilograms: 82
            ))
            try context.save()
        }

        let migrated = try makeContainer(versionedSchema: MarbleSchemaV6.self)
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.id), [exerciseID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetEntry>()).map(\.id), [entryID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SprintPrescription>()).map(\.id), [prescriptionID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SprintGoalSnapshot>()).map(\.id), [snapshotID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMetricEntry>()).map(\.id), [bodyMetricID])
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SprintVariant>()).isEmpty,
            "A migrated store starts with no variants — the launch adoption sweep creates them, not the migration"
        )

        // The adoption sweep makes the legacy prescription loggable as a variant.
        let adopted = SprintVariant.adoptLegacyPrescriptions(in: context)
        XCTAssertEqual(adopted, 1)
        XCTAssertNoThrow(try context.save())
        let variant = try XCTUnwrap(try context.fetch(FetchDescriptor<SprintVariant>()).first)
        XCTAssertEqual(variant.exerciseID, exerciseID)
        XCTAssertEqual(variant.targetLowerTenths, 190)
        XCTAssertEqual(variant.targetUpperTenths, 210)
        XCTAssertEqual(variant.repetitionCount, 4)

        // Idempotent: a second sweep adopts nothing.
        XCTAssertEqual(SprintVariant.adoptLegacyPrescriptions(in: context), 0)
    }

    /// The app's own container factory must select V6 — the one line in
    /// `ModelContainer.swift` that decides which schema ships.
    func testPersistenceControllerOpensAV6Store() throws {
        let container = PersistenceController.makeContainer(useInMemory: true)
        let context = ModelContext(container)
        context.insert(SprintVariant(
            exerciseID: UUID(),
            distance: 100,
            distanceUnit: .meters,
            repetitionCount: 3,
            targetLowerTenths: 140,
            targetUpperTenths: 160
        ))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintVariant>()), 1)
    }

    // MARK: - Helpers

    private func makeContainer(
        versionedSchema: any VersionedSchema.Type,
        migrating: Bool = true
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: versionedSchema)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        if migrating {
            return try ModelContainer(
                for: schema,
                migrationPlan: MarbleMigrationPlan.self,
                configurations: [configuration]
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
