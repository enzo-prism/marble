import SwiftUI

struct RestPicker: View {
    @Binding var restSeconds: Int

    @Environment(\.colorScheme) private var colorScheme

    private let presets: [Int] = [30, 60, 90, 120, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Rest After")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MarbleSpacing.xs) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            restSeconds = seconds
                        } label: {
                            MarbleChipLabel(
                                title: label(for: seconds),
                                isSelected: restSeconds == seconds,
                                isDisabled: false,
                                isExpanded: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("RestPicker.\(seconds)")
                    }
                }
            }

            Text("\(DateHelper.formattedDuration(seconds: restSeconds))")
                .font(MarbleTypography.rowSubtitle)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
    }

    private func label(for seconds: Int) -> String {
        switch seconds {
        case 30:
            return "30s"
        case 60:
            return "60s"
        case 90:
            return "90s"
        case 120:
            return "2m"
        case 180:
            return "3m"
        default:
            return DateHelper.formattedDuration(seconds: seconds)
        }
    }

}
