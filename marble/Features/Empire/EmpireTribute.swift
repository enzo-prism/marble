import Foundation
import UIKit

/// The Daily Tribute loop — Empire's daily, *variable-reward* ritual.
///
/// Each training day you "quarry" a Tribute: a randomised tier of bonus Talents, and sometimes a
/// collectible Relic. A rest-aware streak adds gentle loss-aversion without the streak-anxiety that
/// strict daily streaks inflict on a *fitness* app (rest days are part of training, so they don't
/// break the streak; earnable freezes cover travel/illness).
///
/// All of this lives here as pure, deterministic logic (mirroring `EmpireEconomy`) — no SwiftUI, no
/// persistence — so the reward distribution, streak rules, and milestone payouts are unit-testable
/// and snapshot-stable. The view passes in a `EmpireTributeSnapshot` and applies the returned
/// `EmpireTributeOutcome`.
enum EmpireTribute {
    // MARK: Tunable constants

    /// Rest days allowed between sessions before a freeze is needed. Default 2 → you only have to
    /// train every 3rd day to keep the streak ("normal gap" below).
    static let restAllowanceDays = 2
    /// The longest gap (in days) that keeps a streak with no freeze.
    static var normalGapDays: Int { restAllowanceDays + 1 }
    /// Extra days each "Mason's Reprieve" freeze can bridge beyond the normal gap.
    static let freezeBridgeDays = 4
    /// Sets logged before this hour count toward the previous day (late-night sessions don't split).
    static let graceHours = 4
    /// Floor so even a tiny session's Tribute never feels like nothing.
    static let minTributeFloor: Double = 10
    /// Streak lengths that trigger a "Stonemasons' Guild" milestone reward.
    static let milestones = [7, 30, 100, 365]

    // MARK: Tribute day & seeding

    /// The grace-adjusted training day a date belongs to (start-of-day after shifting back
    /// `graceHours`). Used for once-per-day gating and streak math.
    static func tributeDay(for date: Date, calendar: Calendar = .current) -> Date {
        let shifted = date.addingTimeInterval(-Double(graceHours) * 3600)
        return calendar.startOfDay(for: shifted)
    }

