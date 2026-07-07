import Foundation

/// Pure computations behind the coaching layer of Trends: per-lift progression
/// verdicts, the double-progression hint, rep records, the PR feed, and
/// muscle-group weekly coverage. Everything is derived from logged sets —
/// no schema additions — and stays free of UI so the math is unit-testable.
///
/// Evidence anchors (kept deliberately conservative):
/// - Load- and rep-progression are equivalent stimuli (Plotkin 2022), so any
///   upward e1RM trend counts as progressing — never just added weight.
/// - Progress must be compared at matched effort: more weight at much higher
///   RPE isn't adaptation, it's strain. Verdicts require the effort context.
/// - "Adapted" needs 4+ flat exposures; a single down-day is noise (e1RM
///   estimates swing ±3–5% day to day).
enum LifterCoaching {
    // MARK: - Progression status

    enum ProgressionVerdict: String, Equatable {
        /// e1RM trending up across the window.
        case progressing
        /// Small gains, or flat while effort dropped (consolidating).
        case holding
        /// Flat/down across 4+ exposures at equal-or-higher effort.
        case adapted
        /// Fewer than `minimumExposuresForVerdict` data points.
        case building

        var displayName: String {
            switch self {
            case .progressing: return "Progressing"
            case .holding: return "Holding"
            case .adapted: return "Adapted"
            case .building: return "Building baseline"
            }
        }
    }

    struct ProgressionExposure: Identifiable, Equatable {
        let date: Date
        let e1RMKilograms: Double
        let averageRPE: Double

        var id: Date { date }
    }

    struct ProgressionAssessment: Identifiable, Equatable {
        let exerciseID: UUID
        let exerciseName: String
        let verdict: ProgressionVerdict
        /// Percent change of the fitted e1RM trend across the window (e.g. 4.2 = +4.2%).
        let percentChange: Double
        /// Oldest-first exposures feeding the sparkline, capped at `progressionWindow`.
        let exposures: [ProgressionExposure]
        let latestKilograms: Double
        let displayUnit: WeightUnit

        var id: UUID { exerciseID }

        var latestDisplayValue: Double {
            LifterAnalytics.displayWeight(fromKilograms: latestKilograms, in: displayUnit)
        }
    }

    /// How many recent training days (exposures) feed a verdict.
    static let progressionWindow = 8
    /// Below this many exposures the verdict is `.building` — never judge a
    /// lift on two data points.
    static let minimumExposuresForVerdict = 4
    /// Trend gain across the window that counts as progressing.
    static let progressingThresholdPercent = 2.0
    /// Trend gain below which the lift reads as flat.
    static let flatThresholdPercent = 0.5
    /// Effort may drop this much (recent vs earlier half) and still count as
    /// "equal effort" when calling a lift adapted.
    static let effortMatchTolerance = 0.25

    /// Assesses one exercise from its full history (not range-scoped: the
    /// verdict describes *now*, using the last `progressionWindow` training
    /// days regardless of the chart range on screen).
    static func progressionAssessment(
        history: [SetEntry],
        exercise: Exercise,
        calendar: Calendar = .current
    ) -> ProgressionAssessment? {
        guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { return nil }

        struct DayAccumulator {
            var bestE1RM = 0.0
            var rpeTotal = 0
            var setCount = 0
        }

        var days: [Date: DayAccumulator] = [:]
        var displayUnit: WeightUnit?
        var latestPerformedAt = Date.distantPast

        for entry in history where entry.exercise.id == exercise.id {
            guard
                let weight = entry.weight,
                let reps = entry.reps,
                let estimate = LifterAnalytics.estimatedOneRepMaxKilograms(
                    weight: weight, unit: entry.weightUnit, reps: reps
                )
            else { continue }
            let day = calendar.startOfDay(for: entry.performedAt)
            var accumulator = days[day] ?? DayAccumulator()
            accumulator.bestE1RM = max(accumulator.bestE1RM, estimate)
            accumulator.rpeTotal += entry.difficulty
            accumulator.setCount += 1
            days[day] = accumulator
            if entry.performedAt >= latestPerformedAt {
                latestPerformedAt = entry.performedAt
                displayUnit = entry.weightUnit
            }
        }

        guard !days.isEmpty, let displayUnit else { return nil }

        let exposures = days.keys.sorted().suffix(progressionWindow).map { day -> ProgressionExposure in
            let accumulator = days[day] ?? DayAccumulator()
            return ProgressionExposure(
                date: day,
                e1RMKilograms: accumulator.bestE1RM,
                averageRPE: accumulator.setCount > 0
                    ? Double(accumulator.rpeTotal) / Double(accumulator.setCount)
                    : 0
            )
        }

        guard let latest = exposures.last else { return nil }

        let percentChange = trendPercentChange(values: exposures.map(\.e1RMKilograms))
        let verdict = verdict(exposures: exposures, percentChange: percentChange)

        return ProgressionAssessment(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            verdict: verdict,
            percentChange: percentChange,
            exposures: exposures,
            latestKilograms: latest.e1RMKilograms,
            displayUnit: displayUnit
        )
    }

