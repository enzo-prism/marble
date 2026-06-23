import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
final class ImportViewModel {
    typealias ImportHandler = ([WorkoutImportRecord], ModelContext) async throws -> WorkoutImporter.Summary

    struct SourceState {
        var status: ImportAuthorizationStatus = .notDetermined
        var records: [WorkoutImportRecord] = []
        var alreadyImported: Set<String> = []
        var isFetching = false
        var errorMessage: String?
    }

    private(set) var states: [ImportSource: SourceState] = [:]
    var selection: Set<UUID> = []
    private(set) var isImporting = false
    var lastSummary: WorkoutImporter.Summary?
    var lastSummarySource: ImportSource?
    var importErrorMessage: String?

    private let providers: [ImportSource: WorkoutImportProvider]
    private let importHandler: ImportHandler

    init(
        providers: [WorkoutImportProvider],
        importHandler: @escaping ImportHandler = { records, context in
            try WorkoutImporter.importRecords(records, in: context)
        }
    ) {
        var map: [ImportSource: WorkoutImportProvider] = [:]
        var initialStates: [ImportSource: SourceState] = [:]
        for provider in providers {
            map[provider.source] = provider
            initialStates[provider.source] = SourceState()
        }
        self.providers = map
        self.states = initialStates
        self.importHandler = importHandler
    }

    var sources: [ImportSource] { providers.keys.sorted { $0.rawValue < $1.rawValue } }

    func provider(for source: ImportSource) -> WorkoutImportProvider? { providers[source] }

    func refreshStatus() async {
        for source in sources {
            guard let provider = providers[source] else { continue }
            let status = await provider.authorizationStatus()
            states[source]?.status = status
        }
    }

    func connect(_ source: ImportSource) async {
        guard let provider = providers[source] else { return }
        states[source]?.errorMessage = nil
        do {
            try await provider.authorize()
            await refreshStatus()
        } catch {
            states[source]?.errorMessage = error.localizedDescription
        }
    }

    func disconnect(_ source: ImportSource) async {
        if let strava = providers[source] as? StravaProvider {
            strava.disconnect()
        }
        states[source]?.records = []
        states[source]?.status = .notDetermined
        await refreshStatus()
    }

    /// Count of fetched Apple Health workouts recorded by a given brand (e.g. "Garmin"),
    /// used to reassure users that their bridged data showed up.
    func appleHealthOriginCount(_ originName: String) -> Int {
        (states[.appleHealth]?.records ?? []).filter { $0.originName == originName }.count
    }

    func fetch(_ source: ImportSource, into context: ModelContext, lookbackDays: Int = 30) async {
        guard let provider = providers[source] else { return }
        guard states[source]?.isFetching != true else { return }
        states[source]?.isFetching = true
        states[source]?.errorMessage = nil
        defer {
            states[source]?.isFetching = false
            pruneSelection()
        }
        let range: ClosedRange<Date>? = lookbackDays > 0
            ? (Date().addingTimeInterval(-Double(lookbackDays) * 86_400)...Date())
            : nil
        do {
            let records = try await provider.fetchWorkouts(in: range)
            let imported: Set<String> = Set(records.compactMap { record -> String? in
                let isImported = (try? WorkoutImporter.alreadyImported(record, in: context)) ?? false
                return isImported ? record.externalID : nil
            })
            states[source]?.records = records
            states[source]?.alreadyImported = imported
        } catch {
            states[source]?.records = []
            states[source]?.alreadyImported = []
            states[source]?.errorMessage = error.localizedDescription
        }
    }

    func toggle(_ record: WorkoutImportRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }

    func selectedRecords() -> [WorkoutImportRecord] {
        var result: [WorkoutImportRecord] = []
        for source in sources {
            for record in states[source]?.records ?? [] where selection.contains(record.id) {
                result.append(record)
            }
        }
        return result
    }

    func importSelected(into context: ModelContext) async {
        guard !isImporting else { return }
        let records = selectedRecords()
        guard !records.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        importErrorMessage = nil
        do {
            let summary = try await importHandler(records, context)
            lastSummary = summary
            lastSummarySource = records.first?.source
            if summary.importedSets > 0 {
                MarbleHaptics.success()
            } else {
                MarbleHaptics.lightImpact()
            }
            markImported(records)
            selection.removeAll()
        } catch {
            importErrorMessage = "Couldn’t save the imported workouts. Please try again."
            MarbleHaptics.warning()
        }
    }

    private func markImported(_ records: [WorkoutImportRecord]) {
        for record in records {
            states[record.source]?.alreadyImported.insert(record.externalID)
        }
    }

    private func pruneSelection() {
        let valid = Set(states.values.flatMap { $0.records.map(\.id) })
        selection = selection.intersection(valid)
    }
}
