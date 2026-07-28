import Foundation
import SwiftData

/// The tenths-precision facts about one logged sprint rep that the shipped
/// whole-second columns cannot carry: the exact recorded time and the exact
/// frozen target it was judged against.
///
/// Companion to `SprintGoalSnapshot`, not a replacement — every new sprint rep
/// still writes the legacy snapshot (rounded) so pre-V6 builds, old backups,
/// and the V4 backfill provenance rules keep working; tenths-aware read paths
/// prefer this row when present via `SprintGoalEvaluation.evaluate(snapshot:entry:detail:)`.
/// Additive V6 model, raw-UUID references only (the load-bearing style from
/// the V5 schema comment).
@Model
final class SprintRepDetail {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var setEntryID: UUID
    /// Exact recorded time in tenths (see `SprintTiming`). The paired
    /// `SetEntry.durationSeconds` always holds `SprintTiming.wholeSeconds` of
    /// this value so legacy consumers see the closest representable time.
    var durationTenths: Int
    /// The frozen tenths target — same freeze-at-log-time contract as
    /// `SprintGoalSnapshot`, at the precision the athlete actually set.
    var targetLowerTenths: Int
    var targetUpperTenths: Int
    /// Which `SprintVariant` was being run, when known. Enables per-variant
    /// hit-rate history (progression nudges); nil for legacy-prescription and
    /// fallback logging paths.
    var variantID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        setEntryID: UUID,
        durationTenths: Int,
        targetLowerTenths: Int,
        targetUpperTenths: Int,
        variantID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.setEntryID = setEntryID
        self.durationTenths = durationTenths
        self.targetLowerTenths = targetLowerTenths
        self.targetUpperTenths = targetUpperTenths
        self.variantID = variantID
        self.createdAt = createdAt
    }
}

extension SprintRepDetail {
    var target: SprintTargetTenths {
        SprintTargetTenths(lowerTenths: targetLowerTenths, upperTenths: targetUpperTenths)
    }

    var isValid: Bool {
        SprintTiming.isPlausible(tenths: durationTenths) && target.isValid
    }

    /// Referential-integrity sweep, same key-projected shape as
    /// `SprintGoalSnapshot.removeOrphans` (SetEntry is the largest table —
    /// only its `id` column is ever loaded here).
    static func removeOrphans(in context: ModelContext) {
        var entryIDsDescriptor = FetchDescriptor<SetEntry>()
        entryIDsDescriptor.propertiesToFetch = [\SetEntry.id]
        var detailKeysDescriptor = FetchDescriptor<SprintRepDetail>()
        detailKeysDescriptor.propertiesToFetch = [\SprintRepDetail.setEntryID]
        guard let setEntryIDs = try? Set(context.fetch(entryIDsDescriptor).map(\.id)),
              let details = try? context.fetch(detailKeysDescriptor) else { return }
        details
            .filter { !setEntryIDs.contains($0.setEntryID) }
            .forEach(context.delete)
    }
}
