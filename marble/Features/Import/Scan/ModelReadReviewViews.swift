import SwiftUI
import UIKit

/// Review and processing pieces shared by Scan and Paste or Type for drafts
/// read with Apple Intelligence (HIG, Generative AI): show the reading as it
/// forms, show where each exercise came from, and let the person say whether
/// it was read correctly. Solid content rows — no glass, monochrome.

// MARK: - Streaming preview

/// The notation lines the on-device rewrite has finished so far, under the
/// processing stage text. Lines fill in one at a time; VoiceOver hears the
/// stage (announced separately), and can read the lines as one element if it
/// lands here, rather than being interrupted by every line.
struct StreamingNotationLinesView: View {
    let idPrefix: String
    let lines: [String]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The newest lines only: the list is a sign of progress, not the review.
    private var visibleLines: [(offset: Int, line: String)] {
        let limit = dynamicTypeSize.isAccessibilitySize ? 3 : 6
        let start = max(0, lines.count - limit)
        return lines.enumerated().dropFirst(start).map { ($0.offset, $0.element) }
    }

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                ForEach(visibleLines, id: \.offset) { item in
                    Text(item.line)
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: lines.count)
            .padding(MarbleSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.chipFillColor(for: colorScheme))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Read so far: \(lines.joined(separator: ", "))")
            .accessibilityIdentifier("\(idPrefix).StreamingLines")
        }
    }
}

/// Posts the processing stage to VoiceOver once per change (not per streamed
/// line), so a long read is narrated as "Interpreting…", "Matching…".
struct ProcessingStageAnnouncer: ViewModifier {
    let stage: String

    func body(content: Content) -> some View {
        content.onChange(of: stage) { _, newValue in
            guard UIAccessibility.isVoiceOverRunning else { return }
            AccessibilityNotification.Announcement(newValue).post()
        }
    }
}

extension View {
    func announcesProcessingStage(_ stage: String) -> some View {
        modifier(ProcessingStageAnnouncer(stage: stage))
    }
}

// MARK: - Show sources

/// "From: “…”" under a model-read exercise: the source text it was read from,
/// so the reading can be checked without hunting through the original.
struct ModelSourceExcerptLine: View {
    let idPrefix: String
    let exerciseID: UUID
    let excerpt: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("From: “\(excerpt)”")
            .font(MarbleTypography.caption)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityLabel("Read from your text: \(excerpt)")
            .accessibilityIdentifier("\(idPrefix).Exercise.Source.\(exerciseID.uuidString)")
    }
}

// MARK: - Feedback

/// "Was this read correctly?" with thumbs up / down for a model-read review.
/// Only aggregate counts are stored, on this device. A thumbs-down offers a
/// person-initiated share of the example (their text + Marble's reading) via
/// the system share sheet; nothing is sent automatically.
struct ModelReadFeedbackRow: View {
    let idPrefix: String
    let verdict: ModelReadVerdict?
    /// The frozen reading plus current review; its text is built only when
    /// the share sheet exports it. nil when the original reading isn't
    /// known (a draft restored after relaunch), so nothing misleading is
    /// offered.
    let shareItem: ModelReadShareItem?
    let onVerdict: (ModelReadVerdict) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch verdict {
        case nil:
            question
        case .correct?:
            Label("Thanks — noted on this iPhone.", systemImage: "hand.thumbsup.fill")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(idPrefix).ModelFeedback.Thanks")
        case .incorrect?:
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                Text(shareItem == nil
                     ? "Thanks. Fix anything above before adding."
                     : "Thanks. Fix anything above before adding. You can share this example if you'd like — it includes how Marble first read it, and you choose where it goes.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(idPrefix).ModelFeedback.Thanks")
                if let shareItem {
                    ShareLink(
                        item: shareItem,
                        subject: Text("Marble reading example"),
                        preview: SharePreview("Marble reading example")
                    ) {
                        Label("Share this example", systemImage: "square.and.arrow.up")
                            .font(MarbleTypography.rowMeta)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHint("Opens the share sheet with your text, how Marble read it, and your corrections.")
                    .accessibilityIdentifier("\(idPrefix).ModelFeedback.Share")
                }
            }
        }
    }

    private var question: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MarbleSpacing.xs))
            : AnyLayout(HStackLayout(spacing: MarbleSpacing.s))
        return layout {
            Text("Was this read correctly?")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: MarbleSpacing.s) }
            HStack(spacing: MarbleSpacing.s) {
                verdictButton(.correct, systemImage: "hand.thumbsup", label: "Read correctly", id: "Up")
                verdictButton(.incorrect, systemImage: "hand.thumbsdown", label: "Read incorrectly", id: "Down")
            }
        }
    }

    private func verdictButton(_ verdict: ModelReadVerdict, systemImage: String, label: String, id: String) -> some View {
        Button {
            onVerdict(verdict)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(idPrefix).ModelFeedback.\(id)")
    }
}
