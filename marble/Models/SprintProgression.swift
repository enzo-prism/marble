import Foundation
import SwiftData

/// One logged rep's result within a sequence — the rollup's unit of account.
nonisolated struct SprintRepOutcome: Equatable {
    let tenths: Int
    let outcome: SprintTargetOutcome?

    var isHit: Bool {
        outcome == .metTime || outcome == .inRange
    }
}

/// The hit-rate-driven coaching nudge: when an athlete keeps beating a plan,
/// suggest the next harder target instead of letting a stale goal read as
/// effortless "hits" forever.
///
/// Pure decision core (`suggestion`) + one context-backed convenience (`hint`)
/// so the rule is unit-testable without a store — the `TrainingConsistency`
/// split.
nonisolated enum SprintProgression {
    /// One day's worth of reps against a single variant.
    struct SessionResult: Equatable {
        let day: Date
        let scoredReps: Int
        let hitReps: Int
    }

    /// Sessions that must consecutively clear the bar before nudging.
    static let requiredSessions = 2
    /// A session counts as cleared at ≥80% hits.
    static let requiredHitRate = 0.8
    /// How much faster the suggested target is (tenths): 0.2 s — enough to
    /// mean something at 60–200 m, small enough to stay reachable.
    static let stepTenths = 2

    /// Nil when the athlete hasn't earned the nudge; otherwise a one-line
    /// suggestion. `sessions` must be most-recent-first, one element per
    /// distinct training day.
    static func suggestion(
        target: SprintTargetTenths,
        repetitionCount: Int,
        sessions: [SessionResult]
    ) -> String? {
        guard target.isValid, sessions.count >= requiredSessions else { return nil }
        // A one-rep cameo shouldn't tighten the plan: each qualifying session
        // needs at least half the prescribed reps (min 2) actually scored.
        let minimumReps = max(2, repetitionCount / 2)
        let recent = sessions.prefix(requiredSessions)
        for session in recent {
            guard session.scoredReps >= minimumReps,
                  Double(session.hitReps) / Double(session.scoredReps) >= requiredHitRate else {
                return nil
            }
        }

        switch target.mode {
        case .time:
            let suggested = target.lowerTenths - stepTenths
            guard suggested > 0 else { return nil }
            return "Hit in each of your last \(requiredSessions) sessions — try \(SprintTiming.text(tenths: suggested)) or faster."
        case .range:
            let suggestedUpper = target.upperTenths - stepTenths
            guard suggestedUpper >= target.lowerTenths else { return nil }
            let tightened = SprintTargetTenths(lowerTenths: target.lowerTenths, upperTenths: suggestedUpper)
            return "Hit in each of your last \(requiredSessions) sessions — try tightening the range to \(tightened.targetText())."
        }
    }

    /// Groups a variant's logged rep details into per-day sessions,
    /// most-recent-first, judging each rep against ITS frozen target (not the
    /// variant's current one — past hits stay hits after the plan changes).
    static func sessions(
        details: [(performedAt: Date, tenths: Int, target: SprintTargetTenths)],
        calendar: Calendar = .current
    ) -> [SessionResult] {
        let byDay = Dictionary(grouping: details) { calendar.startOfDay(for: $0.performedAt) }
        return byDay.keys.sorted(by: >).map { day in
            let reps = byDay[day] ?? []
            let hits = reps.filter { rep in
                let outcome = rep.target.outcome(forTenths: rep.tenths)
                return outcome == .metTime || outcome == .inRange
            }
            return SessionResult(day: day, scoredReps: reps.count, hitReps: hits.count)
        }
    }

    /// Store-backed convenience for the logging card. Fetches the variant's
    /// rep details, joins their entries for the performed day, and runs the
    /// pure rule. Both fetches are small (details are per-variant) — cheap
    /// enough for the selection-change call sites, and never called per frame.
    @MainActor
    static func hint(
        variantID: UUID,
        target: SprintTargetTenths,
        repetitionCount: Int,
        in context: ModelContext
    ) -> String? {
        let detailDescriptor = FetchDescriptor<SprintRepDetail>(
            predicate: #Predicate { $0.variantID == variantID }
        )
        guard let details = try? context.fetch(detailDescriptor), !details.isEmpty else { return nil }

        let entryIDs = details.map(\.setEntryID)
        let entryDescriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { entryIDs.contains($0.id) }
        )
        guard let entries = try? context.fetch(entryDescriptor) else { return nil }
        let performedAtByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.performedAt) })

        let joined = details.compactMap { detail -> (Date, Int, SprintTargetTenths)? in
            guard let performedAt = performedAtByID[detail.setEntryID] else { return nil }
            return (performedAt, detail.durationTenths, detail.target)
        }
        return suggestion(
            target: target,
            repetitionCount: repetitionCount,
            sessions: sessions(details: joined.map { (performedAt: $0.0, tenths: $0.1, target: $0.2) })
        )
    }
}
