import HealthKit
import XCTest
@testable import marble

@MainActor
final class ImportProviderMappingTests: MarbleTestCase {

    // MARK: - Strava record mapping

    private func stravaActivity(
        id: Int64? = 9876543210,
        name: String? = "Morning Run",
        distance: Double? = 5000,
        movingTime: Int? = 1700,
        elapsedTime: Int? = 1800,
        type: String? = "Run",
        sportType: String? = "Run",
        startDate: String? = "2025-01-15T08:30:00Z",
        averageHeartrate: Double? = 150
    ) -> StravaActivity {
        StravaActivity(
            id: id,
            name: name,
            distance: distance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            type: type,
            sportType: sportType,
            startDate: startDate,
            averageHeartrate: averageHeartrate
        )
    }

    func testStravaRecordMapsCoreFields() throws {
        let record = try XCTUnwrap(StravaProvider.record(from: stravaActivity()))
        XCTAssertEqual(record.source, .strava)
        XCTAssertEqual(record.externalID, "9876543210")
        XCTAssertEqual(record.title, "Morning Run")
        XCTAssertEqual(record.kind, .running)
        XCTAssertEqual(record.distanceMeters, 5000)
        XCTAssertEqual(record.durationSeconds, 1700) // prefers moving time
        XCTAssertEqual(record.averageHeartRate, 150)
    }

    func testStravaRecordSkippedWhenIdMissing() {
        XCTAssertNil(StravaProvider.record(from: stravaActivity(id: nil)))
    }

    func testStravaRecordSkippedWhenDateUnparseable() {
        XCTAssertNil(StravaProvider.record(from: stravaActivity(startDate: nil)))
        XCTAssertNil(StravaProvider.record(from: stravaActivity(startDate: "not-a-date")))
    }

    func testStravaTitleFallsBackToActivityKind() throws {
        let record = try XCTUnwrap(StravaProvider.record(from: stravaActivity(name: "   ", sportType: "Swim")))
        XCTAssertEqual(record.title, ImportedActivityKind.swimming.displayName)
        XCTAssertEqual(record.kind, .swimming)
    }

    func testStravaSportTypeMapping() {
        XCTAssertEqual(StravaProvider.activityKind(for: "Ride", hasDistance: true), .cycling)
        XCTAssertEqual(StravaProvider.activityKind(for: "VirtualRide", hasDistance: false), .cycling)
        XCTAssertEqual(StravaProvider.activityKind(for: "WeightTraining", hasDistance: false), .strength)
        XCTAssertEqual(StravaProvider.activityKind(for: "Yoga", hasDistance: false), .other)
        XCTAssertEqual(StravaProvider.activityKind(for: "Yoga", hasDistance: true), .otherCardio)
    }

    func testStravaPlaceholderConfigurationIsNotConfigured() {
        XCTAssertFalse(StravaConfiguration.placeholder.isConfigured)
    }

    // MARK: - Strava credential resolution ("if keys are configured")

    func testResolvePrefersEnvironmentOverInfoPlist() {
        let config = StravaConfiguration.resolve(
            infoDictionary: [
                "StravaClientID": "info-id",
                "StravaClientSecret": "info-secret",
                "StravaRedirectURI": "info://callback"
            ],
            environment: [
                "STRAVA_CLIENT_ID": "env-id",
                "STRAVA_CLIENT_SECRET": "env-secret",
                "STRAVA_REDIRECT_URI": "env://callback"
            ]
        )
        XCTAssertEqual(config.clientID, "env-id")
        XCTAssertEqual(config.clientSecret, "env-secret")
        XCTAssertEqual(config.redirectURI, "env://callback")
        XCTAssertTrue(config.isConfigured)
    }

    func testResolveFallsBackToInfoPlistWhenEnvironmentMissing() {
        let config = StravaConfiguration.resolve(
            infoDictionary: [
                "StravaClientID": "info-id",
                "StravaClientSecret": "info-secret",
                "StravaRedirectURI": "info://callback",
                "StravaScope": "activity:read"
            ],
            environment: [:]
        )
        XCTAssertEqual(config.clientID, "info-id")
        XCTAssertEqual(config.redirectURI, "info://callback")
        XCTAssertEqual(config.scope, "activity:read")
        XCTAssertTrue(config.isConfigured)
    }

