import Foundation
import FoundationModels

/// Phrases a `MonthlyReport` as two or three short insights.
///
/// Division of labor is strict: every number is computed by
/// `MonthlyReportBuilder` — the on-device model only chooses words for values
/// it is handed (the ~3B system model is unreliable at arithmetic, so it is
/// never asked to do any). The model is still a model, so its output is not
/// trusted either: `InsightValidator` drops any sentence carrying a number
/// that isn't in the facts, or straying into health / diet / body advice, and
/// fewer than two survivors means the deterministic phrasing below ships
/// instead. The same fallback covers Apple Intelligence being unavailable
/// (older hardware, disabled, unsupported language, simulator) and any model
/// error, so the feature degrades to "less varied prose", never to "missing"
/// or "wrong".
enum TrainingInsights {
    /// Who wrote the sentences — the sheet's footer says so honestly.
    enum Source: Equatable {
        case appleIntelligence
        case template
    }

    struct Result: Equatable {
        let lines: [String]
        let source: Source
    }

    /// One entry per report month *and* exact fact sheet: a new set, a new PR,
    /// or a unit switch changes the facts, so it can never serve stale text.
    struct CacheKey: Hashable {
        let monthStart: Date
        let facts: String
    }

    /// App-session memory of what the model wrote. Greedy sampling makes the
    /// text stable anyway; the cache just spares a model call per sheet open.
    private static var cache: [CacheKey: Result] = [:]

    static func cacheKey(for report: MonthlyReport, unit: WeightUnit) -> CacheKey {
        CacheKey(monthStart: report.monthStart, facts: MonthlyReportPhrasing.promptFacts(for: report, unit: unit))
    }

    static var isModelAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        // Available-but-unsupported-language would write prose the rest of
        // the screen isn't in; the template is the better answer there.
        return model.supportsLocale()
    }

    /// Two-to-three short insights for the report. Falls back to deterministic
    /// phrasing on any model unavailability, error, or failed validation.
    static func insights(for report: MonthlyReport, unit: WeightUnit) async -> Result {
        let fallback = Result(
            lines: MonthlyReportPhrasing.fallbackInsights(for: report, unit: unit),
            source: .template
        )
        let key = cacheKey(for: report, unit: unit)
        if let cached = cache[key] { return cached }
        guard isModelAvailable else { return fallback }

        let result: Result
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: key.facts,
                generating: GeneratedInsights.self,
                // Greedy: the same month reads the same way every time the
                // sheet opens, instead of reshuffling its sentences.
                options: GenerationOptions(samplingMode: .greedy)
            )
            if let lines = InsightValidator.validated(response.content.insights, facts: key.facts, unit: unit) {
                result = Result(lines: lines, source: .appleIntelligence)
            } else {
                result = fallback
            }
        } catch {
            // No retry: a failed or refused generation is remembered as the
            // template so reopening the sheet doesn't call the model again.
            result = fallback
        }
        cache[key] = result
        return result
    }

    static let instructions = """
        You describe monthly training-report facts for a strength athlete. You will \
        receive pre-computed statistics. Write 2-3 short, specific insights, one \
        sentence each, describing what the numbers show. Only use numbers that appear \
        in the facts, written exactly as given with their units — never invent, \
        convert, round differently, or recompute values. Describe only: never give \
        advice or instructions, never say "you should", and never mention injury, \
        recovery, rest days, pain, sleep, medical topics, nutrition, diet, calories, \
        bodyweight, body image, or weight loss. Neutral-optimistic tone; a flat or down \
        month is framed as information, never as failure. No emoji.
        """
}

@Generable
private struct GeneratedInsights {
    @Guide(description: "2-3 one-sentence training insights, each grounded in the provided stats", .count(2...3))
    var insights: [String]
}

// MARK: - Validation

