import SwiftUI

/// Day-by-day training heatmap — the hero of the Consistency section.
///
/// One `Canvas` draws every day of the range so a year of squares stays
/// cheap. The layout adapts to the span: a week strip (≤ 7 days), a month
/// calendar (≤ 42), a contribution grid (≤ 120) and twelve mini-months beyond
/// that. A single overlay button carries the identifier, VoiceOver summary,
/// Audio Graph and the tap → day mapping, exactly like `TrendsChartOverlay`.
struct TrendsConsistencyHeatmap: View {
    let model: TrendsHeatmapModel
    let availableWidth: CGFloat
    let selectedDate: Date?
    let accessibilityValue: String
    let audioGraph: TrendsDateSeriesAudioGraph?
    let onSelectDay: (Date) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 13
    @State private var revealProgress: Double = trendsInitiallyRevealed() ? 1 : 0
    @State private var isRevealed = trendsInitiallyRevealed()

    private var calendar: Calendar { .current }

    private var showsLabels: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var geometry: TrendsHeatmapGeometry {
        TrendsHeatmapGeometry(
            days: model.days.map(\.date),
            width: max(availableWidth, 120),
            labelHeight: showsLabels ? labelHeight : 0,
            monthColumns: dynamicTypeSize >= .xxLarge ? 3 : 4,
            calendar: calendar
        )
    }

    var body: some View {
        let geometry = geometry
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            TrendsHeatmapCanvas(
                model: model,
                geometry: geometry,
                selectedDate: selectedDate.map { calendar.startOfDay(for: $0) },
                showsLabels: showsLabels,
                progress: revealProgress
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay { hitTarget(geometry: geometry) }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !showsLabels, let first = model.first, let last = model.last {
                Text("\(DateHelper.dayLabel(for: first)) – \(DateHelper.dayLabel(for: last))")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            TrendsHeatmapLegend(accent: accent)
        }
        .trendsReveal($isRevealed)
        .onChange(of: isRevealed) { _, revealed in
            guard revealed else { return }
            withAnimation(.easeOut(duration: 0.9)) { revealProgress = 1 }
        }
        .onAppear {
            if isRevealed { revealProgress = 1 }
        }
    }

    private var accent: Color { TrendsPalette.consistency.color(for: colorScheme) }

    private func hitTarget(geometry: TrendsHeatmapGeometry) -> some View {
        Button {
            if TestHooks.isUITesting { selectDefaultDay() }
        } label: {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consistency chart")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("Trends.ConsistencyChart")
        .accessibilityHint("Opens details for the most recent training day.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectDefaultDay() }
        .trendsAudioGraph(audioGraph)
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                // UI tests drive selection through the button action so a tap
                // on a rest day can never race the drilldown they assert.
                guard !TestHooks.isUITesting,
                      let index = geometry.dayIndex(at: value.location),
                      model.days.indices.contains(index)
                else { return }
                MarbleHaptics.selection()
                onSelectDay(model.days[index].date)
            }
        )
        .allowsHitTesting(!model.days.isEmpty)
    }

    private func selectDefaultDay() {
        if let latestActive = model.days.last(where: { $0.count > 0 }) {
            onSelectDay(latestActive.date)
        } else if let last = model.days.last {
            onSelectDay(last.date)
        }
    }
}

// MARK: - Canvas

/// The drawing itself. `Animatable` so the reveal sweep interpolates frame by
/// frame; with motion disabled `progress` is pinned at 1.
private struct TrendsHeatmapCanvas: View, Animatable {
    let model: TrendsHeatmapModel
    let geometry: TrendsHeatmapGeometry
    let selectedDate: Date?
    let showsLabels: Bool
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let scheme = colorScheme
        let accent = TrendsPalette.consistency.color(for: scheme)
        let gold = TrendsPalette.personalRecord.color(for: scheme)
        let empty = Theme.chipFillColor(for: scheme)
        let primary = Theme.primaryTextColor(for: scheme)
        let secondary = Theme.secondaryTextColor(for: scheme)
        let onAccent = Theme.onAccentColor(for: scheme)
        let placeholder = Theme.subtleDividerColor(for: scheme).opacity(0.45)
        let total = max(model.days.count, 1)

