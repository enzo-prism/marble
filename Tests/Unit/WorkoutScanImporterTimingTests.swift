import SwiftData
import XCTest
@testable import marble

/// Pins how import timing resolves: the workout-level date stamps every set unless
/// a set carries its own `performedAt` override.
@MainActor
final class WorkoutScanImporterTimingTests: MarbleTestCase {

    private func date(_ day: Int, hour: Int) -> Date {
        Self.stableCalendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
    }

    func testWorkoutDateStampsAllSetsWithoutOverrides() throws {
        let context = makeInMemoryContext()
        let workoutDate = date(20, hour: 9)
        let draft = ParsedWorkoutDraft(
            performedAt: workoutDate,
            title: "Timing test",
            exercises: [
                ParsedExerciseDraft(name: "Squat", sets: [
                    ParsedSetDraft(weight: 225, reps: 5),
                    ParsedSetDraft(weight: 225, reps: 5)
                ])
            ]
        )

        try WorkoutScanImporter.import(draft, externalID: "timing-1", source: .textEntry, in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.performedAt == workoutDate })
    }

    func testPerSetOverrideWinsOverWorkoutDate() throws {
        let context = makeInMemoryContext()
        let workoutDate = date(20, hour: 9)
        let overrideDate = date(21, hour: 18)
        let draft = ParsedWorkoutDraft(
            performedAt: workoutDate,
            title: "Timing test",
            exercises: [
                ParsedExerciseDraft(name: "Bench", sets: [
                    ParsedSetDraft(weight: 185, reps: 8),
                    ParsedSetDraft(weight: 185, reps: 8, performedAt: overrideDate)
                ])
            ]
        )

        try WorkoutScanImporter.import(draft, externalID: "timing-2", source: .textEntry, in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>()).sorted { $0.performedAt < $1.performedAt }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].performedAt, workoutDate)
        XCTAssertEqual(entries[1].performedAt, overrideDate)

        // No override precedes the workout date, so the ledger keeps it.
        let ledger = try XCTUnwrap(context.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(ledger.workoutDate, workoutDate)
    }

    func testLedgerDateIsEarliestEffectiveSetDate() throws {
        let context = makeInMemoryContext()
        let workoutDate = date(20, hour: 9)
        let earlierOverride = date(18, hour: 7)
        let draft = ParsedWorkoutDraft(
            performedAt: workoutDate,
            title: "Timing test",
            exercises: [
                ParsedExerciseDraft(name: "Deadlift", sets: [
                    ParsedSetDraft(weight: 315, reps: 3),
                    ParsedSetDraft(weight: 315, reps: 3, performedAt: earlierOverride)
                ])
            ]
        )

        try WorkoutScanImporter.import(draft, externalID: "timing-3", source: .textEntry, in: context)

        let ledger = try XCTUnwrap(context.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(ledger.workoutDate, earlierOverride)
        XCTAssertEqual(ledger.setsImported, 2)
    }
}
