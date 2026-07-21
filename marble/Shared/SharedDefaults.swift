import Foundation

/// The one `UserDefaults` surface shared by the app and the `MarbleWidgets`
/// extension.
///
/// This file is compiled into BOTH targets, so it imports Foundation only and
/// must never reference an app type. It is `nonisolated` because the target's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin these
/// statics to the main actor — and a `TimelineProvider` reads them off it.
nonisolated enum SharedDefaults {
    static let suiteName = "group.Prism.marble"

    /// The App Group suite when it is available, `.standard` otherwise.
    ///
    /// `UserDefaults(suiteName:)` returns nil whenever the process can't see
    /// the group (missing entitlement, unsigned test host, a simulator whose
    /// group container was never created). Falling back keeps every call site
    /// working — the app simply degrades to per-process defaults and the
    /// widget shows its neutral placeholder instead of crashing.
    static var suite: UserDefaults { resolvedSuite }

    private static let resolvedSuite: UserDefaults =
        UserDefaults(suiteName: suiteName) ?? .standard

    enum Key {
        static let weeklySessionTarget = "weeklySessionTarget"
        static let weeklyGoalReminderEnabled = "weeklyGoalReminderEnabled"
        static let preferredWeightUnit = "preferredWeightUnit"
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let weeklyGoalSnapshot = "marble.widget.weeklyGoalSnapshot"
        static let didMigrateV1 = "didMigrateSharedDefaultsV1"
    }

    /// Keys that shipped in `.standard` before the App Group existed. Only
    /// these move; everything written from 2.2 on is born in the suite.
    static let legacyKeys = [Key.weeklySessionTarget, Key.weeklyGoalReminderEnabled]

    /// One-time copy of the legacy keys out of `.standard`. Idempotent and
    /// cheap enough to call on every launch. Call it before anything reads
    /// the suite (see ContentView wiring).
    static func migrateIfNeeded() {
        let target = resolvedSuite
        // No real group container: the suite *is* `.standard`, so the values
        // are already where they need to be. Still stamp the flag so a later
        // launch that does get the group doesn't copy stale values back.
        guard target !== UserDefaults.standard else {
            target.set(true, forKey: Key.didMigrateV1)
            return
        }
        migrate(from: .standard, to: target)
    }

    /// Injectable core of `migrateIfNeeded()` so tests can drive throwaway
    /// suites instead of mutating `.standard`.
    static func migrate(from legacy: UserDefaults, to target: UserDefaults) {
        guard !target.bool(forKey: Key.didMigrateV1) else { return }
        for key in legacyKeys {
            // Never clobber a value the suite already holds — the suite is
            // the newer source of truth the moment it has an opinion.
            guard target.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key) else { continue }
            target.set(value, forKey: key)
        }
        target.set(true, forKey: Key.didMigrateV1)
    }
}
