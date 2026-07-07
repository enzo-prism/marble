import SwiftUI

/// The "Personal Best" target card shown while logging.
///
/// Surfaces the all-time heaviest and most-reps sets (each as its full
/// weight × reps combo) plus the lifter's usual working range, so they can
/// see what to beat at a glance. Weight & reps only.
struct PersonalBestCardView: View {
    let records: ExercisePersonalRecords
    let exerciseName: String
    var identifierPrefix: String = "PersonalBest"

    @Environment(\.colorScheme) private var colorScheme

    private static let timesSymbol = "\u{00D7}"

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            if records.hasAnyBest {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: MarbleSpacing.m) {
                        bestCells
                    }
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                        bestCells
                    }
                }

                if let usual = usualLine {
                    Label {
                        Text(usual)
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(usual)
                    .accessibilityIdentifier("\(identifierPrefix).Usual")
                }

                if let cue = PersonalRecords.proximityCue(for: records) {
                    Label {
                        Text(cue.message)
                            .font(MarbleTypography.rowMeta.weight(.semibold))
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "target")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(cue.message)
                    .accessibilityIdentifier("\(identifierPrefix).Proximity")
                }
            } else {
                Text("No personal best yet — log your first set to set the bar. 💪")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifierPrefix).Empty")
            }
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifierPrefix)
    }

    @ViewBuilder
    private var bestCells: some View {
        if let entry = records.heaviestEntry {
            metricCell(
                title: "Heaviest",
                value: comboSummary(for: entry),
                detail: DateHelper.dayLabel(for: entry.performedAt),
                identifier: "\(identifierPrefix).Heaviest"
            )
        }
        if let entry = records.mostRepsEntry {
            metricCell(
                title: "Most reps",
                value: comboSummary(for: entry),
                detail: DateHelper.dayLabel(for: entry.performedAt),
                identifier: "\(identifierPrefix).MostReps"
            )
        }
    }

    private func metricCell(title: String, value: String, detail: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(title)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .textCase(.uppercase)
            HStack(spacing: MarbleSpacing.xxs) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                Text(value)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value), \(detail)")
        .accessibilityIdentifier(identifier)
    }

    private func comboSummary(for entry: SetEntry) -> String {
        if let weight = entry.weight {
            let weightText = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
            if let reps = entry.reps {
                return "\(weightText) \(Self.timesSymbol) \(reps)"
            }
            return weightText
        }
        if let reps = entry.reps {
            return reps == 1 ? "1 rep" : "\(reps) reps"
        }
        return "—"
    }

    private var usualLine: String? {
        var parts: [String] = []
        if let range = records.usualWeightRange, let unit = records.usualWeightUnit {
            parts.append("\(rangeText(range, formatter: Formatters.weight)) \(unit.symbol)")
        }
        if let range = records.usualRepsRange {
            if range.lowerBound == range.upperBound {
                parts.append("\(range.lowerBound) reps")
            } else {
                parts.append("\(range.lowerBound)–\(range.upperBound) reps")
            }
        }
        guard !parts.isEmpty else { return nil }
        return "Usual " + parts.joined(separator: " · ")
    }

    private func rangeText(_ range: ClosedRange<Double>, formatter: NumberFormatter) -> String {
        let lo = formatter.string(from: NSNumber(value: range.lowerBound)) ?? "\(range.lowerBound)"
        if range.lowerBound == range.upperBound {
            return lo
        }
        let hi = formatter.string(from: NSNumber(value: range.upperBound)) ?? "\(range.upperBound)"
        return "\(lo)–\(hi)"
    }
}