/// Pure gate between the model and the screen. A sentence survives only if
/// every number it states appears in the fact sheet (at the precision it was
/// shown, or rounded coarser) and it stays clear of health advice.
nonisolated enum InsightValidator {
    /// Lowercased substrings that mark a sentence as advice or health talk the
    /// app has no business giving. Deliberately blunt: a false drop costs one
    /// sentence of prose, a false keep costs trust.
    static let blocklist: [String] = [
        "injur", "overtrain", "doctor", "physician", "medical", "pain",
        "diet", "calorie", "nutrition", "protein", "hydrat", "supplement",
        "lose weight", "losing weight", "weight loss", "fat", "physique",
        "body image", "bodyweight", "body weight",
        "rest day", "take a rest", "recover", "sleep",
        "you should", "you need to", "make sure"
    ]

    /// A number as written: its value and the smallest step its digits can
    /// express (`12.3t` → 12,300 in steps of 100).
    nonisolated struct Quantity: Equatable {
        let value: Double
        let precision: Double
    }

    /// Spelled small numbers are claims too ("three sessions"). "one" is left
    /// out on purpose — "every one of them" isn't a statistic.
    private static let spelled: [String: Double] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    nonisolated(unsafe) private static let numberPattern = try! NSRegularExpression(
        pattern: #"((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)(?:\s?(k|t|tons?|tonnes?|thousand)\b)?"#,
        options: [.caseInsensitive]
    )

    nonisolated(unsafe) private static let wordPattern = try! NSRegularExpression(
        pattern: #"\b[a-z]+\b"#,
        options: [.caseInsensitive]
    )

    /// The trimmed, de-duplicated survivors (at most three), or nil when fewer
    /// than two remain and the caller should use the template instead.
    static func validated(_ candidates: [String], facts: String, unit: WeightUnit) -> [String]? {
        let allowed = quantities(in: facts)
        var kept: [String] = []
        for candidate in candidates {
            let line = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !kept.contains(line) else { continue }
            guard !isBlocked(line, unit: unit) else { continue }
            guard numbersAreGrounded(line, in: allowed) else { continue }
            kept.append(line)
        }
        guard kept.count >= 2 else { return nil }
        return Array(kept.prefix(3))
    }

    static func isBlocked(_ sentence: String, unit: WeightUnit) -> Bool {
        let lowered = sentence.lowercased()
        if blocklist.contains(where: { lowered.contains($0) }) { return true }
        // Tons are a metric story; a pound user's volume is never "tons".
        if unit == .lb, lowered.contains("ton") { return true }
        return false
    }

    static func numbersAreGrounded(_ sentence: String, in allowed: [Quantity]) -> Bool {
        quantities(in: sentence, includeSpelled: true).allSatisfy { claim in
            allowed.contains { matches(claim, fact: $0) }
        }
    }

    /// True when `claim` is `fact` written at the same or a coarser precision
    /// ("12.3" for 12.30, "7" for 7.4, "27,100" or "27.1k" for 27.1k) — never
    /// when the claim is more precise than the fact or simply different.
    static func matches(_ claim: Quantity, fact: Quantity) -> Bool {
        let tolerance = 1e-6 * max(1, abs(fact.value))
        if claim.precision >= fact.precision - tolerance {
            let rounded = (fact.value / claim.precision).rounded() * claim.precision
            if abs(rounded - claim.value) <= tolerance { return true }
        }
        // A scaled fact ("27.1k") only pins a window; a spelled-out figure
        // inside that window is the same number ("27,100").
        if fact.precision > 1 {
            return abs(claim.value - fact.value) <= fact.precision / 2 + tolerance
        }
        return false
    }

    static func quantities(in text: String, includeSpelled: Bool = false) -> [Quantity] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [Quantity] = numberPattern.matches(in: text, range: range).compactMap { match in
            guard let digitsRange = Range(match.range(at: 1), in: text) else { return nil }
            let digits = text[digitsRange].replacingOccurrences(of: ",", with: "")
            guard let raw = Double(digits) else { return nil }

            // Every suffix the pattern accepts (k, t, tons, thousand) is ×1000.
            let multiplier = match.range(at: 2).location == NSNotFound ? 1.0 : 1000.0

            // Trailing zeros after the point carry no precision: 12.30 == 12.3.
            var decimals = 0
            if let dot = digits.firstIndex(of: ".") {
                decimals = digits[digits.index(after: dot)...].reversed().drop(while: { $0 == "0" }).count
            }
            return Quantity(value: raw * multiplier, precision: pow(10, -Double(decimals)) * multiplier)
        }
        if includeSpelled {
            for match in wordPattern.matches(in: text, range: range) {
                guard let wordRange = Range(match.range, in: text),
                      let value = spelled[text[wordRange].lowercased()] else { continue }
                found.append(Quantity(value: value, precision: 1))
            }
        }
        return found
    }
}

// MARK: - Deterministic phrasing

/// Deterministic wording shared by the fallback path and the model prompt.
enum MonthlyReportPhrasing {
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Metric volume: "850 kg" / "12.3t". Kept for surfaces that don't know
    /// the lifter's unit.
    static func volumeText(kilograms: Double) -> String {
        volumeText(kilograms: kilograms, unit: .kg)
    }

