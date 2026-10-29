import XCTest
@testable import marble

/// Pins the guard rails around the Apple Intelligence monthly insights: the
/// number-grounding and health-advice validator, unit-aware volume wording,
/// the in-progress vs completed fallback phrasing, and the cache key. All of
/// it is pure, so none of it needs the model.
@MainActor
final class TrainingInsightsTests: XCTestCase {
    private let june = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
    private let july = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!

    private func report(
        monthStart: Date? = nil,
        isMonthToDate: Bool = true,
        sessions: Int = 12,
        sets: Int = 140,
        volumeKilograms: Double = 12_300,
        prCount: Int = 2,
        averageRPE: Double? = 7.4,
        sessionsDelta: Int? = 2,
        volumeDeltaPercent: Double? = 12,
        prDelta: Int? = 1,
        comparisonLabel: String? = "vs this point in June"
    ) -> MonthlyReport {
        MonthlyReport(
            monthStart: monthStart ?? july,
            monthLabel: "July 2026",
            isMonthToDate: isMonthToDate,
            sessions: sessions,
            sets: sets,
            volumeKilograms: volumeKilograms,
            prCount: prCount,
            averageRPE: averageRPE,
            topMuscleGroups: [.init(category: .chest, sets: 24)],
            sessionsDelta: sessionsDelta,
            volumeDeltaPercent: volumeDeltaPercent,
            prDelta: prDelta,
            comparisonLabel: comparisonLabel,
            bodyweightStartKilograms: nil,
            bodyweightEndKilograms: nil,
            bodyweightDeltaKilograms: nil,
            bodyweightMeasurements: 0
        )
    }

    // MARK: - Number grounding

    func testSentencesWhoseNumbersAreAllInTheFactsSurvive() {
        let facts = MonthlyReportPhrasing.promptFacts(for: report(), unit: .kg)
        let lines = InsightValidator.validated([
            "You logged 12 sessions and 140 sets in July.",
            "Volume climbed 12% to 12.3t vs this point in June.",
            "Chest led with 24 sets at an average effort of 7.4."
        ], facts: facts, unit: .kg)

        XCTAssertEqual(lines?.count, 3)
    }

    func testSentenceWithAnInventedNumberIsDropped() {
        let facts = MonthlyReportPhrasing.promptFacts(for: report(), unit: .kg)
        let lines = InsightValidator.validated([
            "You logged 12 sessions and 140 sets in July.",
            "Chest led with 24 sets.",
            "That averages out to 3 sessions a week."
        ], facts: facts, unit: .kg)

        XCTAssertEqual(lines, [
            "You logged 12 sessions and 140 sets in July.",
            "Chest led with 24 sets."
        ])
    }

    func testSpelledSmallNumbersMustBeGroundedToo() {
        let facts = MonthlyReportPhrasing.promptFacts(for: report(), unit: .kg)
        XCTAssertTrue(InsightValidator.numbersAreGrounded("You set two personal records.", in: InsightValidator.quantities(in: facts)))
        XCTAssertFalse(InsightValidator.numbersAreGrounded("You trained five days in a row.", in: InsightValidator.quantities(in: facts)))
    }

    func testFormattingToleranceMatchesTheShownPrecision() {
        let allowed = InsightValidator.quantities(in: "Volume: 12.30t, 1,200 lb, 27.1k lb, RPE 7.4, volume +12%")

        // Same number, different spelling.
        XCTAssertTrue(InsightValidator.numbersAreGrounded("12.3t moved", in: allowed))
        XCTAssertTrue(InsightValidator.numbersAreGrounded("12.3 tonnes moved", in: allowed))
        XCTAssertTrue(InsightValidator.numbersAreGrounded("1200 lb total", in: allowed))
        XCTAssertTrue(InsightValidator.numbersAreGrounded("27,100 lb total", in: allowed))
        XCTAssertTrue(InsightValidator.numbersAreGrounded("up 12 percent", in: allowed))
        // Coarser rounding of a shown value is fine…
        XCTAssertTrue(InsightValidator.numbersAreGrounded("effort around 7", in: allowed))
        // …inventing precision or drifting is not.
        XCTAssertFalse(InsightValidator.numbersAreGrounded("effort of 7.45", in: allowed))
        XCTAssertFalse(InsightValidator.numbersAreGrounded("up 13%", in: allowed))
        XCTAssertFalse(InsightValidator.numbersAreGrounded("27,600 lb total", in: allowed))
        XCTAssertFalse(InsightValidator.numbersAreGrounded("12.4t moved", in: allowed))
    }

    func testTrailingZerosCarryNoExtraPrecision() {
        let allowed = InsightValidator.quantities(in: "RPE 7.0")
        XCTAssertTrue(InsightValidator.numbersAreGrounded("RPE 7", in: allowed))
        XCTAssertTrue(InsightValidator.numbersAreGrounded("RPE 7.00", in: allowed))
    }

    // MARK: - Health guardrail

