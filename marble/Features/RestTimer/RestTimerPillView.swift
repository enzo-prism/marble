import SwiftUI

/// The in-app rest countdown, shown as a tab-bar bottom accessory while a rest
/// timer runs. Mirrors the Lock Screen Live Activity so the user never has to
/// leave the app mid-workout to see their rest. The system supplies the glass
/// capsule; content stays solid, monochrome, and one line tall.
struct RestTimerPillView: View {
    let rest: ActiveRest
    let onEnd: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)

            if placement != .inline {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Resting")
                        .font(MarbleTypography.smallLabel)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    Text(rest.exerciseName)
                        .font(MarbleTypography.rowSubtitle.weight(.semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: MarbleSpacing.xs)

            countdown
                .font(MarbleTypography.rowTitle.monospacedDigit())
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .lineLimit(1)

            Button(action: onEnd) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End Rest")
            .accessibilityIdentifier("RestPill.End")
        }
        .padding(.horizontal, MarbleSpacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RestPill")
        .accessibilityLabel("Rest timer, \(rest.exerciseName)")
    }

    /// A self-updating countdown. The range's lower bound is clamped so a render
    /// after the rest has elapsed can't form an invalid (lower > upper) range.
    private var countdown: some View {
        Text(timerInterval: min(Date.now, rest.endsAt)...rest.endsAt, countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}

/// Now-playing chrome for an active workout when rest is not running.
/// Tapping it opens the secondary active-workout sheet. Rest always wins.
struct SessionAccessoryView: View {
    let session: WorkoutSession
    let onOpen: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: MarbleSpacing.s) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                if placement != .inline {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Training")
                            .font(MarbleTypography.smallLabel)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        Text(session.title)
                            .font(MarbleTypography.rowSubtitle.weight(.semibold))
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: MarbleSpacing.xs)

                if TestHooks.isAppStoreScreenshotting {
                    Text("48:12")
                        .font(MarbleTypography.rowTitle.monospacedDigit())
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                } else {
                    Text(session.startedAt, style: .timer)
                        .font(MarbleTypography.rowTitle.monospacedDigit())
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, MarbleSpacing.m)
            .padding(.vertical, MarbleSpacing.xs)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .buttonStyle(.plain)
        .accessibilityIdentifier("SessionPill")
        .accessibilityLabel("Active workout, \(session.title)")
        .accessibilityHint("Opens the active workout")
    }
}

extension View {
    /// Rest pill while a timer runs; otherwise the active-session pill.
    /// Skipped under UI testing unless `MARBLE_ENABLE_REST_PILL` is set — the
    /// accessory perturbs tab-bar hit targets for unrelated flows.
    @ViewBuilder
    func marbleSessionAccessory(
        rest: ActiveRest?,
        session: WorkoutSession?,
        onEndRest: @escaping () -> Void,
        onOpenSession: @escaping () -> Void
    ) -> some View {
        let showsRest = rest != nil
        let showsSession = rest == nil && session != nil
        let isEnabled = showsRest || showsSession

        if TestHooks.isUITesting && !TestHooks.enableRestPillInUITests {
            self
        } else if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isEnabled) {
                if let rest {
                    RestTimerPillView(rest: rest, onEnd: onEndRest)
                } else if let session {
                    SessionAccessoryView(session: session, onOpen: onOpenSession)
                }
            }
        } else if let rest {
            self.tabViewBottomAccessory {
                RestTimerPillView(rest: rest, onEnd: onEndRest)
            }
        } else if let session {
            self.tabViewBottomAccessory {
                SessionAccessoryView(session: session, onOpen: onOpenSession)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func marbleRestPillAccessory(rest: ActiveRest?, onEnd: @escaping () -> Void) -> some View {
        marbleSessionAccessory(rest: rest, session: nil, onEndRest: onEnd, onOpenSession: {})
    }
}
