import Foundation

/// Separate from the workout database: recovery never inserts a workout.
nonisolated struct WorkoutEntryDraft: Codable, Equatable, Sendable {
    var version = 1
    var text: String
    var phase: WorkoutTextEntryViewModel.Phase
    var draft: ParsedWorkoutDraft
    var sessions: [WorkoutImportSession]
    var reviewingSessionID: UUID?
    var resolutions: [UUID: WorkoutTextEntryViewModel.Resolution]
    var externalID: String
    var unparsedLines: [String]
    var unparsedLineIDs: [UUID]
}

@MainActor
protocol WorkoutEntryDraftStoring {
    func load() throws -> WorkoutEntryDraft?
    func save(_ draft: WorkoutEntryDraft) throws
    func clear() throws
}

/// Atomic replacement protects the previous complete draft during interruption.
/// An unknown version or unreadable file is preserved, never silently discarded.
@MainActor
final class WorkoutEntryDraftStore: WorkoutEntryDraftStoring {
    enum Failure: Error { case unsupportedVersion }
    let url: URL

    init(url: URL) { self.url = url }

    static func applicationStore(slot: String) -> WorkoutEntryDraftStore {
        // UI recovery tests can relaunch against the same explicit directory;
        // ordinary tests never need to disable the recovery implementation.
        let defaultBase = URL.applicationSupportDirectory.appendingPathComponent("WorkoutDrafts", isDirectory: true)
        if let namespace = ProcessInfo.processInfo.environment["MARBLE_DRAFT_NAMESPACE"],
           UUID(uuidString: namespace) != nil {
            return WorkoutEntryDraftStore(url: defaultBase.appendingPathComponent(namespace, isDirectory: true).appendingPathComponent("\(slot).json"))
        }
        let base = ProcessInfo.processInfo.environment["MARBLE_DRAFT_DIRECTORY"].map {
            $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : defaultBase.appendingPathComponent($0, isDirectory: true)
        } ?? defaultBase
        return WorkoutEntryDraftStore(url: base.appendingPathComponent("\(slot).json"))
    }

    func load() throws -> WorkoutEntryDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if url == URL.applicationSupportDirectory.appendingPathComponent("WorkoutDrafts/primary.json"),
               let legacy = UserDefaults.standard.string(forKey: "WorkoutEntry.Draft"),
               !legacy.isEmpty {
                let migrated = WorkoutEntryDraft(text: legacy, phase: .input, draft: ParsedWorkoutDraft(), sessions: [], reviewingSessionID: nil, resolutions: [:], externalID: "", unparsedLines: [], unparsedLineIDs: [])
                try save(migrated)
                UserDefaults.standard.removeObject(forKey: "WorkoutEntry.Draft")
                return migrated
            }
            return nil
        }
        let data = try Data(contentsOf: url)
        let draft = try JSONDecoder().decode(WorkoutEntryDraft.self, from: data)
        guard draft.version == 1 else { throw Failure.unsupportedVersion }
        return draft
    }

    func save(_ draft: WorkoutEntryDraft) throws {
        let data = try JSONEncoder().encode(draft)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
