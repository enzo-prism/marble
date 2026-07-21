import SwiftUI
import WidgetKit

// NOTE: This file belongs to the **MarbleWidgets widget-extension target**.
// `SharedDefaults.swift` (which also defines `SharedKeychain`, the transport
// this file reads) and `WeeklyGoalWidgetState.swift` — both under
// `marble/Shared/` — must be added to this target's membership too; see
// SETUP.md and the RestTimerAttributes.swift precedent. The extension needs
// the `keychain-access-groups` entitlement in MarbleWidgets.entitlements to
// read the snapshot at all.
//
// Brand rules that apply here: monochrome, no Liquid Glass on content, no
// emoji, leaf-level accessibility identifiers only.

// MARK: - Timeline

nonisolated struct WeeklyGoalEntry: TimelineEntry {
    let date: Date
    /// nil means "nothing trustworthy to show" — render the neutral card
    /// rather than inventing numbers.
    let state: WeeklyGoalWidgetState?
}

/// `nonisolated` on purpose: the target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and `TimelineProvider`'s
/// requirements are not main-actor isolated.
nonisolated struct WeeklyGoalProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalEntry {
        WeeklyGoalEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalEntry) -> Void) {
        let now = Date()
        // The gallery always gets representative data; a real install gets
        // the truth, including the neutral card when there is none.
        let state = context.isPreview ? WeeklyGoalWidgetState.placeholder : currentState(now: now)
        completion(WeeklyGoalEntry(date: now, state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalEntry>) -> Void) {
        let now = Date()
        let state = currentState(now: now)
        let calendar = Calendar.current

        let nextDay = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60 * 24)

        // Week rollover: from the published week start when we have one,
        // otherwise from the calendar's current week.
        let weekStart = state?.weekStart ?? startOfWeek(for: now, calendar: calendar)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? nextDay

        var entries = [WeeklyGoalEntry(date: now, state: state)]
        // Re-render at each boundary so a rolled-over week can't keep showing
        // yesterday's copy even if a refresh budget is denied.
        for boundary in [nextDay, nextWeek] where boundary > now {
            entries.append(WeeklyGoalEntry(date: boundary, state: state))
        }

        let refreshAt = min(nextDay, nextWeek > now ? nextWeek : nextDay)
        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }

    /// Nil covers every "nothing trustworthy to show" case identically:
    /// nothing published yet, a snapshot older than a rolled-over week, or an
    /// unreadable keychain (no entitlement on the simulator, first-unlock not
    /// yet reached). All three render the neutral "Open Marble" card.
    private func currentState(now: Date) -> WeeklyGoalWidgetState? {
        guard let loaded = WeeklyGoalWidgetState.loadPublished(),
              !loaded.isStale(now: now) else { return nil }
        return loaded
    }

    /// Local copy of the app's week anchoring — the extension can't see
    /// `TrendsDateHelper`, and this only needs the calendar's own week rule.
    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Widget

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklyGoalWidget", provider: WeeklyGoalProvider()) { entry in
            WeeklyGoalWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Goal")
        .description("Sessions logged against this week's training target.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Copy

/// Everything the views say, derived once so every family stays consistent.
private enum WeeklyGoalCopy {
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

// MARK: - Views

private struct WeeklyGoalWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WeeklyGoalEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            accessoryInline
        case .systemMedium:
            medium.widgetURL(URL(string: "marble://trends"))
        default:
            small.widgetURL(URL(string: "marble://trends"))
        }
    }

    // MARK: Home Screen

    private var small: some View {
        Group {
            if let state = entry.state {
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

    private var medium: some View {
        Group {
            if let state = entry.state {
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
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(WeeklyGoalCopy.accessibility(state))
            } else {
                WeeklyGoalEmptyView()
            }
        }
    }

    // MARK: Lock Screen

    private var accessoryCircular: some View {
        Group {
            if let state = entry.state {
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

    private var accessoryRectangular: some View {
        Group {
            if let state = entry.state {
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

    private var accessoryInline: some View {
        Group {
            if let state = entry.state {
                Text("Weekly goal \(WeeklyGoalCopy.progress(state))")
            } else {
                Text("Weekly goal — open Marble")
            }
        }
        .accessibilityIdentifier("weeklyGoalWidget.inline")
    }
}

/// Monochrome progress ring. Deliberately plain shapes — no glass, no colour.
private struct WeeklyGoalRing: View {
    let state: WeeklyGoalWidgetState

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, state.progressFraction))
                .stroke(.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
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
private struct WeeklyGoalEmptyView: View {
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
