import Foundation
import SwiftUI

/// One row of the Progress Top Exercises card: an exercise ranked by SetEntry
/// count plus its personal best.
///
/// PB definition (documented per contract): `PersonalRecords.records(for:entries:)`
/// `.heaviestEntry` — the max-weight set, unit-normalized. Weight and
/// performed-date come from that same set; the date uses
/// `DateHelper.dayLabel`, matching the rest of Trends ("Today",
/// "Yesterday", …). Only exercises with a usable weight PR and date qualify.
struct TrendsShareCardRow: Equatable {
    let exerciseID: UUID
    let exerciseName: String
    /// e.g. "102 kg · Today". Every row has both a PR metric and its date.
    let bestSummary: String
}

/// Pure, unit-testable engine behind the Progress first-screen Top Exercises card.
enum TrendsShareCard {
    static let maxRows = 5

    /// Top `limit` exercises with a dated weight PR, ranked by SetEntry count. Ties break alphabetically
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
        }
        return Array(ranked.lazy.compactMap { group -> TrendsShareCardRow? in
            guard let exercise = group.first?.exercise else { return nil }
            let records = PersonalRecords.records(for: exercise, entries: Array(group))
            guard let bestSummary = makeBestSummary(exercise: exercise, records: records, now: now) else { return nil }
            return TrendsShareCardRow(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                bestSummary: bestSummary
            )
        }.prefix(max(0, limit)))
    }

    private static func makeBestSummary(
        exercise: Exercise,
        records: ExercisePersonalRecords,
        now: Date
    ) -> String? {
        guard let entry = records.heaviestEntry,
              let weight = entry.weight, weight.isFinite, weight > 0,
              entry.performedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return "\(exercise.formattedWeightSummary(weight, unit: entry.weightUnit)) · \(DateHelper.dayLabel(for: entry.performedAt, now: now))"
    }
}

/// Clean minimal card with generous whitespace, designed to be
/// screenshotted. Rendered first on the Progress overview.
struct TrendsShareCardView: View {
    let rows: [TrendsShareCardRow]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            Text("Top Exercises")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            if rows.isEmpty {
                Text("Log a weighted set to see your personal records here.")
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
                                Text("PB \(row.bestSummary)")
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
        .accessibilityIdentifier("Trends.TopExercises")
    }
}
