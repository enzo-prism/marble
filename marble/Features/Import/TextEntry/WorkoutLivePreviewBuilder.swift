import Foundation

/// Pure, sendable live-preview derivation for the workout composer. Keeping
/// this outside the main-actor view model lets long notes and CSV exports parse
/// without competing with typing, selection, or scrolling.
nonisolated enum WorkoutLivePreviewBuilder {
    typealias Preview = WorkoutTextEntryViewModel.LivePreview

    @concurrent
    static func build(
        text: String,
        referenceDate: Date,
        defaultWeightUnit: WeightUnit
    ) async -> Preview? {
        makePreview(
            text: text,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit,
            isCancelled: { Task.isCancelled }
        )
    }

    static func makePreview(
        text: String,
        referenceDate: Date,
        defaultWeightUnit: WeightUnit
    ) -> Preview? {
        makePreview(
            text: text,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit,
            isCancelled: { false }
        )
    }

    private static func makePreview(
        text: String,
        referenceDate: Date,
        defaultWeightUnit: WeightUnit,
        isCancelled: () -> Bool
    ) -> Preview? {
        guard !isCancelled() else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let segments = WorkoutImportOrchestrator.segments(
            from: trimmed,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit
        )
        if segments.count > 1 || segments.contains(where: { $0.draft != nil }) {
            var drafts: [ParsedWorkoutDraft] = []
            var unrecognized: [String] = []
            drafts.reserveCapacity(segments.count)

            for segment in segments {
                guard !isCancelled() else { return nil }
                if let draft = segment.draft, draft.hasContent {
                    drafts.append(draft)
                    continue
                }

                let result = HandwrittenWorkoutParser.parseDetailed(
                    segment.sourceText,
                    referenceDate: referenceDate,
                    defaultWeightUnit: defaultWeightUnit
                )
                guard !isCancelled() else { return nil }
                let hasContent = result.draft.hasContent
                if hasContent {
                    drafts.append(result.draft)
                }
                if !result.droppedLines.isEmpty {
                    unrecognized.append(contentsOf: result.droppedLines)
                } else if !hasContent {
                    unrecognized.append(contentsOf: reviewLines(
                        in: segment.sourceText,
                        referenceDate: referenceDate
                    ))
                }
            }

            return Preview(
                recognized: drafts.enumerated().map { index, draft in
                    Preview.Recognized(
                        id: "session:\(index):\(draft.title.lowercased())",
                        name: draft.title,
                        setCount: draft.totalSetCount
                    )
                },
                unrecognized: unrecognized,
                sessionCount: max(drafts.count, segments.count),
                totalSets: drafts.reduce(0) { $0 + $1.totalSetCount }
            )
        }

        let result = HandwrittenWorkoutParser.parseDetailed(
            trimmed,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit
        )
        guard !isCancelled() else { return nil }
        return Preview(
            recognized: result.draft.importableExercises.enumerated().map { index, exercise in
                Preview.Recognized(
                    id: "exercise:\(index):\(exercise.trimmedName.lowercased())",
                    name: exercise.trimmedName,
                    setCount: exercise.sets.count
                )
            },
            unrecognized: result.droppedLines,
            sessionCount: 1,
            totalSets: result.draft.totalSetCount
        )
    }

    private static func reviewLines(in text: String, referenceDate: Date) -> [String] {
        text.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
                    && !HandwrittenWorkoutParser.isSessionSplitHeader(
                        $0,
                        referenceDate: referenceDate
                    )
            }
    }
}
