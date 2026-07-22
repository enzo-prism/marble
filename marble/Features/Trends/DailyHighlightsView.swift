import SwiftUI
import UIKit

struct DailyHighlightsSection: View {
    let summary: DailyHighlightSummary
    let window: DailyHighlightWindow
    let occurrence: DailyHighlightOccurrence
    let onCustomize: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shareImage: DailyHighlightShareImage?
    @State private var sharePreviewImage: Image?
    @State private var renderFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            sectionHeader

            DailyHighlightsCard(summary: summary)

            shareControl

            if renderFailed {
                Text("Couldn’t create the share image. Try again.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("Trends.DailyHighlights.ShareError")
            }
        }
        .task(id: shareRenderID) {
            prepareShareImage()
        }
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                sectionTitle
                customizeButton
            }
        } else {
            HStack(alignment: .center, spacing: MarbleSpacing.s) {
                sectionTitle
                Spacer(minLength: MarbleSpacing.xs)
                customizeButton
            }
        }
    }

    private var sectionTitle: some View {
        Text("Daily Highlights")
            .font(MarbleTypography.sectionTitle)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("Trends.DailyHighlights")
    }

    private var customizeButton: some View {
        Button(action: onCustomize) {
            Label(expiryText, systemImage: "clock")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityLabel("Customize Daily Highlights window")
        .accessibilityValue(expiryText)
        .accessibilityIdentifier("Trends.DailyHighlights.Customize")
    }

    @ViewBuilder
    private var shareControl: some View {
        if let shareImage, let sharePreviewImage {
            ShareLink(
                item: shareImage,
                subject: Text("Today’s Marble highlights"),
                message: Text(summary.shareMessage),
                preview: SharePreview("Today’s Marble highlights", image: sharePreviewImage)
            ) {
                Label("Share Today’s Highlights", systemImage: "square.and.arrow.up")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Share Today’s Highlights")
            .accessibilityHint("Creates a private image and opens the share sheet.")
            .accessibilityIdentifier("Trends.DailyHighlights.Share")
        } else {
            Button {
                prepareShareImage()
            } label: {
                Label("Preparing Share Image", systemImage: "square.and.arrow.up")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
            .disabled(!renderFailed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(renderFailed ? "Try sharing today’s highlights again" : "Preparing share image")
            .accessibilityIdentifier("Trends.DailyHighlights.Share")
        }
    }

    private var shareRenderID: String {
        "\(summary.id.timeIntervalSince1970)-\(colorScheme == .dark ? "dark" : "light")"
    }

    private var expiryText: String {
        "Until \(occurrence.interval.end.addingTimeInterval(-1).formatted(date: .omitted, time: .shortened))"
    }

    @MainActor
    private func prepareShareImage() {
        renderFailed = false
        guard let rendered = DailyHighlightShareRenderer.render(summary: summary, colorScheme: colorScheme),
              let uiImage = UIImage(data: rendered.pngData) else {
            shareImage = nil
            sharePreviewImage = nil
            renderFailed = true
            return
        }
        shareImage = rendered
        sharePreviewImage = Image(uiImage: uiImage)
    }
}

private struct DailyHighlightsCard: View {
    let summary: DailyHighlightSummary

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.l) {
            cardHeader

            Text(summary.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                ForEach(Array(summary.achievements.enumerated()), id: \.element.id) { index, achievement in
                    DailyHighlightAchievementView(achievement: achievement, index: index)
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) { stats }
                } else {
                    HStack(alignment: .top, spacing: MarbleSpacing.s) { stats }
                }
            }

            Text("Private to this iPhone until you share.")
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MarbleSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    @ViewBuilder
    private var cardHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                dayLabel
                wordmark
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                dayLabel
                Spacer(minLength: MarbleSpacing.xs)
                wordmark
            }
        }
    }

    private var dayLabel: some View {
        Text(dayEyebrow)
            .font(MarbleTypography.smallLabel)
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var wordmark: some View {
        Text("marble")
            .font(MarbleTypography.rowMeta.weight(.semibold))
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stats: some View {
        ForEach(summary.stats.prefix(3)) { stat in
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(stat.value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(stat.label.uppercased())
                    .font(MarbleTypography.smallLabel)
                    .tracking(0.5)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stat.value) \(stat.label)")
        }
    }

    private var dayEyebrow: String {
        "TODAY · \(summary.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())"
    }
}

private struct DailyHighlightAchievementView: View {
    let achievement: DailyHighlightAchievement
    let index: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: MarbleSpacing.s) {
            Image(systemName: achievement.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(achievement.title.uppercased())
                    .font(MarbleTypography.smallLabel)
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(achievement.value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(achievement.detail)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.accessibilityLabel)
        .accessibilityIdentifier("Trends.DailyHighlights.Achievement.\(index)")
    }
}
