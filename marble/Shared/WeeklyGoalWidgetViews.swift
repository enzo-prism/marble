import SwiftUI
import WidgetKit

// NOTE: This file is a member of **both** the app and the MarbleWidgets targets
// (the `RestTimerAttributes.swift` / `WeeklyGoalWidgetState.swift` precedent).
// It therefore references no app-only type: only SwiftUI, WidgetKit, and
// `WeeklyGoalWidgetState`.
//
// It lives here rather than in `MarbleWidgets/WeeklyGoalWidget.swift` so the
// five widget family layouts are reachable from the app's snapshot suite. The
// widget target keeps everything that cannot leave it — the `Widget`, the
// `TimelineProvider`, and the keychain read.
//
// Brand rules that apply here: monochrome, no Liquid Glass on content, no
// emoji, leaf-level accessibility identifiers only.

// MARK: - Copy

/// Everything the views say, derived once so every family stays consistent.
///
/// `nonisolated` because it is pure string formatting that both a `@MainActor`
/// view body and the widget's nonisolated `TimelineProvider` read.
nonisolated enum WeeklyGoalCopy {
    static func progress(_ state: WeeklyGoalWidgetState) -> String {
        "\(state.thisWeekSessions) of \(state.target)"
    }

    static func sessions(_ state: WeeklyGoalWidgetState) -> String {
        "\(progress(state)) sessions"
    }

    static func streak(_ state: WeeklyGoalWidgetState) -> String {
        state.streakWeeks == 1 ? "1-week streak" : "\(state.streakWeeks)-week streak"
    }

    static func flex(_ state: WeeklyGoalWidgetState) -> String {
        state.flexTokens == 1 ? "1 flex week banked" : "\(state.flexTokens) flex weeks banked"
    }

    static func stateLine(_ state: WeeklyGoalWidgetState) -> String {
        switch state.stateRaw {
        case "fresh": "Log a set to start the week."
        case "hit": "Target hit. Week banked."
        case "atRisk": "Every remaining day counts."
        case "comeback": "Back on track."
        default: "On track for this week."
        }
    }

    static func accessibility(_ state: WeeklyGoalWidgetState) -> String {
        "\(sessions(state)) this week. \(streak(state)). \(stateLine(state))"
    }
}

// MARK: - Family router

/// Picks the layout for the current `widgetFamily`. The deep links stay here
/// with the layouts they belong to.
///
/// Tap routing: the card itself opens Trends, and the medium family
/// additionally carries a quick-log `Link` (its area wins over the
/// `widgetURL`). A `Link` rather than an intent `Button` on purpose — the
/// widget process never opens SwiftData, so the only honest action is "open the
/// app to the logger", and Apple asks that widget buttons do more than open the
/// app. `systemSmall` supports exactly one tap target (`widgetURL`), so it stays
/// whole-card; accessory families stay link-only.
struct WeeklyGoalWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    /// nil means "nothing trustworthy to show" — render the neutral card
    /// rather than inventing numbers.
    let state: WeeklyGoalWidgetState?

    init(state: WeeklyGoalWidgetState?) {
        self.state = state
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            WeeklyGoalCircularView(state: state)
        case .accessoryRectangular:
            WeeklyGoalRectangularView(state: state)
        case .accessoryInline:
            WeeklyGoalInlineView(state: state)
        case .systemMedium:
            WeeklyGoalMediumView(state: state)
                .widgetURL(URL(string: "marble://trends"))
        default:
            WeeklyGoalSmallView(state: state)
                .widgetURL(URL(string: "marble://trends"))
        }
    }
}

// MARK: - Home Screen

struct WeeklyGoalSmallView: View {
    let state: WeeklyGoalWidgetState?

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 8) {
                WeeklyGoalRing(state: state)
                    .frame(width: 54, height: 54)
                    .accessibilityIdentifier("weeklyGoalWidget.ring")
                Spacer(minLength: 0)
                Text(WeeklyGoalCopy.sessions(state))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("weeklyGoalWidget.sessions")
                Text(WeeklyGoalCopy.stateLine(state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("weeklyGoalWidget.stateLine")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(WeeklyGoalCopy.accessibility(state))
        } else {
            WeeklyGoalEmptyView()
        }
    }
}

struct WeeklyGoalMediumView: View {
    let state: WeeklyGoalWidgetState?

