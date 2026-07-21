import Foundation
import SwiftData

// MARK: - Versioned schema

/// The current SwiftData schema, captured as an explicit `VersionedSchema`.
///
/// Why this exists: the app ships on the App Store with real user data. Opening a
/// store with a bare `Schema([...])` and no migration plan means a future *incompatible*
/// model change silently falls back to SwiftData's automatic migration — and if that
/// migration can't be inferred, the container fails to open and the app crash-loops on
/// launch with the user's data inaccessible. Declaring versioned schemas gives every
/// future breaking change an explicit home (a `MigrationStage`) and a place to test it.
///
/// The model types are referenced here exactly as they are declared at file scope. They
/// are intentionally **not** nested inside this enum: nesting would change each model's
/// type name and therefore the persisted entity identity, which would break the stores of
/// existing 1.8 users on upgrade.
enum MarbleSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            SetEntry.self,
            SupplementType.self,
            SupplementEntry.self,
            SplitPlan.self,
            SplitDay.self,
            PlannedSet.self,
            ProgressMediaAttachment.self,
            CustomNotification.self,
            ImportedWorkout.self
        ]
    }
}

/// Schema V2 adds first-class workout sessions without changing any existing
/// entity. SwiftData handles this additive change with its automatic lightweight
/// migration, preserving every pre-session set as standalone history.
enum MarbleSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarbleSchemaV1.models + [WorkoutSession.self]
    }
}

/// Schema V3 adds reusable sprint prescriptions as a standalone entity. Existing
/// Exercise and SetEntry entities are unchanged, keeping their shipped checksums stable.
enum MarbleSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarbleSchemaV2.models + [SprintPrescription.self]
    }
}

/// Schema V4 adds immutable per-rep sprint goal snapshots. The reusable exercise
/// prescription remains editable, while each historical rep keeps the exact target
/// it was logged against. This is additive so the shipped SetEntry remains unchanged.
enum MarbleSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarbleSchemaV3.models + [SprintGoalSnapshot.self]
    }
}

/// Schema V5 adds standalone body measurements (`BodyMetricEntry`: canonical
/// kilograms, optional body fat, manual or Apple Health source). Purely
/// additive — no existing entity gains, loses, or retypes a property, and the
/// new model holds no `@Relationship` to anything — so SwiftData's automatic
/// lightweight migration covers V4 → V5 and `stages` stays empty.
///
/// In particular this does NOT touch `SprintPrescription` / `SprintGoalSnapshot`,
/// which reference Exercise and SetEntry by raw `UUID` rather than by
/// `@Relationship`. That raw-UUID style is load-bearing: it is what keeps the
/// shipped version checksums distinct, and "improving" it into real
/// relationships is what caused the build-35 launch crash.
enum MarbleSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarbleSchemaV4.models + [BodyMetricEntry.self]
    }
}

// MARK: - Migration plan

/// Ordered list of schema versions plus the migration stages between them.
///
/// All schema changes through `MarbleSchemaV5` are additive, which SwiftData handles
/// automatically. Do not add a redundant V1 → V2 stage: when opening a store produced by
/// the previous Release build, SwiftData resolves both endpoints to V2 and Core Data aborts
/// with "Duplicate version checksums detected."
///
/// To make a breaking change in the future:
///   1. Copy the current model definitions into a `MarbleSchemaV6` enum (capturing the
///      *old* shape) and bump `versionIdentifier`.
///   2. Apply your change to the live model types.
///   3. Append `MarbleSchemaV6.self` to `schemas`; add a `.custom(...)` stage only when
///      automatic lightweight migration cannot express the required data transformation.
///   4. Add a previous-Release migration test (see `PersistenceRecoveryTests`).
///   5. Bump the single `Schema(versionedSchema:)` line in `ModelContainer.swift`.
///
/// Purely additive changes (a brand-new `@Model` with no relationships, as in V2–V5)
/// need steps 1–2 only in their degenerate form: declare the new version enum as
/// `previous.models + [NewModel.self]` and add NO stage. Adding a stage — or a version
/// whose checksum duplicates another's — is precisely how the build-35 crash happened.
enum MarbleMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MarbleSchemaV1.self,
            MarbleSchemaV2.self,
            MarbleSchemaV3.self,
            MarbleSchemaV4.self,
            MarbleSchemaV5.self
        ]
    }

    static var stages: [MigrationStage] { [] }
}
