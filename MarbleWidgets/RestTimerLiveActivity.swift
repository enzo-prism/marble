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
//
// Every presentation honors two system signals:
// - `context.isStale`: the controller stamps `staleDate = restEndsAt + 60s` on every
//   request/update, so a card the app failed to end (process killed mid-rest) renders as a
//   quiet "Rest over" state instead of a frozen-but-live-looking timer.
// - `\.isLuminanceReduced` (Always-On Display): the design is white-on-black, so the large
//   bright areas (the big countdown, the solid-white filled button) dim rather than glow.

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / banner presentation. Monochrome to match the Marble brand.
            RestTimerLockScreenView(
                exerciseName: context.attributes.exerciseName,
                restEndsAt: context.state.restEndsAt,
                activityID: context.activityID,
                isStale: context.isStale
            )
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? "Rest over" : "Rest", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdownText(endsAt: context.state.restEndsAt, isStale: context.isStale)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.attributes.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Exercise: \(context.attributes.exerciseName)")
                        RestActionButtons(activityID: context.activityID, isStale: context.isStale)
                    }
                }
            } compactLeading: {
                // Compact + minimal presentations stay non-interactive: they're too small for a
                // 44pt target, and a mis-tap there would cancel a rest the user meant to open.
                Image(systemName: "timer")
                    .accessibilityLabel("Rest timer")
            } compactTrailing: {
                RestCountdownText(endsAt: context.state.restEndsAt, isStale: context.isStale)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                // The minimal slot must still answer "how long is left", not show a static
                // glyph — it is the only visible surface when another activity wins the island.
                RestCountdownText(endsAt: context.state.restEndsAt, isStale: context.isStale)
                    .font(.caption2.monospacedDigit())
                    .minimumScaleFactor(0.6)
            }
        }
        // Lets the activity also render in small-family hosts (watch Smart Stack, CarPlay);
        // `RestTimerLockScreenView` reads `\.activityFamily` and collapses to one row there.
        .supplementalActivityFamilies([.small])
    }
}

/// A self-updating countdown that goes quiet once the system marks the content stale.
/// The range's lower bound is clamped so a render after the rest has elapsed can't form an
/// invalid (lower > upper) range.
private struct RestCountdownText: View {
    let endsAt: Date
    let isStale: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isStale {
            // A stale card means the app never got to end the activity. "Done" is honest;
            // a ticking-looking 0:00 would read as a live timer that simply froze.
            Text("Done")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Rest over")
        } else {
            Text(timerInterval: min(Date.now, endsAt)...endsAt, countsDown: true)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText(countsDown: true))
                // Always-On renders at reduced luminance; dropping the countdown below full
                // white keeps the largest text block from being the brightest thing on a
                // sleeping screen while staying comfortably above contrast thresholds.
                .opacity(isLuminanceReduced ? 0.8 : 1)
        }
    }
}

private struct RestTimerLockScreenView: View {
    let exerciseName: String
    let restEndsAt: Date
    let activityID: String
    let isStale: Bool

    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            switch activityFamily {
            case .small:
                // Watch Smart Stack / CarPlay: one glanceable row. The action buttons are
                // dropped — the small family has no room for two 44pt targets, and the watch
                // already offers the system dismiss affordance.
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text(exerciseName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    RestCountdownText(endsAt: restEndsAt, isStale: isStale)
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(12)
            case .medium:
                fullLockScreenBody
            @unknown default:
                fullLockScreenBody
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isStale ? "Rest over, \(exerciseName)" : "Rest timer, \(exerciseName)"
        )
    }

    private var fullLockScreenBody: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isStale ? "Rest over" : "Resting")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                RestCountdownText(endsAt: restEndsAt, isStale: isStale)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 92, alignment: .trailing)
            }
            RestActionButtons(activityID: activityID, isStale: isStale)
        }
        .padding(16)
        // The whole card dims a step on the Always-On Display; per-element tweaks (countdown
        // opacity, translucent filled button) handle the individually bright areas.
        .opacity(isLuminanceReduced ? 0.85 : 1)
    }
}

/// The "+30s" / "End" pair, shared by the Lock Screen view and the Dynamic Island's expanded
/// bottom region so the two presentations can't drift apart. A stale card collapses to a
/// lone "End": extending a rest that already elapsed would be surprising, and the ended
/// state should be quieter than a live one.
private struct RestActionButtons: View {
    let activityID: String
    let isStale: Bool

    var body: some View {
        HStack(spacing: 10) {
            if !isStale {
                RestActionButton(
                    title: "+30s",
                    accessibilityLabel: "Add 30 seconds to rest",
                    style: .filled,
                    intent: ExtendRestIntent(activityID: activityID)
                )
            }
            RestActionButton(
                title: "End",
                accessibilityLabel: "End rest",
                style: .outlined,
                intent: EndRestIntent(activityID: activityID)
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

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(background)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// On the Always-On Display the solid-white capsule would be the largest lit area on
    /// the sleeping screen, so it becomes a translucent fill with a white label instead.
    private var labelColor: Color {
        switch style {
        case .filled:
            return isLuminanceReduced ? .white : .black
        case .outlined:
            return .white
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            Capsule().fill(isLuminanceReduced ? Color.white.opacity(0.25) : Color.white)
        case .outlined:
            Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
    }
}
