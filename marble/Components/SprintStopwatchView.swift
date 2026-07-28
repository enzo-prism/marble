import SwiftUI

/// Pure stopwatch arithmetic, separated from the view so tests can drive it
/// with injected dates (`AppEnvironment.now` convention — the view never
/// touches the wall clock for logic, only for the ticking readout).
nonisolated struct SprintStopwatchEngine: Equatable {
    var startedAt: Date?

    var isRunning: Bool { startedAt != nil }

    mutating func start(at date: Date) {
        startedAt = date
    }

    /// Stops and returns the elapsed tenths, clamped to the plausible sprint
    /// window; nil when not running or the clock went backwards.
    mutating func stop(at date: Date) -> Int? {
        guard let startedAt else { return nil }
        self.startedAt = nil
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }
        let tenths = SprintTiming.tenths(fromSeconds: elapsed)
        return SprintTiming.isPlausible(tenths: tenths) ? tenths : nil
    }

    mutating func reset() {
        startedAt = nil
    }

    func elapsedTenths(at date: Date) -> Int {
        guard let startedAt else { return 0 }
        return max(0, SprintTiming.tenths(fromSeconds: date.timeIntervalSince(startedAt)))
    }
}

/// Start/stop timing for a sprint rep, writing the result into the logger's
/// tenths binding on stop.
///
/// Hidden under UI testing (the rest-pill precedent): its readout ticks on the
/// wall clock, which a frozen `MARBLE_NOW_ISO8601` cannot make deterministic,
/// and the manual decimal field covers every test path. The engine itself is
/// unit-tested with injected dates.
struct SprintStopwatchView: View {
    @Binding var tenths: Int?

    @State private var engine = SprintStopwatchEngine()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            if engine.isRunning {
                // Leaf-scoped so only this Text invalidates per tick — the
                // TimedDailyHighlightsSection rule; the sheet never rebuilds.
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    Text(SprintTiming.text(tenths: engine.elapsedTenths(at: timeline.date)))
                        .font(MarbleTypography.rowTitle)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }
                .accessibilityLabel("Stopwatch running")
                .accessibilityIdentifier("AddSet.Sprint.StopwatchReadout")
            } else {
                Text("Time this rep")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer()

            Button {
                if engine.isRunning {
                    if let stopped = engine.stop(at: AppEnvironment.now) {
                        tenths = stopped
                        MarbleHaptics.success()
                    }
                } else {
                    engine.start(at: AppEnvironment.now)
                    MarbleHaptics.lightImpact()
                }
            } label: {
                Label(
                    engine.isRunning ? "Stop" : "Start",
                    systemImage: engine.isRunning ? "stop.circle.fill" : "stopwatch"
                )
                .font(MarbleTypography.rowSubtitle.weight(.semibold))
                .frame(minWidth: 88, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .background(
                Capsule().fill(Theme.chipFillColor(for: colorScheme))
            )
            .contentShape(Capsule())
            .accessibilityLabel(engine.isRunning ? "Stop stopwatch" : "Start stopwatch")
            .accessibilityHint(engine.isRunning ? "Stops timing and fills in the rep time." : "Times this rep and fills in the result.")
            .accessibilityIdentifier("AddSet.Sprint.Stopwatch")
        }
    }
}