        return Canvas { context, _ in
            if showsLabels {
                for label in geometry.labels {
                    let text = Text(label.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondary)
                    context.draw(context.resolve(text), at: label.point, anchor: label.anchor)
                }
            }

            for placeholderRect in geometry.placeholderRects {
                let path = Path(roundedRect: placeholderRect, cornerRadius: geometry.cornerRadius, style: .continuous)
                context.fill(path, with: .color(placeholder))
            }

            for (index, rect) in geometry.cellRects.enumerated() where model.days.indices.contains(index) {
                let day = model.days[index]
                // A left-to-right sweep: later days start later.
                let delay = Double(index) / Double(total) * 0.55
                let local = min(max((progress - delay) / 0.45, 0), 1)
                guard local > 0 else { continue }

                let scale = 0.55 + 0.45 * local
                let drawRect = rect.insetBy(
                    dx: rect.width * (1 - scale) / 2,
                    dy: rect.height * (1 - scale) / 2
                )
                let path = Path(roundedRect: drawRect, cornerRadius: geometry.cornerRadius * scale, style: .continuous)
                var cellContext = context
                cellContext.opacity = local

                let fill: Color
                if day.level == 0 {
                    fill = empty
                } else if day.hasPR && rect.width < 12 {
                    fill = gold
                } else {
                    fill = accent.opacity(Self.opacity(for: day.level))
                }
                cellContext.fill(path, with: .color(fill))

                if geometry.showsDayNumbers {
                    let dayNumber = Calendar.current.component(.day, from: day.date)
                    let text = Text("\(dayNumber)")
                        .font(.system(size: max(9, rect.width * 0.34), weight: .semibold, design: .rounded))
                        .foregroundStyle(day.level >= 3 ? onAccent : (day.level == 0 ? secondary : primary))
                    cellContext.draw(cellContext.resolve(text), at: CGPoint(x: drawRect.midX, y: drawRect.midY))
                }

                if day.hasPR, rect.width >= 12 {
                    let radius = max(2.5, rect.width * 0.13)
                    let inset = max(2, rect.width * 0.12)
                    let dot = CGRect(
                        x: drawRect.maxX - inset - radius * 2,
                        y: drawRect.minY + inset,
                        width: radius * 2,
                        height: radius * 2
                    )
                    cellContext.fill(Path(ellipseIn: dot.insetBy(dx: -1, dy: -1)), with: .color(day.level >= 3 ? onAccent : Theme.surfaceColor(for: scheme)))
                    cellContext.fill(Path(ellipseIn: dot), with: .color(gold))
                }

                if day.isToday {
                    let ring = Path(roundedRect: drawRect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: geometry.cornerRadius, style: .continuous)
                    cellContext.stroke(ring, with: .color(primary.opacity(0.55)), lineWidth: rect.width < 12 ? 1 : 1.5)
                }

                if let selectedDate, day.date == selectedDate {
                    let ring = Path(
                        roundedRect: drawRect.insetBy(dx: -2.5, dy: -2.5),
                        cornerRadius: geometry.cornerRadius + 2.5,
                        style: .continuous
                    )
                    cellContext.stroke(ring, with: .color(primary), lineWidth: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    static func opacity(for level: Int) -> Double {
        switch level {
        case 1: 0.3
        case 2: 0.52
        case 3: 0.76
        default: 1
        }
    }
}

// MARK: - Legend

private struct TrendsHeatmapLegend: View {
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MarbleSpacing.m) {
                scale
                Spacer(minLength: 0)
                prKey
                todayKey
            }
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                scale
                HStack(spacing: MarbleSpacing.m) {
                    prKey
                    todayKey
                }
            }
        }
        .font(MarbleTypography.rowMeta)
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .accessibilityHidden(true)
    }

    private var scale: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach(0...TrendsHeatmapModel.levelCount, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(level == 0
                        ? Theme.chipFillColor(for: colorScheme)
                        : accent.opacity(TrendsHeatmapCanvas.opacity(for: level)))
                    .frame(width: 11, height: 11)
            }
            Text("More")
        }
    }

    private var prKey: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(TrendsPalette.personalRecord.color(for: colorScheme))
                .frame(width: 7, height: 7)
            Text("PR")
        }
    }

    private var todayKey: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(Theme.primaryTextColor(for: colorScheme).opacity(0.55), lineWidth: 1.25)
                .frame(width: 10, height: 10)
            Text("Today")
        }
    }
}

// MARK: - Geometry

/// Pure layout for the heatmap: where every day's square goes, the axis
/// labels, and the inverse mapping from a tap back to a day.
struct TrendsHeatmapGeometry {
    enum Style: Equatable {
        case strip, calendar, contribution, months
    }

    struct Label {
        let text: String
        let point: CGPoint
        let anchor: UnitPoint
    }

