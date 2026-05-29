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
    /// Talents earned outside the volume formula — Daily Tribute hauls and milestone
    /// rewards. Tracked separately from `storedLifetimeTalents` (which stays a monotonic
    /// volume floor) so a later volume recompute can never absorb or claw back a bonus.
    ///
    /// New stored properties below carry **inline defaults** (not just init defaults): SwiftData
    /// reads migration defaults from the property initializer, so existing on-disk `EmpireState`
    /// rows migrate cleanly when these mandatory attributes are added.
    var bonusTalents: Double = 0
    /// Newline-joined structure identifiers. Stored as a single string to match the
    /// app's convention of avoiding array-typed SwiftData attributes.
    var builtStructureRaw: String

    // MARK: Daily Tribute state
    /// The tribute-day (start-of-day, grace-adjusted) of the most recent claim. Gates
    /// "once per day" and anchors the rest-aware streak math. Optional → nullable column.
    var lastTributeDay: Date?
    /// Rest-aware streak length in training days (survives normal rest; see `EmpireTribute`).
    var tributeStreak: Int = 0
    var longestTributeStreak: Int = 0
    /// "Mason's Reprieve" freezes — earned, never bought; auto-consumed to bridge long gaps.
    var streakFreezes: Int = 0
    /// Newline-joined collected relic ids, and milestone thresholds already awarded.
    var collectedRelicsRaw: String = ""
    var claimedMilestonesRaw: String = ""

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        spentTalents: Double = 0,
        storedLifetimeTalents: Double = 0,
        bonusTalents: Double = 0,
        builtStructureRaw: String = "",
        lastTributeDay: Date? = nil,
        tributeStreak: Int = 0,
        longestTributeStreak: Int = 0,
        streakFreezes: Int = 0,
        collectedRelicsRaw: String = "",
        claimedMilestonesRaw: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.spentTalents = spentTalents
        self.storedLifetimeTalents = storedLifetimeTalents
        self.bonusTalents = bonusTalents
        self.builtStructureRaw = builtStructureRaw
        self.lastTributeDay = lastTributeDay
        self.tributeStreak = tributeStreak
        self.longestTributeStreak = longestTributeStreak
        self.streakFreezes = streakFreezes
        self.collectedRelicsRaw = collectedRelicsRaw
        self.claimedMilestonesRaw = claimedMilestonesRaw
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

    var collectedRelicIDs: [String] {
        get { collectedRelicsRaw.split(separator: "\n").map(String.init) }
        set { collectedRelicsRaw = newValue.joined(separator: "\n") }
    }

    var collectedRelicIDSet: Set<String> {
        Set(collectedRelicIDs)
    }

    /// Milestone streak thresholds already awarded (so each pays out only once).
    var claimedMilestones: Set<Int> {
        get { Set(claimedMilestonesRaw.split(separator: "\n").compactMap { Int($0) }) }
        set { claimedMilestonesRaw = newValue.sorted().map(String.init).joined(separator: "\n") }
    }

    /// Spendable balance: monotonic volume floor plus Tribute/milestone bonuses, minus what
    /// has been spent, never negative. Bonuses are additive on top of the volume-derived
    /// lifetime so they are never clawed back by a volume recompute.
    var balance: Double {
        max(0, storedLifetimeTalents + bonusTalents - spentTalents)
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

    // MARK: Daily Tribute

    /// A read-only snapshot of the tribute-relevant state, handed to the pure `EmpireTribute`
    /// logic so claim math stays testable and the model just applies the result.
    var tributeSnapshot: EmpireTributeSnapshot {
        EmpireTributeSnapshot(
            streak: tributeStreak,
            lastTributeDay: lastTributeDay,
            freezes: streakFreezes,
            longestStreak: longestTributeStreak,
            collectedRelicIDs: collectedRelicIDSet,
            claimedMilestones: claimedMilestones
        )
    }

    /// Whether today's Tribute has already been claimed (the grace-adjusted tribute-day is
    /// passed in by the caller via `EmpireTribute.tributeDay(for:)`).
    func hasClaimedTribute(on tributeDay: Date) -> Bool {
        lastTributeDay == tributeDay
    }

    /// Applies a computed claim outcome: banks bonus Talents, collects relics, advances the
    /// streak, updates the freeze balance, and records claimed milestones + the claim day.
    func apply(_ outcome: EmpireTributeOutcome, now: Date = AppEnvironment.now) {
        bonusTalents += outcome.totalBonus
        if !outcome.relicsGained.isEmpty {
            collectedRelicIDs = collectedRelicIDs + outcome.relicsGained
        }
        tributeStreak = outcome.newStreak
        longestTributeStreak = max(longestTributeStreak, outcome.newLongestStreak)
        streakFreezes = outcome.freezesAfter
        if !outcome.milestonesClaimed.isEmpty {
            claimedMilestones = claimedMilestones.union(outcome.milestonesClaimed)
        }
        lastTributeDay = outcome.day
        updatedAt = now
    }
}
