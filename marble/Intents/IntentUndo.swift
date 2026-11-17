import AppIntents
import Foundation
import SwiftData

/// Undo support for the intents that write a set.
///
/// In-app, a mis-logged set is undoable with the system gestures (shake,
/// three-finger swipe) because `ContentView` hands SwiftData's change tracking
/// the scene's `UndoManager`. A voice-logged set had no such escape: it was
/// saved through a background launch with no scene, so nothing recorded it as
/// an undoable action. `UndoableIntent` (iOS 26) closes exactly that gap by
/// handing the intent an `UndoManager` of its own.
///
/// The registered operation deletes the row it created rather than replaying the
/// store's own change log — the intent's context is saved and gone by the time
/// undo can be invoked, and deleting a known id is the honest inverse of
/// "insert one set".
@MainActor
enum IntentUndo {
    /// Registers "delete the set this intent just logged" with `undoManager`.
    ///
    /// - Parameters:
    ///   - entryID: the inserted `SetEntry`.
    ///   - goalSnapshotID: the `SprintGoalSnapshot` frozen alongside it, if any.
    ///     Undo has to take both, or the sprint goal outlives its set.
    ///   - actionName: what the system offers to undo, e.g. "Log Set".
    static func registerLoggedSet(
        entryID: UUID,
        goalSnapshotID: UUID?,
        container: ModelContainer,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let undoManager else { return }
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: UndoTarget.shared) { target in
            // UndoManager invokes registered operations on the thread that
            // registered them; this one is registered from a `@MainActor`
            // `perform()`, so the hop is already satisfied.
            MainActor.assumeIsolated {
                target.removeLoggedSet(
                    entryID: entryID,
                    goalSnapshotID: goalSnapshotID,
                    in: container
                )
            }
        }
    }

    /// `registerUndo` needs an object to own the operation; a single shared one
    /// keeps intents from each allocating a target that has to outlive them.
    @MainActor
    private final class UndoTarget {
        static let shared = UndoTarget()

        private init() {}

        func removeLoggedSet(entryID: UUID, goalSnapshotID: UUID?, in container: ModelContainer) {
            let context = container.mainContext
            // Exact-ID removal shared with the snippet's Undo button: the entry,
            // its frozen sprint goal and its tenths companion go together.
            guard let changedExerciseID = WorkoutCommands.removeSetRows(
                entryID: entryID, goalSnapshotID: goalSnapshotID, in: context
            ) else { return }

            guard context.saveOrRollback() else { return }
            RestActivityController.shared.cancelRest(startedBy: entryID)

            // The undone set has to leave the widget and the weekly-goal nudge
            // too, for the same reason logging it had to reach them.
            Task { await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [changedExerciseID]) }
        }
    }
}