    let style: Style
    /// Index-aligned with the input days.
    private(set) var cellRects: [CGRect] = []
    /// Days inside a drawn month that fall outside the range.
    private(set) var placeholderRects: [CGRect] = []
    private(set) var labels: [Label] = []
    private(set) var size: CGSize = .zero
    private(set) var cornerRadius: CGFloat = 3
    private(set) var showsDayNumbers = false

    static func style(forDayCount count: Int) -> Style {
        switch count {
        case ...7: .strip
        case ...42: .calendar
        case ...126: .contribution
        default: .months
        }
    }

    init(days: [Date], width: CGFloat, labelHeight: CGFloat, monthColumns: Int = 4, calendar: Calendar) {
        style = Self.style(forDayCount: days.count)
        guard !days.isEmpty else { return }
        switch style {
        case .strip: layoutStrip(days, width: width, labelHeight: labelHeight, calendar: calendar)
        case .calendar: layoutCalendar(days, width: width, labelHeight: labelHeight, calendar: calendar)
        case .contribution: layoutContribution(days, width: width, labelHeight: labelHeight, calendar: calendar)
        case .months: layoutMonths(days, width: width, labelHeight: labelHeight, columns: monthColumns, calendar: calendar)
        }
    }

    /// The day under `point`, or the nearest square within half a cell.
    func dayIndex(at point: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, rect) in cellRects.enumerated() {
            if rect.insetBy(dx: -2, dy: -2).contains(point) { return index }
            let dx = point.x - rect.midX
            let dy = point.y - rect.midY
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= rect.width, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    // MARK: Layouts

    private func weekdayColumn(_ date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    private func weekdaySymbol(column: Int, calendar: Calendar) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(column + calendar.firstWeekday - 1) % 7]
    }

    private mutating func layoutStrip(_ days: [Date], width: CGFloat, labelHeight: CGFloat, calendar: Calendar) {
        let columns: CGFloat = 7
        let cell = min(floor((width - 6 * 6) / columns), 52)
        let gap = (width - columns * cell) / (columns - 1)
        let top = labelHeight > 0 ? labelHeight + 6 : 0
        cornerRadius = cell * 0.26
        showsDayNumbers = true
        // Right-align a short range so today always sits in the last column.
        let offset = Int(columns) - days.count
        for (index, date) in days.enumerated() {
            let column = CGFloat(index + offset)
            let rect = CGRect(x: column * (cell + gap), y: top, width: cell, height: cell)
            cellRects.append(rect)
            if labelHeight > 0 {
                let symbol = weekdaySymbol(column: weekdayColumn(date, calendar: calendar), calendar: calendar)
                labels.append(Label(text: symbol, point: CGPoint(x: rect.midX, y: 0), anchor: .top))
            }
        }
        size = CGSize(width: width, height: top + cell)
    }

    private mutating func layoutCalendar(_ days: [Date], width: CGFloat, labelHeight: CGFloat, calendar: Calendar) {
        let cell = min(floor((width - 6 * 5) / 7), 46)
        let gap = (width - 7 * cell) / 6
        let rowGap = min(gap, 6)
        let top = labelHeight > 0 ? labelHeight + 6 : 0
        cornerRadius = cell * 0.26
        showsDayNumbers = cell >= 24
        guard let first = days.first else { return }
        let firstColumn = weekdayColumn(first, calendar: calendar)
        var maxRow = 0
        for (index, _) in days.enumerated() {
            let slot = firstColumn + index
            let column = slot % 7
            let row = slot / 7
            maxRow = max(maxRow, row)
            cellRects.append(CGRect(
                x: CGFloat(column) * (cell + gap),
                y: top + CGFloat(row) * (cell + rowGap),
                width: cell,
                height: cell
            ))
        }
        if labelHeight > 0 {
            for column in 0..<7 {
                labels.append(Label(
                    text: weekdaySymbol(column: column, calendar: calendar),
                    point: CGPoint(x: CGFloat(column) * (cell + gap) + cell / 2, y: 0),
                    anchor: .top
                ))
            }
        }
        size = CGSize(width: width, height: top + CGFloat(maxRow + 1) * cell + CGFloat(maxRow) * rowGap)
    }

