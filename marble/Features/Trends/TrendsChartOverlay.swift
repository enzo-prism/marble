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
        Rectangle()
            .fill(Color.clear)
            .frame(width: plotSize.width, height: plotSize.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier(accessibilityIdentifier)
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let date = selectionDate(for: value.location) else { return }
                        onSelect(date)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
            .allowsHitTesting(plotSize.width > 0 && plotSize.height > 0 && dataRange != nil)
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

    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            guard horizontal > 10, horizontal > vertical * 1.2 else { return }
            isDragging = true
            isScrubbing = true
        }
        guard let date = selectionDate(for: value.location) else { return }
        onSelect(date)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if isDragging, let date = selectionDate(for: value.location) {
            onSelect(date)
        }
        isDragging = false
        if isScrubbing {
            isScrubbing = false
        }
    }
}
