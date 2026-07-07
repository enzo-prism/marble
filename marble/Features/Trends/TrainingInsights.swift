import Foundation
import FoundationModels

/// Phrases a `MonthlyReport` as two or three short insights.
///
/// Division of labor is strict: every number is computed by
/// `MonthlyReportBuilder` — the on-device model only chooses words for values
/// it is handed (the ~3B system model is unreliable at arithmetic, so it is
/// never asked to do any). When Apple Intelligence is unavailable (older
/// hardware, disabled, simulator) the deterministic phrasing below ships the
/// same facts, so the feature degrades to "less varied prose", never to
/// "missing" or "wrong".
enum TrainingInsights {
    static var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Two-to-three short insights for the report. Falls back to deterministic
    /// phrasing on any model unavailability or error.
    static func insights(for report: MonthlyReport) async -> [String] {
        guard isModelAvailable else {
            return MonthlyReportPhrasing.fallbackInsights(for: report)
        }
        do {
            let session = LanguageModelSession(instructions: """
                You phrase monthly training-report facts for a strength athlete. You will \
                receive pre-computed statistics. Write 2-3 short, specific, encouraging \
                insights (one sentence each). Only reference the numbers provided — \
                never invent or recompute values. Neutral-optimistic tone; a flat or \
                down month is framed as information, never as failure. No emoji.
                """)
            let response = try await session.respond(
                to: MonthlyReportPhrasing.promptFacts(for: report),
                generating: GeneratedInsights.self
            )
            let lines = response.content.insights
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                return MonthlyReportPhrasing.fallbackInsights(for: report)
            }
            return Array(lines.prefix(3))
        } catch {
            return MonthlyReportPhrasing.fallbackInsights(for: report)
        }
    }
}

@Generable
private struct GeneratedInsights {
    @Guide(description: "2-3 one-sentence training insights, each grounded in the provided stats")
    var insights: [String]
}

/// Deterministic wording shared by the fallback path and the model prompt.
enum MonthlyReportPhrasing {
    static func volumeText(kilograms: Double) -> String {
        if kilograms >= 1000 {
            return String(format: "%.1ft", kilograms / 1000)
        }
        return "\(Int(kilograms.rounded())) kg"
    }

    static func promptFacts(for report: MonthlyReport) -> String {
        var facts: [String] = [
            "Month: \(report.monthLabel)\(report.isMonthToDate ? " (in progress)" : "")",
            "Sessions: \(report.sessions)",
            "Sets: \(report.sets)",
            "Total volume: \(volumeText(kilograms: report.volumeKilograms))",
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

    static func fallbackInsights(for report: MonthlyReport) -> [String] {
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
            insights.append("\(report.sessions) sessions and \(report.sets) sets logged — every one of them is in the bank.")
        }

        if report.prCount > 0 {
            insights.append(report.prCount == 1
                ? "You set 1 personal record — proof the numbers are still moving."
                : "You set \(report.prCount) personal records — proof the numbers are still moving.")
        } else if let focus = report.topMuscleGroups.first {
            insights.append("\(focus.category.displayName) led the month with \(focus.sets) sets — heaviest focus on the board.")
        }

        if let sessionsDelta = report.sessionsDelta, sessionsDelta > 0 {
            insights.append(sessionsDelta == 1
                ? "That's 1 more session than last month at this point."
                : "That's \(sessionsDelta) more sessions than last month at this point.")
        }

        return Array(insights.prefix(3))
    }
}
