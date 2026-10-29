import SwiftData
import XCTest
@testable import marble

/// Pins how the Add tab's paste/type → review → log flow resolves workout dates
/// and times, in real time zones rather than only the suite's GMT default.
///
/// Policy under test: a date is a *local* calendar day carrying the reference's
/// time of day (the reference instant itself when the day is today); a date
/// written without a year is never in the future; slash dates are not read out
/// of rep notation; and the model path's `dateText` resolves with the same rules.
@MainActor
final class ImportDateTimeZoneTests: MarbleTestCase {

    private static let zones = [
        "America/Los_Angeles", "Pacific/Honolulu", "Europe/London",
        "Asia/Tokyo", "Pacific/Auckland", "Pacific/Kiritimati",
    ]

    /// Runs `body` with `zone` as the process default time zone, so
    /// `Calendar.current` (which the parser uses) resolves in that zone.
    private func inZone(_ identifier: String, _ body: (Calendar) throws -> Void) rethrows {
        let previous = TimeZone.ReferenceType.default
        let zone = TimeZone(identifier: identifier)!
        TimeZone.ReferenceType.default = zone
        defer { TimeZone.ReferenceType.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        try body(calendar)
    }

    private func local(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func assertLocal(
        _ date: Date?, _ calendar: Calendar,
        _ year: Int, _ month: Int, _ day: Int, hour: Int? = nil, minute: Int? = nil,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let date else {
            return XCTFail("expected \(year)-\(month)-\(day), got nil. \(message)", file: file, line: line)
        }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([c.year, c.month, c.day], [year, month, day], message, file: file, line: line)
        if let hour { XCTAssertEqual(c.hour, hour, "hour. \(message)", file: file, line: line) }
        if let minute { XCTAssertEqual(c.minute, minute, "minute. \(message)", file: file, line: line) }
    }

    // MARK: - Local day, reference time of day

    /// Explicit dates used to be pinned to 12:00 UTC: 5 AM in California and the
    /// *next* day from UTC+12 eastward (Auckland, Kiritimati).
    func testExplicitDateIsTheLocalDayAtTheReferenceTimeInEveryZone() {
        for zone in Self.zones {
            inZone(zone) { calendar in
                let reference = local(calendar, 2026, 7, 23, 18, 45)
                for input in ["7/22 Bench 3x8", "2026-07-22\nBench 3x8", "July 22\nBench 3x8", "22 July\nBench 3x8"] {
                    let draft = HandwrittenWorkoutParser.parse(input, referenceDate: reference)
                    assertLocal(draft.performedAt, calendar, 2026, 7, 22, hour: 18, minute: 45, "\(zone): \(input)")
                }
            }
        }
    }

    /// A date that names today is the reference instant itself — never later.
    /// (A Pacific user pasting "9/26" before 5 AM used to get a future set.)
    func testDateNamingTodayIsTheReferenceInstant() {
        for zone in Self.zones {
            inZone(zone) { calendar in
                for hour in [0, 4, 12, 23] {
                    let reference = local(calendar, 2026, 9, 26, hour, 10)
                    let draft = HandwrittenWorkoutParser.parse("9/26\nBench 3x8", referenceDate: reference)
                    XCTAssertEqual(draft.performedAt, reference, "\(zone) at \(hour):10")
                }
            }
        }
    }

    // MARK: - Year inference never produces future workouts

    func testYearlessDatesResolveToTheMostRecentPastOccurrence() {
        inZone("America/Los_Angeles") { calendar in
            let jan2 = local(calendar, 2027, 1, 2, 9)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("12/30", referenceDate: jan2), calendar, 2026, 12, 30)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("Dec 30", referenceDate: jan2), calendar, 2026, 12, 30)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("1/2", referenceDate: jan2), calendar, 2027, 1, 2)

            // Evening of Dec 31 in LA is already next year in UTC; the local
            // year must win.
            let dec31Evening = local(calendar, 2025, 12, 31, 20)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("12/30", referenceDate: dec31Evening), calendar, 2025, 12, 30)
            XCTAssertEqual(HandwrittenWorkoutDateParser.resolveDateText("12/31", referenceDate: dec31Evening), dec31Evening)

