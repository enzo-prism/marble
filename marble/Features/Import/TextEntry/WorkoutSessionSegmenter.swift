import Foundation

/// Splits a free-text paste into per-workout blocks using date headers.
///
/// The notation parser itself still treats a single block as one session
/// (first date wins). This layer runs *before* that parse so a week of Notes
/// becomes N drafts instead of one collapsed workout. Structured CSV never
/// reaches here — `WorkoutCSVParser` owns those files.
nonisolated enum WorkoutSessionSegmenter {
    /// Ordered session texts. A paste with no date-header boundaries returns a
    /// single trimmed block so existing single-workout hashing stays stable.
    static func segments(from text: String, referenceDate: Date) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let rawLines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var segments: [String] = []
        var current: [String] = []

        func flush() {
            let joined = trimBlankEdges(current).joined(separator: "\n")
            if !joined.isEmpty {
                segments.append(joined)
            }
            current = []
        }

        func currentHasWorkoutContent() -> Bool {
            current.contains { line in
                let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else { return false }
                return !HandwrittenWorkoutParser.isSessionSplitHeader(candidate, referenceDate: referenceDate)
            }
        }

        for line in rawLines {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if HandwrittenWorkoutParser.isSessionSplitHeader(candidate, referenceDate: referenceDate),
               currentHasWorkoutContent() {
                flush()
            }
            current.append(line)
        }
        flush()

        if segments.isEmpty {
            return [trimmed]
        }
        return segments
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var slice = lines
        while let first = slice.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            slice.removeFirst()
        }
        while let last = slice.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            slice.removeLast()
        }
        return slice
    }
}
