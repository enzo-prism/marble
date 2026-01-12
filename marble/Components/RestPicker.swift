import SwiftUI

struct RestPicker: View {
    @Binding var restSeconds: Int

    @Environment(\.colorScheme) private var colorScheme

    private let presets: [Int] = [30, 60, 90, 120, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rest After")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            restSeconds = seconds
                        } label: {
                            Text(label(for: seconds))
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(chipBackground(isSelected: restSeconds == seconds))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        restSeconds = max(restSeconds, 0)
                    } label: {
                        Text("Custom")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(chipBackground(isSelected: !presets.contains(restSeconds)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Stepper(value: $restSeconds, in: 0...600, step: 15) {
                Text("\(DateHelper.formattedDuration(seconds: restSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
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

    private func chipBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Theme.dividerColor(for: colorScheme) : Theme.chipFillColor(for: colorScheme))
    }
}

