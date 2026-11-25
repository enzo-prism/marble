import SwiftUI

/// Color and a familiar symbol separate chapters of the detailed analytics stream.
/// Each chapter badge takes the hue of the data it introduces; Summary mixes
/// every kind of data, so its badge stays neutral ink. The title stays neutral
/// and carries the full meaning for accessibility.
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

        /// Nil means neutral ink (Summary spans every data hue).
        var accent: TrendsChartAccent? {
            switch self {
            case .summary: nil
            case .training: TrendsPalette.training
            case .bodyAndHabits: TrendsPalette.body
            case .milestones: TrendsPalette.record
            }
        }
    }

    let section: Section

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: MarbleSpacing.s) {
            TrendsGlyphBadge(
                systemName: section.symbol,
                accent: section.accent?.color(for: colorScheme) ?? Theme.primaryTextColor(for: colorScheme),
                size: 30,
                filled: true
            )
            Text(section.title)
                .font(TrendsFont.chapter)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, MarbleSpacing.xs)
    }
}
