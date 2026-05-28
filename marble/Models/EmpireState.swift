import Foundation
import SwiftData

/// Persistent state for the Empire (gamification) tab: how many Talents have been
/// spent and which structures have been built. Lifetime earnings are derived from
/// workout volume, but cached here as a monotonic floor so deleting old sets never
/// claws back currency the user already earned (and possibly spent).
@Model
final class EmpireState {
    @Attribute(.unique) var id: UUID
    var spentTalents: Double
    var storedLifetimeTalents: Double
    /// Newline-joined structure identifiers. Stored as a single string to match the
    /// app's convention of avoiding array-typed SwiftData attributes.
    var builtStructureRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        spentTalents: Double = 0,
        storedLifetimeTalents: Double = 0,
        builtStructureRaw: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.spentTalents = spentTalents
        self.storedLifetimeTalents = storedLifetimeTalents
        self.builtStructureRaw = builtStructureRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension EmpireState {
    var builtStructureIDs: [String] {
        get {
            builtStructureRaw
                .split(separator: "\n")
                .map(String.init)
        }
        set {
            builtStructureRaw = newValue.joined(separator: "\n")
        }
    }

    var builtStructureIDSet: Set<String> {
        Set(builtStructureIDs)
    }

    /// Spendable balance: lifetime earnings minus what has been spent, never negative.
    var balance: Double {
        max(0, storedLifetimeTalents - spentTalents)
    }

    func isBuilt(_ structureID: String) -> Bool {
        builtStructureIDSet.contains(structureID)
    }

    /// Records a lifetime-earnings recompute, keeping the value monotonic so edits or
    /// deletions of historical sets cannot reduce a balance the user already banked.
    func updateLifetimeTalents(_ computed: Double) {
        storedLifetimeTalents = max(storedLifetimeTalents, computed)
    }

    /// Attempts to purchase a structure. Returns `true` on success.
    @discardableResult
    func purchase(_ structure: EmpireStructure, now: Date = AppEnvironment.now) -> Bool {
        guard !isBuilt(structure.id), balance >= structure.cost else { return false }
        spentTalents += structure.cost
        builtStructureIDs = builtStructureIDs + [structure.id]
        updatedAt = now
        return true
    }
}
