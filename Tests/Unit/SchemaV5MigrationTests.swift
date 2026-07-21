import Foundation
import SwiftData
import XCTest
@testable import marble

/// Guards the 2.4 "Body" schema bump — the first since V4, and the change class
/// that has already crash-looped this app once (build 35, duplicate version
/// checksums after a relationship was "improved").
///
/// The invariants pinned here are the ones that broke that build:
///   1. `stages` stays empty. V5 is purely additive, so SwiftData's automatic
///      lightweight migration covers it; adding a stage is how V4 broke.
///   2. Every declared version has a distinct identifier, in ascending order.
///   3. A real V4 store on disk opens as V5 with its training data intact.
@MainActor
final class SchemaV5MigrationTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marble-schema-v5-\(UUID().uuidString)", isDirectory: true)
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

    /// The single most important assertion in this file. V5 adds a standalone
    /// `@Model` with no relationships and touches no existing entity, so
    /// lightweight migration handles it and there must be no stage. A
    /// `.custom` stage here — or a version whose checksum duplicates
    /// another's — is exactly what made build 35 crash on launch.
    func testMigrationPlanHasNoStages() {
        XCTAssertTrue(
            MarbleMigrationPlan.stages.isEmpty,
            "V5 is additive; adding a MigrationStage resurrects the build-35 launch crash"
        )
    }

    func testMigrationPlanDeclaresV5AsTheLatestSchema() {
        let identifiers = MarbleMigrationPlan.schemas.map { $0.versionIdentifier }

        XCTAssertEqual(identifiers.count, 5)
        XCTAssertEqual(identifiers.last, Schema.Version(5, 0, 0))
        XCTAssertEqual(MarbleSchemaV5.versionIdentifier, Schema.Version(5, 0, 0))
    }

    /// Distinct and ascending. Two versions sharing an identifier is the
    /// literal "Duplicate version checksums detected" abort.
    func testSchemaVersionsAreDistinctAndAscending() {
        let identifiers = MarbleMigrationPlan.schemas.map { $0.versionIdentifier }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "Version identifiers must be unique")
        XCTAssertEqual(identifiers, identifiers.sorted(), "Versions must be listed oldest to newest")
    }

    /// V5 is V4 plus exactly one model. If this fails, something was removed
    /// or retyped and the change is no longer additive.
    func testV5IsV4PlusBodyMetricEntryOnly() {
        let v4 = MarbleSchemaV4.models.map { String(describing: $0) }
        let v5 = MarbleSchemaV5.models.map { String(describing: $0) }

        XCTAssertEqual(v5.count, v4.count + 1)
        XCTAssertTrue(Set(v4).isSubset(of: Set(v5)), "V5 must not drop or rename any V4 entity")
        XCTAssertEqual(Set(v5).subtracting(Set(v4)), [String(describing: BodyMetricEntry.self)])
    }

    // MARK: - Round trip

    func testV5ContainerRoundTripsABodyMetricEntry() throws {
        let id = UUID()
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let healthKitUUID = UUID()

        try autoreleasepool {
            let container = try makeContainer(versionedSchema: MarbleSchemaV5.self)
            let context = ModelContext(container)
            context.insert(BodyMetricEntry(
                id: id,
                measuredAt: measuredAt,
                weightKilograms: 82.5,
                bodyFatPercent: 14.2,
                source: .healthKit,
                healthKitUUID: healthKitUUID,
                notes: "Morning, fasted"
            ))
            try context.save()
        }

        let reopened = try makeContainer(versionedSchema: MarbleSchemaV5.self)
        let context = ModelContext(reopened)
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMetricEntry>()).first)

        XCTAssertEqual(stored.id, id)
        XCTAssertEqual(stored.measuredAt, measuredAt)
        XCTAssertEqual(stored.weightKilograms, 82.5, accuracy: 0.0001)
        XCTAssertEqual(stored.bodyFatPercent ?? 0, 14.2, accuracy: 0.0001)
        XCTAssertEqual(stored.source, .healthKit)
        XCTAssertEqual(stored.healthKitUUID, healthKitUUID)
        XCTAssertEqual(stored.notes, "Morning, fasted")
    }

    /// The upgrade path a shipped 2.3 user actually takes: a populated V4 store
    /// opens as V5, keeps every row, and accepts the new entity.
    func testPopulatedV4StoreMigratesToV5WithTrainingDataIntact() throws {
        let exerciseID = UUID()
        let entryID = UUID()
        let prescriptionID = UUID()

        try autoreleasepool {
            let container = try makeContainer(versionedSchema: MarbleSchemaV4.self, migrating: false)
            let context = ModelContext(container)
            let exercise = Exercise(
                id: exerciseID,
                name: "Back Squat",
                category: .quads,
                metrics: .weightAndRepsRequired,
                defaultRestSeconds: 180
            )
            context.insert(exercise)
            context.insert(SetEntry(
                id: entryID,
                exercise: exercise,
                performedAt: Date(timeIntervalSince1970: 1_699_000_000),
                weight: 140,
                reps: 5,
                restAfterSeconds: 180
            ))
            // Kept in the fixture deliberately: SprintPrescription references
            // Exercise by raw UUID rather than @Relationship, and that style is
            // load-bearing for checksum distinctness. If a future change turns
            // it into a relationship, this migration is what breaks.
            context.insert(SprintPrescription(
                id: prescriptionID,
                exerciseID: exerciseID,
                distance: 150,
                repetitionCount: 4,
                targetLowerSeconds: 19,
                targetUpperSeconds: 21
            ))
            try context.save()
        }

        let migrated = try makeContainer(versionedSchema: MarbleSchemaV5.self)
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.id), [exerciseID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetEntry>()).map(\.id), [entryID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SprintPrescription>()).map(\.id), [prescriptionID])
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<BodyMetricEntry>()).isEmpty,
            "A migrated store starts with no body metrics — the entity is new, not backfilled"
        )

        // The new entity is usable immediately after migration.
        context.insert(BodyMetricEntry(measuredAt: Date(timeIntervalSince1970: 1_700_000_000), weightKilograms: 84))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 1)
    }

    /// The app's own container factory must select V5 — the one line in
    /// `ModelContainer.swift` that decides which schema ships.
    func testPersistenceControllerOpensAV5Store() throws {
        let container = PersistenceController.makeContainer(useInMemory: true)
        let context = ModelContext(container)
        context.insert(BodyMetricEntry(measuredAt: Date(timeIntervalSince1970: 1_700_000_000), weightKilograms: 80))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 1)
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
