import Foundation
import HealthKit
import Observation
import SwiftData

/// One bodyweight measurement pulled out of HealthKit, already normalized to
/// canonical kilograms. A plain `Sendable` value so the query layer stays
/// testable without a live `HKHealthStore` — the same split
/// `WorkoutImportRecord` gives `HealthKitWorkoutProvider`.
nonisolated struct BodyMetricImportRecord: Sendable, Equatable {
    /// The HealthKit sample's own UUID — the dedup key. Stored verbatim on
    /// `BodyMetricEntry.healthKitUUID`.
    let healthKitUUID: UUID
    let measuredAt: Date
    /// Canonical kilograms. Converted here, once, at the boundary.
    let weightKilograms: Double
    /// Percentage points (0…100), when a same-day body-fat sample exists.
    let bodyFatPercent: Double?
}

/// Reads bodyweight (and, when present, body fat) out of Apple Health.
///
/// Modeled directly on `HealthKitWorkoutProvider`: an anchored query with a
/// persisted `HKQueryAnchor` so each sync sees only what is new, authorization
/// probed through `getRequestStatusForAuthorization`, and pure static helpers
/// so the mapping is unit-testable without HealthKit.
struct HealthBodyMetricsProvider {
    private let healthStore: HKHealthStore

    /// Newest-first cap for a first run, mirroring the workout provider's
    /// guard against replaying a years-deep Health store in one pass.
    static let unboundedFetchLimit = 500

    init(healthStore: HKHealthStore? = nil) {
        self.healthStore = healthStore ?? HKHealthStore()
    }

