import Foundation

/// Turns a typed paste or export file into per-workout segments. Structured
/// CSV is fully parsed here; free text is only sliced, then each slice runs
/// through `WorkoutScanParsing` in the view model.
nonisolated enum WorkoutImportOrchestrator {
    static func segments(
        from text: String,
        referenceDate: Date,
        defaultWeightUnit: WeightUnit = .lb
    ) -> [WorkoutImportSegment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let csv = WorkoutCSVParser.parse(trimmed, defaultWeightUnit: defaultWeightUnit) {
            return csv.workouts.map { workout in
                WorkoutImportSegment(
                    sourceText: workout.sourceText,
                    identityKey: workout.identityKey,
                    kind: csv.kind,
                    draft: workout.draft
                )
            }
        }

        return WorkoutSessionSegmenter.segments(from: trimmed, referenceDate: referenceDate).map { block in
            WorkoutImportSegment(
                sourceText: block,
                identityKey: block,
                kind: .typedText,
                draft: nil
            )
        }
    }

    /// Concatenate several dropped/chosen files without breaking CSV headers.
    static func joinSources(_ parts: [String]) -> String {
        WorkoutCSVParser.merging(parts)
    }

    /// Content identity stored on `ImportedWorkout.externalID`. CSV keys stay
    /// readable and stable across re-exports; free text is hashed so a long
    /// Notes block doesn't bloat the unique key.
    static func externalID(for segment: WorkoutImportSegment) -> String {
        switch segment.kind {
        case .hevyCSV, .strongCSV:
            return segment.identityKey
        case .typedText:
            return WorkoutScanImageHash.hash(Data(segment.identityKey.utf8))
        }
    }
}
