import os

/// Instruments intervals contain counts only, never workout text or health data.
enum HistoryPerformance {
    static let signposter = OSSignposter(subsystem: "Prism.marble", category: "History")
}
