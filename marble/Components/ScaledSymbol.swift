import SwiftUI

/// An SF Symbol at a point size that tracks the user's Dynamic Type setting,
/// optionally inside a square frame that scales with it.
struct ScaledSymbol: View {
    let systemName: String
    let size: CGFloat
    var weight: Font.Weight = .regular
    var frameSize: CGFloat? = nil

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        if let frameSize {
            image.frame(width: frameSize * scale, height: frameSize * scale)
        } else {
            image
        }
    }

    private var image: some View {
        Image(systemName: systemName)
            .font(.system(size: size * scale, weight: weight))
    }
}
