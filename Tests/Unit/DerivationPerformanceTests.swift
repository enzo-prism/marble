import XCTest
@testable import marble

/// Relative-performance tripwires for the hot derivation paths.
///
/// Apple's guidance: simulator timings are only meaningful as *relative*
/// differences — so these tests exist to catch algorithmic regressions in the
/// paths the render memos guard (a future O(n²) slip, an accidental per-row
/// formatter, …), not to assert wall-clock numbers. Datasets are synthetic
/// 5k-row histories, roughly a heavy multi-year user.
final class DerivationPerformanceTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func makeExercise() -> Exercise {
        Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    /// ~2 years of history: `count` sets spread across days, weights cycling
    /// so personal-record detection has real work to do.
    private func syntheticEntries(count: Int, exercise: Exercise) -> [SetEntry] {
        let dayStart = calendar.startOfDay(for: now)
        return (0..<count).map { index in
            let daysAgo = index % 730
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: dayStart) ?? dayStart
            let performedAt = calendar.date(bySettingHour: 8 + (index % 10), minute: index % 60, second: 0, of: day) ?? day
            return SetEntry(
                exercise: exercise,
                performedAt: performedAt,
                weight: Double(95 + (index % 40) * 5),
                weightUnit: .lb,
                reps: 3 + (index % 10),
                difficulty: 5 + (index % 5),
                restAfterSeconds: 90,
                createdAt: performedAt,
                updatedAt: performedAt
            )
        }
    }

    func testTrendsDerivationScalesOn5kEntries() {
        let exercise = makeExercise()
        let entries = syntheticEntries(count: 5000, exercise: exercise)

        measure(metrics: [XCTClockMetric()]) {
            _ = TrendsDerivedData.build(
                entries: entries,
                supplementEntries: [],
                selectedExercise: nil,
                selectedSupplementType: nil,
                range: .all,
                calendar: calendar,
                now: now
            )
        }
    }

    func testPersonalRecordBadgesScaleOn5kEntries() {
        let exercise = makeExercise()
        let entries = syntheticEntries(count: 5000, exercise: exercise)

        measure(metrics: [XCTClockMetric()]) {
            _ = PersonalRecords.badges(for: entries)
        }
    }

    func testJournalDayGroupingScalesOn5kEntries() {
        let exercise = makeExercise()
        let entries = syntheticEntries(count: 5000, exercise: exercise)

        measure(metrics: [XCTClockMetric()]) {
            let grouped = Dictionary(grouping: entries) { entry in
                DateHelper.startOfDay(for: entry.performedAt)
            }
            _ = grouped.keys.sorted(by: >)
        }
    }
}
