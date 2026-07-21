import SwiftUI
import TipKit

/// TipKit definitions for Marble's three least-discoverable features.
///
/// Each tip shows at most once and is invalidated the moment the user actually
/// uses the thing it points at — a tip that keeps reappearing after you've
/// already found the feature reads as nagging, which is the opposite of the
/// brand.
///
/// Attaching them to views is deliberately deferred to a later change (see the
/// integration notes); this file only defines them and owns configuration.

/// Points at the handwritten-workout scanner in the import hub. Nothing else in
/// the app hints that Marble can read a photo of a notebook page.
nonisolated struct ScanWorkoutTip: Tip {
    var title: Text {
        Text("Scan a handwritten workout")
    }

    var message: Text? {
        Text("Photograph a notebook page and Marble reads it on your device, then hands you sets to review.")
    }

    var image: Image? {
        Image(systemName: "text.viewfinder")
    }

    var options: [Option] {
        Tips.MaxDisplayCount(1)
    }
}

/// Points at the coaching cards on Trends. They look like read-only summaries,
/// so people miss that each one is tappable and explains its reasoning.
nonisolated struct CoachingCardsTip: Tip {
    var title: Text {
        Text("Coaching, from your own data")
    }

    var message: Text? {
        Text("These cards read your recent sessions and tell you what to push, hold, or back off.")
    }

    var image: Image? {
        Image(systemName: "lightbulb")
    }

    var options: [Option] {
        Tips.MaxDisplayCount(1)
    }
}

/// Points at the personal-record feed on Trends.
nonisolated struct PRFeedTip: Tip {
    var title: Text {
        Text("Every PR, in one place")
    }

    var message: Text? {
        Text("Marble spots personal records as you log them and collects them here.")
    }

    var image: Image? {
        Image(systemName: "trophy")
    }

    var options: [Option] {
        Tips.MaxDisplayCount(1)
    }
}

enum MarbleTips {
    /// Each tip is capped at one appearance by `MaxDisplayCount(1)`. The other
    /// half of the contract belongs to the call site: whichever control the tip
    /// points at must call `invalidate(reason: .actionPerformed)` on it, so a
    /// user who finds the feature on their own is never shown the tip at all.
    ///
    /// Configures the TipKit datastore. Call once, early in app launch.
    ///
    /// Returns immediately under UI testing: tips float above the content layer,
    /// so a popover appearing mid-flow would intercept taps in the 36 UI tests
    /// and register as an unexpected overlapping element in the accessibility
    /// audit.
    static func configure() {
        guard !TestHooks.isUITesting else { return }
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    /// Clears every recorded tip state. Debug affordance only — never called in
    /// a shipping path.
    static func resetAll() {
        try? Tips.resetDatastore()
    }
}