    var body: some View {
        if let state {
            HStack(alignment: .center, spacing: 16) {
                // Ring + copy stay one combined accessibility element; the
                // quick-log link sits outside the combine so VoiceOver still
                // exposes it as its own tappable control.
                HStack(alignment: .center, spacing: 16) {
                    WeeklyGoalRing(state: state)
                        .frame(width: 64, height: 64)
                        .accessibilityIdentifier("weeklyGoalWidget.ring")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("weeklyGoalWidget.title")
                        Text(WeeklyGoalCopy.sessions(state))
                            .font(.headline)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("weeklyGoalWidget.sessions")
                        Text("\(WeeklyGoalCopy.streak(state)) · \(WeeklyGoalCopy.flex(state))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("weeklyGoalWidget.streak")
                        Text(WeeklyGoalCopy.stateLine(state))
                            .font(.caption)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("weeklyGoalWidget.stateLine")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(WeeklyGoalCopy.accessibility(state))
                Spacer(minLength: 8)
                WeeklyGoalQuickLogLink()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            WeeklyGoalEmptyView()
        }
    }
}

// MARK: - Lock Screen

struct WeeklyGoalCircularView: View {
    let state: WeeklyGoalWidgetState?

    var body: some View {
        if let state {
            Gauge(value: state.progressFraction) {
                EmptyView()
            } currentValueLabel: {
                Text("\(state.thisWeekSessions)")
                    .accessibilityIdentifier("weeklyGoalWidget.accessoryCount")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("Weekly goal")
            .accessibilityValue(WeeklyGoalCopy.sessions(state))
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
                .accessibilityLabel("Open Marble to refresh the weekly goal")
                .accessibilityIdentifier("weeklyGoalWidget.accessoryEmpty")
        }
    }
}

struct WeeklyGoalRectangularView: View {
    let state: WeeklyGoalWidgetState?

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 1) {
                Text("Weekly goal")
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("weeklyGoalWidget.accessoryTitle")
                Text("\(WeeklyGoalCopy.progress(state)) · \(WeeklyGoalCopy.streak(state))")
                    .lineLimit(1)
                    .accessibilityIdentifier("weeklyGoalWidget.accessoryProgress")
                Text(WeeklyGoalCopy.stateLine(state))
                    .font(.caption)
                    .lineLimit(2)
                    .accessibilityIdentifier("weeklyGoalWidget.accessoryStateLine")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(WeeklyGoalCopy.accessibility(state))
        } else {
            Text("Open Marble to refresh your weekly goal.")
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("weeklyGoalWidget.accessoryEmpty")
        }
    }
}

struct WeeklyGoalInlineView: View {
    let state: WeeklyGoalWidgetState?

    var body: some View {
        Group {
            if let state {
                Text("Weekly goal \(WeeklyGoalCopy.progress(state))")
            } else {
                Text("Weekly goal — open Marble")
            }
        }
        .accessibilityIdentifier("weeklyGoalWidget.inline")
    }
}

// MARK: - Pieces

/// The medium family's quick-log affordance: a `Link` whose area overrides the
/// card's `widgetURL`, deep-linking straight to the quick-log sheet
/// (`marble://quicklog` in `ContentView`, the same `QuickLogCoordinator` path
/// `OpenQuickLogIntent` reaches by notification). Monochrome like everything
/// else here — the capsule fill alone marks it as the tappable part.
struct WeeklyGoalQuickLogLink: View {
    var body: some View {
        if let url = URL(string: "marble://quicklog") {
            Link(destination: url) {
                Label("Log set", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    // Monochrome, per the brand rule: a `Link` otherwise renders in
                    // the system accent (blue), which the new widget snapshot suite
                    // caught the moment it had a baseline to look at.
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            // `tint`, not just `foregroundStyle`: a `Link` colours its label
            // through the accent, so the inner style alone left the pill system
            // blue — which the new widget snapshot suite caught. Monochrome is
            // the brand rule.
            .tint(.primary)
            // Accent group: on a tinted/clear Home Screen the one actionable
            // element picks up the accent while the copy stays primary.
            .widgetAccentable()
            .accessibilityLabel("Log a set")
            .accessibilityIdentifier("weeklyGoalWidget.quickLogLink")
        }
    }
}

/// Monochrome progress ring. Deliberately plain shapes — no glass, no colour.
struct WeeklyGoalRing: View {
    let state: WeeklyGoalWidgetState

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, state.progressFraction))
                .stroke(.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Accent group: in accented rendering the progress arc tints
                // while the track and count stay in the primary group, so the
                // ring keeps its hierarchy instead of flattening to one tone.
                // No-op in default rendering — full-colour stays pixel-identical.
                .widgetAccentable()
            Text("\(state.thisWeekSessions)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }
}

/// Shown when no snapshot has been published yet, or the published one is
/// stale. Never fabricates numbers.
struct WeeklyGoalEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly goal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("weeklyGoalWidget.emptyTitle")
            Text("Open Marble to see this week's sessions.")
                .font(.footnote)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("weeklyGoalWidget.emptyBody")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