    /// Volume in the lifter's unit. Metric keeps its tonnes shorthand; pounds
    /// get a "k" shorthand from five digits ("27.1k lb") and never "tons".
    static func volumeText(kilograms: Double, unit: WeightUnit) -> String {
        switch unit {
        case .kg:
            if kilograms >= 1000 {
                return String(format: "%.1ft", kilograms / 1000)
            }
            return "\(Int(kilograms.rounded())) kg"
        case .lb:
            let pounds = LifterAnalytics.displayWeight(fromKilograms: kilograms, in: .lb)
            if pounds >= 10_000 {
                return String(format: "%.1fk lb", pounds / 1000)
            }
            let rounded = pounds.rounded()
            let grouped = groupedFormatter.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))"
            return "\(grouped) lb"
        }
    }

    static func promptFacts(for report: MonthlyReport, unit: WeightUnit) -> String {
        var facts: [String] = [
            "Month: \(report.monthLabel)\(report.isMonthToDate ? " (in progress)" : "")",
            "Sessions: \(report.sessions)",
            "Sets: \(report.sets)",
            "Total volume: \(volumeText(kilograms: report.volumeKilograms, unit: unit))",
            "Personal records: \(report.prCount)"
        ]
        if let averageRPE = report.averageRPE {
            facts.append(String(format: "Average effort (RPE): %.1f", averageRPE))
        }
        if !report.topMuscleGroups.isEmpty {
            let focus = report.topMuscleGroups
                .map { "\($0.category.displayName) (\($0.sets) sets)" }
                .joined(separator: ", ")
            facts.append("Most trained: \(focus)")
        }
        if let comparisonLabel = report.comparisonLabel {
            var deltas: [String] = []
            if let sessionsDelta = report.sessionsDelta {
                deltas.append(String(format: "sessions %+d", sessionsDelta))
            }
            if let volumeDelta = report.volumeDeltaPercent {
                deltas.append(String(format: "volume %+.0f%%", volumeDelta))
            }
            if let prDelta = report.prDelta {
                deltas.append(String(format: "PRs %+d", prDelta))
            }
            if !deltas.isEmpty {
                facts.append("Change \(comparisonLabel): \(deltas.joined(separator: ", "))")
            }
        }
        return facts.joined(separator: "\n")
    }

    /// "than at this point in June" while the month is under way, "than in
    /// June" once it's complete — the builder's comparison label already says
    /// which comparison it made.
    static func sessionComparisonPhrase(for report: MonthlyReport) -> String? {
        guard let label = report.comparisonLabel else { return nil }
        let target = label.hasPrefix("vs ") ? String(label.dropFirst(3)) : label
        return report.isMonthToDate ? "than at \(target)" : "than in \(target)"
    }

    static func fallbackInsights(for report: MonthlyReport, unit: WeightUnit = .lb) -> [String] {
        var insights: [String] = []

        if let volumeDelta = report.volumeDeltaPercent, let comparisonLabel = report.comparisonLabel {
            if volumeDelta >= 5 {
                insights.append(String(format: "Volume is up %.0f%% %@ — the work is trending the right way.", volumeDelta, comparisonLabel))
            } else if volumeDelta <= -5 {
                insights.append(String(format: "Volume is down %.0f%% %@ — worth a look if it wasn't a planned lighter stretch.", abs(volumeDelta), comparisonLabel))
            } else {
                insights.append("Volume is holding steady \(comparisonLabel) — consistency like that is what progress is built on.")
            }
        } else {
            let volume = volumeText(kilograms: report.volumeKilograms, unit: unit)
            let sessions = report.sessions == 1 ? "1 session" : "\(report.sessions) sessions"
            let sets = report.sets == 1 ? "1 set" : "\(report.sets) sets"
            insights.append("\(sessions), \(sets) and \(volume) moved — every one of them is in the bank.")
        }

        if report.prCount > 0 {
            insights.append(report.prCount == 1
                ? "You set 1 personal record — proof the numbers are still moving."
                : "You set \(report.prCount) personal records — proof the numbers are still moving.")
        } else if let focus = report.topMuscleGroups.first {
            insights.append("\(focus.category.displayName) led the month with \(focus.sets) sets — heaviest focus on the board.")
        }

        if let sessionsDelta = report.sessionsDelta, sessionsDelta > 0,
           let comparison = sessionComparisonPhrase(for: report) {
            insights.append(sessionsDelta == 1
                ? "That's 1 more session \(comparison)."
                : "That's \(sessionsDelta) more sessions \(comparison).")
        }

        return Array(insights.prefix(3))
    }
}
