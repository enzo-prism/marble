import Foundation
import HealthKit
import SwiftData

/// Writes completed Marble training days to Apple Health as strength-training
/// workouts, each with a related workout-effort score derived from the
/// session's logged RPE — which is what makes Marble sessions count toward
/// Apple's Training Load rings (Apple can't estimate effort for strength work;
/// it depends on an app or the user supplying it).
///
/// Honesty rules:
/// - Opt-in only (`enabledDefaultsKey`), toggled from the Import screen.
/// - Only sets logged in Marble are exported — entries that came FROM Apple
///   Health (`importedWorkout != nil`) are skipped, so nothing round-trips
///   into a duplicate.
/// - Only completed days (before today) export, once each; later edits to an
///   already-exported day are deliberately ignored rather than re-written.
@MainActor
final class HealthSessionExporter {
    static let shared = HealthSessionExporter()

    static let enabledDefaultsKey = "healthSessionExportEnabled"
    static let exportedDayKeysKey = "healthSessionExportedDayKeys"
    /// How far back a never-exported day is still worth writing.
    static let exportWindowDays = 14
    /// Exported-day bookkeeping kept in defaults (oldest trimmed past this).
    static let exportedDayKeyCap = 90

    private let healthStore = HKHealthStore()
    private var isExporting = false

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    static var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let effort = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
            types.insert(effort)
        }
        return types
    }

    /// Asks for write access; returns whether sharing was granted for workouts.
    /// (Unlike reads, HealthKit does report share authorization truthfully.)
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: [])
        } catch {
            return false
        }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Exports any completed, not-yet-exported training days. Cheap no-op when
    /// disabled; safe to call on every foreground/background transition.
    func exportIfEnabled(from modelContext: ModelContext, now: Date = AppEnvironment.now) async {
        guard isEnabled, !TestHooks.isUITesting else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -Self.exportWindowDays, to: today) else { return }

        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.performedAt >= windowStart },
            sortBy: [SortDescriptor(\.performedAt)]
        )
        guard let entries = try? modelContext.fetch(descriptor) else { return }

        var exportedKeys = UserDefaults.standard.stringArray(forKey: Self.exportedDayKeysKey) ?? []
        let exportedSet = Set(exportedKeys)

        let sessions = Dictionary(grouping: entries.filter { $0.importedWorkout == nil }) {
            calendar.startOfDay(for: $0.performedAt)
        }

        for (day, sets) in sessions.sorted(by: { $0.key < $1.key }) {
            guard day < today else { continue }
            let dayKey = Self.dayKeyFormatter.string(from: day)
            guard !exportedSet.contains(dayKey) else { continue }
            guard await export(sets: sets) else { continue }
            exportedKeys.append(dayKey)
        }

        if exportedKeys.count > Self.exportedDayKeyCap {
            exportedKeys.removeFirst(exportedKeys.count - Self.exportedDayKeyCap)
        }
        UserDefaults.standard.set(exportedKeys, forKey: Self.exportedDayKeysKey)
    }

    /// One day's sets → one strength workout + one related effort sample.
    private func export(sets: [SetEntry]) async -> Bool {
        guard let first = sets.first, let last = sets.last else { return false }

        let start = first.performedAt
        // The last set's own duration/rest keeps the window honest for timed
        // work; a small tail covers the final set's execution otherwise.
        let tailSeconds = max(last.durationSeconds ?? 0, 90)
        let end = last.performedAt.addingTimeInterval(TimeInterval(tailSeconds))
        guard end > start else { return false }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else { return false }
            try await relateEffort(sets: sets, workout: workout, start: start, end: end)
            return true
        } catch {
            return false
        }
    }

    /// Session RPE → Apple's 1–10 effort scale (they share the CR-10 anchor).
    private func relateEffort(sets: [SetEntry], workout: HKWorkout, start: Date, end: Date) async throws {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else { return }
        guard healthStore.authorizationStatus(for: effortType) == .sharingAuthorized else { return }

        let averageRPE = Double(sets.reduce(0) { $0 + $1.difficulty }) / Double(sets.count)
        let score = min(max(averageRPE.rounded(), 1), 10)
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score),
            start: start,
            end: end
        )
        try await healthStore.save(sample)
        try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
    }
}
