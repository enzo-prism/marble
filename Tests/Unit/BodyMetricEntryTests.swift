import Foundation
import SwiftData
import XCTest
@testable import marble

/// `BodyMetricEntry` and everything immediately around it: the canonical-kg
/// discipline, the HealthKit dedup rule, the Trends chart derivation, and the
/// body-metrics auto-import state machine.
///
/// The unit discipline tested here exists because Marble has shipped four
/// separate lb-vs-kg bugs. `BodyMetricEntry` stores kilograms and nothing else;
/// every test below is a guard on that seam.
@MainActor
final class BodyMetricEntryTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
    }

    // MARK: - Canonical kilograms

    func testCanonicalKilogramsConvertsPoundsAndPassesKilogramsThrough() {
        XCTAssertEqual(
            BodyMetricEntry.canonicalKilograms(from: 200, unit: .lb),
            90.718474,
            accuracy: 0.0001
        )
        XCTAssertEqual(BodyMetricEntry.canonicalKilograms(from: 82.5, unit: .kg), 82.5, accuracy: 0.0001)
    }

    /// A value entered in pounds, stored, and read back in pounds must be the
    /// same number — the round trip users actually notice.
    func testDisplayWeightRoundTripsThroughKilograms() {
        let entered = 187.5
        let entry = BodyMetricEntry(
            measuredAt: now,
            weightKilograms: BodyMetricEntry.canonicalKilograms(from: entered, unit: .lb)
        )
        XCTAssertEqual(entry.displayWeight(in: .lb), entered, accuracy: 0.0001)
    }

    /// The stored value is kilograms regardless of what the user typed — the
    /// invariant the whole model exists to hold.
    func testEqualWeightsInDifferentUnitsStoreIdenticalKilograms() {
        let fromPounds = BodyMetricEntry.canonicalKilograms(from: 220.462262, unit: .lb)
        let fromKilos = BodyMetricEntry.canonicalKilograms(from: 100, unit: .kg)
        XCTAssertEqual(fromPounds, fromKilos, accuracy: 0.0001)
    }

    func testPlausibilityRejectsGarbageSamples() {
        XCTAssertTrue(BodyMetricEntry.isPlausible(kilograms: 82.5))
        XCTAssertTrue(BodyMetricEntry.isPlausible(kilograms: 20))
        XCTAssertFalse(BodyMetricEntry.isPlausible(kilograms: 0))
        XCTAssertFalse(BodyMetricEntry.isPlausible(kilograms: -5))
        XCTAssertFalse(BodyMetricEntry.isPlausible(kilograms: 501))
    }

    // MARK: - Persistence

    func testEntryPersistsAndRefetches() throws {
        let context = makeInMemoryContext()
        let healthKitUUID = UUID()
        context.insert(BodyMetricEntry(
            measuredAt: day(-1),
            weightKilograms: 81.4,
            bodyFatPercent: 15.5,
            source: .healthKit,
            healthKitUUID: healthKitUUID,
            notes: "Post-holiday"
        ))
        XCTAssertTrue(context.saveOrRollback())

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMetricEntry>()).first)
        XCTAssertEqual(stored.weightKilograms, 81.4, accuracy: 0.0001)
        XCTAssertEqual(stored.bodyFatPercent ?? 0, 15.5, accuracy: 0.0001)
        XCTAssertEqual(stored.source, .healthKit)
        XCTAssertEqual(stored.healthKitUUID, healthKitUUID)
        XCTAssertEqual(stored.notes, "Post-holiday")
    }

    func testSourceRawValuesAreStableAcrossReleases() {
        // These strings are persisted. Renaming a case renames a column value
        // and silently orphans every existing row.
        XCTAssertEqual(BodyMetricSource.manual.rawValue, "manual")
        XCTAssertEqual(BodyMetricSource.healthKit.rawValue, "healthKit")
    }

    // MARK: - HealthKit dedup

    private func record(
        uuid: UUID = UUID(),
        dayOffset: Int = 0,
        kilograms: Double = 80,
        bodyFat: Double? = nil
    ) -> BodyMetricImportRecord {
        BodyMetricImportRecord(
            healthKitUUID: uuid,
            measuredAt: day(dayOffset),
            weightKilograms: kilograms,
            bodyFatPercent: bodyFat
        )
    }

    func testImportInsertsNewRecordsAsHealthKitSourced() throws {
        let context = makeInMemoryContext()
        let summary = try BodyMetricImporter.importRecords(
            [record(dayOffset: -2, kilograms: 80), record(dayOffset: -1, kilograms: 80.4, bodyFat: 16)],
            in: context
        )

        XCTAssertEqual(summary.importedEntries, 2)
        XCTAssertEqual(summary.skippedDuplicates, 0)

        let stored = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.source == .healthKit })
        XCTAssertTrue(stored.allSatisfy { $0.healthKitUUID != nil })
    }

    /// Re-importing the same HealthKit sample must not duplicate it. This is
    /// what makes a reset or non-advancing anchor harmless.
    func testImportSkipsSamplesAlreadyOnFile() throws {
        let context = makeInMemoryContext()
        let uuid = UUID()

        _ = try BodyMetricImporter.importRecords([record(uuid: uuid, dayOffset: -1)], in: context)
        let second = try BodyMetricImporter.importRecords([record(uuid: uuid, dayOffset: -1)], in: context)

        XCTAssertEqual(second.importedEntries, 0)
        XCTAssertEqual(second.skippedDuplicates, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 1)
    }

    /// A single fetch that repeats a sample UUID also dedups, not just across
    /// separate syncs.
    func testImportDedupsWithinOneBatch() throws {
        let context = makeInMemoryContext()
        let uuid = UUID()
        let summary = try BodyMetricImporter.importRecords(
            [record(uuid: uuid, dayOffset: -1), record(uuid: uuid, dayOffset: -1)],
            in: context
        )

        XCTAssertEqual(summary.importedEntries, 1)
        XCTAssertEqual(summary.skippedDuplicates, 1)
    }

    /// Manual entries have a nil `healthKitUUID`; they must never be mistaken
    /// for a duplicate of an incoming sample.
    func testImportIgnoresManualEntriesWhenDeduping() throws {
        let context = makeInMemoryContext()
        context.insert(BodyMetricEntry(measuredAt: day(-1), weightKilograms: 80, source: .manual))
        XCTAssertTrue(context.saveOrRollback())

        let summary = try BodyMetricImporter.importRecords([record(dayOffset: -1)], in: context)

        XCTAssertEqual(summary.importedEntries, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 2)
    }

    func testImportOfEmptyRecordsIsANoOp() throws {
        let context = makeInMemoryContext()
        let summary = try BodyMetricImporter.importRecords([], in: context)
        XCTAssertEqual(summary, BodyMetricImporter.Summary())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 0)
    }

    // MARK: - Chart derivation

    private func entry(dayOffset: Int, hour: Int, kilograms: Double, bodyFat: Double? = nil) -> BodyMetricEntry {
        let base = day(dayOffset)
        let measuredAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        return BodyMetricEntry(measuredAt: measuredAt, weightKilograms: kilograms, bodyFatPercent: bodyFat)
    }

    func testTrendDataIsEmptyWithoutEntries() {
        let data = BodyweightTrendData.build(entries: [], displayUnit: .kg, calendar: calendar)
        XCTAssertTrue(data.isEmpty)
        XCTAssertNil(data.latest)
        XCTAssertNil(data.changeInDisplayUnit)
        XCTAssertEqual(data.accessibilityValue, "No data")
    }

    /// Multiple weigh-ins in one day collapse to the last one — morning and
    /// evening weight differ by more than a week of real change.
    func testTrendDataKeepsTheLastMeasurementOfEachDay() {
        let data = BodyweightTrendData.build(
            entries: [
                entry(dayOffset: -1, hour: 7, kilograms: 80),
                entry(dayOffset: -1, hour: 20, kilograms: 81.2),
                entry(dayOffset: 0, hour: 7, kilograms: 80.5)
            ],
            displayUnit: .kg,
            calendar: calendar
        )

        XCTAssertEqual(data.points.count, 2)
        XCTAssertEqual(data.points[0].kilograms, 81.2, accuracy: 0.0001)
        XCTAssertEqual(data.points[1].kilograms, 80.5, accuracy: 0.0001)
    }

    func testTrendDataOrdersPointsOldestFirstRegardlessOfInputOrder() {
        let data = BodyweightTrendData.build(
            entries: [
                entry(dayOffset: 0, hour: 7, kilograms: 82),
                entry(dayOffset: -5, hour: 7, kilograms: 80),
                entry(dayOffset: -2, hour: 7, kilograms: 81)
            ],
            displayUnit: .kg,
            calendar: calendar
        )
        XCTAssertEqual(data.points.map(\.kilograms), [80, 81, 82])
    }

    /// The chart displays the preferred unit while the store stays in kg.
    func testTrendDataConvertsToTheDisplayUnit() {
        let data = BodyweightTrendData.build(
            entries: [entry(dayOffset: 0, hour: 7, kilograms: 90.718474)],
            displayUnit: .lb,
            calendar: calendar
        )
        XCTAssertEqual(data.displayUnit, .lb)
        XCTAssertEqual(data.points.first?.displayValue ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(data.points.first?.kilograms ?? 0, 90.718474, accuracy: 0.0001)
    }

    func testTrendDataReportsChangeAndAverageInDisplayUnit() throws {
        let data = BodyweightTrendData.build(
            entries: [
                entry(dayOffset: -2, hour: 7, kilograms: 80),
                entry(dayOffset: 0, hour: 7, kilograms: 84)
            ],
            displayUnit: .kg,
            calendar: calendar
        )
        XCTAssertEqual(try XCTUnwrap(data.changeInDisplayUnit), 4, accuracy: 0.0001)
        XCTAssertEqual(data.averageDisplayValue, 82, accuracy: 0.0001)
    }

    /// One weigh-in is not a trend, so there is no change to report.
    func testTrendDataReportsNoChangeForASingleMeasurement() {
        let data = BodyweightTrendData.build(
            entries: [entry(dayOffset: 0, hour: 7, kilograms: 80)],
            displayUnit: .kg,
            calendar: calendar
        )
        XCTAssertNotNil(data.latest)
        XCTAssertNil(data.changeInDisplayUnit)
    }

    // MARK: - Auto-import service

    private func makeDefaults() -> UserDefaults {
        let suiteName = "BodyMetricEntryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testEnableStampsSinceDateAndDisableClearsIt() {
        let defaults = makeDefaults()
        let service = BodyMetricsAutoImportService(defaults: defaults, now: { self.now }) { _, _ in ([], nil) }

        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(service.enabledSince)

        service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(service.enabledSince, now)

        service.setEnabled(false)
        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(service.enabledSince, "Disabling must clear the window so a re-enable starts fresh")
    }

    /// Body metrics are opt-in: nothing is read from Health until the user
    /// turns the feature on.
    func testSyncDoesNothingWhenDisabled() async {
        let defaults = makeDefaults()
        var fetchCount = 0
        let service = BodyMetricsAutoImportService(defaults: defaults, now: { self.now }) { _, _ in
            fetchCount += 1
            return ([], nil)
        }

        await service.syncIfEnabled(into: makeInMemoryContext())
        XCTAssertEqual(fetchCount, 0)
    }

    func testSyncImportsNewRecordsAndPersistsAnchor() async throws {
        let defaults = makeDefaults()
        let anchorToken = Data("body-anchor-1".utf8)
        let imported = record(dayOffset: -1, kilograms: 79.8)

        let service = BodyMetricsAutoImportService(defaults: defaults, now: { self.now }) { anchor, notBefore in
            XCTAssertNil(anchor, "First sync starts with no anchor")
            XCTAssertEqual(notBefore, self.now, "The window opens when the user enabled the feature")
            return ([imported], anchorToken)
        }
        service.setEnabled(true)

        let context = makeInMemoryContext()
        await service.syncIfEnabled(into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 1)
        XCTAssertEqual(defaults.data(forKey: "marble.health.bodyMetricsAnchor"), anchorToken)
        XCTAssertEqual(service.lastResult?.importedEntries, 1)
    }

    /// A failed fetch must not advance the anchor, so the next sync retries the
    /// same window.
    func testSyncKeepsOldAnchorWhenTheFetchFails() async throws {
        struct Boom: Error {}
        let defaults = makeDefaults()
        let service = BodyMetricsAutoImportService(defaults: defaults, now: { self.now }) { _, _ in
            throw Boom()
        }
        service.setEnabled(true)

        let context = makeInMemoryContext()
        await service.syncIfEnabled(into: context)

        XCTAssertNil(defaults.data(forKey: "marble.health.bodyMetricsAnchor"))
        XCTAssertNil(service.lastResult)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 0)
    }

    /// Re-running a sync that returns the same samples imports nothing new —
    /// the UUID dedup makes replay harmless.
    func testRepeatedSyncIsIdempotent() async throws {
        let defaults = makeDefaults()
        let imported = record(dayOffset: -1, kilograms: 79.8)
        let service = BodyMetricsAutoImportService(defaults: defaults, now: { self.now }) { _, _ in
            ([imported], Data("body-anchor-1".utf8))
        }
        service.setEnabled(true)

        let context = makeInMemoryContext()
        await service.syncIfEnabled(into: context)
        await service.syncIfEnabled(into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 1)
    }

    /// The opt-in flag uses the key the roadmap specifies; the integrator's
    /// Settings toggle and this service must agree on it.
    func testEnabledFlagUsesTheDocumentedDefaultsKey() {
        let defaults = makeDefaults()
        let service = BodyMetricsAutoImportService(defaults: defaults, now: { self.now }) { _, _ in ([], nil) }

        service.setEnabled(true)
        XCTAssertTrue(defaults.bool(forKey: "marble.health.bodyMetricsEnabled"))
    }
}
