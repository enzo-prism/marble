import Charts
import SwiftUI

struct TrendsChartOverlay: View {
    let plotSize: CGSize
    let proxy: ChartProxy
    let dataRange: ClosedRange<Date>?
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityValue: String
    @Binding var isScrubbing: Bool
    let onSelect: (Date) -> Void

    @State private var isDragging = false

    var body: some View {
        Button {
            if TestHooks.isUITesting {
                selectDefaultDate()
            }
        } label: {
            Rectangle()
                .fill(Color.clear)
                .frame(width: plotSize.width, height: plotSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityHint("Opens details for the nearest point.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                selectDefaultDate()
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let date = selectionDate(for: value.location) else { return }
                        onSelect(date)
                    }
            )
            .allowsHitTesting(plotSize.width > 0 && plotSize.height > 0 && dataRange != nil)
    }

    private func selectDefaultDate() {
        guard let dataRange else { return }
        if dataRange.lowerBound == dataRange.upperBound {
            onSelect(dataRange.lowerBound)
            return
        }
        let midpoint = dataRange.lowerBound.addingTimeInterval(
            dataRange.upperBound.timeIntervalSince(dataRange.lowerBound) / 2
        )
        onSelect(midpoint)
    }

    private func selectionDate(for location: CGPoint) -> Date? {
        guard let dataRange else { return nil }
        guard plotSize.width > 0 else { return dataRange.lowerBound }
        let clampedX = min(max(location.x, 0), plotSize.width)
        if let date: Date = proxy.value(atX: clampedX) {
            return date
        }
        if dataRange.lowerBound == dataRange.upperBound {
            return dataRange.lowerBound
        }
        let ratio = clampedX / plotSize.width
        return dataRange.lowerBound.addingTimeInterval(
            dataRange.upperBound.timeIntervalSince(dataRange.lowerBound) * Double(ratio)
        )
    }

}
