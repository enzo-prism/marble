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
        let delimiter = CSVFields.delimiter(in: headerLine)
        let headers = CSVFields.parse(headerLine, delimiter: delimiter).map(normalizeHeader)
        guard let kind = detectKind(headers: headers) else { return nil }

        let columns = ColumnMap(
            headers: headers,
            kind: kind,
            defaultWeightUnit: defaultWeightUnit,
            decimalComma: delimiter == ";"
        )
        guard columns.exerciseName != nil else { return nil }

        var groups: [GroupKey: Group] = [:]
        var order: [GroupKey] = []

        for line in lines.dropFirst() {
            let fields = CSVFields.parse(line, delimiter: delimiter)
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
        let delimiter = CSVFields.delimiter(in: line)
        let headers = CSVFields.parse(line, delimiter: delimiter).map(normalizeHeader)
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
        var workoutDuration: Int?
        var rpe: Int?
        var setNotes: Int?
        var exerciseNotes: Int?
        var workoutNotes: Int?
        var superset: Int?
        var decimalComma: Bool

        init(
            headers: [String],
            kind: WorkoutImportPayloadKind,
            defaultWeightUnit: WeightUnit,
            decimalComma: Bool = false
        ) {
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
            // Hevy `duration_seconds` / Strong `Seconds` are per-set. Strong's
            // `Duration` ("60m") is the workout clock and must not land here —
            // a bare "45" in that column would otherwise become a 45s set.
            duration = index(["duration_seconds", "duration seconds", "seconds"])
            workoutDuration = index(["duration"])
            rpe = index(["rpe"])
            setNotes = index(["notes"])
            exerciseNotes = index(["exercise_notes", "exercise notes"])
            workoutNotes = index(["workout notes", "description"])
            superset = index(["superset_id", "superset id", "superset"])
            self.decimalComma = decimalComma

            if let lbs = index(["weight_lbs", "weight lbs", "lbs", "weight (lbs)", "weight (lb)"]) {
                weight = lbs
                weightUnit = .lb
            } else if let kg = index(["weight_kg", "weight kg", "kg", "weight (kg)"]) {
                weight = kg
                weightUnit = .kg
            } else {
                weight = index(["weight"])
                weightUnit = defaultWeightUnit
            }

            if let miles = index(["distance_miles", "distance miles", "distance (miles)", "distance (mi)"]) {
                distance = miles
                distanceUnit = .miles
            } else if let km = index(["distance_km", "distance km", "distance (km)", "distance (kilometers)"]) {
                distance = km
                distanceUnit = .kilometers
            } else {
                distance = index(["distance", "distance (m)", "distance (meters)"])
                // Strong's bare Distance is the user's preferred unit (km or mi),
                // never metres — a "5.0" run is 5 km/mi, not 5 m. Hevy names the
                // unit in the header (`distance_miles` / `distance_km`).
                if kind == .hevyCSV {
                    distanceUnit = .miles
                } else {
                    distanceUnit = defaultWeightUnit == .kg ? .kilometers : .miles
                }
            }
        }
    }

    private struct Row {
        var title: String
        var startRaw: String
        var startDate: Date?
        var endDate: Date?
        var workoutDurationSeconds: Int?
        var workoutNotes: String?
        var exerciseName: String
        var setIndex: Int
        var weight: Double?
        var weightUnit: WeightUnit
        var reps: Int?
        var distance: Double?
        var distanceUnit: DistanceUnit
        var durationSeconds: Int?
        var difficulty: Int?
        var notes: String?
        var isFailureSet: Bool

        var hasSetValues: Bool {
            weight != nil || reps != nil || distance != nil || durationSeconds != nil || isFailureSet
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

            let setType = field(columns.setType)
            // Warmup rows inflate volume and PRs; drop them. Drop sets and
            // failure sets stay — they are real working sets.
            if CSVSetType.isWarmup(setType) { return nil }

            title = field(columns.title)
            if title.isEmpty { title = "Imported workout" }
            startRaw = field(columns.start)
            startDate = CSVWorkoutDate.parse(startRaw)
            endDate = CSVWorkoutDate.parse(field(columns.end))
            workoutDurationSeconds = CSVNumber.workoutDurationToken(field(columns.workoutDuration))
            let description = field(columns.workoutNotes)
            workoutNotes = description.isEmpty ? nil : description
            exerciseName = name
            setIndex = Int(field(columns.setIndex)) ?? 0
            weight = CSVNumber.positiveDouble(field(columns.weight), decimalComma: columns.decimalComma)
            weightUnit = columns.weightUnit
            isFailureSet = CSVSetType.isFailure(setType)
            let parsedReps = CSVNumber.nonNegativeInt(field(columns.reps), decimalComma: columns.decimalComma)
            if parsedReps == 0 {
                // Cardio rows log 0 reps; failed attempts keep the zero.
                reps = isFailureSet ? 0 : nil
            } else {
                reps = parsedReps
            }
            distance = CSVNumber.positiveDouble(field(columns.distance), decimalComma: columns.decimalComma)
            distanceUnit = columns.distanceUnit
            durationSeconds = CSVNumber.positiveInt(field(columns.duration), decimalComma: columns.decimalComma)
                ?? CSVNumber.durationToken(field(columns.duration))
            difficulty = CSVNumber.rpe(field(columns.rpe), decimalComma: columns.decimalComma)
            notes = CSVSetNotes.compose(
                exerciseNotes: field(columns.exerciseNotes),
                setNotes: field(columns.setNotes),
                setType: setType,
                supersetID: field(columns.superset)
            )
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
        var end: Date?
        var durationSeconds: Int?
        var notes: String?
        /// Contiguous same-name runs. A `set_index` reset (Hevy logging the
        /// same lift twice) starts a new exercise so sort-by-index cannot
        /// interleave the two blocks.
        var runs: [ExerciseBucket] = []

        mutating func append(_ row: Row) {
            if end == nil { end = row.endDate }
            if durationSeconds == nil { durationSeconds = row.workoutDurationSeconds }
            if (notes == nil || notes?.isEmpty == true), let note = row.workoutNotes, !note.isEmpty {
                notes = note
            }
            let set = ParsedSetDraft(
                weight: row.weight,
                weightUnit: row.weightUnit,
                reps: row.reps,
                distance: row.distance,
                distanceUnit: row.distanceUnit,
                durationSeconds: row.durationSeconds,
                performedAt: row.startDate,
                difficulty: row.difficulty,
                notes: row.notes
            )
            if var last = runs.last,
               last.name.compare(row.exerciseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
               row.setIndex >= last.lastIndex {
                last.sets.append(set)
                last.lastIndex = row.setIndex
                runs[runs.count - 1] = last
            } else {
                runs.append(ExerciseBucket(name: row.exerciseName, lastIndex: row.setIndex, sets: [set]))
            }
        }

        func makeWorkout(kind: WorkoutImportPayloadKind) -> Workout? {
            let parsedExercises: [ParsedExerciseDraft] = runs.compactMap { bucket in
                guard !bucket.sets.isEmpty else { return nil }
                return ParsedExerciseDraft(name: CSVExerciseName.normalized(bucket.name), sets: bucket.sets)
            }
            guard !parsedExercises.isEmpty else { return nil }

            var endedAt: Date?
            var duration = durationSeconds
            if let start, let end, end > start {
                endedAt = end
                duration = Int(end.timeIntervalSince(start).rounded())
            } else if let start, let duration, duration > 0 {
                endedAt = start.addingTimeInterval(TimeInterval(duration))
            }

            var draft = ParsedWorkoutDraft(
                performedAt: start,
                endedAt: endedAt,
                durationSeconds: duration.flatMap { $0 > 0 ? $0 : nil },
                notes: notes,
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
        var lastIndex: Int
        var sets: [ParsedSetDraft]
    }
}

nonisolated enum CSVSetType {
    static func isWarmup(_ raw: String) -> Bool {
        let normalized = compacted(raw)
        return normalized == "warmup" || normalized == "wu"
    }

    static func isFailure(_ raw: String) -> Bool {
        switch compacted(raw) {
        case "failure", "fail", "tofailure": return true
        default: return false
        }
    }

    static func noteTag(_ raw: String) -> String? {
        switch compacted(raw) {
        case "dropset", "drop": return "Drop set"
        case "failure", "fail", "tofailure": return "Failure"
        default: return nil
        }
    }

    private static func compacted(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter }
    }
}

/// Strong exports often append equipment (`Squat (Barbell)`). Strip it on the
/// draft name so library matching sees the same name as a handwritten
/// promotion. Grouping still uses the raw export name so `Squat (Barbell)`
/// and `Squat (Dumbbell)` stay two exercises.
nonisolated enum CSVExerciseName {
    static func normalized(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = result.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) {
            let stripped = result.replacingCharacters(in: range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty { result = stripped }
        }
        return result
    }
}

nonisolated enum CSVSetNotes {
    static func compose(
        exerciseNotes: String,
        setNotes: String,
        setType: String,
        supersetID: String = ""
    ) -> String? {
        var parts: [String] = []
        let exercise = exerciseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let set = setNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !exercise.isEmpty { parts.append(exercise) }
        if !set.isEmpty, set.caseInsensitiveCompare(exercise) != .orderedSame {
            parts.append(set)
        }
        if let tag = CSVSetType.noteTag(setType) { parts.append(tag) }
        let superset = supersetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !superset.isEmpty { parts.append("Superset \(superset)") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ")
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
    /// Picks `;` for EU/Android Strong exports when that is the majority
    /// unquoted separator; otherwise comma (Hevy and US Strong).
    static func delimiter(in line: String) -> Character {
        var commas = 0
        var semicolons = 0
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if !inQuotes {
                if character == "," { commas += 1 }
                else if character == ";" { semicolons += 1 }
            }
            index = line.index(after: index)
        }
        return semicolons > commas ? ";" : ","
    }

    /// Splits a single CSV line, honouring quoted separators and doubled quotes.
    static func parse(_ line: String, delimiter: Character = ",") -> [String] {
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
            } else if character == delimiter, !inQuotes {
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
    static func positiveDouble(_ raw: String, decimalComma: Bool = false) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned: String
        if decimalComma {
            // EU exports: "100,5" is 100.5; "1.000,5" is 1000.5.
            cleaned = trimmed.replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    static func positiveInt(_ raw: String, decimalComma: Bool = false) -> Int? {
        guard let value = positiveDouble(raw, decimalComma: decimalComma) else { return nil }
        return Int(value.rounded())
    }

    /// Zero is a real failed-rep count; empty still returns nil.
    static func nonNegativeInt(_ raw: String, decimalComma: Bool = false) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned: String
        if decimalComma {
            cleaned = trimmed.replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Double(cleaned), value >= 0 else { return nil }
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

    /// Hevy/Strong RPE. Empty and zero keep the journal default; half-steps round.
    static func rpe(_ raw: String, decimalComma: Bool = false) -> Int? {
        guard let value = positiveDouble(raw, decimalComma: decimalComma) else { return nil }
        return min(10, max(1, Int(value.rounded())))
    }

    /// Strong's workout `Duration` ("60m", "1h 5m") or a colon clock ("1:16:00").
    /// A bare number is minutes — that column is never seconds.
    static func workoutDurationToken(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let colon = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if colon.count == 3,
           let hours = Int(colon[0]), let minutes = Int(colon[1]), let seconds = Int(colon[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        if colon.count == 2, let minutes = Int(colon[0]), let seconds = Int(colon[1]) {
            return minutes * 60 + seconds
        }

        guard let regex = durationPieceRegex else { return nil }
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, range: nsRange)
        if matches.isEmpty {
            if trimmed.allSatisfy(\.isNumber), let minutes = Int(trimmed), minutes > 0 {
                return minutes * 60
            }
            return nil
        }
        var total = 0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: trimmed),
                  let unitRange = Range(match.range(at: 2), in: trimmed),
                  let value = Double(trimmed[numberRange]) else { continue }
            switch trimmed[unitRange].first {
            case "h": total += Int((value * 3600).rounded())
            case "m": total += Int((value * 60).rounded())
            case "s": total += Int(value.rounded())
            default: break
            }
        }
        return total > 0 ? total : nil
    }

    private static let durationPieceRegex = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours|m|min|mins|minutes|s|sec|secs|seconds)\b"#
    )

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
