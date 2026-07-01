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

extension View {
    /// Installs the rest-timer pill as the tab bar's bottom accessory. Skipped
    /// entirely under UI testing (even disabled, the accessory perturbs the tab
    /// bar's accessibility layout and fails audits); the dedicated rest-pill
    /// test opts back in via `MARBLE_ENABLE_REST_PILL`.
    @ViewBuilder
    func marbleRestPillAccessory(rest: ActiveRest?, onEnd: @escaping () -> Void) -> some View {
        if TestHooks.isUITesting && !TestHooks.enableRestPillInUITests {
            self
        } else {
            self.tabViewBottomAccessory(isEnabled: rest != nil) {
                if let rest {
                    RestTimerPillView(rest: rest, onEnd: onEnd)
                }
            }
        }
    }
}
