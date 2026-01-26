import SwiftUI

struct RPEPicker: View {
    @Binding var value: Int
    @State private var showAll = false

    @Environment(\.colorScheme) private var colorScheme

    private let quickRange = Array(6...10)
    private let fullRange = Array(1...10)

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Difficulty (RPE)")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: MarbleSpacing.xs), count: 5), spacing: MarbleSpacing.xs) {
                ForEach(showAll ? fullRange : quickRange, id: \.self) { rating in
                    Button {
                        value = rating
                    } label: {
                        MarbleChipLabel(title: "\(rating)", isSelected: value == rating, isDisabled: false, isExpanded: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("RPEPicker.\(rating)")
                    .accessibilityLabel("RPE \(rating)")
                }
            }

            Button {
                showAll.toggle()
            } label: {
                Text(showAll ? "Show 6-10" : "Show 1-10")
                    .font(MarbleTypography.caption.weight(.semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .padding(.horizontal, MarbleSpacing.s)
                    .padding(.vertical, MarbleSpacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                            .fill(Theme.chipFillColor(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                            .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RPEPicker.Toggle")
        }
    }
}
