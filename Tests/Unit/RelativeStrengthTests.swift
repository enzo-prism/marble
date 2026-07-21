import Foundation
import XCTest
@testable import marble

/// DOTS and the nearest-in-time bodyweight lookup behind the Trends
/// relative-strength line. Pure math — no store, no HealthKit, no views.
///
/// Reference values below were computed from the published DOTS polynomial
/// (BVDK / Tim Konertz; same coefficients as OpenPowerlifting's
/// `modules/coefficients/src/dots.rs` and OpenLifter):
///
///   coefficient = 500 / (A·x⁴ + B·x³ + C·x² + D·x + E),  x = bodyweight kg
///   DOTS        = total kg × coefficient
final class RelativeStrengthTests: MarbleTestCase {
    private let tolerance = 0.01
    /// Fixed GMT calendar so `bodyweightAgeDays` can't drift across a DST edge.
    private let calendar = MarbleTestCase.stableCalendar

    // MARK: - Golden values

    /// The canonical sanity check: a 100 kg lifter moving a 100 kg total scores
    /// ~61.55 on the men's curve.
    func testDotsMatchesReferenceValueForOneHundredKilogramLifter() {
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 100, bodyweightKilograms: 100, isFemale: false),
            61.5516,
            accuracy: tolerance
        )
    }

    /// An elite raw men's 93 kg total.
    func testDotsMatchesReferenceValueForMaleMiddleweightTotal() {
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 700, bodyweightKilograms: 93, isFemale: false),
            445.3758,
            accuracy: tolerance
        )
    }

    func testDotsMatchesReferenceValueForMaleEightyThreeKilogramTotal() {
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 500, bodyweightKilograms: 83, isFemale: false),
            337.5437,
            accuracy: tolerance
        )
    }

    /// The women's curve is a genuinely different polynomial, not a scale
    /// factor on the men's — same inputs must give a different score.
    func testDotsUsesDistinctFemaleCoefficients() {
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 300, bodyweightKilograms: 60, isFemale: true),
            174.0330,
            accuracy: tolerance
        )
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 100, bodyweightKilograms: 100, isFemale: true),
            46.9171,
            accuracy: tolerance
        )
        XCTAssertNotEqual(
            LifterAnalytics.dots(totalKilograms: 100, bodyweightKilograms: 100, isFemale: true),
            LifterAnalytics.dots(totalKilograms: 100, bodyweightKilograms: 100, isFemale: false),
            accuracy: 1.0
        )
    }

    /// DOTS is linear in the total at a fixed bodyweight — doubling the lift
    /// doubles the score.
    func testDotsIsLinearInTotal() {
        let single = LifterAnalytics.dots(totalKilograms: 150, bodyweightKilograms: 80, isFemale: false)
        let double = LifterAnalytics.dots(totalKilograms: 300, bodyweightKilograms: 80, isFemale: false)
        XCTAssertEqual(double, single * 2, accuracy: tolerance)
    }

    /// The same lift is worth more at a lighter bodyweight — the whole point of
    /// the metric.
    func testDotsRewardsLighterBodyweightForTheSameLift() {
        let lighter = LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 70, isFemale: false)
        let heavier = LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 110, isFemale: false)
        XCTAssertGreaterThan(lighter, heavier)
    }

    /// Outside the fitted range the quartic turns over and produces nonsense,
    /// so bodyweight is clamped exactly as the reference implementations do.
    func testDotsClampsBodyweightToTheFittedRange() {
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 250, isFemale: false),
            LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 210, isFemale: false),
            accuracy: tolerance,
            "Men's curve clamps at 210 kg"
        )
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 12, isFemale: false),
            LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 40, isFemale: false),
            accuracy: tolerance,
            "Both curves clamp at 40 kg"
        )
        XCTAssertEqual(
            LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 400, isFemale: true),
            LifterAnalytics.dots(totalKilograms: 200, bodyweightKilograms: 150, isFemale: true),
            accuracy: tolerance,
            "Women's curve clamps at 150 kg"
        )
    }

    func testDotsReturnsZeroForNonPositiveInputs() {
        XCTAssertEqual(LifterAnalytics.dots(totalKilograms: 0, bodyweightKilograms: 80, isFemale: false), 0)
        XCTAssertEqual(LifterAnalytics.dots(totalKilograms: 100, bodyweightKilograms: 0, isFemale: false), 0)
        XCTAssertEqual(LifterAnalytics.dots(totalKilograms: -100, bodyweightKilograms: 80, isFemale: false), 0)
    }

    // MARK: - Nearest bodyweight lookup

    private func day(_ offset: Int, from reference: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        reference.addingTimeInterval(Double(offset) * 86_400)
    }

    func testNearestBodyweightPicksTheClosestMeasurement() {
        let target = day(0)
        let samples = [
            LifterAnalytics.BodyweightSample(date: day(-10), kilograms: 80),
            LifterAnalytics.BodyweightSample(date: day(-2), kilograms: 82),
            LifterAnalytics.BodyweightSample(date: day(9), kilograms: 84)
        ]
        XCTAssertEqual(LifterAnalytics.nearestBodyweight(to: target, in: samples)?.kilograms, 82)
    }

    /// Lookback and lookahead are symmetric: a weigh-in three days *after* a
    /// lift is still the honest nearest measurement.
    func testNearestBodyweightLooksForwardAsWellAsBack() {
        let target = day(0)
        let samples = [
            LifterAnalytics.BodyweightSample(date: day(-8), kilograms: 80),
            LifterAnalytics.BodyweightSample(date: day(3), kilograms: 85)
        ]
        XCTAssertEqual(LifterAnalytics.nearestBodyweight(to: target, in: samples)?.kilograms, 85)
    }

    func testNearestBodyweightReturnsNilOutsideTheFourteenDayWindow() {
        XCTAssertEqual(LifterAnalytics.bodyweightLookupWindowDays, 14)
        let samples = [LifterAnalytics.BodyweightSample(date: day(-15), kilograms: 80)]
        XCTAssertNil(
            LifterAnalytics.nearestBodyweight(to: day(0), in: samples),
            "A measurement older than the window must be refused, not stretched"
        )
    }

    func testNearestBodyweightAcceptsTheWindowBoundary() {
        let samples = [LifterAnalytics.BodyweightSample(date: day(-14), kilograms: 80)]
        XCTAssertEqual(LifterAnalytics.nearestBodyweight(to: day(0), in: samples)?.kilograms, 80)
    }

    func testNearestBodyweightIsEmptySafe() {
        XCTAssertNil(LifterAnalytics.nearestBodyweight(to: day(0), in: []))
    }

    /// Equidistant measurements resolve to the more recent one, so the result
    /// does not depend on array order.
    func testNearestBodyweightResolvesTiesToTheMoreRecentSample() {
        let target = day(0)
        let earlier = LifterAnalytics.BodyweightSample(date: day(-4), kilograms: 80)
        let later = LifterAnalytics.BodyweightSample(date: day(4), kilograms: 90)

        XCTAssertEqual(LifterAnalytics.nearestBodyweight(to: target, in: [earlier, later])?.kilograms, 90)
        XCTAssertEqual(LifterAnalytics.nearestBodyweight(to: target, in: [later, earlier])?.kilograms, 90)
    }

    // MARK: - Series

    private func series(points: [(offset: Int, kilograms: Double)]) -> LifterAnalytics.OneRepMaxSeries {
        let mapped = points.map { point in
            LifterAnalytics.OneRepMaxPoint(
                date: day(point.offset),
                kilograms: point.kilograms,
                displayValue: point.kilograms,
                bestSetSummary: "\(Int(point.kilograms)) kg × 1"
            )
        }
        return LifterAnalytics.OneRepMaxSeries(
            points: mapped,
            best: mapped.max(by: { $0.kilograms < $1.kilograms }),
            displayUnit: .kg
        )
    }

    func testRelativeStrengthReturnsNilWithoutAnyBodyweightData() {
        XCTAssertNil(
            LifterAnalytics.relativeStrength(
                oneRepMax: series(points: [(0, 140)]),
                bodyweights: [],
                isFemale: false,
                calendar: calendar
            ),
            "No bodyweight data means the metric is omitted, never estimated"
        )
    }

    /// Bodyweight exists, but not within reach of any training day — still nil.
    func testRelativeStrengthReturnsNilWhenEveryBodyweightIsOutsideTheWindow() {
        XCTAssertNil(
            LifterAnalytics.relativeStrength(
                oneRepMax: series(points: [(0, 140), (2, 145)]),
                bodyweights: [LifterAnalytics.BodyweightSample(date: day(-40), kilograms: 82)],
                isFemale: false,
                calendar: calendar
            )
        )
    }

    func testRelativeStrengthScoresEachDayAgainstItsNearestBodyweight() throws {
        let summary = try XCTUnwrap(LifterAnalytics.relativeStrength(
            oneRepMax: series(points: [(0, 140), (10, 150)]),
            bodyweights: [
                LifterAnalytics.BodyweightSample(date: day(0), kilograms: 80),
                LifterAnalytics.BodyweightSample(date: day(10), kilograms: 85)
            ],
            isFemale: false,
            calendar: calendar
        ))

        XCTAssertEqual(summary.points.count, 2)
        XCTAssertEqual(summary.points[0].bodyweightKilograms, 80)
        XCTAssertEqual(summary.points[1].bodyweightKilograms, 85)
        XCTAssertEqual(
            summary.points[0].dots,
            LifterAnalytics.dots(totalKilograms: 140, bodyweightKilograms: 80, isFemale: false),
            accuracy: tolerance
        )
        XCTAssertEqual(summary.latest?.date, day(10))
    }

    /// Days that can't be scored drop out; the days that can still report.
    func testRelativeStrengthSkipsOnlyTheUnscorableDays() throws {
        let summary = try XCTUnwrap(LifterAnalytics.relativeStrength(
            oneRepMax: series(points: [(0, 140), (60, 150)]),
            bodyweights: [LifterAnalytics.BodyweightSample(date: day(1), kilograms: 80)],
            isFemale: false,
            calendar: calendar
        ))

        XCTAssertEqual(summary.points.map(\.date), [day(0)])
        XCTAssertEqual(summary.points.first?.bodyweightAgeDays, 1)
    }

    /// `best` is the highest score, which is not necessarily the heaviest lift:
    /// a lighter lift at a much lighter bodyweight can outscore it.
    func testRelativeStrengthBestIsHighestScoreNotHeaviestLift() throws {
        let summary = try XCTUnwrap(LifterAnalytics.relativeStrength(
            oneRepMax: series(points: [(0, 150), (20, 155)]),
            bodyweights: [
                LifterAnalytics.BodyweightSample(date: day(0), kilograms: 70),
                LifterAnalytics.BodyweightSample(date: day(20), kilograms: 110)
            ],
            isFemale: false,
            calendar: calendar
        ))

        XCTAssertEqual(summary.best?.date, day(0))
        XCTAssertEqual(summary.latest?.date, day(20))
        XCTAssertGreaterThan(
            try XCTUnwrap(summary.best).dots,
            try XCTUnwrap(summary.latest).dots
        )
    }

    func testRelativeStrengthRecordsBodyweightAge() throws {
        let summary = try XCTUnwrap(LifterAnalytics.relativeStrength(
            oneRepMax: series(points: [(0, 140)]),
            bodyweights: [LifterAnalytics.BodyweightSample(date: day(-6), kilograms: 80)],
            isFemale: false,
            calendar: calendar
        ))
        XCTAssertEqual(summary.points.first?.bodyweightAgeDays, 6)
        XCTAssertEqual(summary.points.first?.bodyweightMeasuredAt, day(-6))
    }
}
