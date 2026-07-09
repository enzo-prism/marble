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
/// entity. This is a lightweight, additive migration and preserves every
/// pre-session set as standalone history.
enum MarbleSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarbleSchemaV1.models + [WorkoutSession.self]
    }
}

// MARK: - Migration plan

/// Ordered list of schema versions plus the migration stages between them.
///
/// All schema changes up to and including `MarbleSchemaV1` are additive (new optional
/// properties and new models), which SwiftData handles as lightweight migrations
/// automatically — so there are no stages yet.
///
/// To make a breaking change in the future:
///   1. Copy the current model definitions into a `MarbleSchemaV2` enum (capturing the
///      *old* shape) and bump `versionIdentifier`.
///   2. Apply your change to the live model types.
///   3. Append `MarbleSchemaV2.self` to `schemas` and add a `.lightweight` or
///      `.custom(...)` `MigrationStage` from V1 to V2 below.
///   4. Add a migration test (see `SchemaMigrationTests`).
enum MarbleMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MarbleSchemaV1.self, MarbleSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: MarbleSchemaV1.self, toVersion: MarbleSchemaV2.self)
        ]
    }
}