    func testResolveDefaultsScopeAndStaysUnconfiguredWhenEmpty() {
        let config = StravaConfiguration.resolve(infoDictionary: [:], environment: [:])
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.scope, "activity:read_all")
    }

    func testResolveIsNotConfiguredWithPartialKeys() {
        let config = StravaConfiguration.resolve(
            infoDictionary: [:],
            environment: ["STRAVA_CLIENT_ID": "env-id"] // missing secret + redirect
        )
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.clientID, "env-id")
    }

    func testResolveBlankEnvironmentDoesNotShadowInfoPlist() {
        let config = StravaConfiguration.resolve(
            infoDictionary: ["StravaClientID": "info-id"],
            environment: ["STRAVA_CLIENT_ID": "   "] // whitespace-only must not win
        )
        XCTAssertEqual(config.clientID, "info-id")
    }

    // MARK: - HealthKit activity kind mapping

    func testHealthKitActivityKindMapping() {
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .running, hasDistance: true), .running)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .traditionalStrengthTraining, hasDistance: false), .strength)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .yoga, hasDistance: false), .other)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .yoga, hasDistance: true), .otherCardio)
    }

    /// The expanded mapping: gym cardio, sports, and multisport types stop
    /// collapsing into "other" — Garmin especially maps many profiles here.
    func testHealthKitExpandedActivityKindMapping() {
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .rowing, hasDistance: true), .otherCardio)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .elliptical, hasDistance: false), .otherCardio)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .highIntensityIntervalTraining, hasDistance: false), .otherCardio)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .stairClimbing, hasDistance: false), .otherCardio)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .coreTraining, hasDistance: false), .strength)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .swimBikeRun, hasDistance: true), .swimming)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .soccer, hasDistance: false), .otherCardio)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .handCycling, hasDistance: true), .cycling)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .wheelchairRunPace, hasDistance: true), .walking)
    }

    // MARK: - HealthKit metadata parsing (pure seams over the metadata dictionary)

    func testElevationAscendedParsesQuantityMetadata() {
        let metadata: [String: Any] = [
            HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: 84)
        ]
        XCTAssertEqual(HealthKitWorkoutProvider.elevationAscendedMeters(from: metadata), 84)
        XCTAssertNil(HealthKitWorkoutProvider.elevationAscendedMeters(from: [:]))
        XCTAssertNil(HealthKitWorkoutProvider.elevationAscendedMeters(from: nil))
        XCTAssertNil(
            HealthKitWorkoutProvider.elevationAscendedMeters(from: [
                HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: 0)
            ]),
            "Zero elevation reads as 'not recorded', not a stat worth showing"
        )
    }

    func testIsIndoorParsesBoolMetadata() {
        XCTAssertEqual(HealthKitWorkoutProvider.isIndoor(from: [HKMetadataKeyIndoorWorkout: true]), true)
        XCTAssertEqual(HealthKitWorkoutProvider.isIndoor(from: [HKMetadataKeyIndoorWorkout: false]), false)
        XCTAssertNil(HealthKitWorkoutProvider.isIndoor(from: [:]))
        XCTAssertNil(HealthKitWorkoutProvider.isIndoor(from: nil))
    }

    // MARK: - HealthKit origin detection (the import-hub labeling)

    func testOriginDetectsGarminFromSourceName() {
        XCTAssertEqual(
            HealthKitWorkoutProvider.originName(sourceName: "Garmin Connect", bundleIdentifier: "com.garmin.connect.mobile", deviceManufacturer: "Garmin", deviceName: nil),
            "Garmin"
        )
    }

    func testOriginDetectsStravaFromBundleID() {
        XCTAssertEqual(
            HealthKitWorkoutProvider.originName(sourceName: "Strava", bundleIdentifier: "com.strava.stravaride", deviceManufacturer: nil, deviceName: nil),
            "Strava"
        )
    }

    func testOriginDetectsAppleWatchFromDevice() {
        XCTAssertEqual(
            HealthKitWorkoutProvider.originName(sourceName: "Workout", bundleIdentifier: "com.apple.health", deviceManufacturer: "Apple Inc.", deviceName: "Apple Watch"),
            "Apple Watch"
        )
    }

    func testOriginFallsBackToSourceName() {
        XCTAssertEqual(
            HealthKitWorkoutProvider.originName(sourceName: "Gentler Streak", bundleIdentifier: "com.example.gs", deviceManufacturer: nil, deviceName: nil),
            "Gentler Streak"
        )
    }

    func testOriginIsNilWhenNothingIdentifiable() {
        XCTAssertNil(
            HealthKitWorkoutProvider.originName(sourceName: nil, bundleIdentifier: nil, deviceManufacturer: nil, deviceName: nil)
        )
    }
}
