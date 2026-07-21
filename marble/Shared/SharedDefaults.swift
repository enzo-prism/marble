import Foundation
import Security

/// The one `UserDefaults` surface shared by the app and the `MarbleWidgets`
/// extension.
///
/// This file is compiled into BOTH targets, so it imports Foundation (plus
/// `Security`, which is available to app extensions) only and must never
/// reference an app type. It is `nonisolated` because the target's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin these
/// statics to the main actor — and a `TimelineProvider` reads them off it.
nonisolated enum SharedDefaults {
    /// `UserDefaults.standard`, deliberately.
    ///
    /// 2.2 briefly routed these through an App Group suite
    /// (`group.Prism.marble`). That group never existed in the developer
    /// portal, cannot be created through the App Store Connect API, and its
    /// entitlement broke Release archiving outright. It was also never needed:
    /// **none of these preferences require cross-process sharing.** The widget
    /// extension reads exactly one thing — the weekly-goal snapshot — and that
    /// travels through `SharedKeychain` (a team-prefixed keychain access group,
    /// which the existing App Store profiles already grant). The weekly target
    /// the widget renders is baked into that snapshot by the publisher, so the
    /// extension never reads `weeklySessionTarget` itself.
    ///
    /// Do not "restore" the App Group without a concrete new requirement that
    /// the keychain snapshot genuinely cannot satisfy.
    static var suite: UserDefaults { resolvedSuite }

    private static let resolvedSuite: UserDefaults = .standard

    enum Key {
        static let weeklySessionTarget = "weeklySessionTarget"
        static let weeklyGoalReminderEnabled = "weeklyGoalReminderEnabled"
        static let preferredWeightUnit = "preferredWeightUnit"
        static let didCompleteOnboarding = "didCompleteOnboarding"
        /// Written the first time the onboarding flow is actually presented.
        /// Without it, a user who force-quits midway through onboarding is
        /// indistinguishable on the next launch from someone upgrading from
        /// 2.1 — both have `didSeedMarbleData` set and no completion flag —
        /// and the gate would skip them permanently. See `OnboardingGate`.
        static let didBeginOnboarding = "didBeginOnboarding"
        /// Retained for continuity only. The snapshot no longer lives in
        /// `UserDefaults` — `SharedKeychain.service` reuses this same string as
        /// its `kSecAttrService`. Nothing reads this key any more; the app may
        /// still hold a stale 2.2 blob under it, which is harmless.
        static let weeklyGoalSnapshot = "marble.widget.weeklyGoalSnapshot"
        static let didMigrateV1 = "didMigrateSharedDefaultsV1"
    }

    /// Keys that shipped in `.standard` before the (now removed) App Group.
    /// With `suite` back to `.standard` they are already home; the list stays
    /// so `migrate(from:to:)` keeps a single definition of "what moves".
    static let legacyKeys = [Key.weeklySessionTarget, Key.weeklyGoalReminderEnabled]

    /// One-time copy of the legacy keys out of `.standard`. Idempotent and
    /// cheap enough to call on every launch. Call it before anything reads
    /// the suite (see ContentView wiring).
    ///
    /// Now that `suite` *is* `.standard`, this only stamps the flag — the
    /// values were never anywhere else. Kept because call sites exist and
    /// because the injectable core below still pins the copy semantics.
    static func migrateIfNeeded() {
        let target = resolvedSuite
        // No separate container: the suite *is* `.standard`, so the values are
        // already where they need to be. Still stamp the flag so nothing later
        // mistakes an unmigrated-looking store for one that needs a copy.
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
            // Never clobber a value the target already holds — it is the newer
            // source of truth the moment it has an opinion.
            guard target.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key) else { continue }
            target.set(value, forKey: key)
        }
        target.set(true, forKey: Key.didMigrateV1)
    }
}

