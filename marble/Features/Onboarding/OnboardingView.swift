import SwiftUI

/// First-run introduction: what Marble is, how often you plan to train, and
/// which weight unit you think in.
///
/// Self-contained on purpose — it owns no presentation logic and no dismissal.
/// `ContentView` decides whether to show it (via `OnboardingGate`) and reacts to
/// `onFinish`. Both preference pages write straight through to the shared
/// defaults suite as the user picks, so a mid-flow force-quit still keeps the
/// choices; only the completion flag waits for the final tap.
struct OnboardingView: View {
    /// Called once the user finishes the last page. The caller is responsible
    /// for dismissing; `didCompleteOnboarding` is already written by then.
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(SharedDefaults.Key.weeklySessionTarget, store: SharedDefaults.suite)
    private var weeklyTarget = TrainingConsistency.defaultWeeklyTarget

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    @State private var page = 0

    private static let pageCount = 3
    private static let weeklyTargetRange = 2...6

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    private var isLastPage: Bool { page == Self.pageCount - 1 }

    var body: some View {
        ZStack {
            Theme.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: MarbleSpacing.l) {
                TabView(selection: $page) {
                    welcomePage
                        .tag(0)
                    weeklyGoalPage
                        .tag(1)
                    weightUnitPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                advanceButton
                    .padding(.horizontal, MarbleLayout.pagePadding)
                    .padding(.bottom, MarbleSpacing.l)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Pages

    private var welcomePage: some View {
        pageLayout(
            symbol: "lock.shield",
            title: "Marble is yours alone",
            body: "Every set, session, and photo stays on this iPhone. No account, no server, no tracking — your training data never leaves your phone.",
            detail: "Backups are files you export yourself, whenever you want one."
        ) {
            EmptyView()
        }
    }

    private var weeklyGoalPage: some View {
        pageLayout(
            symbol: "target",
            title: "Set a weekly goal",
            body: "Marble tracks how many days you train each week and quietly nudges you when the goal is on the line.",
            detail: "You can change this any time in Settings."
        ) {
            VStack(spacing: MarbleSpacing.s) {
                Text("\(weeklyTarget)")
                    .font(.system(size: 56, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                Stepper(
                    value: $weeklyTarget,
                    in: Self.weeklyTargetRange,
                    step: 1
                ) {
                    Text("\(weeklyTarget) sessions per week")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: weeklyTarget) { _, _ in
                    MarbleHaptics.selection()
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Weekly session goal")
                .accessibilityValue("\(weeklyTarget) sessions per week")
                .accessibilityIdentifier("Onboarding.WeeklyTarget")
            }
        }
    }

    private var weightUnitPage: some View {
        pageLayout(
            symbol: "scalemass",
            title: "Pounds or kilos?",
            body: "New sets start in the unit you pick here.",
            detail: "Every set stores its own unit, so you can switch on any individual set without disturbing your history."
        ) {
            Picker("Default weight unit", selection: Binding(
                get: { weightUnit },
                set: { newValue in
                    guard newValue != weightUnit else { return }
                    preferredWeightUnitRaw = newValue.rawValue
                    MarbleHaptics.selection()
                }
            )) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .tint(Theme.dividerColor(for: colorScheme))
            .frame(minHeight: 44)
            .accessibilityIdentifier("Onboarding.WeightUnit")
        }
    }

    // MARK: - Building blocks

    /// One page: symbol, headline, supporting copy, then an optional control.
    /// Texts stay unclamped and vertically fixed so Dynamic Type can grow them
    /// without the accessibility audit flagging clipped lines.
    private func pageLayout<Control: View>(
        symbol: String,
        title: String,
        body copy: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    Text(title)
                        .font(MarbleTypography.screenTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(copy)
                        .font(MarbleTypography.body)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                control()

                Text(detail)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MarbleSpacing.xxl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MarbleLayout.pagePadding)
            .padding(.top, MarbleSpacing.xxl)
        }
    }

    /// A single button below the pager rather than one per page: the position
    /// stays put while paging, and only one "Continue"/"Get Started" identifier
    /// is ever live in the accessibility tree.
    private var advanceButton: some View {
        Button(action: advance) {
            Text(isLastPage ? "Get Started" : "Continue")
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
        .accessibilityIdentifier(isLastPage ? "Onboarding.Done" : "Onboarding.Continue")
    }

    private func advance() {
        guard !isLastPage else {
            finish()
            return
        }
        MarbleHaptics.selection()
        if TestHooks.disableAnimations || TestHooks.reduceDecorativeMotion {
            page += 1
        } else {
            withAnimation(.snappy(duration: 0.22)) {
                page += 1
            }
        }
    }

    private func finish() {
        // Make sure both preferences exist on disk even if the user never
        // touched either control, so downstream readers see a real value
        // rather than falling back independently.
        SharedDefaults.suite.set(weeklyTarget, forKey: SharedDefaults.Key.weeklySessionTarget)
        preferredWeightUnitRaw = weightUnit.rawValue
        OnboardingGate.markComplete()
        MarbleHaptics.celebrate()
        onFinish()
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
