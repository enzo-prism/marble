import SwiftUI

/// The intentionally quiet default state for Progress. Detailed metrics and
/// controls live behind the navigation-bar Details action; this surface answers
/// only the emotional question, "How is this week going?"
struct ProgressOverviewView: View {
    let snapshot: TrainingConsistency.Snapshot

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Text("THIS WEEK")
                    .font(MarbleTypography.smallLabel)
                    .tracking(1.1)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                Text(statusHeadline)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("This week. \(statusHeadline)")
                    .accessibilityIdentifier(statusIdentifier)
            }
            .frame(maxWidth: 520, alignment: .leading)

            Spacer(minLength: 96)
                .accessibilityHidden(true)
        }
        .padding(.top, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusIdentifier: String {
        snapshot.lifetimeSets == 0 ? "Trends.EmptyState" : "Trends.Overview.Status"
    }

    private var statusHeadline: String {
        switch snapshot.state {
        case .fresh:
            return "Start when you’re ready."
        case .inProgress:
            return "You’re building consistency."
        case .atRisk:
            return "This week is still within reach."
        case .hit:
            return "This week is complete."
        case .comeback:
            return "You’re back on track."
        }
    }
}

/// A plain section marker for the detailed analytics stream. It uses typography
/// rather than another card or glass layer to establish hierarchy.
struct ProgressDetailHeading: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