            // Tomorrow is last year's date, for slash and month-name forms alike.
            let sep26 = local(calendar, 2026, 9, 26, 9)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("9/27", referenceDate: sep26), calendar, 2025, 9, 27)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("Sept 27", referenceDate: sep26), calendar, 2025, 9, 27)
        }
    }

    func testImpossibleDatesAreRejectedNotRolledOver() {
        inZone("America/Los_Angeles") { calendar in
            let reference = local(calendar, 2026, 9, 26, 9)
            XCTAssertNil(HandwrittenWorkoutDateParser.resolveDateText("2/30", referenceDate: reference))
            XCTAssertNil(HandwrittenWorkoutDateParser.resolveDateText("2026-02-30", referenceDate: reference))
            XCTAssertNil(HandwrittenWorkoutDateParser.resolveDateText("7/22/202", referenceDate: reference))
            XCTAssertNil(HandwrittenWorkoutDateParser.resolveDateText("2026-02-30T10:00:00", referenceDate: reference))
            XCTAssertNil(HandwrittenWorkoutDateParser.resolveDateText("2026-02-30T10:00:00Z", referenceDate: reference))
        }
    }

    // MARK: - Rep notation is not a date

    func testRepNotationIsNeverReadAsADate() {
        inZone("America/Los_Angeles") { calendar in
            let reference = local(calendar, 2026, 9, 26, 21, 30)

            // A 3-rung ladder used to become 2010-10-10 and lose the exercise.
            let ladder = HandwrittenWorkoutParser.parse("Bench 135x10/10/10", referenceDate: reference)
            XCTAssertNil(ladder.performedAt)
            XCTAssertEqual(ladder.exercises.map(\.name), ["Bench"])
            XCTAssertEqual(ladder.exercises.first?.sets.map(\.reps), [10, 10, 10])

            for input in [
                "Pull-ups 10/8", "Pull ups 10/8", "Dips 12/10", "Chins 10/8 bw", "Lunges 12/12",
                "Curl 12/10/10 @ 25", "12/10/10 @ 25", "10/10/10", "Legs 12/12/10", "Bench 3x12/10/10",
                "Run 3/4 mile", "Bike 1/2 hr", "Row at 3/4 effort", "Last set bench 10/8",
            ] {
                XCTAssertNil(HandwrittenWorkoutParser.parse(input, referenceDate: reference).performedAt, input)
                XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader(input, referenceDate: reference), input)
            }

            // "Pull-ups 10/8" used to split the paste into a second, future-dated
            // session.
            let paste = "Bench 3x8 @ 185\nPull-ups 10/8\nSquat 5x5"
            XCTAssertEqual(WorkoutSessionSegmenter.segments(from: paste, referenceDate: reference).count, 1)
        }
    }

    /// After a movement name the numbers' shape decides, whatever the date:
    /// rep pairs hold or drop ("12/10", "12/12"), a titled workout's date rises
    /// ("Bench 9/22"). December is when "Dips 12/10" is also a recent date.
    func testMovementTitledDatesDependOnShapeNotSeason() {
        inZone("America/Los_Angeles") { calendar in
            for reference in [local(calendar, 2026, 9, 26, 18, 30), local(calendar, 2026, 12, 15, 18, 30)] {
                for notation in ["Dips 12/10", "Bench 12/10", "Lunges 12/12 each leg", "Curl 10/8", "Pull-ups 12/10"] {
                    XCTAssertNil(HandwrittenWorkoutParser.parse(notation, referenceDate: reference).performedAt, notation)
                    XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader(notation, referenceDate: reference), notation)
                }
                for header in ["Bench 9/22", "Squat - 9/22", "Deadlift (9/22)", "Bench PR 9/22", "Clean & Jerk 9/22"] {
                    assertLocal(HandwrittenWorkoutParser.parse("\(header)\nBench 3x8", referenceDate: reference).performedAt,
                                calendar, 2026, 9, 22, header)
                }
            }
        }
    }

    func testDateHeadersStillSplitAndDate() {
        inZone("America/Los_Angeles") { calendar in
            let reference = local(calendar, 2026, 9, 26, 21, 30)
            // Split-program titles carry no "day" word; they must stay dated
            // headers ("Push 3/5", "Legs 3/5", "Pull 3/5", …).
            for header in [
                "3/5", "3/5 Push", "Push day 3/5", "Monday 3/5", "Workout 3/5", "yesterday 3/5",
                "Push 3/5", "Legs 3/5", "Pull 3/5", "Upper A 3/5", "Chest & Back 3/5",
                "Push (3/5)", "PUSH A - 3/5", "Bench day 3/5", "Tues 3/5",
            ] {
                XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader(header, referenceDate: reference), header)
                let draft = HandwrittenWorkoutParser.parse("\(header)\nBench 3x8", referenceDate: reference)
                assertLocal(draft.performedAt, calendar, 2026, 3, 5, hour: 21, minute: 30, header)
            }
            // Numbered labels before a date keep the date too.
            for header in ["Day 3 3/5", "Wk 3 Day 2 3/5", "Workout #3 3/5", "Full Body x2 3/5", "Max 1 3/5"] {
                let draft = HandwrittenWorkoutParser.parse("\(header)\nBench 3x8", referenceDate: reference)
                assertLocal(draft.performedAt, calendar, 2026, 3, 5, header)
            }
            // An explicit old year on a titled line is still a date.
            assertLocal(HandwrittenWorkoutParser.parse("Push 9/22/19\nBench 3x8", referenceDate: reference).performedAt,
                        calendar, 2019, 9, 22)

            // Where/when notes after the date don't hide it.
            for header in ["Push 9/21 @ 6am", "Legs 9/21 @ gym", "Legs 9/21 set PR"] {
                assertLocal(HandwrittenWorkoutParser.parse("\(header)\nBench 3x8", referenceDate: reference).performedAt,
                            calendar, 2026, 9, 21, header)
            }

            for week in [
                "Push 9/21\nBench 3x8 @ 185\nPull 9/22\nRow 3x10\nLegs 9/23\nSquat 5x5 @ 225",
                // Workouts titled by their main lift: a recent date after a
                // movement name is still a header.
                "Bench 9/21\nBench 3x8 @ 185\nSquat - 9/22\nSquat 5x5 @ 225\nDeadlift (9/23)\nDeadlift 1x5 @ 315",
                "Push 9/21 @ 6am\nBench 3x8\nPull 9/22 @ 6am\nRow 3x10\nLegs 9/23 @ 6am\nSquat 5x5",
            ] {
                let segments = WorkoutSessionSegmenter.segments(from: week, referenceDate: reference)
                XCTAssertEqual(segments.count, 3, week)
                let days = segments.map {
                    HandwrittenWorkoutParser.parse($0, referenceDate: reference).performedAt.map { calendar.component(.day, from: $0) }
                }
                XCTAssertEqual(days, [21, 22, 23], week)
            }
        }
    }

    // MARK: - Weekdays and relative words

    func testExplicitDateBeatsWeekdayOnTheSameLine() {
        inZone("America/Los_Angeles") { calendar in
            let saturday = local(calendar, 2026, 9, 26, 21, 30)
            let draft = HandwrittenWorkoutParser.parse("Wednesday 7/15\nBench 3x8", referenceDate: saturday)
            assertLocal(draft.performedAt, calendar, 2026, 7, 15)
        }
    }

    func testAbbreviatedWeekdayInAnExerciseNameIsNotADate() {
        inZone("America/Los_Angeles") { calendar in
            let saturday = local(calendar, 2026, 9, 26, 21, 30)
            for input in ["Sun salutation 3x5", "Sat 3x10 wall sit"] {
                XCTAssertNil(HandwrittenWorkoutParser.parse(input, referenceDate: saturday).performedAt, input)
            }
            // A full weekday or an abbreviation with a separator still dates it.
            assertLocal(HandwrittenWorkoutParser.parse("Sun: Push\nBench 3x8", referenceDate: saturday).performedAt,
                        calendar, 2026, 9, 20)
            assertLocal(HandwrittenWorkoutParser.parse("Monday bench 3x8", referenceDate: saturday).performedAt,
                        calendar, 2026, 9, 21)
        }
    }

    /// The Apple Intelligence path reports the date phrase and code resolves it.
    /// Weekdays, "last …", and "N days ago" used to resolve to nil and silently
    /// became "now".
    func testModelDateTextResolvesLikeTheDeterministicParser() {
        inZone("America/Los_Angeles") { calendar in
            let saturday = local(calendar, 2026, 9, 26, 21, 30)
            let resolve = { HandwrittenWorkoutDateParser.resolveDateText($0, referenceDate: saturday) }

            XCTAssertEqual(resolve("today"), saturday)
            XCTAssertEqual(resolve("Today."), saturday)
            XCTAssertEqual(resolve("this morning"), saturday)
            XCTAssertEqual(resolve("Saturday"), saturday)
            assertLocal(resolve("yesterday"), calendar, 2026, 9, 25, hour: 21, minute: 30)
            assertLocal(resolve("last night"), calendar, 2026, 9, 25)
            assertLocal(resolve("Monday"), calendar, 2026, 9, 21, hour: 21, minute: 30)
            assertLocal(resolve("Mon"), calendar, 2026, 9, 21)
            assertLocal(resolve("last Tuesday"), calendar, 2026, 9, 22)
            assertLocal(resolve("last Saturday"), calendar, 2026, 9, 19)
            assertLocal(resolve("2 days ago"), calendar, 2026, 9, 24)
            assertLocal(resolve("three days ago"), calendar, 2026, 9, 23)
            assertLocal(resolve("7/22"), calendar, 2026, 7, 22, hour: 21, minute: 30)
            // 7/22/2026 is a Wednesday: the explicit date wins over "Monday".
            assertLocal(resolve("Monday 7/22"), calendar, 2026, 7, 22)
            assertLocal(resolve("July 22nd"), calendar, 2026, 7, 22)
            // A full timestamp keeps its own time; a zone suffix is honored.
            assertLocal(resolve("2026-07-22T18:00:00"), calendar, 2026, 7, 22, hour: 18, minute: 0)
            assertLocal(resolve("2026-07-22T02:00:00Z"), calendar, 2026, 7, 21, hour: 19, minute: 0)
            assertLocal(resolve("2026-07-22T23:30:00-07:00"), calendar, 2026, 7, 22, hour: 23, minute: 30)
            XCTAssertNil(resolve(""))
            XCTAssertNil(resolve("the other day"))
        }
    }

    func testYesterdayAcrossADaylightSavingChange() {
        inZone("America/Los_Angeles") { calendar in
            // 2026-03-08 is the spring-forward day in the US.
            let reference = local(calendar, 2026, 3, 9, 0, 30)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("yesterday", referenceDate: reference),
                        calendar, 2026, 3, 8, hour: 0, minute: 30)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("3/8", referenceDate: reference),
                        calendar, 2026, 3, 8, hour: 0, minute: 30)

            // "Yesterday" at 02:30 on 3/9 is 02:30 on 3/8, a wall-clock time the
            // spring-forward gap skips; the day must still be 3/8.
            let inGap = local(calendar, 2026, 3, 9, 2, 30)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("yesterday", referenceDate: inGap), calendar, 2026, 3, 8)
            assertLocal(HandwrittenWorkoutDateParser.resolveDateText("3/8", referenceDate: inGap), calendar, 2026, 3, 8)
        }
    }

    // MARK: - Commit

    func testUndatedImportEndsAtNowAndNothingLandsInTheFuture() throws {
        let context = makeInMemoryContext()
        let draft = ParsedWorkoutDraft(exercises: [
            ParsedExerciseDraft(name: "Bench", sets: [ParsedSetDraft(weight: 185, reps: 8), ParsedSetDraft(weight: 185, reps: 8)]),
            ParsedExerciseDraft(name: "Row", sets: [ParsedSetDraft(weight: 135, reps: 10)]),
        ])
        try WorkoutScanImporter.import(draft, externalID: "undated", source: .textEntry, in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt)]))
        XCTAssertEqual(entries.map(\.exercise.name), ["Bench", "Bench", "Row"])
        XCTAssertEqual(entries.last?.performedAt, now)
        XCTAssertTrue(entries.allSatisfy { $0.performedAt <= now && now.timeIntervalSince($0.performedAt) < 1 })
    }

    func testFutureDraftDatesAreSavedAsNow() throws {
        let context = makeInMemoryContext()
        let future = now.addingTimeInterval(3 * 86_400)
        let draft = ParsedWorkoutDraft(performedAt: future, exercises: [
            ParsedExerciseDraft(name: "Bench", sets: [
                ParsedSetDraft(weight: 185, reps: 8),
                ParsedSetDraft(weight: 185, reps: 8, performedAt: future),
            ]),
        ])
        try WorkoutScanImporter.import(draft, externalID: "future", source: .textEntry, in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.performedAt <= now }, "\(entries.map(\.performedAt))")
        let ledger = try XCTUnwrap(context.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertLessThanOrEqual(ledger.workoutDate, now)
    }

    /// The chronological cascade ends on the workout date, so it runs *back*
    /// from it; just after midnight it must not spill into the previous day.
    func testCascadeNeverCrossesIntoThePreviousDay() throws {
        try inZone("Pacific/Auckland") { calendar in
            let context = makeInMemoryContext()
            let justAfterMidnight = local(calendar, 2024, 7, 22).addingTimeInterval(0.010)
            let sets = (0..<50).map { _ in ParsedSetDraft(weight: 100, reps: 5) }
            let draft = ParsedWorkoutDraft(performedAt: justAfterMidnight, exercises: [ParsedExerciseDraft(name: "Squat", sets: sets)])
            try WorkoutScanImporter.import(draft, externalID: "midnight", source: .textEntry, in: context)

            let entries = try context.fetch(FetchDescriptor<SetEntry>())
            XCTAssertEqual(entries.count, 50)
            XCTAssertTrue(entries.allSatisfy { calendar.isDate($0.performedAt, inSameDayAs: justAfterMidnight) })
            XCTAssertTrue(entries.allSatisfy { $0.performedAt <= justAfterMidnight }, "nothing after the workout date")
            XCTAssertEqual(entries.map(\.performedAt).max(), justAfterMidnight)
            XCTAssertEqual(Set(entries.map(\.performedAt)).count, 50, "every set keeps a distinct timestamp")
        }
    }

    /// Only sets sharing a date are spread, so an explicit per-set time is
    /// saved exactly, and the ledger/session start is the earliest saved set.
    func testPerSetTimeIsKeptExactlyAndLedgerMatchesSavedSets() throws {
        let context = makeInMemoryContext()
        let workoutDate = now.addingTimeInterval(-3600)
        let override = now.addingTimeInterval(-7200)
        let draft = ParsedWorkoutDraft(performedAt: workoutDate, exercises: [
            ParsedExerciseDraft(name: "Bench", sets: [
                ParsedSetDraft(weight: 185, reps: 8, performedAt: override),
                ParsedSetDraft(weight: 185, reps: 8),
                ParsedSetDraft(weight: 185, reps: 8),
            ]),
        ])
        try WorkoutScanImporter.import(draft, externalID: "override", source: .textEntry, in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt)]))
        XCTAssertEqual(entries.first?.performedAt, override)
        XCTAssertEqual(entries.last?.performedAt, workoutDate)
        let ledger = try XCTUnwrap(context.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(ledger.workoutDate, entries.first?.performedAt)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.startedAt, entries.first?.performedAt)
        XCTAssertLessThanOrEqual(try XCTUnwrap(session.endedAt), now)
    }

    /// End to end through the parser and importer in a far-east zone: the
    /// journal day is the day the user wrote.
    func testParsedDateLandsOnTheWrittenDayInTheJournal() throws {
        try inZone("Pacific/Auckland") { calendar in
            let context = makeInMemoryContext()
            let draft = HandwrittenWorkoutParser.parse("7/22 Push Day\nBench 3x8 @ 185", referenceDate: now)
            try WorkoutScanImporter.import(draft, externalID: "auckland", source: .textEntry, in: context)

            let entries = try context.fetch(FetchDescriptor<SetEntry>())
            XCTAssertEqual(entries.count, 3)
            for entry in entries {
                assertLocal(entry.performedAt, calendar, 2024, 7, 22)
            }
        }
    }
}