    /// A deterministic per-day seed (stable across launches), so the day's reward tier can't be
    /// re-rolled by reopening the app, and tests are reproducible. Folds the day number with the
    /// state's UUID bytes (FNV-1a) rather than `hashValue`, which is randomised per process.
    static func seed(forDay day: Date, salt: UUID) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ byte: UInt8) { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let u = salt.uuid
        for byte in [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15] {
            mix(byte)
        }
        let dayNumber = Int64((day.timeIntervalSince1970 / 86_400).rounded())
        withUnsafeBytes(of: dayNumber.littleEndian) { $0.forEach { mix($0) } }
        return h
    }

    // MARK: Core logic

    /// Rolls a reward tier from a seeded RNG using the published odds.
    static func rollTier(_ rng: inout EmpireSeededRNG) -> EmpireTributeTier {
        let roll = rng.unit()
        var cumulative = 0.0
        for tier in EmpireTributeTier.allCases {
            cumulative += tier.odds
            if roll < cumulative { return tier }
        }
        return .goodHaul
    }

    /// Advances the rest-aware streak. Returns the new streak length and how many freezes were
    /// consumed to bridge an over-long gap (0 in the common case). Freezes are only spent when they
    /// can *fully* bridge the gap — otherwise the streak resets and the freezes are kept.
    static func advanceStreak(
        previous: Int,
        last: Date?,
        today: Date,
        freezes: Int,
        calendar: Calendar = .current
    ) -> (streak: Int, freezesConsumed: Int) {
        guard let last else { return (1, 0) }
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        if gap <= 0 { return (max(previous, 1), 0) }          // same day (shouldn't happen post-guard)
        if gap <= normalGapDays { return (previous + 1, 0) }  // consecutive or within rest allowance

        let beyond = gap - normalGapDays
        let needed = Int((Double(beyond) / Double(freezeBridgeDays)).rounded(.up))
        if freezes >= needed {
            return (previous + 1, needed)
        }
        return (1, 0)
    }

    /// A rarity-weighted random uncollected relic id, or nil if every relic is already owned.
    static func pickRelic(excluding collected: Set<String>, rng: inout EmpireSeededRNG) -> String? {
        let available = EmpireRelic.catalog.filter { !collected.contains($0.id) }
        guard !available.isEmpty else { return nil }
        let weights = available.map { $0.rarity.weight }
        let total = weights.reduce(0, +)
        var roll = rng.int(total)
        for (relic, weight) in zip(available, weights) {
            if roll < weight { return relic.id }
            roll -= weight
        }
        return available.last?.id
    }

    /// Milestone thresholds newly reached at `streak` that haven't been awarded yet.
    static func milestonesReached(streak: Int, alreadyClaimed: Set<Int>) -> [Int] {
        milestones.filter { $0 <= streak && !alreadyClaimed.contains($0) }
    }

    /// The next milestone above the current streak, and how many more training days it needs.
    static func nextMilestone(after streak: Int) -> (threshold: Int, daysAway: Int)? {
        guard let threshold = milestones.first(where: { $0 > streak }) else { return nil }
        return (threshold, threshold - streak)
    }

    static func milestoneTalents(for threshold: Int) -> Double {
        switch threshold {
        case 7: return 250
        case 30: return 1_500
        case 100: return 8_000
        case 365: return 50_000
        default: return Double(threshold) * 50
        }
    }

    // MARK: Claim orchestration (pure)

    /// Computes the full result of claiming today's Tribute from a state snapshot. Deterministic for
    /// a given `seed`. The caller (`EmpireView`) applies the outcome via `EmpireState.apply(_:)`.
    static func claim(
        _ snapshot: EmpireTributeSnapshot,
        day: Date,
        todayScore: Double,
        seed: UInt64,
        calendar: Calendar = .current
    ) -> EmpireTributeOutcome {
        var rng = EmpireSeededRNG(seed: seed)
        let tier = rollTier(&rng)

        // Streak first (independent of the RNG draw order above is fine — tier already drawn).
        let advance = advanceStreak(
            previous: snapshot.streak,
            last: snapshot.lastTributeDay,
            today: day,
            freezes: snapshot.freezes,
            calendar: calendar
        )
        var freezes = snapshot.freezes - advance.freezesConsumed

        // Tribute Talents, scaled to the day's effort, with a floor.
        var baseBonus = max(minTributeFloor, (todayScore * tier.multiplier).rounded())

        var collected = snapshot.collectedRelicIDs
        var relicsGained: [String] = []

        // Relic / Mother-lode tiers grant a relic; Mother-lode also grants a freeze.
        if tier.grantsRelic {
            if let relic = pickRelic(excluding: collected, rng: &rng) {
                relicsGained.append(relic)
                collected.insert(relic)
            } else {
                // Collection complete — convert the relic into a Talent bonus so it still feels good.
                baseBonus += max(minTributeFloor, (todayScore * 0.25).rounded())
            }
        }
        if tier.grantsFreeze {
            freezes += 1
        }

        // Milestones (normally at most one per claim, but award all newly-passed thresholds).
        var milestoneBonus = 0.0
        var milestonesClaimed: [Int] = []
        for threshold in milestonesReached(streak: advance.streak, alreadyClaimed: snapshot.claimedMilestones) {
            milestonesClaimed.append(threshold)
            milestoneBonus += milestoneTalents(for: threshold)
            freezes += 1
            if let relic = pickRelic(excluding: collected, rng: &rng) {
                relicsGained.append(relic)
                collected.insert(relic)
            } else {
                milestoneBonus += 100
            }
        }

        return EmpireTributeOutcome(
            tier: tier,
            baseBonus: baseBonus,
            milestoneBonus: milestoneBonus,
            relicsGained: relicsGained,
            newStreak: advance.streak,
            newLongestStreak: max(snapshot.longestStreak, advance.streak),
            freezesAfter: freezes,
            freezesConsumed: advance.freezesConsumed,
            milestonesClaimed: milestonesClaimed,
            day: day
        )
    }
}

// MARK: - Reward tiers

/// The four Tribute outcomes. Odds are published (a tap-to-view breakdown in the UI) — Marble has no
/// real-money currency, so this is an ethically-clean variable reward, not a paid loot box.
enum EmpireTributeTier: CaseIterable {
    case goodHaul
    case richVein
    case relic
    case motherLode

    /// Probability of this tier. Must sum to 1 across all cases.
    var odds: Double {
        switch self {
        case .goodHaul: return 0.55
        case .richVein: return 0.27
        case .relic: return 0.13
        case .motherLode: return 0.05
        }
    }

    /// Bonus Talents as a fraction of the day's training volume.
    var multiplier: Double {
        switch self {
        case .goodHaul: return 0.15
        case .richVein: return 0.30
        case .relic: return 0.40
        case .motherLode: return 1.00
        }
    }

    var grantsRelic: Bool { self == .relic || self == .motherLode }
    var grantsFreeze: Bool { self == .motherLode }

    var title: String {
        switch self {
        case .goodHaul: return "Good Haul"
        case .richVein: return "Rich Vein"
        case .relic: return "Relic Unearthed"
        case .motherLode: return "Mother Lode"
        }
    }

    var headline: String {
        switch self {
        case .goodHaul: return "A solid day's quarrying."
        case .richVein: return "The marble runs deep today."
        case .relic: return "Your diggers strike something ancient."
        case .motherLode: return "A legendary find!"
        }
    }
}

// MARK: - Relics

enum EmpireRelicRarity {
    case common
    case rare
    case legendary

    /// Selection weight (commons surface most often).
    var weight: Int {
        switch self {
        case .common: return 3
        case .rare: return 2
        case .legendary: return 1
        }
    }

    var label: String {
        switch self {
        case .common: return "Common"
        case .rare: return "Rare"
        case .legendary: return "Legendary"
        }
    }
}