    /// The lifts shown on the strength dashboard: weight+reps exercises ranked
    /// by set count within the visible range, assessed against full history.
    static func topLiftAssessments(
        rangeEntries: [SetEntry],
        history: [SetEntry],
        limit: Int = 3,
        calendar: Calendar = .current
    ) -> [ProgressionAssessment] {
        var setCounts: [UUID: Int] = [:]
        var exercisesByID: [UUID: Exercise] = [:]
        for entry in rangeEntries {
            let exercise = entry.exercise
            guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { continue }
            guard entry.weight != nil, entry.reps != nil else { continue }
            setCounts[exercise.id, default: 0] += 1
            exercisesByID[exercise.id] = exercise
        }

        let ranked = setCounts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                let lhsName = exercisesByID[lhs.key]?.name ?? ""
                let rhsName = exercisesByID[rhs.key]?.name ?? ""
                return lhsName < rhsName
            }
            return lhs.value > rhs.value
        }

        var assessments: [ProgressionAssessment] = []
        for (exerciseID, _) in ranked {
            guard assessments.count < limit else { break }
            guard let exercise = exercisesByID[exerciseID],
                  let assessment = progressionAssessment(history: history, exercise: exercise, calendar: calendar)
            else { continue }
            assessments.append(assessment)
        }
        return assessments
    }

    /// Least-squares slope expressed as percent change across the window.
    /// A fitted trend shrugs off one noisy day where first-vs-last would not.
    static func trendPercentChange(values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        guard mean > 0 else { return 0 }
        let meanIndex = (n - 1) / 2
        var numerator = 0.0
        var denominator = 0.0
        for (index, value) in values.enumerated() {
            let dx = Double(index) - meanIndex
            numerator += dx * (value - mean)
            denominator += dx * dx
        }
        guard denominator > 0 else { return 0 }
        let slope = numerator / denominator
        return slope * (n - 1) / mean * 100
    }

    private static func verdict(
        exposures: [ProgressionExposure],
        percentChange: Double
    ) -> ProgressionVerdict {
        guard exposures.count >= minimumExposuresForVerdict else { return .building }
        if percentChange >= progressingThresholdPercent { return .progressing }
        guard percentChange <= flatThresholdPercent else { return .holding }

        // Flat trend: only "adapted" when effort held steady or rose — a lift
        // that's flat while the lifter backed off is consolidating, not stuck.
        let half = exposures.count / 2
        let earlier = exposures.prefix(exposures.count - half).map(\.averageRPE)
        let recent = exposures.suffix(half).map(\.averageRPE)
        let earlierMean = earlier.reduce(0, +) / Double(earlier.count)
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        if recentMean >= earlierMean - effortMatchTolerance {
            return .adapted
        }
        return .holding
    }

    // MARK: - Double-progression hint

    struct DoubleProgressionHint: Equatable {
        /// e.g. "All 3 sets hit 8+ reps at 135 lb"
        let evidence: String
        /// e.g. "double progression suggests trying 140 lb next time"
        let suggestion: String
    }

    /// Reps every working set must reach before the hint suggests adding load.
    static let doubleProgressionRepCeiling = 8
    /// Sets above this effort don't trigger the hint — no adding weight on
    /// top of grinding sets.
    static let doubleProgressionMaxRPE = 8.5

    /// The one deliberately *informative* suggestion in the app: when the last
    /// session's working sets all topped the rep ceiling at matched load and
    /// manageable effort, name the classic next step — with the evidence, never
    /// as a command. Anything short of that clean pattern shows nothing.
    static func doubleProgressionHint(
        history: [SetEntry],
        exercise: Exercise,
        calendar: Calendar = .current
    ) -> DoubleProgressionHint? {
        guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { return nil }

        let entries = history.filter {
            $0.exercise.id == exercise.id && $0.weight != nil && $0.reps != nil
        }
        guard let lastDate = entries.map(\.performedAt).max() else { return nil }
        let lastDay = calendar.startOfDay(for: lastDate)
        let session = entries.filter { calendar.startOfDay(for: $0.performedAt) == lastDay }

        guard session.count >= 2 else { return nil }
        guard let weight = session.first?.weight,
              let unit = session.first?.weightUnit,
              session.allSatisfy({ $0.weight == weight && $0.weightUnit == unit })
        else { return nil }

        let reps = session.compactMap(\.reps)
        guard let minReps = reps.min(), minReps >= doubleProgressionRepCeiling else { return nil }
        let averageRPE = Double(session.reduce(0) { $0 + $1.difficulty }) / Double(session.count)
        guard averageRPE <= doubleProgressionMaxRPE else { return nil }

        let nextWeight = nextLoadSuggestion(after: weight, unit: unit)
        let weightText = exercise.formattedWeightSummary(weight, unit: unit)
        let nextText = exercise.formattedWeightSummary(nextWeight, unit: unit)
        return DoubleProgressionHint(
            evidence: "All \(session.count) sets hit \(minReps)+ reps at \(weightText)",
            suggestion: "double progression suggests trying \(nextText) next time"
        )
    }

    /// Smallest meaningful jump: ~2.5%, rounded up to real plate math
    /// (2.5 lb / 1.25 kg steps), never less than one step.
    static func nextLoadSuggestion(after weight: Double, unit: WeightUnit) -> Double {
        let step = unit == .kg ? 1.25 : 2.5
        let raw = weight * 1.025
        let stepped = (raw / step).rounded(.up) * step
        return max(stepped, weight + step)
    }

    // MARK: - Rep records (quiet table)

    /// Best weight ever lifted at each rep count 1–12 — Hevy's "set records"
    /// pattern: records live in a quiet table and never fire celebrations.
    struct RepRecord: Identifiable, Equatable {
        let reps: Int
        let kilograms: Double
        /// Weight formatted in the unit the record was set in.
        let weightText: String
        let date: Date

        var id: Int { reps }
    }

    static let repRecordCap = LifterAnalytics.oneRepMaxRepCap

    static func repRecords(history: [SetEntry], exercise: Exercise) -> [RepRecord] {
        guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { return [] }

        struct Best {
            let entry: SetEntry
            let kilograms: Double
        }

        var bests: [Int: Best] = [:]
        for entry in history where entry.exercise.id == exercise.id {
            guard let weight = entry.weight, weight > 0,
                  let reps = entry.reps, (1...repRecordCap).contains(reps)
            else { continue }
            let kilograms = PersonalRecords.kilograms(weight, unit: entry.weightUnit)
            if let current = bests[reps], current.kilograms >= kilograms - PersonalRecords.weightEpsilon {
                continue
            }
            bests[reps] = Best(entry: entry, kilograms: kilograms)
        }

        return bests.keys.sorted().compactMap { reps in
            guard let best = bests[reps], let weight = best.entry.weight else { return nil }
            return RepRecord(
                reps: reps,
                kilograms: best.kilograms,
                weightText: best.entry.exercise.formattedWeightSummary(weight, unit: best.entry.weightUnit),
                date: best.entry.performedAt
            )
        }
    }

    // MARK: - PR feed

    struct PREvent: Identifiable, Equatable {
        let entryID: UUID
        let date: Date
        let exerciseName: String
        let badge: PersonalRecordBadge
        /// e.g. "225 lb × 5"
        let setSummary: String

        var id: UUID { entryID }

        static func == (lhs: PREvent, rhs: PREvent) -> Bool {
            lhs.entryID == rhs.entryID && lhs.badge == rhs.badge
        }
    }

    /// An exercise needs this many distinct training days before its records
    /// start feeding the celebrated feed — early logs make every session a
    /// "PR" and dense celebrations are cheap.
    static let prFeedMinimumSessions = 3

    /// Genuine record-breaking sets, newest first. Unlike the journal's badge
    /// trail this excludes baselines (a first-ever set breaks nothing) and
    /// suppresses each exercise's noisy first sessions.
    static func prEvents(
        history: [SetEntry],
        rangeStart: Date?,
        selectedExerciseID: UUID?,
        calendar: Calendar = .current
    ) -> [PREvent] {
        var events: [PREvent] = []
        let grouped = Dictionary(grouping: history) { $0.exercise.id }

        for (exerciseID, group) in grouped {
            if let selectedExerciseID, exerciseID != selectedExerciseID { continue }
            guard let sample = group.first else { continue }
            let usesWeight = sample.exercise.metrics.usesWeight
            let usesReps = sample.exercise.metrics.usesReps
            guard usesWeight || usesReps else { continue }

            let ordered = group.sorted { lhs, rhs in
                if lhs.performedAt != rhs.performedAt { return lhs.performedAt < rhs.performedAt }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            var bestKilograms: Double?
            var bestReps: Int?
            var seenDays = Set<Date>()

            for entry in ordered {
                seenDays.insert(calendar.startOfDay(for: entry.performedAt))
                var badge: PersonalRecordBadge = []

                if usesWeight, let weight = entry.weight, weight > 0 {
                    let kilos = PersonalRecords.kilograms(weight, unit: entry.weightUnit)
                    if let current = bestKilograms {
                        if kilos > current + PersonalRecords.weightEpsilon {
                            badge.insert(.weight)
                            bestKilograms = kilos
                        }
                    } else {
                        bestKilograms = kilos
                    }
                }

                if usesReps, let reps = entry.reps, reps > 0 {
                    if let current = bestReps {
                        if reps > current {
                            badge.insert(.reps)
                            bestReps = reps
                        }
                    } else {
                        bestReps = reps
                    }
                }

                guard !badge.isEmpty, seenDays.count > prFeedMinimumSessions else { continue }
                if let rangeStart, entry.performedAt < rangeStart { continue }
                events.append(PREvent(
                    entryID: entry.id,
                    date: entry.performedAt,
                    exerciseName: entry.exercise.name,
                    badge: badge,
                    setSummary: prSetSummary(for: entry)
                ))
            }
        }

        return events.sorted { $0.date > $1.date }
    }

    private static func prSetSummary(for entry: SetEntry) -> String {
        if let weight = entry.weight {
            let weightText = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
            if let reps = entry.reps {
                return "\(weightText) \u{00D7} \(reps)"
            }
            return weightText
        }
        if let reps = entry.reps {
            return reps == 1 ? "1 rep" : "\(reps) reps"
        }
        return ""
    }

    // MARK: - Muscle-group weekly coverage

    enum VolumeBand: String, Equatable {
        case below
        case inRange
        case high

        var label: String {
            switch self {
            case .below: return "Room to grow"
            case .inRange: return "In range"
            case .high: return "High volume"
            }
        }
    }

    struct MuscleGroupCoverage: Identifiable, Equatable {
        let category: ExerciseCategory
        /// Fractional hard sets per week (indirect work counts 0.5).
        let setsPerWeek: Double
        let directSets: Int
        let indirectSets: Double
        let lastTrainedDaysAgo: Int?
        let band: VolumeBand

        var id: ExerciseCategory { category }
    }

    /// The 10–20 weekly hard-set guide (Schoenfeld 2017 dose-response;
    /// practitioner consensus band). A guide, not a verdict — the caption in
    /// the UI must say so.
    static let weeklySetBand: ClosedRange<Double> = 10...20

    /// Which secondary muscle groups a category's sets meaningfully train.
    /// Deliberately conservative — pressing hits triceps and shoulders,
    /// pulling hits biceps, combined leg work hits quads and hamstrings —
    /// counted at 0.5 per set (Pelland 2024 fractional-set convention).
    static let indirectContributions: [ExerciseCategory: [ExerciseCategory]] = [
        .chest: [.triceps, .shoulders],
        .back: [.biceps],
        .shoulders: [.triceps],
        .legs: [.quads, .hamstrings]
    ]

    /// How recently a muscle must have been trained (in history) for a
    /// zero-sets-in-range row to still appear as a nudge.
    static let recencyWindowDays = 60

    static func muscleGroupCoverage(
        rangeEntries: [SetEntry],
        history: [SetEntry],
        weekCount: Double?,
        now: Date,
        calendar: Calendar = .current
    ) -> [MuscleGroupCoverage] {
        let allowed = Set(LifterAnalytics.muscleGroupCategories)

        var direct: [ExerciseCategory: Int] = [:]
        var indirect: [ExerciseCategory: Double] = [:]
        for entry in rangeEntries {
            let category = entry.exercise.category
            guard allowed.contains(category) else { continue }
            direct[category, default: 0] += 1
            for secondary in indirectContributions[category] ?? [] {
                indirect[secondary, default: 0] += 0.5
            }
        }

        var lastTrained: [ExerciseCategory: Date] = [:]
        for entry in history {
            let category = entry.exercise.category
            guard allowed.contains(category) else { continue }
            if let current = lastTrained[category] {
                if entry.performedAt > current { lastTrained[category] = entry.performedAt }
            } else {
                lastTrained[category] = entry.performedAt
            }
        }

        let today = calendar.startOfDay(for: now)
        var coverage: [MuscleGroupCoverage] = []
        var categories = Set(direct.keys).union(indirect.keys)

        // Muscles trained recently (but not in this range) still appear as a
        // zero row — "you train hamstrings, they've had nothing for 12 days"
        // is exactly the actionable gap the chart exists to expose.
        for (category, date) in lastTrained {
            let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
            if daysAgo <= recencyWindowDays {
                categories.insert(category)
            }
        }

        for category in categories {
            let directCount = direct[category] ?? 0
            let indirectCount = indirect[category] ?? 0
            let totalSets = Double(directCount) + indirectCount
            let perWeek: Double
            if let weekCount, weekCount >= 1 {
                perWeek = totalSets / weekCount
            } else {
                perWeek = totalSets
            }

            let daysAgo = lastTrained[category].map { date in
                calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
            }

            let band: VolumeBand
            if perWeek < weeklySetBand.lowerBound {
                band = .below
            } else if perWeek > weeklySetBand.upperBound {
                band = .high
            } else {
                band = .inRange
            }

            coverage.append(MuscleGroupCoverage(
                category: category,
                setsPerWeek: perWeek,
                directSets: directCount,
                indirectSets: indirectCount,
                lastTrainedDaysAgo: daysAgo,
                band: band
            ))
        }

        return coverage.sorted { lhs, rhs in
            if lhs.setsPerWeek == rhs.setsPerWeek {
                return lhs.category.displayName < rhs.category.displayName
            }
            return lhs.setsPerWeek > rhs.setsPerWeek
        }
    }
}
