import Foundation
import SwiftData

/// Database-side filtering keeps typing independent of the size of the log.
enum WorkoutHistoryQuery {
    static let pageSize = 40

    /// Reviewed text/scan imports encode their order newest-first for Journal.
    /// Use that same ordering for completed import detail and Repeat. Explicit
    /// per-set timestamps still win; manual/mixed sessions remain chronological.
    static func orderedEntries(for session: WorkoutSession) -> [SetEntry] {
        guard session.endedAt != nil,
              let ledger = session.entries.first?.importedWorkout,
              ledger.source == .textEntry || ledger.source == .photoScan,
              session.entries.allSatisfy({ $0.importedWorkout?.id == ledger.id }) else {
            return session.orderedEntries
        }
        return session.entries.sorted { lhs, rhs in
            if lhs.performedAt != rhs.performedAt { return lhs.performedAt > rhs.performedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func descriptor(search: String, day: Date?, offset: Int = 0) -> FetchDescriptor<WorkoutSession> {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = day.map { Calendar.current.startOfDay(for: $0) } ?? .distantPast
        let end = day.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) } ?? .distantFuture
        let predicate: Predicate<WorkoutSession>
        if term.isEmpty {
            predicate = #Predicate {
                $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end
            }
        } else {
            predicate = #Predicate {
                $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end &&
                ($0.title.localizedStandardContains(term) ||
                 $0.entries.contains { $0.exercise.name.localizedStandardContains(term) })
            }
        }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize + 1
        descriptor.fetchOffset = offset
        return descriptor
    }
}

/// Copies values, never model objects or source timestamps. Consecutive blocks
/// preserve circuits such as Squat → Row → Squat in the editable review.
enum WorkoutRepeatDraft {
    static func make(from session: WorkoutSession, now: Date = AppEnvironment.now, sprintDetails: [UUID: SprintRepDetail] = [:]) -> ParsedWorkoutDraft {
        var exercises: [ParsedExerciseDraft] = []
        for entry in WorkoutHistoryQuery.orderedEntries(for: session) {
            var notes = entry.notes
            if let detail = sprintDetails[entry.id] {
                let precisionNote = "Previous sprint: \(SprintTiming.text(tenths: detail.durationTenths)). Previous target: \(SprintTiming.text(tenths: detail.targetLowerTenths))–\(SprintTiming.text(tenths: detail.targetUpperTenths))."
                notes = [notes, precisionNote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            }
            let set = ParsedSetDraft(
                weight: entry.weight, weightUnit: entry.weightUnit, reps: entry.reps,
                distance: entry.distance, distanceUnit: entry.distanceUnit,
                durationSeconds: entry.durationSeconds, restSeconds: entry.restAfterSeconds,
                difficulty: entry.difficulty, notes: notes
            )
            if exercises.last?.libraryExerciseID == entry.exercise.id {
                exercises[exercises.count - 1].sets.append(set)
            } else {
                exercises.append(ParsedExerciseDraft(
                    name: entry.exercise.name, sets: [set], libraryExerciseID: entry.exercise.id
                ))
            }
        }
        return ParsedWorkoutDraft(performedAt: now, notes: session.notes, title: session.title, exercises: exercises)
    }
}
