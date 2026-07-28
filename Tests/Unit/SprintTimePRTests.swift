import Foundation
import SwiftData
import XCTest
@testable import marble

/// The sprint-time PR trail: fastest recorded time at the same exercise AND
/// the same distance, precise tenths preferred over legacy whole seconds.
@MainActor
final class SprintTimePRTests: MarbleTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var exercise: Exercise!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = PersistenceController.makeContainer(useInMemory: true)
        context = ModelContext(container)
        exercise = Exercise(
            name: "Sprint",
            category: .run,
            metrics: ExerciseMetricsProfile(weight: .none, reps: .none, distance: .required, durationSeconds: .required),
            defaultRestSeconds: 60
        )
        context.insert(exercise)
    }

    override func tearDownWithError() throws {
        exercise = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private func entry(daysAgo: Int, meters: Double, seconds: Int) -> SetEntry {
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400),
            distance: meters,
            distanceUnit: .meters,
            durationSeconds: seconds,
            restAfterSeconds: 60
        )
        context.insert(entry)
        return entry
    }

    func testFastestTimeTrailBadgesBaselineAndEveryImprovementPerDistance() {
        let first60 = entry(daysAgo: 3, meters: 60, seconds: 9)
        let slower60 = entry(daysAgo: 2, meters: 60, seconds: 10)
        let faster60 = entry(daysAgo: 1, meters: 60, seconds: 8)
        let first150 = entry(daysAgo: 2, meters: 150, seconds: 21)

        let entries = [first60, slower60, faster60, first150]
        let times = [
            first60.id: 90,
            slower60.id: 100,
            faster60.id: 80,
            first150.id: 210
        ]
        let badges = PersonalRecords.sprintTimeBadges(for: entries, sprintTimes: times)

        XCTAssertEqual(badges[first60.id], .sprintTime, "First timed rep at a distance is the baseline record")
        XCTAssertNil(badges[slower60.id])
        XCTAssertEqual(badges[faster60.id], .sprintTime)
        XCTAssertEqual(badges[first150.id], .sprintTime, "Each distance keeps its own trail")
    }

    func testTenthsBreakWholeSecondTies() {
        let first = entry(daysAgo: 2, meters: 60, seconds: 9)
        let tenthFaster = entry(daysAgo: 1, meters: 60, seconds: 9)

        let badges = PersonalRecords.sprintTimeBadges(
            for: [first, tenthFaster],
            sprintTimes: [first.id: 90, tenthFaster.id: 88]
        )
        XCTAssertEqual(badges[tenthFaster.id], .sprintTime, "8.8 beats 9.0 even though both round to 9 s")
    }

    func testSprintTimesPrefersDetailTenthsOverLegacySeconds() {
        let legacy = entry(daysAgo: 2, meters: 60, seconds: 9)
        let precise = entry(daysAgo: 1, meters: 60, seconds: 9)

        let snapshot = SprintGoalSnapshot(
            setEntryID: legacy.id,
            exerciseID: exercise.id,
            distance: 60,
            distanceUnit: .meters,
            repetitionNumber: 1,
            repetitionCount: 4,
            targetLowerSeconds: 9,
            targetUpperSeconds: 9
        )
        let detail = SprintRepDetail(
            setEntryID: precise.id,
            durationTenths: 87,
            targetLowerTenths: 90,
            targetUpperTenths: 90
        )

        let times = PersonalRecords.sprintTimes(
            entries: [legacy, precise],
            sprintGoals: [legacy.id: snapshot],
            sprintDetails: [precise.id: detail]
        )
        XCTAssertEqual(times[legacy.id], 90, "Legacy sprint rep: whole seconds ×10")
        XCTAssertEqual(times[precise.id], 87, "Detailed rep: exact tenths")
    }

    func testNonSprintTimedWorkIsExcluded() {
        let plank = entry(daysAgo: 1, meters: 0, seconds: 75)
        let times = PersonalRecords.sprintTimes(entries: [plank], sprintGoals: [:], sprintDetails: [:])
        XCTAssertTrue(times.isEmpty, "No snapshot and no detail means not a sprint")
    }

    func testBadgesMergeSprintAndStrengthTrails() {
        let sprintEntry = entry(daysAgo: 1, meters: 60, seconds: 9)
        let badges = PersonalRecords.badges(
            for: [sprintEntry],
            sprintTimes: [sprintEntry.id: 90]
        )
        XCTAssertEqual(badges[sprintEntry.id], .sprintTime)
        XCTAssertEqual(PersonalRecordBadge.sprintTime.shortTitle, "Fastest")
        XCTAssertEqual(PersonalRecordBadge.sprintTime.accessibilityDescription, "Personal record: fastest time")
    }

    func testStopwatchEngineRoundTrips() {
        var engine = SprintStopwatchEngine()
        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(engine.stop(at: now))

        engine.start(at: now)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.elapsedTenths(at: now.addingTimeInterval(14.8)), 148)
        XCTAssertEqual(engine.stop(at: now.addingTimeInterval(14.84)), 148)
        XCTAssertFalse(engine.isRunning)

        // Clock going backwards yields nil, never a negative time.
        engine.start(at: now)
        XCTAssertNil(engine.stop(at: now.addingTimeInterval(-5)))

        // Implausibly long "reps" (left running overnight) are rejected.
        engine.start(at: now)
        XCTAssertNil(engine.stop(at: now.addingTimeInterval(4_000)))
    }
}
