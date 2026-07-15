import Foundation
import Observation
import SwiftData

/// Imports new Apple Health workouts automatically when the app comes to the
/// foreground, so the journal stays current without a trip through the import
/// hub. Incremental: a persisted `HKQueryAnchor` means each sync sees only
/// workouts added since the last one, and `autoImportSince` (stamped when the
/// user enables the feature) bounds the very first run so years of history
/// aren't replayed.
///
/// Best-effort by design: failures are silent (the manual Load path surfaces
/// errors), the anchor only advances after a successful save, and the dedup
/// ledger makes any replay harmless.
@MainActor
@Observable
final class HealthAutoImportService {
    static let shared = HealthAutoImportService()

    struct Result: Equatable {
        var date: Date
        var importedWorkouts: Int
        var importedSets: Int
    }

    typealias FetchNewRecords = (_ anchor: Data?, _ notBefore: Date) async throws
        -> (records: [WorkoutImportRecord], anchor: Data?)

    private(set) var isSyncing = false
    /// The most recent sync that actually imported something; drives the
    /// "Auto-imported N workouts" line in the import hub.
    private(set) var lastResult: Result?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetchNewRecords: FetchNewRecords

    private static let enabledKey = "marble.health.autoImportEnabled"
    private static let anchorKey = "marble.health.autoImportAnchor"
    private static let sinceKey = "marble.health.autoImportSince"

    init(
        defaults: UserDefaults = .standard,
        now: (() -> Date)? = nil,
        fetchNewRecords: FetchNewRecords? = nil
    ) {
        self.defaults = defaults
        self.now = now ?? { AppEnvironment.now }
        self.fetchNewRecords = fetchNewRecords ?? { anchor, notBefore in
            try await HealthKitWorkoutProvider().fetchNewWorkouts(sinceAnchor: anchor, notBefore: notBefore)
        }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    /// The moment auto-import was switched on; only workouts recorded after
    /// this are auto-imported ("new workouts from here on").
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

    /// Fetches and imports workouts added to Health since the last sync.
    /// No-op when disabled, already running, or under UI testing (querying
    /// HealthKit without granted authorization errors, and tests need
    /// deterministic journals).
    func syncIfEnabled(into context: ModelContext) async {
        guard isEnabled, !isSyncing, !TestHooks.isUITesting else { return }
        guard let since = enabledSince else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let anchor = defaults.data(forKey: Self.anchorKey)
            let (records, newAnchor) = try await fetchNewRecords(anchor, since)
            var summary = WorkoutImporter.Summary()
            if !records.isEmpty {
                summary = try WorkoutImporter.importRecords(records, in: context)
            }
            // Only advance the anchor once everything the fetch returned is
            // safely saved (or was already in the ledger).
            if let newAnchor {
                defaults.set(newAnchor, forKey: Self.anchorKey)
            }
            if summary.importedWorkouts > 0 {
                lastResult = Result(
                    date: now(),
                    importedWorkouts: summary.importedWorkouts,
                    importedSets: summary.importedSets
                )
                MarbleHaptics.lightImpact()
            }
        } catch {
            // Best-effort: keep the old anchor so the next sync retries the
            // same window.
        }
    }
}
