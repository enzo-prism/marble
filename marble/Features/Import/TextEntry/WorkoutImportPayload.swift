import Foundation

/// How a typed/pasted/file import identified itself before parsing.
/// Structured exports skip the on-device model; free text uses the existing
/// notation + Foundation Models pipeline per session.
nonisolated enum WorkoutImportPayloadKind: String, Sendable, Equatable, Codable {
    case typedText
    case hevyCSV
    case strongCSV

    var originName: String {
        switch self {
        case .typedText: return "Paste or Type"
        case .hevyCSV: return "Hevy"
        case .strongCSV: return "Strong"
        }
    }
}

/// One workout sliced out of a bulk paste or export file, before library matching.
nonisolated struct WorkoutImportSegment: Equatable, Sendable {
    /// Text fed to the notation / model parsers. For CSV this is a readable
    /// reconstruction used for unparsed diagnostics and Edit Text identity.
    var sourceText: String
    /// Stable dedup identity for this session (hashed for long text; structured
    /// for CSV so re-exporting the same workout skips).
    var identityKey: String
    var kind: WorkoutImportPayloadKind
    /// Pre-built draft when the source is a structured export. `nil` means the
    /// caller should run `WorkoutScanParsing` on `sourceText`.
    var draft: ParsedWorkoutDraft?
}

/// One reviewed workout inside a bulk import, including selection and ledger state.
nonisolated struct WorkoutImportSession: Equatable, Identifiable, Sendable, Codable {
    var id: UUID
    var sourceText: String
    var externalID: String
    var kind: WorkoutImportPayloadKind
    var draft: ParsedWorkoutDraft
    var unparsedLines: [String]
    var alreadyImported: Bool
    var selected: Bool

    init(
        id: UUID = UUID(),
        sourceText: String,
        externalID: String,
        kind: WorkoutImportPayloadKind,
        draft: ParsedWorkoutDraft,
        unparsedLines: [String] = [],
        alreadyImported: Bool = false,
        selected: Bool = true
    ) {
        self.id = id
        self.sourceText = sourceText
        self.externalID = externalID
        self.kind = kind
        self.draft = draft
        self.unparsedLines = unparsedLines
        self.alreadyImported = alreadyImported
        self.selected = selected
    }
}
