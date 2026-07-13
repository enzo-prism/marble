import SwiftUI

struct RestPicker: View {
    @Binding var restSeconds: Int

    @Environment(\.colorScheme) private var colorScheme

    private let presets: [Int]

    init(restSeconds: Binding<Int>, presets: [Int] = [30, 60, 90, 120, 180]) {
        _restSeconds = restSeconds
        self.presets = presets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Rest")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MarbleSpacing.xs) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            restSeconds = seconds
                        } label: {
                            restChipLabel(for: seconds, isSelected: restSeconds == seconds)
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

    private func restChipLabel(for seconds: Int, isSelected: Bool) -> some View {
        Text(label(for: seconds))
            .font(MarbleTypography.chip)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: MarbleLayout.chipMinHeight)
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xxs)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .fill(Theme.chipFillColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .stroke(isSelected ? Theme.primaryTextColor(for: colorScheme) : Theme.dividerColor(for: colorScheme), lineWidth: 1)
            )
    }

}