/// A collectible treasure. Pure static data, like `EmpireEconomy.catalog`; `EmpireState` only stores
/// which ids have been collected. Each relic borrows an `EmpireAge` palette for its colour.
struct EmpireRelic: Identifiable, Hashable {
    let id: String
    let name: String
    let flavor: String
    let symbolName: String
    let rarity: EmpireRelicRarity
    let age: EmpireAge

    /// Falls back to a safe glyph if the preferred SF Symbol is unavailable, mirroring
    /// `EmpireStructure.resolvedSymbolName`.
    var resolvedSymbolName: String {
        UIImage(systemName: symbolName) != nil ? symbolName : "seal.fill"
    }

    static let catalog: [EmpireRelic] = [
        EmpireRelic(id: "olive", name: "Olive Branch", flavor: "Peace earned through effort.", symbolName: "leaf.fill", rarity: .common, age: .foundations),
        EmpireRelic(id: "brazier", name: "Eternal Brazier", flavor: "A flame that never tires.", symbolName: "flame.fill", rarity: .common, age: .foundations),
        EmpireRelic(id: "shield", name: "Hoplite Shield", flavor: "Bronze, dented, proud.", symbolName: "shield.fill", rarity: .common, age: .foundations),
        EmpireRelic(id: "fountain", name: "Marble Fountain", flavor: "Cool water for the weary.", symbolName: "drop.fill", rarity: .common, age: .golden),
        EmpireRelic(id: "laurel", name: "Laurel of Victory", flavor: "Worn only by champions.", symbolName: "laurel.leading", rarity: .legendary, age: .golden),
        EmpireRelic(id: "sundisc", name: "Sun Disc", flavor: "Gold caught at high noon.", symbolName: "sun.max.fill", rarity: .rare, age: .golden),
        EmpireRelic(id: "lyre", name: "Bard's Star", flavor: "A song for every set.", symbolName: "star.fill", rarity: .common, age: .golden),
        EmpireRelic(id: "crown", name: "Gilded Crown", flavor: "Heavy is the head.", symbolName: "crown.fill", rarity: .legendary, age: .empire),
        EmpireRelic(id: "seal", name: "Imperial Seal", flavor: "Stamped on every decree.", symbolName: "seal.fill", rarity: .rare, age: .empire),
        EmpireRelic(id: "banner", name: "Legion Banner", flavor: "Carried to the world's edge.", symbolName: "flag.fill", rarity: .common, age: .empire),
        EmpireRelic(id: "trophy", name: "Champion's Trophy", flavor: "Won in the arena's sand.", symbolName: "trophy.fill", rarity: .rare, age: .empire),
        EmpireRelic(id: "scroll", name: "Ancient Scroll", flavor: "Wisdom of older athletes.", symbolName: "scroll.fill", rarity: .common, age: .industrial),
        EmpireRelic(id: "library", name: "Great Library", flavor: "Every lesson, kept.", symbolName: "books.vertical.fill", rarity: .rare, age: .industrial),
        EmpireRelic(id: "key", name: "Key of the City", flavor: "Granted to its builders.", symbolName: "key.fill", rarity: .rare, age: .industrial),
        EmpireRelic(id: "globe", name: "Celestial Globe", flavor: "The heavens, mapped.", symbolName: "globe", rarity: .rare, age: .future),
        EmpireRelic(id: "jewel", name: "Tyrant's Jewel", flavor: "It hums with cold light.", symbolName: "diamond.fill", rarity: .legendary, age: .future)
    ]

    static func relic(id: String) -> EmpireRelic? {
        catalog.first { $0.id == id }
    }

    static var totalCount: Int { catalog.count }
}

// MARK: - Value types passed across the model boundary

/// Read-only snapshot of the tribute-relevant state, so claim math stays pure/testable.
struct EmpireTributeSnapshot {
    let streak: Int
    let lastTributeDay: Date?
    let freezes: Int
    let longestStreak: Int
    let collectedRelicIDs: Set<String>
    let claimedMilestones: Set<Int>
}

/// The computed result of a claim, applied to `EmpireState` via `apply(_:)`.
struct EmpireTributeOutcome {
    let tier: EmpireTributeTier
    let baseBonus: Double
    let milestoneBonus: Double
    let relicsGained: [String]
    let newStreak: Int
    let newLongestStreak: Int
    let freezesAfter: Int
    let freezesConsumed: Int
    let milestonesClaimed: [Int]
    let day: Date

    var totalBonus: Double { baseBonus + milestoneBonus }
    var relics: [EmpireRelic] { relicsGained.compactMap(EmpireRelic.relic(id:)) }
}

// MARK: - Deterministic RNG (SplitMix64)

/// A tiny seeded PRNG so Tribute rolls are deterministic (reproducible tests, stable snapshots, no
/// save-scumming). SplitMix64 — small, fast, good distribution.
struct EmpireSeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A Double in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// An Int in 0..<n (0 for n <= 0).
    mutating func int(_ n: Int) -> Int {
        n <= 0 ? 0 : Int(next() % UInt64(n))
    }
}
