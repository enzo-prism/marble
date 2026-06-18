import HealthKit
import XCTest
@testable import marble

@MainActor
final class ImportProviderMappingTests: MarbleTestCase {

    // MARK: - Garmin record mapping

    private func activity(
        id: Int? = 12345,
        name: String? = "Morning Run",
        start: String? = "2025-01-15T08:30:00Z",
        duration: Double? = 1800,
        distance: Double? = 5000,
        typeKey: String? = "running"
    ) -> GarminActivity {
        GarminActivity(
            activityId: id,
            activityName: name,
            startTimeGMT: start,
            duration: duration,
            distance: distance,
            averageHR: 150,
            maxHR: 170,
            calories: 320,
            activityType: GarminActivityType(typeKey: typeKey)
        )
    }

    func testGarminRecordMapsCoreFields() throws {
        let record = try XCTUnwrap(GarminConnectProvider.record(from: activity()))
        XCTAssertEqual(record.source, .garminConnect)
        XCTAssertEqual(record.externalID, "12345")
        XCTAssertEqual(record.title, "Morning Run")
        XCTAssertEqual(record.kind, .running)
        XCTAssertEqual(record.distanceMeters, 5000)
        XCTAssertEqual(record.durationSeconds, 1800)
    }

    func testGarminRecordSkippedWhenActivityIdMissing() {
        // No stable id means we can't deduplicate; the old code coerced this to "0",
        // collapsing every id-less activity into a single record.
        XCTAssertNil(GarminConnectProvider.record(from: activity(id: nil)))
    }

    func testGarminRecordSkippedWhenDateUnparseable() {
        XCTAssertNil(GarminConnectProvider.record(from: activity(start: nil)))
        XCTAssertNil(GarminConnectProvider.record(from: activity(start: "not-a-date")))
    }

    func testGarminTitleFallsBackToActivityKind() throws {
        let record = try XCTUnwrap(GarminConnectProvider.record(from: activity(name: "   ", typeKey: "lap_swimming")))
        XCTAssertEqual(record.title, ImportedActivityKind.swimming.displayName)
        XCTAssertEqual(record.kind, .swimming)
    }

    func testGarminActivityKindFallsBackByDistance() {
        XCTAssertEqual(GarminConnectProvider.activityKind(for: "unknown_type", hasDistance: true), .otherCardio)
        XCTAssertEqual(GarminConnectProvider.activityKind(for: "unknown_type", hasDistance: false), .other)
        XCTAssertEqual(GarminConnectProvider.activityKind(for: "indoor_cycling", hasDistance: false), .cycling)
    }

    // MARK: - HealthKit activity kind mapping

    func testHealthKitActivityKindMapping() {
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .running, hasDistance: true), .running)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .traditionalStrengthTraining, hasDistance: false), .strength)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .yoga, hasDistance: false), .other)
        XCTAssertEqual(HealthKitWorkoutProvider.activityKind(for: .yoga, hasDistance: true), .otherCardio)
    }

    // MARK: - Garmin configuration gating

    func testPlaceholderGarminConfigurationIsNotConfigured() {
        XCTAssertFalse(GarminConnectConfiguration.placeholder.isConfigured)
    }
}
