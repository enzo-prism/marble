import Foundation

/// Matches free-text exercise names ("incline db press", "bnech 3x5") against the
/// user's exercise library so imports reuse existing rows instead of silently
/// creating near-duplicates.
///
/// Pure value type over a snapshot of library names — no SwiftData, no model, no
/// main-actor requirement — so matching is fully unit-testable and cheap enough to
/// run per keystroke. Matching is layered, cheapest first:
///   1. Normalization (case, punctuation) + gym-shorthand aliases (db → dumbbell).
///   2. Exact normalized equality.
///   3. Token overlap with per-token edit-distance tolerance for typos.
nonisolated struct ExerciseMatcher: Sendable {

    struct Candidate: Equatable, Sendable, Identifiable {
        let id: UUID
        let name: String
    }

    /// Ordered weakest to strongest so callers can compare with `>=`.
    enum Confidence: Int, Equatable, Sendable, Comparable {
        /// Plausible, but different enough that the user should confirm
        /// (e.g. "Bench" against "Bench Press").
        case likely
        /// Same movement modulo spelling, word order, or shorthand.
        case strong
        /// Identical after normalization and aliasing.
        case exact

        static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Match: Equatable, Sendable {
        let candidate: Candidate
        let confidence: Confidence
        /// Token-overlap score in 0...1; 1 is a perfect normalized match.
        let score: Double
    }

    private struct IndexedCandidate {
        let candidate: Candidate
        let joined: String
        let tokens: [String]
    }

    private let indexed: [IndexedCandidate]

    init(candidates: [Candidate]) {
        indexed = candidates.map { candidate in
            let tokens = Self.normalizedTokens(candidate.name)
            return IndexedCandidate(
                candidate: candidate,
                joined: tokens.joined(separator: " "),
                tokens: tokens
            )
        }
    }

    /// The single best library match for `name`, or nil when nothing clears the
    /// suggestion threshold and the right move is creating a new exercise.
    func bestMatch(for name: String) -> Match? {
        ranked(for: name).first
    }

    /// Ranked plausible matches for a disambiguation picker, best first.
    func topMatches(for name: String, limit: Int = 5) -> [Match] {
        Array(ranked(for: name).prefix(limit))
    }

    private func ranked(for name: String) -> [Match] {
        let queryTokens = Self.normalizedTokens(name)
        guard !queryTokens.isEmpty else { return [] }
        let queryJoined = queryTokens.joined(separator: " ")

        return indexed.compactMap { entry -> Match? in
            if entry.joined == queryJoined {
                return Match(candidate: entry.candidate, confidence: .exact, score: 1)
            }
            let score = Self.tokenOverlapScore(queryTokens, entry.tokens)
            guard score >= Self.likelyThreshold else { return nil }
            return Match(
                candidate: entry.candidate,
                confidence: score >= Self.strongThreshold ? .strong : .likely,
                score: score
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            // Deterministic tie-break so tests and UI ordering are stable.
            return lhs.candidate.name < rhs.candidate.name
        }
    }

    // MARK: - Scoring

    /// Below this the names don't plausibly describe the same movement.
    private static let likelyThreshold = 0.55
    /// At or above this the names differ only by typo, order, or shorthand.
    private static let strongThreshold = 0.85
    /// Per-token similarity needed before two tokens count as the same word.
    private static let tokenSimilarityThreshold = 0.75

    /// Dice-style coefficient over tokens, where tokens match fuzzily (edit
    /// distance) so "bnech press" still lines up with "bench press".
    private static func tokenOverlapScore(_ query: [String], _ candidate: [String]) -> Double {
        guard !query.isEmpty, !candidate.isEmpty else { return 0 }
        var remaining = candidate
        var matchedSimilarity = 0.0
        var matchedCount = 0
        for token in query {
            var bestIndex: Int?
            var bestSimilarity = 0.0
            for (index, other) in remaining.enumerated() {
                let similarity = tokenSimilarity(token, other)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestIndex = index
                }
            }
            if let bestIndex, bestSimilarity >= tokenSimilarityThreshold {
                matchedSimilarity += bestSimilarity
                matchedCount += 1
                remaining.remove(at: bestIndex)
            }
        }
        guard matchedCount > 0 else { return 0 }
        return (2 * matchedSimilarity) / Double(query.count + candidate.count)
    }

    private static func tokenSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 0 }
        // Short tokens ("db", "row") have no room for typos: near-misses like
        // "row"/"raw" are different words, so require equality below 4 chars.
        guard min(a.count, b.count) >= 4 else { return 0 }
        return 1 - Double(editDistance(a, b)) / Double(maxLength)
    }

    /// Optimal-string-alignment distance: Levenshtein plus adjacent
    /// transpositions as a single edit, so the classic "bnech" swap typo stays
    /// one mistake instead of two.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var rows = [[Int]](repeating: [Int](repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { rows[i][0] = i }
        for j in 0...bChars.count { rows[0][j] = j }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
                if i > 1, j > 1, aChars[i - 1] == bChars[j - 2], aChars[i - 2] == bChars[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }
        return rows[aChars.count][bChars.count]
    }

    // MARK: - Normalization

    /// Gym shorthand expanded during normalization. Multi-word expansions keep
    /// token counts honest ("ohp" and "overhead press" score identically).
    private static let aliases: [String: [String]] = [
        "db": ["dumbbell"], "dbs": ["dumbbell"], "dumbell": ["dumbbell"], "dumbbells": ["dumbbell"],
        "bb": ["barbell"], "barbells": ["barbell"],
        "kb": ["kettlebell"], "kbs": ["kettlebell"],
        "bw": ["bodyweight"],
        "ohp": ["overhead", "press"],
        "rdl": ["romanian", "deadlift"], "rdls": ["romanian", "deadlift"],
        "sldl": ["stiff", "leg", "deadlift"],
        "dl": ["deadlift"],
        "gm": ["good", "morning"], "gms": ["good", "morning"],
        "lats": ["lat"],
        "hs": ["hamstring"], "ham": ["hamstring"], "hams": ["hamstring"],
        "tri": ["triceps"], "tris": ["triceps"], "tricep": ["triceps"],
        "bi": ["biceps"], "bis": ["biceps"], "bicep": ["biceps"],
        "ext": ["extension"], "exts": ["extension"]
    ]

    private static func normalizedTokens(_ name: String) -> [String] {
        let cleaned = String(name.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " })
        return cleaned.split(separator: " ")
            .map(String.init)
            .flatMap { aliases[$0] ?? [$0] }
            .map(singularized)
    }

    /// Light plural folding so "curls" matches "Curl". Double-s words ("press")
    /// and short tokens are left alone.
    private static func singularized(_ token: String) -> String {
        guard token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") else { return token }
        return String(token.dropLast())
    }
}
