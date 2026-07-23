import Accessibility
import SwiftUI

// Audio Graph descriptors for the Trends charts. Swift Charts synthesizes
// per-mark VoiceOver elements on its own, but not the `AXChartDescriptor`
// behind Audio Graphs ("Describe Chart", sonification, haptic exploration) —
// Apple's VoiceOver evaluation criteria treat that descriptor as part of a
// complete chart experience. Every Trends chart shares the two shapes below,
// so each call site supplies only title/summary/axis names/points and never
// touches AX boilerplate.
//
// `nonisolated` throughout: these are pure value types built from data the
// views already derived, the AX axis closures must stay free of main-actor
// state, and the unit tests exercise the range/label math directly.

/// Shared speech formatting for descriptor axes and points.
nonisolated enum TrendsAudioGraph {
    /// Dates spoken as "June 6", never "6/6" — the wide-month form the
    /// Calendar accessibility labels already use for spoken dates. The locale
    /// parameter exists for deterministic tests; production callers omit it.
    static func spokenDay(for date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.month(.wide).day().locale(locale))
    }

    /// Numbers spoken with at most two fraction digits (mirroring
    /// `Formatters.weight`), with an optional trailing unit.
    static func spokenValue(_ value: Double, unit: String?, locale: Locale = .autoupdatingCurrent) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }

    /// An axis range spanning `values`, widened when it would be degenerate:
    /// Audio Graphs need a non-empty span to plot against, so a single value
    /// pads upward and no values fall back to the unit range.
    static func axisRange(for values: [Double]) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0 ... 1
        }
        guard minValue < maxValue else {
            return minValue ... (maxValue + 1)
        }
        return minValue ... maxValue
    }
}

/// Audio Graph descriptor for the date-on-x line and bar charts (consistency,
/// volume, supplements, estimated 1RM, effort, bodyweight, exercise progress).
nonisolated struct TrendsDateSeriesAudioGraph: AXChartDescriptorRepresentable {
    struct Point {
        let date: Date
        let value: Double
        /// Full spoken value for this point, e.g. "185 lb, from 5 × 100 lb".
        let valueText: String

        /// What VoiceOver reads at this point of the graph.
        var spokenLabel: String {
            "\(TrendsAudioGraph.spokenDay(for: date)), \(valueText)"
        }
    }

    struct Series {
        let name: String
        let points: [Point]
    }

    let title: String
    /// The one-sentence overview VoiceOver reads before playing the graph —
    /// the same summary string the chart exposes as its accessibility value.
    let summary: String
    /// Spoken name of the value axis, e.g. "Estimated 1RM".
    let valueAxisName: String
    /// Unit appended when speaking raw axis values, e.g. "lb". Nil for
    /// unitless scores.
    let valueUnit: String?
    let series: [Series]

    /// Single-series convenience — most Trends charts plot one line.
    init(
        title: String,
        summary: String,
        valueAxisName: String,
        valueUnit: String?,
        seriesName: String,
        points: [Point]
    ) {
        self.init(
            title: title,
            summary: summary,
            valueAxisName: valueAxisName,
            valueUnit: valueUnit,
            series: [Series(name: seriesName, points: points)]
        )
    }

    init(
        title: String,
        summary: String,
        valueAxisName: String,
        valueUnit: String?,
        series: [Series]
    ) {
        self.title = title
        self.summary = summary
        self.valueAxisName = valueAxisName
        self.valueUnit = valueUnit
        self.series = series
    }

    /// X range in absolute time across every series.
    var dateRange: ClosedRange<Double> {
        TrendsAudioGraph.axisRange(
            for: series.flatMap { $0.points.map { $0.date.timeIntervalSinceReferenceDate } }
        )
    }

    /// Y range across every series.
    var valueRange: ClosedRange<Double> {
        TrendsAudioGraph.axisRange(for: series.flatMap { $0.points.map(\.value) })
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let unit = valueUnit
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: dateRange,
            gridlinePositions: []
        ) { value in
            TrendsAudioGraph.spokenDay(for: Date(timeIntervalSinceReferenceDate: value))
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: valueAxisName,
            range: valueRange,
            gridlinePositions: []
        ) { value in
            TrendsAudioGraph.spokenValue(value, unit: unit)
        }

        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: series.map { series in
                AXDataSeriesDescriptor(
                    name: series.name,
                    isContinuous: true,
                    dataPoints: series.points.map { point in
                        AXDataPoint(
                            x: point.date.timeIntervalSinceReferenceDate,
                            y: point.value,
                            label: point.spokenLabel
                        )
                    }
                )
            }
        )
    }
}

/// Audio Graph descriptor for the categorical bar charts (sets per muscle
/// group, rep ranges). The category axis is the independent axis regardless of
/// the bars' visual orientation.
nonisolated struct TrendsCategoryAudioGraph: AXChartDescriptorRepresentable {
    struct Bar {
        let category: String
        let value: Double
        /// Full spoken value for this bar, e.g. "12 sets, 40 percent".
        let valueText: String

        /// What VoiceOver reads at this bar of the graph.
        var spokenLabel: String {
            "\(category), \(valueText)"
        }
    }

    let title: String
    /// The one-sentence overview VoiceOver reads before playing the graph.
    let summary: String
    /// Spoken name of the category axis, e.g. "Muscle group".
    let categoryAxisName: String
    /// Spoken name of the value axis, e.g. "Hard sets per week".
    let valueAxisName: String
    /// Unit appended when speaking raw axis values. Nil for bare counts.
    let valueUnit: String?
    let bars: [Bar]

    /// Bars grow from zero, so the audible range is anchored there.
    var valueRange: ClosedRange<Double> {
        TrendsAudioGraph.axisRange(for: bars.map(\.value) + [0])
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let unit = valueUnit
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: categoryAxisName,
            categoryOrder: bars.map(\.category)
        )

        let yAxis = AXNumericDataAxisDescriptor(
            title: valueAxisName,
            range: valueRange,
            gridlinePositions: []
        ) { value in
            TrendsAudioGraph.spokenValue(value, unit: unit)
        }

        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [
                AXDataSeriesDescriptor(
                    name: title,
                    isContinuous: false,
                    dataPoints: bars.map { bar in
                        AXDataPoint(x: bar.category, y: bar.value, label: bar.spokenLabel)
                    }
                )
            ]
        )
    }
}

extension View {
    /// Attaches an Audio Graph descriptor when one is provided. Lets the
    /// scrub-overlay charts thread an optional descriptor through
    /// `TrendsChartOverlay` without every call site changing shape.
    @ViewBuilder
    func trendsAudioGraph(_ descriptor: TrendsDateSeriesAudioGraph?) -> some View {
        if let descriptor {
            accessibilityChartDescriptor(descriptor)
        } else {
            self
        }
    }
}
