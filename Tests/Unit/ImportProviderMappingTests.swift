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

    // MARK: - HealthKit activity kind mapping

    func testHealthKitActivityKindMapping() {
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .running, hasDistance: true), .running)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .traditionalStrengthTraining, hasDistance: false), .strength)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .yoga, hasDistance: false), .other)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .yoga, hasDistance: true), .otherCardio)
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
