import XCTest
@testable import marble

/// Pins the pre-set PR proximity cue: fires only when a record sits just past
/// the usual working range (opportunity framing), never when it's far away.
final class PersonalRecordProximityTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func set(_ exercise: Exercise, daysAgo: Int, weight: Double, reps: Int, minute: Int = 0) -> SetEntry {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: start) ?? start
        let performedAt = calendar.date(bySettingHour: 9, minute: minute, second: 0, of: day) ?? day
        return SetEntry(exercise: exercise, performedAt: performedAt, weight: weight, weightUnit: .lb, reps: reps, restAfterSeconds: 90)
    }

    func testWeightCueFiresWhenRecordIsJustPastUsualTop() {
        let exercise = bench()
        var entries: [SetEntry] = []
        // Usual recent work: 210–215 lb. All-time best: 225 lb (older).
        entries.append(set(exercise, daysAgo: 30, weight: 225, reps: 3))
        for index in 0..<10 {
            entries.append(set(exercise, daysAgo: index + 1, weight: index.isMultiple(of: 2) ? 210 : 215, reps: 5, minute: index))
        }

        let records = PersonalRecords.records(for: exercise, entries: entries)
        let cue = PersonalRecords.proximityCue(for: records)

        guard case .weight(let deltaText) = cue else {
            return XCTFail("Expected a weight proximity cue, got \(String(describing: cue))")
        }
        XCTAssertTrue(deltaText.contains("10"), "225 − 215 = 10 lb away, got \(deltaText)")
    }

    func testNoCueWhenRecordIsFarAway() {
        let exercise = bench()
        var entries: [SetEntry] = []
        entries.append(set(exercise, daysAgo: 30, weight: 225, reps: 5))
        for index in 0..<10 {
            entries.append(set(exercise, daysAgo: index + 1, weight: 180, reps: 5, minute: index))
        }

        let records = PersonalRecords.records(for: exercise, entries: entries)

        XCTAssertNil(PersonalRecords.proximityCue(for: records))
    }

    func testRepCueFiresWithinTwoRepsOfRecord() {
        let exercise = bench()
        var entries: [SetEntry] = []
        // Rep record 12, usual recent top 10. Weights identical so the
        // weight cue can't fire first.
        entries.append(set(exercise, daysAgo: 30, weight: 135, reps: 12))
        for index in 0..<10 {
            entries.append(set(exercise, daysAgo: index + 1, weight: 135, reps: index.isMultiple(of: 2) ? 8 : 10, minute: index))
        }

        let records = PersonalRecords.records(for: exercise, entries: entries)
        let cue = PersonalRecords.proximityCue(for: records)

        guard case .reps(let delta) = cue else {
            return XCTFail("Expected a reps proximity cue, got \(String(describing: cue))")
        }
        XCTAssertEqual(delta, 2)
    }
}
