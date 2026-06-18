import SwiftData
import XCTest
@testable import marble

private enum MockImportError: Error { case fetchFailed }

private struct MockWorkoutImportProvider: WorkoutImportProvider {
    let source: ImportSource
    var status: ImportAuthorizationStatus = .authorized
    var records: [WorkoutImportRecord] = []
    var shouldThrowOnFetch = false

    func authorizationStatus() async -> ImportAuthorizationStatus { status }
    func authorize() async throws {}
    func fetchWorkouts(in range: ClosedRange<Date>?) async throws -> [WorkoutImportRecord] {
        if shouldThrowOnFetch { throw MockImportError.fetchFailed }
        return records
    }
}

@MainActor
final class ImportViewModelTests: MarbleTestCase {
    private func record(externalID: String, source: ImportSource = .appleHealth) -> WorkoutImportRecord {
        WorkoutImportRecord(
            source: source,
            externalID: externalID,
            date: now,
            title: "Run",
            kind: .running,
            distanceMeters: 5000,
            durationSeconds: 1800
        )
    }

    func testRefreshStatusReflectsProviderStatus() async {
        let provider = MockWorkoutImportProvider(source: .appleHealth, status: .denied)
        let viewModel = ImportViewModel(providers: [provider])
        await viewModel.refreshStatus()
        XCTAssertEqual(viewModel.states[.appleHealth]?.status, .denied)
    }

    func testFetchPopulatesRecordsAndClearsFetchingFlag() async {
        let context = makeInMemoryContext()
        let provider = MockWorkoutImportProvider(
            source: .appleHealth,
            records: [record(externalID: "a"), record(externalID: "b")]
        )
        let viewModel = ImportViewModel(providers: [provider])

        await viewModel.fetch(.appleHealth, into: context)

        XCTAssertEqual(viewModel.states[.appleHealth]?.records.count, 2)
        XCTAssertEqual(viewModel.states[.appleHealth]?.isFetching, false)
        XCTAssertNil(viewModel.states[.appleHealth]?.errorMessage)
    }

    func testFetchFlagsAlreadyImportedRecords() async throws {
        let context = makeInMemoryContext()
        context.insert(
            ImportedWorkout(source: .appleHealth, externalID: "a", title: "Run", workoutDate: now, setsImported: 1)
        )
        try context.save()

        let provider = MockWorkoutImportProvider(
            source: .appleHealth,
            records: [record(externalID: "a"), record(externalID: "b")]
        )
        let viewModel = ImportViewModel(providers: [provider])

        await viewModel.fetch(.appleHealth, into: context)

        let alreadyImported = viewModel.states[.appleHealth]?.alreadyImported ?? []
        XCTAssertTrue(alreadyImported.contains("a"))
        XCTAssertFalse(alreadyImported.contains("b"))
    }

    func testFetchSurfacesErrorAndEmptiesRecords() async {
        let context = makeInMemoryContext()
        let provider = MockWorkoutImportProvider(source: .appleHealth, shouldThrowOnFetch: true)
        let viewModel = ImportViewModel(providers: [provider])

        await viewModel.fetch(.appleHealth, into: context)

        XCTAssertNotNil(viewModel.states[.appleHealth]?.errorMessage)
        XCTAssertEqual(viewModel.states[.appleHealth]?.records.count, 0)
        XCTAssertEqual(viewModel.states[.appleHealth]?.isFetching, false)
    }

    func testImportSelectedPersistsAndClearsSelection() async throws {
        let context = makeInMemoryContext()
        let first = record(externalID: "a")
        let second = record(externalID: "b")
        let provider = MockWorkoutImportProvider(source: .appleHealth, records: [first, second])
        let viewModel = ImportViewModel(providers: [provider])

        await viewModel.fetch(.appleHealth, into: context)
        viewModel.toggle(first)
        viewModel.toggle(second)
        XCTAssertEqual(viewModel.selectedRecords().count, 2)

        await viewModel.importSelected(into: context)

        XCTAssertEqual(viewModel.lastSummary?.importedWorkouts, 2)
        XCTAssertTrue(viewModel.selection.isEmpty)
        XCTAssertNil(viewModel.importErrorMessage)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 2)
    }

    func testAlreadyImportedRecordsAreSkippedOnImport() async throws {
        let context = makeInMemoryContext()
        let only = record(externalID: "a")
        let provider = MockWorkoutImportProvider(source: .appleHealth, records: [only])
        let viewModel = ImportViewModel(providers: [provider])

        await viewModel.fetch(.appleHealth, into: context)
        viewModel.toggle(only)
        await viewModel.importSelected(into: context)
        // Re-fetch + re-select + re-import the same record: it must dedupe, not duplicate.
        await viewModel.fetch(.appleHealth, into: context)
        viewModel.toggle(only)
        await viewModel.importSelected(into: context)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(viewModel.lastSummary?.skipped, 1)
    }
}
