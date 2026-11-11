import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityCard(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(MarbleURLs.url("workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Workout", systemImage: "figure.strengthtraining.traditional").font(.caption) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.setCount) sets").font(.headline) }
                DynamicIslandExpandedRegion(.bottom) { WorkoutActivityCard(context: context) }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
            } compactTrailing: {
                Text("\(context.state.setCount)").monospacedDigit().accessibilityLabel("\(context.state.setCount) sets")
            } minimal: { Image(systemName: "figure.strengthtraining.traditional") }
            .widgetURL(MarbleURLs.url("workout"))
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct WorkoutActivityCard: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    @Environment(\.activityFamily) private var family
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.state.title).font(.headline).lineLimit(1).privacySensitive()
                Spacer(minLength: 8)
                Text(context.attributes.startedAt, style: .timer).monospacedDigit()
                    .accessibilityLabel("Workout elapsed time")
            }
            if let exercise = context.state.exerciseName {
                Text("\(exercise) · \(context.state.setCount) sets").font(.subheadline).lineLimit(2).privacySensitive()
            } else { Text("Ready for your first set").font(.subheadline) }
            if let end = context.state.restEndsAt, end > Date.now, !context.isStale {
                HStack {
                    Text("Rest")
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true).monospacedDigit()
                    if family != .small {
                        Button(intent: ExtendRestIntent()) { Text("+30s").frame(minHeight: 44) }
                            .accessibilityIdentifier("WorkoutActivity.ExtendRest")
                        Button(intent: EndRestIntent()) { Text("End Rest").frame(minHeight: 44) }
                            .accessibilityIdentifier("WorkoutActivity.EndRest")
                    }
                }
                .font(.subheadline)
            }
            if context.isStale { Text("Open Marble to update").font(.caption) }
        }
        .foregroundStyle(.white)
        .padding(12)
        .opacity(isLuminanceReduced ? 0.8 : 1)
    }
}
