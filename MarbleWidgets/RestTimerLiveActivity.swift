import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// NOTE: This file belongs to the **MarbleWidgets widget-extension target**, not the app.
// It renders the rest-timer Live Activity the app starts via `RestActivityController`.
// `RestTimerAttributes` is shared: add `marble/Features/RestTimer/RestTimerAttributes.swift`
// to this extension target's membership too (see SETUP.md). The "+30s" / "End" buttons are
// driven by `ExtendRestIntent` / `EndRestIntent` from the equally-shared
// `marble/Shared/MarbleSharedIntents.swift`; both are `LiveActivityIntent`s, so they run in
// the *app's* process and can mutate `RestActivityController.shared` directly.

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / banner presentation. Monochrome to match the Marble brand.
            RestTimerLockScreenView(
                exerciseName: context.attributes.exerciseName,
                restEndsAt: context.state.restEndsAt
            )
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(to: context.state.restEndsAt)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.attributes.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RestActionButtons()
                    }
                }
            } compactLeading: {
                // Compact + minimal presentations stay non-interactive: they're too small for a
                // 44pt target, and a mis-tap there would cancel a rest the user meant to open.
                Image(systemName: "timer")
            } compactTrailing: {
                countdown(to: context.state.restEndsAt)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    /// A self-updating countdown. The range's lower bound is clamped so a render after the
    /// rest has elapsed can't form an invalid (lower > upper) range.
    private func countdown(to endsAt: Date) -> some View {
        Text(timerInterval: min(Date.now, endsAt)...endsAt, countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}

private struct RestTimerLockScreenView: View {
    let exerciseName: String
    let restEndsAt: Date

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resting")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(timerInterval: min(Date.now, restEndsAt)...restEndsAt, countsDown: true)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 92, alignment: .trailing)
            }
            RestActionButtons()
        }
        .padding(16)
    }
}

/// The "+30s" / "End" pair, shared by the Lock Screen view and the Dynamic Island's expanded
/// bottom region so the two presentations can't drift apart.
private struct RestActionButtons: View {
    var body: some View {
        HStack(spacing: 10) {
            RestActionButton(
                title: "+30s",
                accessibilityLabel: "Add 30 seconds to rest",
                style: .filled,
                intent: ExtendRestIntent()
            )
            RestActionButton(
                title: "End",
                accessibilityLabel: "End rest",
                style: .outlined,
                intent: EndRestIntent()
            )
        }
    }
}

/// A monochrome Live Activity action button. Both variants are ≥44pt tall and text-only (no
/// emoji), so they satisfy the hit-region and caption-text accessibility audits.
private struct RestActionButton<Action: AppIntent>: View {
    enum Style: Equatable {
        /// White fill, black label — the primary action.
        case filled
        /// Transparent with a white hairline border — the secondary action.
        case outlined
    }

    let title: String
    let accessibilityLabel: String
    let style: Style
    let intent: Action

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(style == .filled ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(background)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            Capsule().fill(Color.white)
        case .outlined:
            Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
    }
}
