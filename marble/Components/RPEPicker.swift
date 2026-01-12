import SwiftUI

struct RPEPicker: View {
    @Binding var value: Int
    @State private var showAll = false

    @Environment(\.colorScheme) private var colorScheme

    private let quickRange = Array(6...10)
    private let fullRange = Array(1...10)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty (RPE)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(showAll ? fullRange : quickRange, id: \.self) { rating in
                    Button {
                        value = rating
                    } label: {
                        Text("\(rating)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(chipBackground(isSelected: value == rating))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("RPEPicker.\(rating)")
                    .accessibilityLabel("RPE \(rating)")
                }
            }

            Button(showAll ? "Show 6-10" : "Show 1-10") {
                showAll.toggle()
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .buttonStyle(.plain)
            .accessibilityIdentifier("RPEPicker.Toggle")
        }
    }

    private func chipBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Theme.dividerColor(for: colorScheme) : Theme.chipFillColor(for: colorScheme))
    }
}
