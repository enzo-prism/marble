import ActivityKit
import SwiftUI
import WidgetKit

// NOTE: This file belongs to the **MarbleWidgets widget-extension target**, not the app.
// It renders the rest-timer Live Activity the app starts via `RestActivityController`.
// `RestTimerAttributes` is shared: add `marble/Features/RestTimer/RestTimerAttributes.swift`
// to this extension target's membership too (see SETUP.md).

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
                    Text(context.attributes.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
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
        .padding(16)
    }
}
