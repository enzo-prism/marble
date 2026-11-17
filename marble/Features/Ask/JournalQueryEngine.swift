import Foundation
import SwiftData

/// The deterministic half of "Ask your journal": every number Ask ever shows
/// is computed here, from bounded SwiftData fetches, and returned as plain
/// values (facts, a template sentence, and verifiable cards). The model layer
/// only chooses which of these queries to run and phrases the result.
///
/// Fetch bounds: "last time" reads one row (or 200-row pages when a weight
/// threshold filters in memory); bests and per-exercise totals are scoped to
/// one exercise and the asked period by predicate; workout lists use
/// `fetchLimit` + `fetchCount`. Only an all-time, all-exercise total scans
/// every set, and it fetches just the four columns it sums.
@MainActor
struct JournalQueryEngine {
    let context: ModelContext
    /// The lifter's preferred weight unit; every weight is shown in it.
    let unit: WeightUnit
    let now: Date
    let calendar: Calendar

    static let sessionListLimit = 5
    static let thresholdPageSize = 200

    init(context: ModelContext, unit: WeightUnit, now: Date = AppEnvironment.now, calendar: Calendar = .current) {
        self.context = context
        self.unit = unit
        self.now = now
        self.calendar = calendar
    }

    // MARK: - Library + resolution

