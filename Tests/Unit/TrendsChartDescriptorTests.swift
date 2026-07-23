import Accessibility
import Foundation
import XCTest
@testable import marble

/// The Audio Graph descriptor helper behind every Trends chart: axis-range
/// padding, speech formatting, point labels, and the assembled
/// `AXChartDescriptor`. Pure value math — no views, no AX runtime.
final class TrendsChartDescriptorTests: MarbleTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    /// Noon UTC so the calendar day is stable across CI timezones.
    private func day(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: "\(iso)T12:00:00Z")!
    }

    // MARK: - Speech formatting

    func testSpokenDayUsesWideMonthNeverNumericSlashes() {
        let spoken = TrendsAudioGraph.spokenDay(for: day("2025-06-06"), locale: posix)

        XCTAssertEqual(spoken, "June 6")
        XCTAssertFalse(spoken.contains("/"))
    }

    func testSpokenValueAppendsUnitAndCapsFractionDigits() {
        XCTAssertEqual(TrendsAudioGraph.spokenValue(185, unit: "lb", locale: posix), "185 lb")
        XCTAssertEqual(TrendsAudioGraph.spokenValue(72.5, unit: "kg", locale: posix), "72.5 kg")
        XCTAssertEqual(TrendsAudioGraph.spokenValue(8.333333, unit: nil, locale: posix), "8.33")
        XCTAssertEqual(TrendsAudioGraph.spokenValue(12, unit: "", locale: posix), "12")
    }

    // MARK: - Axis ranges

    func testAxisRangeSpansValuesAndPadsDegenerateInputs() {
        XCTAssertEqual(TrendsAudioGraph.axisRange(for: [3, 9, 5]), 3 ... 9)
        // A single value must not collapse the range to a point.
        XCTAssertEqual(TrendsAudioGraph.axisRange(for: [7]), 7 ... 8)
        // No values at all falls back to the unit range.
        XCTAssertEqual(TrendsAudioGraph.axisRange(for: []), 0 ... 1)
    }

    func testDateSeriesRangesSpanAllSeries() {
        let first = day("2025-01-01")
        let last = day("2025-01-08")
        let graph = TrendsDateSeriesAudioGraph(
            title: "Estimated 1RM",
            summary: "Best 185 lb",
            valueAxisName: "Estimated 1RM",
            valueUnit: "lb",
            series: [
                TrendsDateSeriesAudioGraph.Series(name: "A", points: [
                    TrendsDateSeriesAudioGraph.Point(date: first, value: 180, valueText: "180 lb")
                ]),
                TrendsDateSeriesAudioGraph.Series(name: "B", points: [
                    TrendsDateSeriesAudioGraph.Point(date: last, value: 185, valueText: "185 lb")
                ])
            ]
        )

        XCTAssertEqual(
            graph.dateRange,
            first.timeIntervalSinceReferenceDate ... last.timeIntervalSinceReferenceDate
        )
        XCTAssertEqual(graph.valueRange, 180 ... 185)
    }

    func testCategoryValueRangeIsAnchoredAtZero() {
        let graph = TrendsCategoryAudioGraph(
            title: "Rep ranges",
            summary: "30 sets across 3 rep ranges",
            categoryAxisName: "Rep range",
            valueAxisName: "Sets",
            valueUnit: "sets",
            bars: [
                TrendsCategoryAudioGraph.Bar(category: "Strength", value: 4, valueText: "4 sets"),
                TrendsCategoryAudioGraph.Bar(category: "Hypertrophy", value: 20, valueText: "20 sets")
            ]
        )

        XCTAssertEqual(graph.valueRange, 0 ... 20)
    }

    // MARK: - Point labels

    func testDatePointSpokenLabelLeadsWithTheSpokenDay() {
        let point = TrendsDateSeriesAudioGraph.Point(
            date: day("2025-06-06"),
            value: 185,
            valueText: "185 lb, from 5 × 165 lb"
        )

        XCTAssertEqual(
            point.spokenLabel,
            "\(TrendsAudioGraph.spokenDay(for: point.date)), 185 lb, from 5 × 165 lb"
        )
    }

    func testBarSpokenLabelLeadsWithTheCategory() {
        let bar = TrendsCategoryAudioGraph.Bar(
            category: "Chest",
            value: 12.5,
            valueText: "12.5 sets per week, in range"
        )

        XCTAssertEqual(bar.spokenLabel, "Chest, 12.5 sets per week, in range")
    }

    // MARK: - Assembled descriptors

    func testDateSeriesDescriptorCarriesTitleSummaryAxesAndPoints() {
        let graph = TrendsDateSeriesAudioGraph(
            title: "Bodyweight",
            summary: "Latest 172 lb across 2 measurements",
            valueAxisName: "Bodyweight",
            valueUnit: "lb",
            seriesName: "Bodyweight",
            points: [
                TrendsDateSeriesAudioGraph.Point(date: day("2025-01-01"), value: 171, valueText: "171 lb"),
                TrendsDateSeriesAudioGraph.Point(date: day("2025-01-02"), value: 172, valueText: "172 lb")
            ]
        )

        let descriptor = graph.makeChartDescriptor()

        XCTAssertEqual(descriptor.title, "Bodyweight")
        XCTAssertEqual(descriptor.summary, "Latest 172 lb across 2 measurements")

        let xAxis = descriptor.xAxis as? AXNumericDataAxisDescriptor
        XCTAssertEqual(xAxis?.title, "Date")
        XCTAssertEqual(xAxis?.range, graph.dateRange)
        XCTAssertEqual(descriptor.yAxis?.title, "Bodyweight")
        XCTAssertEqual(descriptor.yAxis?.range, 171 ... 172)

        XCTAssertEqual(descriptor.series.count, 1)
        XCTAssertEqual(descriptor.series.first?.name, "Bodyweight")
        XCTAssertEqual(descriptor.series.first?.isContinuous, true)
        XCTAssertEqual(
            descriptor.series.first?.dataPoints.map(\.label),
            graph.series.first?.points.map(\.spokenLabel)
        )
    }

    func testCategoryDescriptorPreservesBarOrderAsCategoricalAxis() {
        let graph = TrendsCategoryAudioGraph(
            title: "Weekly sets per muscle group",
            summary: "3 muscle groups in range",
            categoryAxisName: "Muscle group",
            valueAxisName: "Hard sets per week",
            valueUnit: "sets per week",
            bars: [
                TrendsCategoryAudioGraph.Bar(category: "Chest", value: 12, valueText: "12 sets per week"),
                TrendsCategoryAudioGraph.Bar(category: "Back", value: 16, valueText: "16 sets per week"),
                TrendsCategoryAudioGraph.Bar(category: "Legs", value: 9, valueText: "9 sets per week")
            ]
        )

        let descriptor = graph.makeChartDescriptor()

        let xAxis = descriptor.xAxis as? AXCategoricalDataAxisDescriptor
        XCTAssertEqual(xAxis?.title, "Muscle group")
        XCTAssertEqual(xAxis?.categoryOrder, ["Chest", "Back", "Legs"])
        XCTAssertEqual(descriptor.yAxis?.range, 0 ... 16)
        XCTAssertEqual(descriptor.series.first?.isContinuous, false)
        XCTAssertEqual(descriptor.series.first?.dataPoints.count, 3)
    }
}
