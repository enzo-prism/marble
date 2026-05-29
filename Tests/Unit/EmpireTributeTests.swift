import XCTest
@testable import marble

final class EmpireTributeTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func day(_ offsetDays: Int) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offsetDays, to: start) ?? start
    }

    private func seed(forTier tier: EmpireTributeTier) -> UInt64 {
        for candidate in UInt64(1)...100_000 {
            var rng = EmpireSeededRNG(seed: candidate)
            if EmpireTribute.rollTier(&rng) == tier { return candidate }
        }
        XCTFail("No seed produced tier \(tier)")
        return 1
    }

    // MARK: Tier odds

    func testTierOddsSumToOne() {
        let total = EmpireTributeTier.allCases.reduce(0.0) { $0 + $1.odds }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }

    func testRollTierIsDeterministicForASeed() {
        var a = EmpireSeededRNG(seed: 42)
        var b = EmpireSeededRNG(seed: 42)
        XCTAssertEqual(EmpireTribute.rollTier(&a), EmpireTribute.rollTier(&b))
    }

    func testTierDistributionRoughlyMatchesOdds() {
        var counts: [EmpireTributeTier: Int] = [:]
        let n = 20_000
        for s in 0..<n {
            var rng = EmpireSeededRNG(seed: UInt64(s) &* 2_654_435_761)
            counts[EmpireTribute.rollTier(&rng), default: 0] += 1
        }
        for tier in EmpireTributeTier.allCases {
            let observed = Double(counts[tier, default: 0]) / Double(n)
            XCTAssertEqual(observed, tier.odds, accuracy: 0.03, "Tier \(tier) frequency off")
        }
    }

    // MARK: Tribute day & grace window

    func testGraceWindowFoldsLateNightIntoPreviousDay() {
        let twoAM = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: day(0))!
        let fiveAM = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: day(0))!
        XCTAssertEqual(EmpireTribute.tributeDay(for: twoAM, calendar: calendar), day(-1))
        XCTAssertEqual(EmpireTribute.tributeDay(for: fiveAM, calendar: calendar), day(0))
    }

    func testSeedIsStableForSameDayAndSalt() {
        let salt = UUID()
        XCTAssertEqual(
            EmpireTribute.seed(forDay: day(0), salt: salt),
            EmpireTribute.seed(forDay: day(0), salt: salt)
        )
        XCTAssertNotEqual(
            EmpireTribute.seed(forDay: day(0), salt: salt),
            EmpireTribute.seed(forDay: day(1), salt: salt)
        )
    }

    // MARK: Rest-aware streak

    func testFirstClaimStartsStreakAtOne() {
        let result = EmpireTribute.advanceStreak(previous: 0, last: nil, today: day(0), freezes: 0, calendar: calendar)
        XCTAssertEqual(result.streak, 1)
        XCTAssertEqual(result.freezesConsumed, 0)
    }

    func testConsecutiveDayExtendsStreak() {
        let result = EmpireTribute.advanceStreak(previous: 4, last: day(-1), today: day(0), freezes: 0, calendar: calendar)
        XCTAssertEqual(result.streak, 5)
        XCTAssertEqual(result.freezesConsumed, 0)
    }

    func testRestDayWithinAllowanceKeepsStreak() {
        // Two rest days between sessions (gap of 3) is within the default allowance.
        let result = EmpireTribute.advanceStreak(previous: 9, last: day(-3), today: day(0), freezes: 0, calendar: calendar)
        XCTAssertEqual(result.streak, 10, "Rest days should not break the streak")
        XCTAssertEqual(result.freezesConsumed, 0)
    }

    func testLongGapWithoutFreezeResetsStreak() {
        let result = EmpireTribute.advanceStreak(previous: 12, last: day(-6), today: day(0), freezes: 0, calendar: calendar)
        XCTAssertEqual(result.streak, 1)
        XCTAssertEqual(result.freezesConsumed, 0)
    }

    func testFreezeBridgesAnOverlongGap() {
        // gap 6 → beyond normal (3) by 3 → needs 1 freeze (bridges 4 days).
        let result = EmpireTribute.advanceStreak(previous: 12, last: day(-6), today: day(0), freezes: 1, calendar: calendar)
        XCTAssertEqual(result.streak, 13)
        XCTAssertEqual(result.freezesConsumed, 1)
    }

    func testFreezeNotSpentWhenItCannotFullyBridge() {
        // gap 12 → beyond normal by 9 → needs 3 freezes; only 1 available → reset and keep the freeze.
        let result = EmpireTribute.advanceStreak(previous: 20, last: day(-12), today: day(0), freezes: 1, calendar: calendar)
        XCTAssertEqual(result.streak, 1)
        XCTAssertEqual(result.freezesConsumed, 0)
    }

    // MARK: Milestones

    func testMilestonesReachedReturnsOnlyNewThresholds() {
        XCTAssertEqual(EmpireTribute.milestonesReached(streak: 7, alreadyClaimed: []), [7])
        XCTAssertEqual(EmpireTribute.milestonesReached(streak: 7, alreadyClaimed: [7]), [])
        XCTAssertEqual(EmpireTribute.milestonesReached(streak: 30, alreadyClaimed: [7]), [30])
    }

    func testNextMilestoneCountsDown() {
        XCTAssertEqual(EmpireTribute.nextMilestone(after: 3)?.threshold, 7)
        XCTAssertEqual(EmpireTribute.nextMilestone(after: 3)?.daysAway, 4)
        XCTAssertNil(EmpireTribute.nextMilestone(after: 365))
    }

    // MARK: Relics

    func testPickRelicReturnsNilWhenAllCollected() {
        let all = Set(EmpireRelic.catalog.map(\.id))
        var rng = EmpireSeededRNG(seed: 1)
        XCTAssertNil(EmpireTribute.pickRelic(excluding: all, rng: &rng))
    }

    func testPickRelicExcludesCollected() {
        let collected = Set(EmpireRelic.catalog.dropLast().map(\.id)) // only the last remains
        var rng = EmpireSeededRNG(seed: 7)
        XCTAssertEqual(EmpireTribute.pickRelic(excluding: collected, rng: &rng), EmpireRelic.catalog.last?.id)
    }

    // MARK: Claim orchestration

    private func emptySnapshot(streak: Int = 0, last: Date? = nil, freezes: Int = 0, collected: Set<String> = [], claimed: Set<Int> = []) -> EmpireTributeSnapshot {
        EmpireTributeSnapshot(streak: streak, lastTributeDay: last, freezes: freezes, longestStreak: streak, collectedRelicIDs: collected, claimedMilestones: claimed)
    }

    func testClaimAppliesFloorAndScalesWithEffort() {
        let snapshot = emptySnapshot()
        let outcome = EmpireTribute.claim(snapshot, day: day(0), todayScore: 0, seed: 5, calendar: calendar)
        XCTAssertGreaterThanOrEqual(outcome.baseBonus, EmpireTribute.minTributeFloor)
        XCTAssertEqual(outcome.totalBonus, outcome.baseBonus + outcome.milestoneBonus, accuracy: 0.001)
        XCTAssertEqual(outcome.newStreak, 1)
        XCTAssertEqual(outcome.day, day(0))
    }

    func testRelicTierGrantsARelic() {
        let snapshot = emptySnapshot()
        let outcome = EmpireTribute.claim(snapshot, day: day(0), todayScore: 1_000, seed: seed(forTier: .relic), calendar: calendar)
        XCTAssertEqual(outcome.tier, .relic)
        XCTAssertEqual(outcome.relicsGained.count, 1)
    }

    func testMotherLodeGrantsRelicAndFreeze() {
        let snapshot = emptySnapshot()
        let outcome = EmpireTribute.claim(snapshot, day: day(0), todayScore: 1_000, seed: seed(forTier: .motherLode), calendar: calendar)
        XCTAssertEqual(outcome.tier, .motherLode)
        XCTAssertEqual(outcome.relicsGained.count, 1)
        XCTAssertGreaterThanOrEqual(outcome.freezesAfter, 1, "Mother lode grants a freeze")
    }

    func testRelicTierConvertsToTalentsWhenCollectionComplete() {
        let all = Set(EmpireRelic.catalog.map(\.id))
        let snapshot = emptySnapshot(collected: all)
        let outcome = EmpireTribute.claim(snapshot, day: day(0), todayScore: 1_000, seed: seed(forTier: .relic), calendar: calendar)
        XCTAssertTrue(outcome.relicsGained.isEmpty)
        // relic value folded into Talents on top of the base 40% tier multiplier.
        XCTAssertGreaterThan(outcome.baseBonus, 1_000 * EmpireTributeTier.relic.multiplier)
    }

    func testClaimAwardsMilestoneWhenStreakHitsThreshold() {
        let snapshot = emptySnapshot(streak: 6, last: day(-1), freezes: 0)
        let outcome = EmpireTribute.claim(snapshot, day: day(0), todayScore: 500, seed: 9, calendar: calendar)
        XCTAssertEqual(outcome.newStreak, 7)
        XCTAssertEqual(outcome.milestonesClaimed, [7])
        XCTAssertGreaterThanOrEqual(outcome.milestoneBonus, EmpireTribute.milestoneTalents(for: 7))
        XCTAssertGreaterThanOrEqual(outcome.freezesAfter, 1, "Milestone grants a freeze")
    }

    // MARK: EmpireState economy integration

    func testBalanceIncludesBonusTalents() {
        let state = EmpireState(spentTalents: 200, storedLifetimeTalents: 1_000, bonusTalents: 500)
        XCTAssertEqual(state.balance, 1_300, accuracy: 0.001)
    }

    func testBonusTalentsAreNotClawedBackByVolumeRecompute() {
        let state = EmpireState(storedLifetimeTalents: 5_000, bonusTalents: 300)
        state.updateLifetimeTalents(3_000) // a deletion lowering computed volume
        XCTAssertEqual(state.storedLifetimeTalents, 5_000, accuracy: 0.001)
        XCTAssertEqual(state.bonusTalents, 300, accuracy: 0.001)
        XCTAssertEqual(state.balance, 5_300, accuracy: 0.001)
    }

    func testApplyOutcomeBanksBonusCollectsRelicAndAdvancesStreak() {
        let state = EmpireState(storedLifetimeTalents: 1_000)
        let outcome = EmpireTributeOutcome(
            tier: .relic,
            baseBonus: 400,
            milestoneBonus: 250,
            relicsGained: ["olive"],
            newStreak: 7,
            newLongestStreak: 7,
            freezesAfter: 2,
            freezesConsumed: 0,
            milestonesClaimed: [7],
            day: day(0)
        )
        state.apply(outcome, now: now)
        XCTAssertEqual(state.bonusTalents, 650, accuracy: 0.001)
        XCTAssertEqual(state.balance, 1_650, accuracy: 0.001)
        XCTAssertTrue(state.collectedRelicIDSet.contains("olive"))
        XCTAssertEqual(state.tributeStreak, 7)
        XCTAssertEqual(state.longestTributeStreak, 7)
        XCTAssertEqual(state.streakFreezes, 2)
        XCTAssertTrue(state.claimedMilestones.contains(7))
        XCTAssertEqual(state.lastTributeDay, day(0))
        XCTAssertTrue(state.hasClaimedTribute(on: day(0)))
    }

    func testBonusTalentsCanFundAPurchase() {
        let state = EmpireState(storedLifetimeTalents: 0, bonusTalents: 300)
        let quarry = EmpireEconomy.structure(id: "quarry")! // costs 250
        XCTAssertTrue(state.purchase(quarry, now: now))
        XCTAssertEqual(state.spentTalents, 250, accuracy: 0.001)
        XCTAssertEqual(state.balance, 50, accuracy: 0.001)
    }
}