    /// Library exercises, most recently logged first, then by name.
    func library() -> [ExerciseMatcher.Candidate] {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let recent = (try? context.fetch(SetEntryQueries.recentEntriesForPicker)) ?? []
        var order: [UUID: Int] = [:]
        for (index, entry) in recent.enumerated() where order[entry.exercise.id] == nil {
            order[entry.exercise.id] = index
        }
        return exercises
            .sorted { lhs, rhs in
                let left = order[lhs.id] ?? .max
                let right = order[rhs.id] ?? .max
                if left != right { return left < right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { ExerciseMatcher.Candidate(id: $0.id, name: $0.name) }
    }

    func matcher(library: [ExerciseMatcher.Candidate]? = nil) -> JournalQuestionMatcher {
        JournalQuestionMatcher(library: library ?? self.library(), preferredUnit: unit, now: now, calendar: calendar)
    }

    /// Resolves a free-text exercise name ("bench", "db rows", "squatting")
    /// against the library through `ExerciseMatcher`.
    func resolveExercise(named name: String, library: [ExerciseMatcher.Candidate]? = nil) -> ExerciseMatcher.Candidate? {
        let candidates = library ?? self.library()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !candidates.isEmpty else { return nil }
        if let direct = ExerciseMatcher(candidates: candidates).bestMatch(for: trimmed), direct.confidence >= .strong {
            return direct.candidate
        }
        return matcher(library: candidates).reading(of: trimmed).exercise
            ?? ExerciseMatcher(candidates: candidates).bestMatch(for: trimmed)?.candidate
    }

    var isJournalEmpty: Bool {
        var sets = FetchDescriptor<SetEntry>()
        sets.fetchLimit = 1
        var sessions = FetchDescriptor<WorkoutSession>()
        sessions.fetchLimit = 1
        return ((try? context.fetchCount(sets)) ?? 0) == 0 && ((try? context.fetchCount(sessions)) ?? 0) == 0
    }

    /// Three or four tappable questions, phrased around the exercise the
    /// lifter logged most recently so they answer something real.
    func exampleQuestions(library: [ExerciseMatcher.Candidate]? = nil) -> [String] {
        var examples: [String] = []
        if let recent = (library ?? self.library()).first, let exercise = exercise(id: recent.id),
           SetEntryQueries.mostRecentEntry(for: exercise.id, in: context) != nil {
            examples.append("When did I last do \(exercise.name)?")
            examples.append(exercise.metrics.usesWeight ? "What's my heaviest \(exercise.name)?" : "What's my best \(exercise.name)?")
        } else {
            examples.append("When was my last workout?")
        }
        examples.append("How many sets did I do this week?")
        examples.append("What did I train last week?")
        return examples
    }

    // MARK: - Running queries

    func run(_ query: JournalQuery) -> JournalResult {
        if isJournalEmpty {
            return JournalResult(
                facts: ["The journal has no sets or workouts yet."],
                sentence: "Your journal is empty so far. Log a set, then ask again.",
                cards: [],
                found: false
            )
        }
        switch query {
        case .lastPerformed(let exerciseID, let threshold):
            return lastPerformed(exerciseID: exerciseID, atLeast: threshold)
        case .best(let exerciseID, let measure, let period, let distance):
            return best(exerciseID: exerciseID, measure: measure, period: period, distanceMeters: distance)
        case .totals(let period, let exerciseID):
            return totals(period: period, exerciseID: exerciseID)
        case .recentSession(let term):
            return recentSession(matching: term)
        case .sessions(let period):
            return sessions(in: period)
        }
    }

    // MARK: Last performed

    private func lastPerformed(exerciseID: UUID, atLeast threshold: WeightThreshold?) -> JournalResult {
        guard let exercise = exercise(id: exerciseID) else { return missingExercise() }
        let name = exercise.name
        // Dumbbell pairs store the pair total but are entered, shown and asked
        // about per dumbbell ("DB bench at 50 lb" means 50 lb each), so the
        // threshold applies to one dumbbell — the same input convention as the
        // logger and LogSetIntent.
        let style = exercise.resistanceTrackingStyle
        let eachSuffix = style == .singleDumbbellPair ? " each" : ""
        let thresholdText = threshold.map { "\(AskFormat.number($0.value, maximumFractionDigits: 2)) \($0.unit.symbol)\(eachSuffix)" }

        let entry: SetEntry?
        if let threshold {
            entry = newestEntry(of: exerciseID) { candidate in
                guard let weight = candidate.weight, weight > 0,
                      let entered = style.inputWeight(from: weight) else { return false }
                return PersonalRecords.kilograms(entered, unit: candidate.weightUnit) >= threshold.kilograms - PersonalRecords.weightEpsilon
            }
        } else {
            entry = SetEntryQueries.mostRecentEntry(for: exerciseID, in: context)
        }

        guard let entry else {
            let sentence = thresholdText.map { "No \(name) sets at \($0) or more are in your journal." }
                ?? "No \(name) sets are in your journal yet."
            var facts = ["Exercise: \(name)", "No \(name) sets found."]
            if let thresholdText { facts.insert("Filter: sets at or above \(thresholdText)", at: 1) }
            return JournalResult(facts: facts, sentence: sentence, cards: [], found: false)
        }

        let day = calendar.startOfDay(for: entry.performedAt)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? entry.performedAt
        let dayEntries = entries(of: exerciseID, in: DateInterval(start: day, end: nextDay))
        let tenths = timeTenths(for: dayEntries + [entry])
        let shown = threshold == nil ? (topSet(in: dayEntries, exercise: exercise, tenths: tenths) ?? entry) : entry
        let summary = setSummary(shown, tenths: tenths[shown.id])
        let session = session(containing: shown.id)
        let dateText = AskFormat.date(entry.performedAt, calendar: calendar)
        let relative = AskFormat.relativeDay(entry.performedAt, now: now, calendar: calendar)

        var facts = ["Exercise: \(name)"]
        if let thresholdText { facts.append("Filter: sets at or above \(thresholdText)") }
        facts.append("Last logged: \(dateText) (\(relative))")
        facts.append("Sets of \(name) that day: \(max(dayEntries.count, 1))")
        facts.append("\(threshold == nil ? "Top set that day" : "Matching set"): \(summary.text)")
        if let logged = summary.logged { facts.append("Logged as: \(logged)") }
        if let session { facts.append("Workout: \(session.title)") }
        if let source = entry.importedWorkout?.source { facts.append("Imported from \(source.displayName)") }

        let sentence: String
        if let thresholdText {
            sentence = "The last time you did \(name) at \(thresholdText) or more was \(dateText) (\(relative)): \(summary.text)."
        } else {
            let sets = AskFormat.count(max(dayEntries.count, 1), "set")
            sentence = "You last did \(name) on \(dateText) (\(relative)): \(sets), top set \(summary.text)."
        }
        let card = setCard(
            shown,
            label: thresholdText.map { "Last at \($0)+" } ?? "Last time",
            summary: summary,
            session: session
        )
        return JournalResult(facts: facts, sentence: sentence, cards: [card], found: true)
    }

    // MARK: Bests

    private func best(exerciseID: UUID, measure requested: JournalBestMeasure, period: JournalPeriod, distanceMeters: Double?) -> JournalResult {
        guard let exercise = exercise(id: exerciseID) else { return missingExercise() }
        let name = exercise.name
        let interval = period.interval(now: now, calendar: calendar)
        let candidates = entries(of: exerciseID, in: interval)
        let tenths = timeTenths(for: candidates)
        let measure = resolvedMeasure(requested, exercise: exercise, entries: candidates, tenths: tenths)
        let periodSuffix = period == .allTime ? "" : " \(period.label(calendar: calendar))"

        var winner: SetEntry?
        var distanceLabel: String?
        switch measure {
        case .heaviest, .automatic:
            winner = candidates.filter { ($0.weight ?? 0) > 0 }.max(by: Self.heaviestIsLess)
        case .mostReps:
            winner = candidates.filter { ($0.reps ?? 0) > 0 }.max(by: Self.mostRepsIsLess)
        case .fastest:
            let timed = candidates.filter { ($0.distance ?? 0) > 0 && (tenths[$0.id] ?? 0) > 0 }
            if let key = targetDistanceKey(timed: timed, requestedMeters: distanceMeters) {
                let atDistance = timed.filter { Self.distanceKey($0) == key }
                winner = atDistance.min { lhs, rhs in
                    let left = tenths[lhs.id] ?? .max
                    let right = tenths[rhs.id] ?? .max
                    if left != right { return left < right }
                    return lhs.performedAt > rhs.performedAt
                }
                if let winner, let distance = winner.distance {
                    distanceLabel = "\(AskFormat.number(distance, maximumFractionDigits: 2)) \(winner.distanceUnit.symbol)"
                }
            }
        case .longest:
            winner = candidates.filter { (tenths[$0.id] ?? 0) > 0 }.max { lhs, rhs in
                let left = tenths[lhs.id] ?? 0
                let right = tenths[rhs.id] ?? 0
                if left != right { return left < right }
                return lhs.performedAt < rhs.performedAt
            }
        }

        let title: String
        switch measure {
        case .heaviest, .automatic: title = "Heaviest set"
        case .mostReps: title = "Most reps"
        case .fastest: title = distanceLabel.map { "Fastest \($0)" } ?? "Fastest time"
        case .longest: title = "Longest time"
        }

        guard let winner else {
            let what: String
            switch measure {
            case .heaviest, .automatic: what = "weighted \(name) sets"
            case .mostReps: what = "\(name) sets with reps"
            case .fastest:
                if let distanceMeters {
                    what = "timed \(name) sets at \(AskFormat.number(distanceMeters, maximumFractionDigits: 1)) m"
                } else {
                    what = "timed \(name) sets with a distance"
                }
            case .longest: what = "timed \(name) sets"
            }
            let sentence = period == .allTime
                ? "No \(what) are in your journal yet."
                : "No \(what) were logged\(periodSuffix)."
            return JournalResult(
                facts: ["Exercise: \(name)", "Period: \(period.label(calendar: calendar))", "No \(what) found."],
                sentence: sentence,
                cards: [],
                found: false
            )
        }

        let summary = setSummary(winner, tenths: tenths[winner.id])
        let session = session(containing: winner.id)
        let dateText = AskFormat.date(winner.performedAt, calendar: calendar)
        let headline: String
        let sentence: String
        switch measure {
        case .heaviest, .automatic:
            headline = summary.text
            sentence = "Your heaviest \(name) set\(periodSuffix) is \(summary.text), on \(dateText)."
        case .mostReps:
            headline = summary.text
            sentence = "Your most reps on \(name)\(periodSuffix): \(summary.text), on \(dateText)."
        case .fastest:
            let time = AskFormat.time(tenths: tenths[winner.id] ?? 0, hasDistance: true)
            headline = time
            sentence = "Your fastest \(distanceLabel ?? "") \(name)\(periodSuffix) is \(time), on \(dateText)."
                .replacingOccurrences(of: "  ", with: " ")
        case .longest:
            let time = AskFormat.time(tenths: tenths[winner.id] ?? 0, hasDistance: winner.distance != nil)
            headline = time
            sentence = "Your longest \(name)\(periodSuffix) is \(time), on \(dateText)."
        }

        var facts = [
            "Exercise: \(name)",
            "Period: \(period.label(calendar: calendar))",
            "\(title): \(headline) on \(dateText)"
        ]
        if headline != summary.text { facts.append("Set: \(summary.text)") }
        if let logged = summary.logged { facts.append("Logged as: \(logged)") }
        facts.append("Sets compared: \(candidates.count)")
        if let session { facts.append("Workout: \(session.title)") }
        if let source = winner.importedWorkout?.source { facts.append("Imported from \(source.displayName)") }

        let card = setCard(winner, label: title, summary: summary, session: session)
        return JournalResult(facts: facts, sentence: sentence, cards: [card], found: true)
    }

    private func resolvedMeasure(_ requested: JournalBestMeasure, exercise: Exercise, entries: [SetEntry], tenths: [UUID: Int]) -> JournalBestMeasure {
        guard requested == .automatic else { return requested }
        let metrics = exercise.metrics
        if metrics.usesWeight, entries.contains(where: { ($0.weight ?? 0) > 0 }) { return .heaviest }
        if metrics.usesReps, entries.contains(where: { ($0.reps ?? 0) > 0 }) { return .mostReps }
        if metrics.usesDistance, metrics.usesDuration { return .fastest }
        if metrics.usesDuration { return .longest }
        if metrics.usesReps { return .mostReps }
        return .heaviest
    }

    /// The asked distance, else the distance timed most often (ties: the one
    /// run most recently) — a 60 m best says nothing about 150 m.
    private func targetDistanceKey(timed: [SetEntry], requestedMeters: Double?) -> Int? {
        guard !timed.isEmpty else { return nil }
        if let requestedMeters { return Int((requestedMeters * 10).rounded()) }
        var counts: [Int: Int] = [:]
        var latest: [Int: Date] = [:]
        for entry in timed {
            let key = Self.distanceKey(entry)
            counts[key, default: 0] += 1
            latest[key] = max(latest[key] ?? .distantPast, entry.performedAt)
        }
        return counts.keys.max { lhs, rhs in
            if counts[lhs] != counts[rhs] { return (counts[lhs] ?? 0) < (counts[rhs] ?? 0) }
            return (latest[lhs] ?? .distantPast) < (latest[rhs] ?? .distantPast)
        }
    }

    /// Distance in decimeters so 100 m == 0.1 km across units.
    private static func distanceKey(_ entry: SetEntry) -> Int {
        Int((entry.distanceUnit.meters(from: entry.distance ?? 0) * 10).rounded())
    }

    /// Same ordering as `PersonalRecords`: heavier (unit-normalized), then
    /// more reps, then the later set. Compared on stored weight: every set of
    /// one exercise shares its tracking style, so per-dumbbell and pair-total
    /// order identically, and the winner is shown per dumbbell.
    private static func heaviestIsLess(_ lhs: SetEntry, _ rhs: SetEntry) -> Bool {
        let left = PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
        let right = PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
        if abs(left - right) > PersonalRecords.weightEpsilon { return left < right }
        if (lhs.reps ?? 0) != (rhs.reps ?? 0) { return (lhs.reps ?? 0) < (rhs.reps ?? 0) }
        return lhs.performedAt < rhs.performedAt
    }

    /// More reps, then heavier, then the later set.
    private static func mostRepsIsLess(_ lhs: SetEntry, _ rhs: SetEntry) -> Bool {
        if (lhs.reps ?? 0) != (rhs.reps ?? 0) { return (lhs.reps ?? 0) < (rhs.reps ?? 0) }
        let left = PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
        let right = PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
        if abs(left - right) > PersonalRecords.weightEpsilon { return left < right }
        return lhs.performedAt < rhs.performedAt
    }

    private func topSet(in entries: [SetEntry], exercise: Exercise, tenths: [UUID: Int]) -> SetEntry? {
        if exercise.metrics.usesWeight, let heaviest = entries.filter({ ($0.weight ?? 0) > 0 }).max(by: Self.heaviestIsLess) {
            return heaviest
        }
        if let reps = entries.filter({ ($0.reps ?? 0) > 0 }).max(by: Self.mostRepsIsLess) { return reps }
        return entries.max { $0.performedAt < $1.performedAt }
    }

    // MARK: Totals

    private func totals(period: JournalPeriod, exerciseID: UUID?) -> JournalResult {
        let interval = period.interval(now: now, calendar: calendar)
        let start = interval?.start ?? .distantPast
        let end = interval?.end ?? .distantFuture
        var exerciseName: String?
        if let exerciseID {
            guard let exercise = exercise(id: exerciseID) else { return missingExercise() }
            exerciseName = exercise.name
        }

        var descriptor: FetchDescriptor<SetEntry>
        if let exerciseID {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.exercise.id == exerciseID && $0.performedAt >= start && $0.performedAt < end })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.performedAt >= start && $0.performedAt < end })
        }
        descriptor.propertiesToFetch = [\.performedAt, \.weight, \.weightUnit, \.reps]
        let rows = (try? context.fetch(descriptor)) ?? []

        let sets = rows.count
        let days = Set(rows.map { calendar.startOfDay(for: $0.performedAt) }).count
        let volumeKilograms = rows.reduce(0.0) { total, entry in
            guard let weight = entry.weight, weight > 0, let reps = entry.reps, reps > 0 else { return total }
            return total + PersonalRecords.kilograms(weight, unit: entry.weightUnit) * Double(reps)
        }
        let workouts = completedSessionCount(start: start, end: end, exerciseID: exerciseID)
        let volumeText = volumeKilograms > 0 ? MonthlyReportPhrasing.volumeText(kilograms: volumeKilograms, unit: unit) : nil

        let label = period.label(calendar: calendar)
        var facts: [String] = []
        if let exerciseName { facts.append("Exercise: \(exerciseName)") }
        facts.append("Period: \(label)")
        if let interval, period != .today, period != .yesterday {
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            facts.append("Dates: \(AskFormat.date(interval.start, calendar: calendar)) to \(AskFormat.date(lastDay, calendar: calendar))")
        }
        facts.append("Sets: \(sets)")
        facts.append("Training days: \(days)")
        facts.append("Recorded workouts: \(workouts)")
        if let volumeText { facts.append("Volume (weight × reps): \(volumeText)") }

        let lead = Self.capitalized(period == .allTime ? "in total" : label)
        let subject = exerciseName.map { "\($0) " } ?? ""
        let sentence: String
        if sets == 0 {
            sentence = period == .allTime
                ? "No \(subject)sets are logged yet."
                : "No \(subject)sets were logged \(label)."
        } else {
            var parts = "\(AskFormat.count(sets, "set")) across \(AskFormat.count(days, exerciseName == nil ? "training day" : "day"))"
            if let volumeText { parts += ", \(volumeText) of volume" }
            sentence = exerciseName.map { "\($0) \(period == .allTime ? "in total" : label): \(parts)." } ?? "\(lead): \(parts)."
        }

        var detail = [AskFormat.count(days, "training day"), AskFormat.count(workouts, "workout")]
        if let volumeText { detail.append("\(volumeText) volume") }
        let card = JournalCard(
            id: "totals.\(exerciseID?.uuidString ?? "all").\(label)",
            label: exerciseName == nil ? "Totals" : "\(exerciseName ?? "") totals",
            title: Self.capitalized(label),
            value: AskFormat.count(sets, "set"),
            detail: detail.joined(separator: " · "),
            destination: exerciseID.map { .exercise($0) }
        )
        return JournalResult(facts: facts, sentence: sentence, cards: [card], found: sets > 0)
    }

    private func completedSessionCount(start: Date, end: Date, exerciseID: UUID?) -> Int {
        let descriptor: FetchDescriptor<WorkoutSession>
        if let exerciseID {
            descriptor = FetchDescriptor(predicate: #Predicate {
                $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end &&
                $0.entries.contains { $0.exercise.id == exerciseID }
            })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate {
                $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end
            })
        }
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: Workouts

    private func recentSession(matching rawTerm: String) -> JournalResult {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = WorkoutHistoryQuery.descriptor(search: term, day: nil)
        descriptor.fetchLimit = 1
        let matchPhrase = term.isEmpty ? "" : " matching “\(term)”"
        guard let session = (try? context.fetch(descriptor))?.first else {
            return JournalResult(
                facts: ["No completed workouts\(matchPhrase) found."],
                sentence: "No completed workouts\(matchPhrase) are in your history yet.",
                cards: [],
                found: false
            )
        }
        let fact = sessionFacts(session)
        var facts = ["Most recent workout\(matchPhrase): \(session.title)"]
        facts.append(contentsOf: fact.lines)
        var sentence = "Your most recent workout\(matchPhrase) was \(session.title) on \(fact.date) (\(fact.relative)): \(fact.sets)"
        if let duration = fact.duration { sentence += " in \(duration)" }
        sentence += "."
        return JournalResult(facts: facts, sentence: sentence, cards: [sessionCard(session, label: "Latest workout", fact: fact)], found: true)
    }

    private func sessions(in period: JournalPeriod) -> JournalResult {
        let interval = period.interval(now: now, calendar: calendar)
        let start = interval?.start ?? .distantPast
        let end = interval?.end ?? .distantFuture
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        let total = (try? context.fetchCount(descriptor)) ?? 0
        descriptor.fetchLimit = Self.sessionListLimit
        let sessions = (try? context.fetch(descriptor)) ?? []
        let label = period.label(calendar: calendar)
        let when = period == .allTime ? "so far" : label

        guard let latest = sessions.first else {
            let looseSets = (try? context.fetchCount(FetchDescriptor<SetEntry>(
                predicate: #Predicate { $0.performedAt >= start && $0.performedAt < end }
            ))) ?? 0
            var facts = ["Period: \(label)", "Recorded workouts: 0"]
            var sentence = "No recorded workouts \(when)."
            if looseSets > 0 {
                facts.append("Sets logged outside workouts: \(looseSets)")
                sentence = "No recorded workouts \(when), though \(AskFormat.count(looseSets, "set")) \(looseSets == 1 ? "is" : "are") in your log."
            }
            return JournalResult(facts: facts, sentence: sentence, cards: [], found: false)
        }

        var facts = ["Period: \(label)", "Recorded workouts: \(total)"]
        var cards: [JournalCard] = []
        for session in sessions {
            let fact = sessionFacts(session)
            facts.append("Workout: \(session.title) on \(fact.date) — \(fact.sets)")
            cards.append(sessionCard(session, label: "Workout", fact: fact))
        }
        if total > sessions.count {
            facts.append("Showing the latest \(sessions.count) of \(total).")
        }
        let latestDate = AskFormat.date(latest.startedAt, calendar: calendar)
        let sentence = total == 1
            ? "You recorded 1 workout \(when): \(latest.title) on \(latestDate)."
            : "You recorded \(total) workouts \(when); the latest was \(latest.title) on \(latestDate)."
        return JournalResult(facts: facts, sentence: sentence, cards: cards, found: true)
    }

    private struct SessionFacts {
        let date: String
        let relative: String
        let sets: String
        let duration: String?
        let exercises: [String]
        let lines: [String]
    }

    private func sessionFacts(_ session: WorkoutSession) -> SessionFacts {
        let date = AskFormat.date(session.startedAt, calendar: calendar)
        let relative = AskFormat.relativeDay(session.startedAt, now: now, calendar: calendar)
        let sets = AskFormat.count(session.entries.count, "set")
        let seconds = Int(session.duration)
        let duration = seconds >= 60 ? DateHelper.formattedDuration(seconds: seconds) : nil
        var names: [String] = []
        for entry in session.orderedEntries where !names.contains(entry.exercise.name) {
            names.append(entry.exercise.name)
        }
        var lines = ["Date: \(date) (\(relative))", "Sets: \(session.entries.count)"]
        if let duration { lines.append("Duration: \(duration)") }
        if !names.isEmpty { lines.append("Exercises: \(names.prefix(4).joined(separator: ", "))") }
        return SessionFacts(date: date, relative: relative, sets: sets, duration: duration, exercises: names, lines: lines)
    }

    private func sessionCard(_ session: WorkoutSession, label: String, fact: SessionFacts) -> JournalCard {
        var value = fact.sets
        if let duration = fact.duration { value += " · \(duration)" }
        var detail = [fact.date]
        if !fact.exercises.isEmpty { detail.append(fact.exercises.prefix(3).joined(separator: ", ")) }
        return JournalCard(
            id: "session.\(session.id.uuidString)",
            label: label,
            title: session.title,
            value: value,
            detail: detail.joined(separator: " · "),
            destination: .session(session.id)
        )
    }

    // MARK: - Fetch helpers

    func exercise(id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Sets of one exercise in an optional interval, newest first.
    private func entries(of exerciseID: UUID, in interval: DateInterval?) -> [SetEntry] {
        let start = interval?.start ?? .distantPast
        let end = interval?.end ?? .distantFuture
        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise.id == exerciseID && $0.performedAt >= start && $0.performedAt < end },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Pages newest-first through one exercise's sets until `matches` holds.
    /// Keyset paging on `performedAt` (not `fetchOffset`, which a context
    /// with unsaved inserts does not apply consistently), de-duplicated by
    /// id so equal timestamps across a page boundary are never skipped.
    private func newestEntry(of exerciseID: UUID, where matches: (SetEntry) -> Bool) -> SetEntry? {
        var cursor = Date.distantFuture
        var inclusive = true
        var seen = Set<UUID>()
        while true {
            let bound = cursor
            var descriptor: FetchDescriptor<SetEntry>
            if inclusive {
                descriptor = FetchDescriptor(predicate: #Predicate { $0.exercise.id == exerciseID && $0.performedAt <= bound })
            } else {
                descriptor = FetchDescriptor(predicate: #Predicate { $0.exercise.id == exerciseID && $0.performedAt < bound })
            }
            descriptor.sortBy = [SortDescriptor(\.performedAt, order: .reverse)]
            descriptor.fetchLimit = Self.thresholdPageSize
            guard let page = try? context.fetch(descriptor), let oldest = page.last?.performedAt else { return nil }
            let fresh = page.filter { seen.insert($0.id).inserted }
            if let hit = fresh.first(where: matches) { return hit }
            if page.count < Self.thresholdPageSize { return nil }
            if fresh.isEmpty {
                // A full page at one instant: read that instant whole, then step past it.
                let instant = FetchDescriptor<SetEntry>(predicate: #Predicate { $0.exercise.id == exerciseID && $0.performedAt == oldest })
                let rest = ((try? context.fetch(instant)) ?? []).filter { seen.insert($0.id).inserted }
                if let hit = rest.first(where: matches) { return hit }
                inclusive = false
            } else {
                inclusive = true
            }
            cursor = oldest
        }
    }

    private func session(containing entryID: UUID) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.entries.contains { $0.id == entryID } }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// One tenths-domain time per timed set: the exact `SprintRepDetail`
    /// tenths where recorded, else the whole-second column × 10.
    private func timeTenths(for entries: [SetEntry]) -> [UUID: Int] {
        let timed = entries.filter { ($0.durationSeconds ?? 0) > 0 }
        guard !timed.isEmpty else { return [:] }
        let ids = timed.map(\.id)
        let details = (try? context.fetch(FetchDescriptor<SprintRepDetail>(
            predicate: #Predicate { ids.contains($0.setEntryID) }
        ))) ?? []
        let precise = Dictionary(details.map { ($0.setEntryID, $0.durationTenths) }, uniquingKeysWith: { first, _ in first })
        var result: [UUID: Int] = [:]
        for entry in timed {
            if let tenths = precise[entry.id], tenths > 0 {
                result[entry.id] = tenths
            } else if let seconds = entry.durationSeconds {
                result[entry.id] = SprintTiming.tenths(fromWholeSeconds: seconds)
            }
        }
        return result
    }

    // MARK: - Formatting

    /// "225 lb × 5", "50 lb each × 10", "12 reps", "100 m in 12.4s", "2m 30s".
    func setSummary(_ entry: SetEntry, tenths: Int?) -> (text: String, logged: String?) {
        var parts: [String] = []
        var logged: String?
        if let weight = entry.weight, weight > 0 {
            let formatted = AskFormat.weight(
                stored: weight,
                loggedUnit: entry.weightUnit,
                preferred: unit,
                style: entry.exercise.resistanceTrackingStyle
            )
            logged = formatted.logged
            if let reps = entry.reps, reps > 0 {
                parts.append("\(formatted.display) × \(reps)")
            } else {
                parts.append(formatted.display)
            }
        } else if let reps = entry.reps, reps > 0 {
            parts.append(AskFormat.count(reps, "rep"))
        }
        let hasDistance = (entry.distance ?? 0) > 0
        if let distance = entry.distance, distance > 0 {
            let distanceText = "\(AskFormat.number(distance, maximumFractionDigits: 2)) \(entry.distanceUnit.symbol)"
            if let tenths, tenths > 0 {
                parts.append("\(distanceText) in \(AskFormat.time(tenths: tenths, hasDistance: true))")
            } else {
                parts.append(distanceText)
            }
        } else if let tenths, tenths > 0 {
            parts.append(AskFormat.time(tenths: tenths, hasDistance: hasDistance))
        }
        if parts.isEmpty { parts.append("1 set") }
        return (parts.joined(separator: " · "), logged)
    }

    private func setCard(_ entry: SetEntry, label: String, summary: (text: String, logged: String?), session: WorkoutSession?) -> JournalCard {
        var detail = [AskFormat.date(entry.performedAt, calendar: calendar)]
        if let session { detail.append(session.title) }
        if let logged = summary.logged { detail.append("logged as \(logged)") }
        if let source = entry.importedWorkout?.source { detail.append("Imported from \(source.displayName)") }
        return JournalCard(
            id: "set.\(label).\(entry.id.uuidString)",
            label: label,
            title: entry.exercise.name,
            value: summary.text,
            detail: detail.joined(separator: " · "),
            destination: session.map { .session($0.id) } ?? .exercise(entry.exercise.id)
        )
    }

    private func missingExercise() -> JournalResult {
        JournalResult(
            facts: ["That exercise is not in the library."],
            sentence: "That exercise isn't in your library.",
            cards: [],
            found: false
        )
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
