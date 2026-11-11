import Foundation
import HealthKit
import SwiftData

/// Opt-in export of completed, manually logged workouts. Stable sync identities
/// and separate checkpoints make retrying safe after a partial HealthKit save.
/// Journal set difficulty is not a session effort rating; no effort score is
/// fabricated from default or inherited set values. Historical entries without
/// an explicit activity classification export as Other, with unknown location.
@MainActor
final class HealthSessionExporter {
    static let shared = HealthSessionExporter()

    static let enabledDefaultsKey = "healthSessionExportEnabled"
    static let exportedDayKeysKey = "healthSessionExportedDayKeys"
    static let exportedSessionIDsKey = "healthSessionExportedSessionIDs"
    /// How far back a never-exported day is still worth writing.
    static let exportWindowDays = 14
    /// Exported-day bookkeeping kept in defaults (oldest trimmed past this).
    static let exportedDayKeyCap = 90

    private let healthStore = HKHealthStore()
    private var isExporting = false
    private let transactions = HealthExportTransaction()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    static var shareTypes: Set<HKSampleType> { [.workoutType()] }

    /// Asks for write access; returns whether sharing was granted for workouts.
    /// (Unlike reads, HealthKit does report share authorization truthfully.)
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.shareTypes)
        } catch {
            return false
        }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Exports any completed, not-yet-exported training days. Cheap no-op when
    /// disabled; safe to call on every foreground/background transition.
    func exportIfEnabled(from modelContext: ModelContext, now suppliedNow: Date? = nil) async {
        let now = suppliedNow ?? AppEnvironment.now
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

        let sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= windowStart && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        var exportedSessionIDs = Set(UserDefaults.standard.stringArray(forKey: Self.exportedSessionIDsKey) ?? [])

        for session in sessions where !exportedSessionIDs.contains(session.id.uuidString) {
            let manualSets = session.orderedEntries.filter { $0.importedWorkout == nil }
            guard !manualSets.isEmpty else { continue }
            guard await export(sets: manualSets, start: session.startedAt, end: session.endedAt, identifier: "Prism.marble.session.\(session.id.uuidString)") else { continue }
            exportedSessionIDs.insert(session.id.uuidString)
        }
        UserDefaults.standard.set(Array(exportedSessionIDs).sorted(), forKey: Self.exportedSessionIDsKey)

        var exportedKeys = UserDefaults.standard.stringArray(forKey: Self.exportedDayKeysKey) ?? []
        let exportedSet = Set(exportedKeys)

        let sessionEntryIDs = Set(sessions.flatMap(\.entries).map(\.id))
        let legacyDays = Dictionary(grouping: entries.filter {
            $0.importedWorkout == nil && !sessionEntryIDs.contains($0.id)
        }) {
            calendar.startOfDay(for: $0.performedAt)
        }

        for (day, sets) in legacyDays.sorted(by: { $0.key < $1.key }) {
            guard day < today else { continue }
            let dayKey = Self.dayKeyFormatter.string(from: day)
            guard !exportedSet.contains(dayKey) else { continue }
            guard await export(sets: sets, start: nil, end: nil, identifier: "Prism.marble.day.\(dayKey)") else { continue }
            exportedKeys.append(dayKey)
        }

        if exportedKeys.count > Self.exportedDayKeyCap {
            exportedKeys.removeFirst(exportedKeys.count - Self.exportedDayKeyCap)
        }
        UserDefaults.standard.set(exportedKeys, forKey: Self.exportedDayKeysKey)
    }

    /// One session/day → one workout. Unclassified history stays unclassified.
    private func export(sets: [SetEntry], start explicitStart: Date?, end explicitEnd: Date?, identifier: String) async -> Bool {
        guard let first = sets.first, let last = sets.last else { return false }

        let start = explicitStart ?? first.performedAt
        // The last set's own duration/rest keeps the window honest for timed
        // work; a small tail covers the final set's execution otherwise.
        let tailSeconds = max(last.durationSeconds ?? 0, 90)
        let end = explicitEnd ?? last.performedAt.addingTimeInterval(TimeInterval(tailSeconds))
        guard end > start else { return false }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown

        return await transactions.run(identifier: identifier, lookup: {
            try await self.findWorkout(identifier: identifier)
        }, create: {
            let builder = HKWorkoutBuilder(healthStore: self.healthStore, configuration: configuration, device: .local())
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: identifier,
                HKMetadataKeySyncVersion: NSNumber(value: 1)
            ])
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout()
        }, attachEffort: { workout in
            // Preserve the separately retriable stage for existing checkpoints.
            // Session effort must be explicitly rated, not inferred from set RPE.
            _ = workout
        })
    }

    private func findWorkout(identifier: String) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKWorkout) }
            }
            healthStore.execute(query)
        }
    }

}