    /// Read types for *this* provider only. Deliberately separate from
    /// `HealthKitWorkoutProvider.readTypes`: the two features are independently
    /// opt-in, and widening the workout provider's set would make the workout
    /// permission sheet ask for body data the user never enabled.
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for identifier in [HKQuantityTypeIdentifier.bodyMass, .bodyFatPercentage] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Read authorization is opaque in HealthKit by design: the system never
    /// reveals whether read access was granted or denied, only whether we still
    /// need to ask. So `getRequestStatusForAuthorization` is the only honest
    /// probe. **Never use `authorizationStatus(for:)` here** — that reports
    /// *sharing* (write) status, which this app never requests, so gating reads
    /// on it reports "denied" to users who actually granted read access. That
    /// exact bug was already fixed once on the workout path; don't reintroduce
    /// it on this one.
    func authorizationStatus() async -> ImportAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .needsConfiguration("Health data isn’t available on this device.")
        }
        let status: HKAuthorizationRequestStatus = await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: Self.readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .unnecessary:
            return .authorized
        default:
            return .notDetermined
        }
    }

    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitImportError.unavailable
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: Self.readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: HealthKitImportError.authorizationDenied)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Incremental fetch: bodyweight samples added to Health since `anchorData`,
    /// plus the new anchor to persist. `notBefore` bounds the very first run so
    /// a nil anchor doesn't replay a decade of weigh-ins.
    ///
    /// Body fat rides along as enrichment rather than as its own anchored
    /// stream: `BodyMetricEntry.weightKilograms` is non-optional, so a body-fat
    /// sample with no bodyweight beside it has no row to live on. This is the
    /// same shape as the workout provider enriching workouts with heart rate.
    func fetchNewBodyMetrics(
        sinceAnchor anchorData: Data?,
        notBefore: Date,
        calendar: Calendar = .current
    ) async throws -> (records: [BodyMetricImportRecord], anchor: Data?) {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitImportError.unavailable
        }
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return ([], anchorData)
        }

        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let predicate = HKQuery.predicateForSamples(withStart: notBefore, end: nil, options: .strictStartDate)

        let (samples, newAnchor): ([HKQuantitySample], HKQueryAnchor?) = try await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: bodyMassType,
                predicate: predicate,
                anchor: anchor,
                limit: anchor == nil ? Self.unboundedFetchLimit : HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, _ in
                continuation.resume(returning: ((samples as? [HKQuantitySample]) ?? [], newAnchor))
            }
            healthStore.execute(query)
        }

        var bodyFat: [Date: Double] = [:]
        if !samples.isEmpty {
            bodyFat = await bodyFatByDay(covering: samples, calendar: calendar)
        }

        let records = Self.records(from: samples, bodyFatByDay: bodyFat, calendar: calendar)
        let archived = newAnchor.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        return (records, archived)
    }

    /// Body-fat percentage keyed by start-of-day, across the span the incoming
    /// bodyweight samples cover. One bounded query, not one per sample.
    private func bodyFatByDay(
        covering samples: [HKQuantitySample],
        calendar: Calendar
    ) async -> [Date: Double] {
        guard
            let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
            let earliest = samples.map(\.startDate).min(),
            let latest = samples.map(\.startDate).max()
        else { return [:] }

        let start = calendar.startOfDay(for: earliest)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest)) ?? latest
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let fatSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyFatType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        var byDay: [Date: Double] = [:]
        for sample in fatSamples {
            // HealthKit stores body fat as a 0…1 fraction; Marble displays
            // percentage points.
            let percent = sample.quantity.doubleValue(for: .percent()) * 100
            guard percent > 0, percent < 100 else { continue }
            // Later sample on the same day wins (samples arrive ascending).
            byDay[calendar.startOfDay(for: sample.startDate)] = percent
        }
        return byDay
    }

    /// Pure mapping from HealthKit samples to import records, so unit tests can
    /// drive it without a health store. Implausible weights are dropped rather
    /// than imported — a stray 0 kg sample would wreck the chart's Y domain and
    /// divide-by-near-zero the DOTS denominator.
    static func records(
        from samples: [HKQuantitySample],
        bodyFatByDay: [Date: Double],
        calendar: Calendar = .current
    ) -> [BodyMetricImportRecord] {
        samples.compactMap { sample in
            let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard BodyMetricEntry.isPlausible(kilograms: kilograms) else { return nil }
            return BodyMetricImportRecord(
                healthKitUUID: sample.uuid,
                measuredAt: sample.startDate,
                weightKilograms: kilograms,
                bodyFatPercent: bodyFatByDay[calendar.startOfDay(for: sample.startDate)]
            )
        }
        .sorted { $0.measuredAt < $1.measuredAt }
    }
}

// MARK: - Import

/// Inserts fetched body-metric records, skipping any HealthKit sample already
/// on file. Separated from the provider so the dedup rule is testable against
/// an in-memory context with no HealthKit involved.
enum BodyMetricImporter {
    struct Summary: Equatable {
        var importedEntries: Int = 0
        var skippedDuplicates: Int = 0
    }

    /// Dedup is by HealthKit sample `UUID`, which is stable across re-reads —
    /// so an anchor that fails to advance (or a re-enable that resets it)
    /// replays harmlessly instead of duplicating every weigh-in.
    @discardableResult
    static func importRecords(_ records: [BodyMetricImportRecord], in context: ModelContext) throws -> Summary {
        guard !records.isEmpty else { return Summary() }

        // Fetch only the window the incoming records touch, then match in
        // memory: `#Predicate` can't express "optional UUID in this set", and
        // the date bound keeps this off a full-table scan (measuredAt is indexed).
        let earliest = records.map(\.measuredAt).min() ?? .distantPast
        let descriptor = FetchDescriptor<BodyMetricEntry>(
            predicate: #Predicate { $0.measuredAt >= earliest }
        )
        let existing = Set(try context.fetch(descriptor).compactMap(\.healthKitUUID))

        var summary = Summary()
        var seenInBatch: Set<UUID> = []

        for record in records {
            guard !existing.contains(record.healthKitUUID),
                  seenInBatch.insert(record.healthKitUUID).inserted
            else {
                summary.skippedDuplicates += 1
                continue
            }
            context.insert(BodyMetricEntry(
                measuredAt: record.measuredAt,
                weightKilograms: record.weightKilograms,
                bodyFatPercent: record.bodyFatPercent,
                source: .healthKit,
                healthKitUUID: record.healthKitUUID
            ))
            summary.importedEntries += 1
        }

        if summary.importedEntries > 0 {
            context.saveOrRollback()
        }
        return summary
    }
}

