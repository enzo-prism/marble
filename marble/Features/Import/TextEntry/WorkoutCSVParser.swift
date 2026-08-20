import Foundation

/// Deterministic Hevy / Strong CSV import. These files are tables, not prose —
/// they never go through Foundation Models. Each distinct (title, start time)
/// group becomes one `ParsedWorkoutDraft`.
nonisolated enum WorkoutCSVParser {
    struct ParseResult: Equatable, Sendable {
        var kind: WorkoutImportPayloadKind
        var workouts: [Workout]
    }

    struct Workout: Equatable, Sendable {
        var identityKey: String
        var sourceText: String
        var draft: ParsedWorkoutDraft
    }

    /// Parses `text` when it looks like a Hevy or Strong export. Returns nil when
    /// the first non-empty line is not a known header row, so Notes pastes that
    /// happen to contain commas stay on the text path.
    static func parse(_ text: String, defaultWeightUnit: WeightUnit = .lb) -> ParseResult? {
        let lines = CSVRecords.records(in: text)
        guard let headerLine = lines.first else { return nil }
        let headers = CSVFields.parse(headerLine).map(normalizeHeader)
        guard let kind = detectKind(headers: headers) else { return nil }

        let columns = ColumnMap(headers: headers, kind: kind, defaultWeightUnit: defaultWeightUnit)
        guard columns.exerciseName != nil else { return nil }

        var groups: [GroupKey: Group] = [:]
        var order: [GroupKey] = []

        for line in lines.dropFirst() {
            let fields = CSVFields.parse(line)
            guard let row = Row(fields: fields, columns: columns) else { continue }
            guard row.hasSetValues else { continue }

            let key = GroupKey(title: row.title, startRaw: row.startRaw)
            if groups[key] == nil {
                order.append(key)
                groups[key] = Group(title: row.title, start: row.startDate, startRaw: row.startRaw)
            }
            groups[key]?.append(row)
        }

        let workouts: [Workout] = order.compactMap { key in
            guard let group = groups[key] else { return nil }
            return group.makeWorkout(kind: kind)
        }
        guard !workouts.isEmpty else { return nil }
        return ParseResult(kind: kind, workouts: workouts)
    }

    // MARK: - Detection

    private static func detectKind(headers: [String]) -> WorkoutImportPayloadKind? {
        let set = Set(headers)
        if set.contains("exercise_title") || (set.contains("exercise title") && set.contains("start_time")) {
            return .hevyCSV
        }
        if set.contains("exercise name"), set.contains("date") || set.contains("workout name") {
            return .strongCSV
        }
        if set.contains("exercise_title") || set.contains("exercise title") {
            return .hevyCSV
        }
        return nil
    }

    private static func normalizeHeader(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .lowercased()
    }

    /// Joins several files/pastes. Extra Hevy/Strong header rows are dropped so
    /// two exports of the same app don't spawn a bogus "exercise_title" workout.
    static func merging(_ parts: [String]) -> String {
        let trimmed = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = trimmed.first else { return "" }
        guard trimmed.count > 1 else { return first }
        guard let header = headerFields(in: first) else {
            return trimmed.joined(separator: "\n\n")
        }
        var combined = [first]
        for part in trimmed.dropFirst() {
            if headerFields(in: part) == header {
                let rest = CSVRecords.records(in: part).dropFirst().joined(separator: "\n")
                if !rest.isEmpty { combined.append(rest) }
            } else {
                combined.append(part)
            }
        }
        return combined.joined(separator: "\n")
    }

    private static func headerFields(in text: String) -> [String]? {
        guard let line = CSVRecords.records(in: text).first else { return nil }
        let headers = CSVFields.parse(line).map(normalizeHeader)
        guard detectKind(headers: headers) != nil else { return nil }
        return headers
    }

    // MARK: - Columns / rows

    private struct ColumnMap {
        var title: Int?
        var start: Int?
        var end: Int?
        var exerciseName: Int?
        var setIndex: Int?
        var setType: Int?
        var weight: Int?
        var weightUnit: WeightUnit
        var reps: Int?
        var distance: Int?
        var distanceUnit: DistanceUnit
        var duration: Int?

        init(headers: [String], kind: WorkoutImportPayloadKind, defaultWeightUnit: WeightUnit) {
            func index(_ names: [String]) -> Int? {
                for name in names {
                    if let found = headers.firstIndex(of: name) { return found }
                }
                return nil
            }

            title = index(["title", "workout name", "workout"])
            start = index(["start_time", "start time", "date", "workout date"])
            end = index(["end_time", "end time"])
            exerciseName = index(["exercise_title", "exercise title", "exercise name", "exercise"])
            setIndex = index(["set_index", "set index", "set order", "set"])
            setType = index(["set_type", "set type"])
            reps = index(["reps", "repetitions", "rep"])
            duration = index(["duration_seconds", "duration seconds", "seconds", "duration"])

            if let lbs = index(["weight_lbs", "weight lbs", "lbs"]) {
                weight = lbs
                weightUnit = .lb
            } else if let kg = index(["weight_kg", "weight kg", "kg"]) {
                weight = kg
                weightUnit = .kg
            } else {
                weight = index(["weight"])
                weightUnit = defaultWeightUnit
            }

            if let miles = index(["distance_miles", "distance miles"]) {
                distance = miles
                distanceUnit = .miles
            } else if let km = index(["distance_km", "distance km"]) {
                distance = km
                distanceUnit = .kilometers
            } else {
                distance = index(["distance"])
                distanceUnit = kind == .hevyCSV ? .miles : .meters
            }
        }
    }

    private struct Row {
        var title: String
        var startRaw: String
        var startDate: Date?
        var exerciseName: String
        var setIndex: Int
        var weight: Double?
        var weightUnit: WeightUnit
        var reps: Int?
        var distance: Double?
        var distanceUnit: DistanceUnit
        var durationSeconds: Int?

        var hasSetValues: Bool {
            weight != nil || reps != nil || distance != nil || durationSeconds != nil
        }

        init?(fields: [String], columns: ColumnMap) {
            func field(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let name = field(columns.exerciseName)
            guard !name.isEmpty else { return nil }
            // A concatenated export's second header row looks like data.
            let lowered = name.lowercased()
            if lowered == "exercise_title" || lowered == "exercise title"
                || lowered == "exercise name" || lowered == "exercise" {
                return nil
            }

            title = field(columns.title)
            if title.isEmpty { title = "Imported workout" }
            startRaw = field(columns.start)
            startDate = CSVWorkoutDate.parse(startRaw)
            exerciseName = name
            setIndex = Int(field(columns.setIndex)) ?? 0
            weight = CSVNumber.positiveDouble(field(columns.weight))
            weightUnit = columns.weightUnit
            reps = CSVNumber.positiveInt(field(columns.reps))
            distance = CSVNumber.positiveDouble(field(columns.distance))
            distanceUnit = columns.distanceUnit
            durationSeconds = CSVNumber.positiveInt(field(columns.duration))
                ?? CSVNumber.durationToken(field(columns.duration))
        }
    }

    private struct GroupKey: Hashable {
        var title: String
        var startRaw: String
    }

    private struct Group {
        var title: String
        var start: Date?
        var startRaw: String
        var exercises: [String: ExerciseBucket] = [:]
        var exerciseOrder: [String] = []

        mutating func append(_ row: Row) {
            let key = row.exerciseName.lowercased()
            if exercises[key] == nil {
                exerciseOrder.append(key)
                exercises[key] = ExerciseBucket(name: row.exerciseName)
            }
            exercises[key]?.sets.append(
                SetRow(
                    index: row.setIndex,
                    set: ParsedSetDraft(
                        weight: row.weight,
                        weightUnit: row.weightUnit,
                        reps: row.reps,
                        distance: row.distance,
                        distanceUnit: row.distanceUnit,
                        durationSeconds: row.durationSeconds,
                        performedAt: row.startDate
                    )
                )
            )
        }

        func makeWorkout(kind: WorkoutImportPayloadKind) -> Workout? {
            let parsedExercises: [ParsedExerciseDraft] = exerciseOrder.compactMap { key in
                guard var bucket = exercises[key] else { return nil }
                bucket.sets.sort { lhs, rhs in
                    if lhs.index != rhs.index { return lhs.index < rhs.index }
                    return false
                }
                let sets = bucket.sets.map(\.set)
                guard !sets.isEmpty else { return nil }
                return ParsedExerciseDraft(name: bucket.name, sets: sets)
            }
            guard !parsedExercises.isEmpty else { return nil }

            var draft = ParsedWorkoutDraft(
                performedAt: start,
                title: title,
                exercises: parsedExercises
            )
            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.title = "Imported workout"
            }

            let identity = "\(kind.rawValue)|\(title)|\(startRaw)"
            let sourceText = reconstructedSource(draft: draft)
            return Workout(identityKey: identity, sourceText: sourceText, draft: draft)
        }

        private func reconstructedSource(draft: ParsedWorkoutDraft) -> String {
            var lines: [String] = [draft.title]
            if let start {
                lines.append(CSVWorkoutDate.display.string(from: start))
            }
            for exercise in draft.exercises {
                lines.append(exercise.name)
                for (index, set) in exercise.sets.enumerated() {
                    var parts = ["Set \(index + 1):"]
                    if let weight = set.weight {
                        parts.append("\(CSVNumber.display(weight)) \(set.weightUnit.symbol)")
                    }
                    if let reps = set.reps {
                        parts.append("x \(reps)")
                    }
                    if let duration = set.durationSeconds {
                        parts.append("\(duration)s")
                    }
                    if let distance = set.distance {
                        parts.append("\(CSVNumber.display(distance)) \(set.distanceUnit.rawValue)")
                    }
                    lines.append(parts.joined(separator: " "))
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    private struct ExerciseBucket {
        var name: String
        var sets: [SetRow] = []
    }

    private struct SetRow {
        var index: Int
        var set: ParsedSetDraft
    }
}

// MARK: - CSV records / fields

/// Splits a CSV document into records, honouring quoted commas *and* quoted
/// newlines (Hevy notes often wrap).
nonisolated enum CSVRecords {
    static func records(in text: String) -> [String] {
        var body = text
        if body.hasPrefix("\u{FEFF}") {
            body.removeFirst()
        }
        var records: [String] = []
        var current = ""
        var inQuotes = false
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "\"" {
                current.append(character)
                let next = body.index(after: index)
                if inQuotes, next < body.endIndex, body[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r" {
                    let next = body.index(after: index)
                    if next < body.endIndex, body[next] == "\n" {
                        index = next
                    }
                }
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { records.append(trimmed) }
                current = ""
            } else {
                current.append(character)
            }
            index = body.index(after: index)
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { records.append(trimmed) }
        return records
    }
}

nonisolated enum CSVFields {
    /// Splits a single CSV line, honouring quoted commas and doubled quotes.
    static func parse(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Numbers / dates

nonisolated enum CSVNumber {
    static func positiveDouble(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    static func positiveInt(_ raw: String) -> Int? {
        guard let value = positiveDouble(raw) else { return nil }
        return Int(value.rounded())
    }

    /// Strong's Duration column is often "60m" / "1h 5m" on the workout, not the set.
    /// Only accept tokens that look like a *set* duration ("45s", "90").
    static func durationToken(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("s"), let value = positiveInt(String(trimmed.dropLast())) {
            return value
        }
        return nil
    }

    static func display(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(value)
    }
}

nonisolated enum CSVWorkoutDate {
    static let display: DateFormatter = {
        makeFormatter("d MMM yyyy, HH:mm")
    }()

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let cached: [String: DateFormatter] = {
        Dictionary(uniqueKeysWithValues: formats.map { ($0, makeFormatter($0)) })
    }()

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = isoFractional.date(from: trimmed) { return date }
        if let date = isoBasic.date(from: trimmed) { return date }

        for format in formats {
            if let date = cached[format]?.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static let formats = [
        "d MMM yyyy, HH:mm",
        "d MMM yyyy, H:mm",
        "dd MMM yyyy, HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
        "M/d/yyyy HH:mm",
        "M/d/yyyy",
        "M/d/yy"
    ]

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
