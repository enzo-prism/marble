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

struct HealthKitWorkoutProvider: WorkoutImportProvider {
    let source: ImportSource = .appleHealth
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore? = nil) {
        self.healthStore = healthStore ?? HKHealthStore()
    }

    func authorizationStatus() async -> ImportAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .needsConfiguration("Health data isn’t available on this device.")
        }
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        default:
            return .notDetermined
        }
    }

    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitImportError.unavailable
        }
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .activeEnergyBurned
        ]
        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
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
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 50,
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
        return workouts.map { Self.record(from: $0) }
    }
}

extension HealthKitWorkoutProvider {
    private static func record(from workout: HKWorkout) -> WorkoutImportRecord {
        let kind = activityKind(for: workout.workoutActivityType, hasDistance: workout.totalDistance != nil)
        let distance = workout.totalDistance?.doubleValue(for: .meter())
        let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        var title = kind.displayName
        if let distance, distance > 0, workout.duration > 0 {
            let pace = distance / workout.duration
            if pace > 0 {
                let secondsPerKilometer = 1000.0 / pace
                title += String(format: " · %d:%02d /km", Int(secondsPerKilometer) / 60, Int(secondsPerKilometer) % 60)
            }
        }

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
            title: title,
            kind: kind,
            distanceMeters: distance,
            durationSeconds: Int(workout.duration.rounded()),
            calories: calories,
            averageHeartRate: nil,
            strengthSets: [],
            originName: origin
        )
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
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .walking:
            return .walking
        case .hiking:
            return .hiking
        case .traditionalStrengthTraining, .functionalStrengthTraining, .preparationAndRecovery:
            return .strength
        default:
            return hasDistance ? .otherCardio : .other
        }
    }
}
