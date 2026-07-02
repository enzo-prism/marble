import Foundation
import HealthKit

enum HealthKitImportError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data isn’t available on this device."
        case .authorizationDenied:
            return "Health access was denied. Enable it in Settings › Health › Marble."
        }
    }
}

/// One averaged heart-rate bucket inside a workout window, for the detail sparkline.
nonisolated struct HeartRatePoint: Sendable, Identifiable {
    let id = UUID()
    let date: Date
    let beatsPerMinute: Double
}

struct HealthKitWorkoutProvider: WorkoutImportProvider {
    let source: ImportSource = .appleHealth
    private let healthStore: HKHealthStore

    /// Newest-first cap when fetching with no date range, so "load everything"
    /// on a years-deep Health store can't stall the UI with thousands of
    /// per-workout enrichment queries.
    static let unboundedFetchLimit = 500

    init(healthStore: HKHealthStore? = nil) {
        self.healthStore = healthStore ?? HKHealthStore()
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .activeEnergyBurned,
            .heartRate
        ]
        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Read authorization is deliberately opaque in HealthKit: the system never
    /// reveals whether the user granted or denied *read* access, only whether we
    /// still need to ask. So the honest states are "not connected yet"
    /// (`shouldRequest`) and "connected" (`unnecessary` — the request was made;
    /// what the user granted is between them and Health). The old implementation
    /// read the *sharing* status, which reports write access we never ask for,
    /// and could show "Access denied" to users who had granted read access.
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

    func fetchWorkouts(in range: ClosedRange<Date>?) async throws -> [WorkoutImportRecord] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitImportError.unavailable
        }
        let predicate = range.map {
            HKQuery.predicateForSamples(withStart: $0.lowerBound, end: $0.upperBound, options: .strictStartDate)
        }
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let limit = range == nil ? Self.unboundedFetchLimit : HKObjectQueryNoLimit
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            healthStore.execute(query)
        }
        return await Self.records(from: workouts, in: healthStore)
    }

    /// Incremental fetch for auto-import: returns only workouts added to Health
    /// since the given anchor, plus the new anchor to persist. `notBefore`
    /// bounds the very first run (nil anchor would otherwise replay the user's
    /// entire Health history).
    func fetchNewWorkouts(sinceAnchor anchorData: Data?, notBefore: Date) async throws -> (records: [WorkoutImportRecord], anchor: Data?) {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitImportError.unavailable
        }
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let predicate = HKQuery.predicateForSamples(withStart: notBefore, end: nil, options: .strictStartDate)
        let (workouts, newAnchor): ([HKWorkout], HKQueryAnchor?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ((samples as? [HKWorkout]) ?? [], newAnchor))
                }
            }
            healthStore.execute(query)
        }
        let records = await Self.records(from: workouts, in: healthStore)
        let archived = newAnchor.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        return (records, archived)
    }

    /// Minute-bucketed average heart rate across a workout window, oldest first —
    /// enough resolution for the detail sparkline without pulling every sample.
    func heartRateSeries(start: Date, end: Date, buckets: Int = 60) async -> [HeartRatePoint] {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              end > start, buckets > 0
        else { return [] }

        let bucketSeconds = max(15, Int(end.timeIntervalSince(start)) / buckets)
        var interval = DateComponents()
        interval.second = bucketSeconds
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let collection: HKStatisticsCollection? = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }

        guard let collection else { return [] }
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        var points: [HeartRatePoint] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let average = statistics.averageQuantity()?.doubleValue(for: beatsPerMinute), average > 0 {
                points.append(HeartRatePoint(date: statistics.startDate, beatsPerMinute: average))
            }
        }
        return points
    }
}

extension HealthKitWorkoutProvider {
    /// Caps concurrent per-workout enrichment queries so a large fetch doesn't
    /// flood HealthKit; enrichment used to run serially, which made a 90-day
    /// load crawl.
    private static let enrichmentConcurrency = 6

    private static func records(from workouts: [HKWorkout], in store: HKHealthStore) async -> [WorkoutImportRecord] {
        guard !workouts.isEmpty else { return [] }
        var heartRates: [UUID: (average: Double?, maximum: Double?)] = [:]
        heartRates.reserveCapacity(workouts.count)

        await withTaskGroup(of: (UUID, (average: Double?, maximum: Double?)).self) { group in
            var iterator = workouts.makeIterator()
            @discardableResult
            func addNext() -> Bool {
                guard let workout = iterator.next() else { return false }
                group.addTask {
                    (workout.uuid, await heartRate(for: workout, in: store))
                }
                return true
            }
            for _ in 0..<enrichmentConcurrency {
                if !addNext() { break }
            }
            for await (uuid, rates) in group {
                heartRates[uuid] = rates
                addNext()
            }
        }

        return workouts.map { record(from: $0, heartRate: heartRates[$0.uuid] ?? (nil, nil)) }
    }

