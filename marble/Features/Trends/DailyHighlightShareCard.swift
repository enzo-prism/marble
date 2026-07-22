import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Immutable, in-memory share payload. The PNG is created on device and only
/// handed to the system share sheet after an explicit tap.
struct DailyHighlightShareImage: Transferable, Equatable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
        .suggestedFileName("marble-daily-highlights.png")
    }
}

@MainActor
enum DailyHighlightShareRenderer {
    static let pointSize = CGSize(width: 360, height: 450)
    static let scale: CGFloat = 3

    static func render(
        summary: DailyHighlightSummary,
        colorScheme: ColorScheme
    ) -> DailyHighlightShareImage? {
        let renderer = ImageRenderer(
            content: DailyHighlightShareCard(summary: summary)
                .environment(\.colorScheme, colorScheme)
                .frame(width: pointSize.width, height: pointSize.height)
        )
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else { return nil }
        return DailyHighlightShareImage(pngData: data)
    }
}

/// Control-free 4:5 export surface. Its fixed canvas yields a 1080x1350 PNG
/// at 3x while preserving the same information hierarchy as the in-app card.
struct DailyHighlightShareCard: View {
    let summary: DailyHighlightSummary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayEyebrow)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(secondary)
                Spacer()
                Text("marble")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(primary)
            }

            Spacer(minLength: 20)

            Text(summary.headline)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 22)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(summary.achievements.prefix(3)) { achievement in
                    DailyHighlightExportAchievement(achievement: achievement)
                }
            }

            Spacer(minLength: 20)

            HStack(alignment: .top, spacing: 16) {
                ForEach(summary.stats.prefix(3)) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.value.uppercased())
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(primary)
                        Text(stat.label.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 16)

            Text("PRIVATE TO THIS IPHONE UNTIL YOU SHARE")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .accessibilityHidden(true)
    }

    private var dayEyebrow: String {
        summary.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }

    private var background: Color {
        colorScheme == .dark ? .black : .white
    }

    private var primary: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondary: Color {
        primary.opacity(0.62)
    }
}

private struct DailyHighlightExportAchievement: View {
    let achievement: DailyHighlightAchievement

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: achievement.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(achievement.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(achievement.detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var primary: Color { colorScheme == .dark ? .white : .black }
    private var secondary: Color { primary.opacity(0.62) }
}
