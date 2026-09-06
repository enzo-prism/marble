import Foundation
import SwiftUI

/// One row of the Trends shareable card: an exercise ranked by SetEntry count
/// plus its personal best.
///
/// PB definition (documented per contract): `PersonalRecords.records(for:entries:)`
/// `.heaviestEntry` — the max-weight set, unit-normalized, tie-break more reps
/// then later date. Reps and performed-date come from that same set; the date
/// uses `DateHelper.dayLabel`, matching the rest of Trends ("Today",
/// "Yesterday", …). Exercises without logged weight fall back to
/// `.mostRepsEntry` so bodyweight/cardio work still shows a best.
struct TrendsShareCardRow: Equatable {
    let exerciseID: UUID
    let exerciseName: String
    let setCount: Int
    /// e.g. "102 kg · 5 reps · Today", or "12 reps · Yesterday" for weightless
    /// work, or nil when the exercise has no usable best.
    let bestSummary: String?
    /// One line of the shared text export, e.g. "1. Bench Press — 8 sets · PB 102 kg × 5 (Today)".
    let shareLine: String
}

/// Pure, unit-testable engine behind the Trends first-screen shareable card.
enum TrendsShareCard {
    static let maxRows = 5

    /// Top `limit` exercises by SetEntry count. Ties break alphabetically
    /// (case-insensitive) so the ranking is deterministic.
    static func topExercises(
        from entries: [SetEntry],
        limit: Int = maxRows,
        now: Date = AppEnvironment.now
    ) -> [TrendsShareCardRow] {
        let grouped = Dictionary(grouping: entries) { $0.exercise.id }
        let ranked = grouped.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let lhsName = lhs.first?.exercise.name ?? ""
            let rhsName = rhs.first?.exercise.name ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }.prefix(max(0, limit))
        var rank = 0
        return ranked.compactMap { group in
            guard let exercise = group.first?.exercise else { return nil }
            rank += 1
            let records = PersonalRecords.records(for: exercise, entries: Array(group))
            let bestSummary = makeBestSummary(exercise: exercise, records: records, now: now)
            let shareLine = "\(rank). \(exercise.name) — \(group.count) \(group.count == 1 ? "set" : "sets") · PB \(bestSummary ?? "—")"
            return TrendsShareCardRow(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                setCount: group.count,
                bestSummary: bestSummary,
                shareLine: shareLine
            )
        }
    }

    /// Plain-text export for `ShareLink`. Text only: the card is already a
    /// minimal text ranking, so an image render adds no information.
    static func shareText(rows: [TrendsShareCardRow]) -> String {
        guard !rows.isEmpty else { return "No exercises logged yet." }
        return (["My Top Exercises"] + rows.map(\.shareLine)).joined(separator: "\n")
    }

    private static func makeBestSummary(
        exercise: Exercise,
        records: ExercisePersonalRecords,
        now: Date
    ) -> String? {
        if let entry = records.heaviestEntry, let weight = entry.weight {
            var parts = [exercise.formattedWeightSummary(weight, unit: entry.weightUnit)]
            if let reps = entry.reps, reps > 0 {
                parts.append(reps == 1 ? "1 rep" : "\(reps) reps")
            }
            parts.append(DateHelper.dayLabel(for: entry.performedAt, now: now))
            return parts.joined(separator: " · ")
        }
        if let entry = records.mostRepsEntry, let reps = entry.reps, reps > 0 {
            return "\(reps == 1 ? "1 rep" : "\(reps) reps") · \(DateHelper.dayLabel(for: entry.performedAt, now: now))"
        }
        return nil
    }
}

/// Clean minimal card with generous whitespace, designed to be
/// screenshotted/shared. Rendered first on the Trends tab.
struct TrendsShareCardView: View {
    let rows: [TrendsShareCardRow]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top Exercises")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Spacer()
                if !rows.isEmpty {
                    ShareLink(item: TrendsShareCard.shareText(rows: rows)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(MarbleTypography.button)
                    }
                    .tint(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.ShareButton")
                }
            }

            if rows.isEmpty {
                Text("Log sets to see your most-repeated exercises here.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .padding(.vertical, MarbleSpacing.s)
            } else {
                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    ForEach(Array(rows.enumerated()), id: \.element.exerciseID) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                            Text("\(index + 1)")
                                .font(MarbleTypography.rowMeta)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .monospacedDigit()
                                .frame(minWidth: 12, alignment: .trailing)
                            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                                Text(row.exerciseName)
                                    .font(MarbleTypography.rowTitle)
                                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                                Text("\(row.setCount) \(row.setCount == 1 ? "set" : "sets")\(row.bestSummary.map { " · PB \($0)" } ?? "")")
                                    .font(MarbleTypography.rowMeta)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            }
                            Spacer(minLength: MarbleSpacing.s)
                        }
                    }
                }
                .padding(.vertical, MarbleSpacing.xxxs)
            }
        }
        .padding(MarbleSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.large))
        .accessibilityIdentifier("Trends.ShareCard")
    }
}