    private mutating func layoutContribution(_ days: [Date], width: CGFloat, labelHeight: CGFloat, calendar: Calendar) {
        guard let first = days.first else { return }
        let firstColumn = weekdayColumn(first, calendar: calendar)
        let weekCount = (firstColumn + days.count + 6) / 7
        let leading: CGFloat = labelHeight > 0 ? labelHeight + 6 : 0
        let gap: CGFloat = 4
        let cell = min(floor((width - leading - CGFloat(weekCount - 1) * gap) / CGFloat(weekCount)), 24)
        let top = labelHeight > 0 ? labelHeight + 6 : 0
        cornerRadius = max(2, cell * 0.24)
        var lastMonth: Int?
        var lastLabelX: CGFloat = -.infinity
        for (index, date) in days.enumerated() {
            let slot = firstColumn + index
            let week = slot / 7
            let weekday = slot % 7
            let rect = CGRect(
                x: leading + CGFloat(week) * (cell + gap),
                y: top + CGFloat(weekday) * (cell + gap),
                width: cell,
                height: cell
            )
            cellRects.append(rect)
            let month = calendar.component(.month, from: date)
            if labelHeight > 0, month != lastMonth {
                let x = lastMonth == nil ? leading : rect.minX
                let label = Label(
                    text: calendar.shortStandaloneMonthSymbols[month - 1],
                    point: CGPoint(x: x, y: 0),
                    anchor: .topLeading
                )
                if lastMonth == nil || x - lastLabelX > cell * 2.6 {
                    labels.append(label)
                    lastLabelX = x
                } else if labels.count == 1 {
                    // Too close to the range's partial first month: the first
                    // whole month is the more useful landmark, so it wins.
                    labels[0] = label
                    lastLabelX = x
                }
            }
            lastMonth = month
        }
        if labelHeight > 0 {
            for weekday in [0, 2, 4, 6] {
                labels.append(Label(
                    text: weekdaySymbol(column: weekday, calendar: calendar),
                    point: CGPoint(x: 0, y: top + CGFloat(weekday) * (cell + gap) + cell / 2),
                    anchor: .leading
                ))
            }
        }
        size = CGSize(width: width, height: top + 7 * cell + 6 * gap)
    }

    private mutating func layoutMonths(
        _ days: [Date],
        width: CGFloat,
        labelHeight: CGFloat,
        columns: Int,
        calendar: Calendar
    ) {
        guard let lastDay = days.last,
              let lastMonth = calendar.dateInterval(of: .month, for: lastDay)?.start
        else { return }
        // The twelve calendar months ending with this one.
        let months: [Date] = (0..<12).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: lastMonth)
        }
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        cellRects = Array(repeating: .zero, count: days.count)

        let blockGap: CGFloat = 12
        let rowGap: CGFloat = 14
        let blockWidth = (width - CGFloat(columns - 1) * blockGap) / CGFloat(columns)
        let gap: CGFloat = 2
        let cell = floor((blockWidth - 6 * gap) / 7)
        let header = labelHeight > 0 ? labelHeight + 4 : 0
        let blockHeight = header + 6 * cell + 5 * gap
        cornerRadius = max(1.5, cell * 0.22)

        for (monthOffset, monthStart) in months.enumerated() {
            let blockX = CGFloat(monthOffset % columns) * (blockWidth + blockGap)
            let blockY = CGFloat(monthOffset / columns) * (blockHeight + rowGap)
            if labelHeight > 0 {
                let month = calendar.component(.month, from: monthStart)
                labels.append(Label(
                    text: calendar.shortStandaloneMonthSymbols[month - 1],
                    point: CGPoint(x: blockX, y: blockY),
                    anchor: .topLeading
                ))
            }
            let firstColumn = weekdayColumn(monthStart, calendar: calendar)
            let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            for offset in 0..<dayCount {
                guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
                let slot = firstColumn + offset
                let rect = CGRect(
                    x: blockX + CGFloat(slot % 7) * (cell + gap),
                    y: blockY + header + CGFloat(slot / 7) * (cell + gap),
                    width: cell,
                    height: cell
                )
                if let index = dayIndex[calendar.startOfDay(for: date)] {
                    cellRects[index] = rect
                } else if date <= lastDay {
                    placeholderRects.append(rect)
                }
            }
        }
        // Range days older than the twelve drawn months (All Time) stay
        // un-hittable rather than stacking at the origin.
        for index in cellRects.indices where cellRects[index] == .zero {
            cellRects[index] = CGRect(x: -1000, y: -1000, width: 0, height: 0)
        }
        let rows = (months.count + columns - 1) / columns
        size = CGSize(width: width, height: CGFloat(rows) * blockHeight + CGFloat(rows - 1) * rowGap)
    }
}
