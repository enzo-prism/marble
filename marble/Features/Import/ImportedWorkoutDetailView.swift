import SwiftUI
import Charts

/// Read-only detail for an imported (or importable) workout: everything the
/// summary row can't fit — full stats grid, provenance, and a heart-rate
/// sparkline fetched live from Apple Health. Works from either a fetched
/// `WorkoutImportRecord` (pre-import) or an `ImportedWorkout` ledger row
/// (post-import history), so both paths share one screen.
struct ImportedWorkoutDetailView: View {
    /// Unified display payload for both entry points.
    struct Details {
        let title: String
        let kind: ImportedActivityKind
        let date: Date
        let source: ImportSource
        let originName: String?
        let sourceAppName: String?
        let deviceName: String?
        let durationSeconds: Int?
        let distanceMeters: Double?
        let calories: Double?
        let averageHeartRate: Double?
        let maxHeartRate: Double?
        let elevationAscendedMeters: Double?
        let isIndoor: Bool?

        var displayOrigin: String { originName ?? source.displayName }

        var paceSecondsPerKilometer: Int? {
            guard let distanceMeters, distanceMeters > 0,
                  let durationSeconds, durationSeconds > 0 else { return nil }
            return Int((Double(durationSeconds) / (distanceMeters / 1000)).rounded())
        }

        /// The workout's time window, for the heart-rate series query.
        var window: ClosedRange<Date>? {
            guard let durationSeconds, durationSeconds > 0 else { return nil }
            return date...date.addingTimeInterval(TimeInterval(durationSeconds))
        }

        init(record: WorkoutImportRecord) {
            title = record.title
            kind = record.kind
            date = record.date
            source = record.source
            originName = record.originName
            sourceAppName = record.sourceAppName
            deviceName = record.deviceName
            durationSeconds = record.durationSeconds
            distanceMeters = record.distanceMeters
            calories = record.calories
            averageHeartRate = record.averageHeartRate
            maxHeartRate = record.maxHeartRate
            elevationAscendedMeters = record.elevationAscendedMeters
            isIndoor = record.isIndoor
        }

        init(workout: ImportedWorkout) {
            title = workout.title
            kind = workout.kind ?? .other
            date = workout.workoutDate
            source = workout.source
            originName = workout.originName
            sourceAppName = workout.sourceAppName
            deviceName = workout.deviceName
            durationSeconds = workout.durationSeconds
            distanceMeters = workout.distanceMeters
            calories = workout.calories
            averageHeartRate = workout.averageHeartRate
            maxHeartRate = workout.maxHeartRate
            elevationAscendedMeters = workout.elevationAscendedMeters
            isIndoor = workout.isIndoor
        }
    }

    let details: Details
    /// Loads the heart-rate sparkline for the workout window; `nil` (non-Health
    /// sources, tests) hides the chart section entirely.
    var heartRateLoader: ((_ start: Date, _ end: Date) async -> [HeartRatePoint])?

    @Environment(\.colorScheme) private var colorScheme
    @State private var heartRatePoints: [HeartRatePoint] = []
    @State private var isLoadingHeartRate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                header
                statsGrid
                heartRateSection
                provenance
            }
            .padding(MarbleLayout.pagePadding)
        }
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("ImportDetail.View")
        .task {
            await loadHeartRate()
        }
    }

    private var header: some View {
        HStack(spacing: MarbleSpacing.s) {
            ScaledSymbol(systemName: details.kind.systemImage, size: 28, weight: .semibold)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(details.title)
                    .font(MarbleTypography.screenTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Text(Formatters.fullDateTime.string(from: details.date))
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            Spacer(minLength: 0)
        }
    }

    private struct Stat: Identifiable {
        let id: String
        let label: String
        let value: String
        var accessibilityValue: String { "\(label), \(value)" }
    }

    private var stats: [Stat] {
        var result: [Stat] = []
        if let duration = details.durationSeconds, duration > 0 {
            result.append(Stat(id: "duration", label: "Duration", value: DateHelper.formattedDuration(seconds: duration)))
        }
        if let distance = details.distanceMeters, distance > 0 {
            result.append(Stat(id: "distance", label: "Distance", value: Self.distanceText(distance)))
        }
        if let pace = details.paceSecondsPerKilometer, details.kind.isCardio {
            result.append(Stat(id: "pace", label: "Pace", value: String(format: "%d:%02d /km", pace / 60, pace % 60)))
        }
        if let calories = details.calories, calories > 0 {
            result.append(Stat(id: "calories", label: "Calories", value: "\(Int(calories)) kcal"))
        }
        if let average = details.averageHeartRate, average > 0 {
            result.append(Stat(id: "avgHR", label: "Avg Heart Rate", value: "\(Int(average)) bpm"))
        }
        if let maximum = details.maxHeartRate, maximum > 0 {
            result.append(Stat(id: "maxHR", label: "Max Heart Rate", value: "\(Int(maximum)) bpm"))
        }
        if let elevation = details.elevationAscendedMeters, elevation > 0 {
            result.append(Stat(id: "elevation", label: "Elevation Gain", value: "\(Int(elevation)) m"))
        }
        if let isIndoor = details.isIndoor {
            result.append(Stat(id: "environment", label: "Environment", value: isIndoor ? "Indoor" : "Outdoor"))
        }
        return result
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: MarbleSpacing.m
        ) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(stat.label)
                        .font(MarbleTypography.smallLabel)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    Text(stat.value)
                        .font(MarbleTypography.rowTitle)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.accessibilityValue)
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground()
        .accessibilityIdentifier("ImportDetail.Stats")
    }

    /// Garmin bridges HR sparsely (sometimes just a couple of samples per
    /// workout), so the sparkline only renders when there's a real curve to
    /// show; avg/max stay in the stats grid regardless.
    private static let sparklineMinimumPoints = 8

    @ViewBuilder
    private var heartRateSection: some View {
        if heartRatePoints.count >= Self.sparklineMinimumPoints {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Text("Heart Rate")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Chart(heartRatePoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("BPM", point.beatsPerMinute)
                    )
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: 120)
                .accessibilityElement()
                .accessibilityLabel(heartRateAccessibilityLabel)
                .accessibilityIdentifier("ImportDetail.HeartRateChart")
            }
        } else if isLoadingHeartRate {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private var heartRateAccessibilityLabel: String {
        var label = "Heart rate over the workout"
        if let average = details.averageHeartRate, average > 0 {
            label += ", average \(Int(average)) beats per minute"
        }
        if let maximum = details.maxHeartRate, maximum > 0 {
            label += ", peak \(Int(maximum))"
        }
        return label
    }

    @ViewBuilder
    private var provenance: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Source")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            provenanceRow(label: "Recorded by", value: details.displayOrigin)
            if let app = details.sourceAppName, app != details.displayOrigin {
                provenanceRow(label: "Via", value: app)
            }
            if let device = details.deviceName {
                provenanceRow(label: "Device", value: device)
            }
        }
        .accessibilityIdentifier("ImportDetail.Source")
    }

    private func provenanceRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Spacer(minLength: MarbleSpacing.s)
            Text(value)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadHeartRate() async {
        guard let loader = heartRateLoader, let window = details.window else { return }
        isLoadingHeartRate = true
        heartRatePoints = await loader(window.lowerBound, window.upperBound)
        isLoadingHeartRate = false
    }

    static func distanceText(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}