// MARK: - Auto-import service

/// Pulls new Apple Health bodyweight samples in when the app comes to the
/// foreground, so the Trends bodyweight chart and the DOTS line stay current
/// without a manual weigh-in.
///
/// Mirrors `HealthAutoImportService` exactly: opt-in flag, a persisted anchor
/// so each sync is incremental, a `since` stamp bounding the first run, and
/// best-effort failure handling (the anchor only advances after a successful
/// save, and the UUID dedup makes any replay harmless).
@MainActor
@Observable
final class BodyMetricsAutoImportService {
    static let shared = BodyMetricsAutoImportService()

    struct Result: Equatable {
        var date: Date
        var importedEntries: Int
    }

    typealias FetchNewRecords = (_ anchor: Data?, _ notBefore: Date) async throws
        -> (records: [BodyMetricImportRecord], anchor: Data?)

    private(set) var isSyncing = false
    /// The most recent sync that actually imported something.
    private(set) var lastResult: Result?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetchNewRecords: FetchNewRecords

    // Key naming follows HealthAutoImportService's ("marble.health.autoImport*").
    private static let enabledKey = "marble.health.bodyMetricsEnabled"
    private static let anchorKey = "marble.health.bodyMetricsAnchor"
    private static let sinceKey = "marble.health.bodyMetricsSince"

    init(
        defaults: UserDefaults = .standard,
        now: (() -> Date)? = nil,
        fetchNewRecords: FetchNewRecords? = nil
    ) {
        self.defaults = defaults
        self.now = now ?? { AppEnvironment.now }
        self.fetchNewRecords = fetchNewRecords ?? { anchor, notBefore in
            try await HealthBodyMetricsProvider().fetchNewBodyMetrics(sinceAnchor: anchor, notBefore: notBefore)
        }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    /// The moment body-metrics import was switched on; only samples recorded
    /// after this are pulled in.
    var enabledSince: Date? {
        defaults.object(forKey: Self.sinceKey) as? Date
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            if enabledSince == nil {
                defaults.set(now(), forKey: Self.sinceKey)
            }
        } else {
            // A later re-enable starts fresh from that moment.
            defaults.removeObject(forKey: Self.anchorKey)
            defaults.removeObject(forKey: Self.sinceKey)
            lastResult = nil
        }
    }

    /// Fetches and imports bodyweight samples added to Health since the last
    /// sync. No-op when disabled, already running, or under UI testing
    /// (querying HealthKit without granted authorization errors, and tests need
    /// deterministic data).
    func syncIfEnabled(into context: ModelContext) async {
        guard isEnabled, !isSyncing, !TestHooks.isUITesting else { return }
        guard let since = enabledSince else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let anchor = defaults.data(forKey: Self.anchorKey)
            let (records, newAnchor) = try await fetchNewRecords(anchor, since)
            var summary = BodyMetricImporter.Summary()
            if !records.isEmpty {
                summary = try BodyMetricImporter.importRecords(records, in: context)
            }
            // Only advance the anchor once everything the fetch returned is
            // safely saved (or was already on file).
            if let newAnchor {
                defaults.set(newAnchor, forKey: Self.anchorKey)
            }
            if summary.importedEntries > 0 {
                lastResult = Result(date: now(), importedEntries: summary.importedEntries)
            }
        } catch {
            // Best-effort: keep the old anchor so the next sync retries the
            // same window.
        }
    }
}