    /// Average + max heart rate for a workout. Prefers the statistics the
    /// recording app associated with the workout (exact), falling back to a
    /// window statistics query (catches bridged sources like Garmin that write
    /// HR samples without associating them).
    private static func heartRate(for workout: HKWorkout, in store: HKHealthStore) async -> (average: Double?, maximum: Double?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        if let statistics = workout.statistics(for: heartRateType) {
            let average = statistics.averageQuantity()?.doubleValue(for: beatsPerMinute)
            let maximum = statistics.maximumQuantity()?.doubleValue(for: beatsPerMinute)
            if average != nil || maximum != nil {
                return (average, maximum)
            }
        }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, statistics, _ in
                continuation.resume(returning: (
                    statistics?.averageQuantity()?.doubleValue(for: beatsPerMinute),
                    statistics?.maximumQuantity()?.doubleValue(for: beatsPerMinute)
                ))
            }
            store.execute(query)
        }
    }

    private static func record(from workout: HKWorkout, heartRate: (average: Double?, maximum: Double?)) -> WorkoutImportRecord {
        let kind = activityKind(for: workout.workoutActivityType, hasDistance: workout.totalDistance != nil)
        let distance = workout.totalDistance?.doubleValue(for: .meter())
        let calories = activeEnergyBurned(for: workout)

        let origin = originName(
            sourceName: workout.sourceRevision.source.name,
            bundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            deviceManufacturer: workout.device?.manufacturer,
            deviceName: workout.device?.name
        )

        return WorkoutImportRecord(
            source: .appleHealth,
            externalID: workout.uuid.uuidString,
            date: workout.startDate,
            title: kind.displayName,
            kind: kind,
            distanceMeters: distance,
            durationSeconds: Int(workout.duration.rounded()),
            calories: calories,
            averageHeartRate: heartRate.average.flatMap { $0 > 0 ? $0 : nil },
            maxHeartRate: heartRate.maximum.flatMap { $0 > 0 ? $0 : nil },
            elevationAscendedMeters: elevationAscendedMeters(from: workout.metadata),
            isIndoor: isIndoor(from: workout.metadata),
            strengthSets: [],
            originName: origin,
            sourceAppName: workout.sourceRevision.source.name,
            deviceName: workout.device?.name ?? workout.device?.model
        )
    }

    private static func activeEnergyBurned(for workout: HKWorkout) -> Double? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }
        return workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }

    /// Elevation climbed, from workout metadata. Pure over the dictionary so
    /// it's unit-testable without an `HKWorkout`.
    static func elevationAscendedMeters(from metadata: [String: Any]?) -> Double? {
        guard let quantity = metadata?[HKMetadataKeyElevationAscended] as? HKQuantity else {
            return nil
        }
        let meters = quantity.doubleValue(for: .meter())
        return meters > 0 ? meters : nil
    }

    /// Indoor/outdoor flag, from workout metadata. Pure for unit tests.
    static func isIndoor(from metadata: [String: Any]?) -> Bool? {
        (metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue
    }

    /// Identifies which app/device actually recorded a HealthKit workout so the import hub
    /// can label it. Apple Health aggregates many sources (Apple Watch, Garmin, Strava,
    /// Wahoo, …); we surface the recognizable brand, falling back to the source app's own
    /// name. Pure and case-insensitive so it's unit-testable without an `HKWorkout`.
    static func originName(
        sourceName: String?,
        bundleIdentifier: String?,
        deviceManufacturer: String?,
        deviceName: String?
    ) -> String? {
        let haystacks = [sourceName, bundleIdentifier, deviceManufacturer, deviceName]
            .compactMap { $0?.lowercased() }
        func mentions(_ needle: String) -> Bool { haystacks.contains { $0.contains(needle) } }

        if mentions("garmin") { return "Garmin" }
        if mentions("strava") { return "Strava" }
        if mentions("wahoo") { return "Wahoo" }
        if mentions("polar") { return "Polar" }
        if mentions("whoop") { return "Whoop" }
        if mentions("coros") { return "COROS" }
        if mentions("fitbit") { return "Fitbit" }
        if mentions("zwift") { return "Zwift" }
        if mentions("peloton") { return "Peloton" }
        if (deviceName?.lowercased().contains("watch") ?? false) || mentions("apple") {
            return "Apple Watch"
        }
        if let sourceName, !sourceName.isEmpty { return sourceName }
        return nil
    }

    static func activityKind(for type: HKWorkoutActivityType, hasDistance: Bool) -> ImportedActivityKind {
        switch type {
        case .running, .trackAndField:
            return .running
        case .cycling, .handCycling:
            return .cycling
        case .swimming, .swimBikeRun:
            return .swimming
        case .walking, .wheelchairWalkPace, .wheelchairRunPace:
            return .walking
        case .hiking, .climbing:
            return .hiking
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining,
             .preparationAndRecovery:
            return .strength
        case .rowing, .elliptical, .stairClimbing, .stairs, .stepTraining, .jumpRope,
             .highIntensityIntervalTraining, .crossTraining, .mixedCardio, .cardioDance,
             .socialDance, .kickboxing, .boxing, .martialArts, .paddleSports, .surfingSports,
             .downhillSkiing, .crossCountrySkiing, .snowboarding, .snowSports, .skatingSports,
             .soccer, .basketball, .tennis, .tableTennis, .badminton, .racquetball, .squash,
             .pickleball, .volleyball, .americanFootball, .australianFootball, .rugby,
             .hockey, .lacrosse, .baseball, .softball, .golf, .discSports:
            return .otherCardio
        default:
            // Mind-and-body types (yoga, pilates, tai chi, …) and anything
            // unrecognized: distance decides whether it reads as cardio.
            return hasDistance ? .otherCardio : .other
        }
    }
}
