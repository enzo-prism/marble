import Foundation

/// Pure tenths-of-a-second arithmetic and formatting for sprint timing.
///
/// **Tenths are canonical for sprint times.** Sprint progress at 60–200 m lives
/// in fractions of a second, and Marble's shipped `durationSeconds: Int` cannot
/// carry them. Every precise sprint duration and target in the app is an
/// integer count of tenths (14.8 s == 148) so comparisons are exact — the same
/// "one canonical integer unit" rule that keeps `BodyMetricEntry` in kilograms
/// and weight comparisons in `PersonalRecords.kilograms`. Doubles appear only
/// at the UI seam (parsing a typed "14.8", measuring a stopwatch interval).
///
/// `nonisolated`: pure value math, used from SwiftData model accessors and
/// background evaluation as well as main-actor UI (see the note on
/// `BodyMetricSource` for why this matters under default MainActor isolation).
nonisolated enum SprintTiming {
    /// Longest sprint time the UI accepts: 30 minutes covers any interval work
    /// while rejecting garbage that would wreck chart domains (same guard idea
    /// as `BodyMetricEntry.plausibleKilograms`).
    static let maxTenths = 30 * 60 * 10

    /// Converts wall-clock seconds (stopwatch interval, typed decimal) to
    /// canonical tenths, rounding to nearest.
    static func tenths(fromSeconds seconds: Double) -> Int {
        Int((seconds * 10).rounded())
    }

    /// Canonical tenths for a legacy whole-second duration.
    static func tenths(fromWholeSeconds seconds: Int) -> Int {
        seconds * 10
    }

    /// The whole-second value stored alongside tenths in the shipped
    /// `SetEntry.durationSeconds` column, rounded to nearest so legacy
    /// consumers (widgets, analytics, backups read by older builds) see the
    /// closest representable time.
    static func wholeSeconds(fromTenths tenths: Int) -> Int {
        Int((Double(tenths) / 10).rounded())
    }

    static func seconds(fromTenths tenths: Int) -> Double {
        Double(tenths) / 10
    }

    /// Whether a tenths value is a plausible sprint time.
    static func isPlausible(tenths: Int) -> Bool {
        tenths > 0 && tenths <= maxTenths
    }

    /// "14.8s" under a minute, "1:02.4" from a minute up — the sprint-facing
    /// counterpart of `DateHelper.formattedClockDuration`. Whole tenths always
    /// render one decimal place so times align in monospaced columns and a
    /// 15.0 s rep is visibly distinct from a legacy 15 s one.
    static func text(tenths: Int) -> String {
        let totalSeconds = tenths / 10
        let fraction = abs(tenths % 10)
        if totalSeconds < 60 {
            return "\(totalSeconds).\(fraction)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }

    /// Compact delta ("0.4 seconds", "1 second", "2.5 seconds") for
    /// evaluation reasons.
    static func deltaText(tenths: Int) -> String {
        let value = abs(tenths)
        if value == 10 { return "1 second" }
        if value % 10 == 0 { return "\(value / 10) seconds" }
        return "\(value / 10).\(value % 10) seconds"
    }

    /// Parses user-typed decimal seconds ("14.8", "14,8", "15") into tenths.
    /// Returns nil for empty/garbage/implausible input.
    static func tenths(fromInput input: String) -> Int? {
        let normalized = input
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(normalized), seconds > 0 else { return nil }
        let tenths = Self.tenths(fromSeconds: seconds)
        return isPlausible(tenths: tenths) ? tenths : nil
    }

    /// The editable-field representation of a tenths value: "14.8", "15"
    /// (whole seconds drop the ".0" so typing feels natural).
    static func inputText(fromTenths tenths: Int) -> String {
        if tenths % 10 == 0 { return "\(tenths / 10)" }
        return "\(tenths / 10).\(tenths % 10)"
    }
}
