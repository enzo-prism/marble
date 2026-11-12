import SwiftUI

/// Color and a familiar symbol separate chapters of the detailed analytics stream.
/// The title stays neutral and carries the full meaning for accessibility.
struct ProgressDetailHeading: View {
    enum Section {
        case summary, training, bodyAndHabits, milestones

        var title: String {
            switch self {
            case .summary: "Summary"
            case .training: "Training"
            case .bodyAndHabits: "Body & Habits"
            case .milestones: "Milestones"
            }
        }

        var symbol: String {
            switch self {
            case .summary: "chart.bar.xaxis"
            case .training: "dumbbell.fill"
            case .bodyAndHabits: "heart.text.square"
            case .milestones: "trophy.fill"
            }
        }

        var accent: TrendsChartAccent {
            switch self {
            case .summary: TrendsPalette.strength
            case .training: TrendsPalette.volumeWeighted
            case .bodyAndHabits: TrendsPalette.consistency
            case .milestones: TrendsPalette.personalRecord
            }
        }
    }

    let section: Section

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
            Image(systemName: section.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(section.accent.color(for: colorScheme))
                .accessibilityHidden(true)
            Text(section.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
