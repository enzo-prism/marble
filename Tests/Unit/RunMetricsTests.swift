import XCTest
import SwiftData
@testable import marble

final class RunMetricsTests: MarbleTestCase {
    func testMetersPerUnitConversions() {
        XCTAssertEqual(DistanceUnit.meters.meters(from: 200), 200)
        XCTAssertEqual(DistanceUnit.kilometers.meters(from: 5), 5000)
        XCTAssertEqual(DistanceUnit.miles.meters(from: 6), 9656.064, accuracy: 0.001)
        XCTAssertEqual(DistanceUnit.yards.meters(from: 100), 91.44, accuracy: 0.001)
        XCTAssertEqual(DistanceUnit.feet.meters(from: 100), 30.48, accuracy: 0.001)
    }

    func testPaceReferenceUnits() {
        XCTAssertEqual(DistanceUnit.meters.paceReferenceUnit, .kilometers)
        XCTAssertEqual(DistanceUnit.kilometers.paceReferenceUnit, .kilometers)
        XCTAssertEqual(DistanceUnit.miles.paceReferenceUnit, .miles)
        XCTAssertEqual(DistanceUnit.yards.paceReferenceUnit, .miles)
        XCTAssertEqual(DistanceUnit.feet.paceReferenceUnit, .miles)
    }

    func testPaceTextForSprint() {
        // 200 m in 28 s = 140 s per km.
        XCTAssertEqual(
            Formatters.paceText(distance: 200, unit: .meters, durationSeconds: 28),
            "2:20 /km"
        )
    }

    func testPaceTextForLongRuns() {
        // 5 K in 25 minutes = 5:00 per km.
        XCTAssertEqual(
            Formatters.paceText(distance: 5, unit: .kilometers, durationSeconds: 1500),
            "5:00 /km"
        )
        // 6 mi in exactly one hour = 10:00 per mile.
        XCTAssertEqual(
            Formatters.paceText(distance: 6, unit: .miles, durationSeconds: 3600),
            "10:00 /mi"
        )
    }

    func testPaceTextUndefinedCases() {
        XCTAssertNil(Formatters.paceText(distance: 0, unit: .kilometers, durationSeconds: 600))
        XCTAssertNil(Formatters.paceText(distance: 5, unit: .kilometers, durationSeconds: 0))
    }

    func testFormattedDurationWithHours() {
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 3600), "1h")
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 4500), "1h 15m")
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 3725), "1h 2m 5s")
        // Sub-hour behavior is unchanged.
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 95), "1m 35s")
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 28), "28s")
    }

    func testFormattedClockDurationWithHours() {
        XCTAssertEqual(DateHelper.formattedClockDuration(seconds: 3725), "1:02:05")
        XCTAssertEqual(DateHelper.formattedClockDuration(seconds: 1500), "25:00")
        XCTAssertEqual(DateHelper.formattedClockDuration(seconds: 28), "0:28")
    }

    func testRunCategoryDisplay() {
        XCTAssertEqual(ExerciseCategory.run.displayName, "Run")
        XCTAssertFalse(ExerciseCategory.run.symbolName.isEmpty)
        XCTAssertFalse(ExerciseCategory.run.emojiSuggestions.isEmpty)
    }

    func testSeedDataIncludesRun() {
        let context = makeInMemoryContext()
        SeedData.seedExercises(in: context)
        let exercises: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        guard let run = exercises.first(where: { $0.name == "Run" }) else {
            XCTFail("Expected a seeded Run exercise")
            return
        }
        XCTAssertEqual(run.category, .run)
        XCTAssertEqual(run.preferredDistanceUnit, .kilometers)
        XCTAssertTrue(run.metrics.distanceIsRequired)
        XCTAssertTrue(run.metrics.durationIsRequired)
        XCTAssertFalse(run.metrics.usesWeight)
        XCTAssertFalse(run.metrics.usesReps)
    }
}
