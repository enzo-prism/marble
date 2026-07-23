import Foundation

/// Pure timing rules for the Daily Highlights quote rotator, extracted from the
/// view so the resume decision is unit-testable.
///
/// Semantics: auto-rotation advances once per `interval`-sized tick of absolute
/// time. A manual tap (or VoiceOver adjustment) pins the chosen quote, but only
/// until the first tick boundary that guarantees the pick was on screen for at
/// least one full interval — the boundary after the *next* one, since the tap
/// may land moments before a boundary. Rotation then resumes on the shared
/// schedule instead of staying pinned for the rest of the session. When
/// auto-rotation is off entirely (VoiceOver, Reduce Motion, tests), a manual
/// selection is permanent and the schedule never runs.
enum DailyHighlightQuoteRotation {
    /// A user's explicit quote pick, stamped with the tick it was made in.
    struct ManualSelection: Equatable {
        let index: Int
        let tick: Int
    }

    /// Which interval-sized slot `now` falls in since the reference date.
    static func tick(at now: Date, interval: TimeInterval) -> Int {
        Int(now.timeIntervalSinceReferenceDate / interval)
    }

    /// Whether a manual pick still overrides the schedule at `currentTick`.
    static func manualSelectionIsActive(
        _ selection: ManualSelection?,
        autoRotates: Bool,
        currentTick: Int
    ) -> Bool {
        guard let selection else { return false }
        guard autoRotates else { return true }
        return currentTick <= selection.tick + 1
    }

    /// The quote index to show.
    static func displayedIndex(
        quoteCount: Int,
        autoRotates: Bool,
        manualSelection: ManualSelection?,
        currentTick: Int
    ) -> Int {
        guard quoteCount > 0 else { return 0 }
        if manualSelectionIsActive(manualSelection, autoRotates: autoRotates, currentTick: currentTick),
           let manualSelection {
            return positiveModulo(manualSelection.index, quoteCount)
        }
        guard autoRotates else { return 0 }
        return positiveModulo(currentTick, quoteCount)
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