    func testBlocklistDropsHealthAndAdviceSentences() {
        XCTAssertTrue(InsightValidator.isBlocked("Watch for injury with volume this high.", unit: .kg))
        XCTAssertTrue(InsightValidator.isBlocked("You should add a rest day.", unit: .kg))
        XCTAssertTrue(InsightValidator.isBlocked("Pair this with a calorie surplus.", unit: .kg))
        XCTAssertTrue(InsightValidator.isBlocked("Great month to lose weight.", unit: .kg))
        XCTAssertTrue(InsightValidator.isBlocked("Signs of overtraining are worth noting.", unit: .kg))
        XCTAssertFalse(InsightValidator.isBlocked("You logged 12 sessions in July.", unit: .kg))
    }

    func testPoundUsersNeverSeeTons() {
        XCTAssertTrue(InsightValidator.isBlocked("You moved 27 tons.", unit: .lb))
        XCTAssertFalse(InsightValidator.isBlocked("You moved 12.3 tonnes.", unit: .kg))
    }

    func testFewerThanTwoSurvivorsMeansFallback() {
        let facts = MonthlyReportPhrasing.promptFacts(for: report(), unit: .kg)
        let lines = InsightValidator.validated([
            "You logged 12 sessions in July.",
            "You should see a doctor about 12 sessions.",
            "That is 99 sets."
        ], facts: facts, unit: .kg)

        XCTAssertNil(lines)
    }

    func testDuplicatesAndBlanksDoNotCountTowardTheMinimum() {
        let facts = MonthlyReportPhrasing.promptFacts(for: report(), unit: .kg)
        let lines = InsightValidator.validated([
            "You logged 12 sessions in July.",
            "  You logged 12 sessions in July.  ",
            "   "
        ], facts: facts, unit: .kg)

        XCTAssertNil(lines)
    }

    func testTemplateSentencesPassTheirOwnValidator() {
        for unit in WeightUnit.allCases {
            for base in [report(), report(sessionsDelta: nil, volumeDeltaPercent: nil, prDelta: nil, comparisonLabel: nil)] {
                let facts = MonthlyReportPhrasing.promptFacts(for: base, unit: unit)
                let lines = MonthlyReportPhrasing.fallbackInsights(for: base, unit: unit)
                XCTAssertEqual(InsightValidator.validated(lines, facts: facts, unit: unit), lines, "\(unit): \(lines)")
            }
        }
    }

    // MARK: - Units

    func testVolumeTextRespectsTheUnit() {
        XCTAssertEqual(MonthlyReportPhrasing.volumeText(kilograms: 850, unit: .kg), "850 kg")
        XCTAssertEqual(MonthlyReportPhrasing.volumeText(kilograms: 12_300, unit: .kg), "12.3t")
        XCTAssertEqual(MonthlyReportPhrasing.volumeText(kilograms: 500, unit: .lb), "1,102 lb")
        XCTAssertEqual(MonthlyReportPhrasing.volumeText(kilograms: 12_300, unit: .lb), "27.1k lb")
        // Legacy metric entry point is unchanged.
        XCTAssertEqual(MonthlyReportPhrasing.volumeText(kilograms: 12_300), "12.3t")
    }

    func testPoundFactsAndFallbackUsePounds() {
        let base = report(sessionsDelta: nil, volumeDeltaPercent: nil, prDelta: nil, comparisonLabel: nil)
        let facts = MonthlyReportPhrasing.promptFacts(for: base, unit: .lb)
        XCTAssertTrue(facts.contains("Total volume: 27.1k lb"))
        XCTAssertFalse(facts.contains("12.3t"))

        let first = MonthlyReportPhrasing.fallbackInsights(for: base, unit: .lb).first ?? ""
        XCTAssertTrue(first.contains("27.1k lb"), first)
        XCTAssertFalse(first.lowercased().contains("ton"), first)
    }

    // MARK: - Fallback wording

    func testInProgressMonthComparesAtThisPoint() {
        let lines = MonthlyReportPhrasing.fallbackInsights(for: report(isMonthToDate: true, comparisonLabel: "vs this point in June"))
        XCTAssertTrue(lines.contains("That's 2 more sessions than at this point in June."), "\(lines)")
    }

    func testCompletedMonthComparesTheWholeMonth() {
        let lines = MonthlyReportPhrasing.fallbackInsights(for: report(isMonthToDate: false, sessionsDelta: 1, comparisonLabel: "vs June"))
        XCTAssertTrue(lines.contains("That's 1 more session than in June."), "\(lines)")
        XCTAssertFalse(lines.joined().contains("at this point"))
    }

    // MARK: - Caching + provenance

    func testCacheKeyTracksMonthUnitAndFacts() {
        let base = TrainingInsights.cacheKey(for: report(), unit: .lb)

        XCTAssertEqual(TrainingInsights.cacheKey(for: report(), unit: .lb), base)
        XCTAssertNotEqual(TrainingInsights.cacheKey(for: report(), unit: .kg), base)
        XCTAssertNotEqual(TrainingInsights.cacheKey(for: report(monthStart: june), unit: .lb), base)
        XCTAssertNotEqual(TrainingInsights.cacheKey(for: report(sets: 141), unit: .lb), base)
    }

    func testFooterSaysWhoWroteTheInsights() {
        XCTAssertTrue(MonthlyReportSheet.provenanceText(for: .appleIntelligence).contains("Apple Intelligence"))
        XCTAssertFalse(MonthlyReportSheet.provenanceText(for: .template).contains("Apple Intelligence"))
        XCTAssertFalse(MonthlyReportSheet.provenanceText(for: nil).contains("Apple Intelligence"))
    }
}