/// The app → widget transport for the weekly-goal snapshot: a generic-password
/// keychain item in a team-prefixed access group.
///
/// Why the keychain and not an App Group: both existing App Store provisioning
/// profiles already grant `keychain-access-groups = ["L49MKXGVM4.*",
/// "com.apple.token"]`, so this needs **no portal capability and no profile
/// regeneration**, whereas `group.Prism.marble` requires a portal App Group
/// that does not exist and cannot be created through the API.
///
/// Compiled into BOTH targets. Every `SecItem*` call fails silently — a
/// keychain error must never crash the app or the extension, and on the
/// **simulator** access groups are not enforced, so calls can return
/// `errSecMissingEntitlement`. The correct degraded behaviour is "no
/// snapshot", which the widget already renders as the neutral "Open Marble"
/// card.
nonisolated enum SharedKeychain {
    /// Must stay in sync with the `keychain-access-groups` entitlement in both
    /// `marble.entitlements` and `MarbleWidgets/MarbleWidgets.entitlements`,
    /// which spell it `$(AppIdentifierPrefix)Prism.marble.shared`.
    ///
    /// The team prefix is hardcoded here because `$(AppIdentifierPrefix)` is a
    /// build-time plist expansion — it is substituted into the entitlements
    /// file by the build system and is never visible to Swift source.
    static let accessGroup = "L49MKXGVM4.Prism.marble.shared"

    /// `kSecAttrService` — one service per shared payload.
    static let service = "marble.widget.weeklyGoalSnapshot"

    /// `kSecAttrAccount` — fixed, because there is exactly one snapshot.
    static let account = "current"

    /// **Load-bearing.** Lock Screen widget families (`accessoryCircular`,
    /// `accessoryRectangular`, `accessoryInline`) render while the device is
    /// locked, so `kSecAttrAccessibleWhenUnlocked` would make the widget read
    /// nothing on a locked screen. `…ThisDeviceOnly` additionally keeps this
    /// device-local app state out of iCloud Keychain sync — it is a cache of
    /// data the app can always regenerate, not a credential worth syncing.
    ///
    /// Computed rather than a stored `static let` so it never has to satisfy
    /// the `Sendable` requirement strict concurrency puts on global storage —
    /// `CFString` is imported from C and this target compiles with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    // MARK: - Pure query construction (unit-testable, touches no keychain)

    /// The attributes that *identify* the item. Never includes a value, so it
    /// is safe as the query half of both `SecItemUpdate` and `SecItemDelete`.
    static func identityQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    /// Identity plus "give me the bytes, at most one match".
    static func loadQuery() -> [String: Any] {
        var query = identityQuery()
        // A Swift `Bool`, not `kCFBooleanTrue`: the latter is imported as an
        // implicitly-unwrapped `CFBoolean!` and would box an Optional into the
        // `Any` value, which the CFDictionary bridge does not unwrap.
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    /// Identity plus value plus accessibility, for `SecItemAdd`.
    static func addQuery(data: Data) -> [String: Any] {
        var query = identityQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility
        return query
    }

    /// The *changes* half of `SecItemUpdate`. Identity attributes must not
    /// appear here — only what is being rewritten.
    static func updateAttributes(data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
    }

    // MARK: - Thin SecItem layer (never exercised by unit tests)

    /// Upsert. Tries an in-place update first and falls back to an add, so a
    /// repeated publish can never accumulate duplicate items.
    static func saveSnapshot(_ data: Data) {
        let status = SecItemUpdate(
            identityQuery() as CFDictionary,
            updateAttributes(data: data) as CFDictionary
        )
        guard status != errSecSuccess else { return }
        // Nothing to update (first publish), or the existing item is
        // unusable — replace it outright. Both calls are best-effort, and the
        // delete keeps the add from ever failing with `errSecDuplicateItem`.
        _ = SecItemDelete(identityQuery() as CFDictionary)
        _ = SecItemAdd(addQuery(data: data) as CFDictionary, nil)
    }

    /// The published bytes, or nil for *any* failure: no item, locked-out
    /// class, missing entitlement on the simulator, wrong result type.
    static func loadSnapshot() -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(loadQuery() as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Best-effort removal. A missing item is success as far as callers care.
    static func removeSnapshot() {
        _ = SecItemDelete(identityQuery() as CFDictionary)
    }
}
