import Security
import XCTest
@testable import marble

/// Pins the one-time legacy-defaults migration. Every case drives throwaway
/// suites — `.standard` is never mutated, because a test that dirtied it would
/// leak into the simulator and into every other test in the run.
///
/// `@MainActor` because the app target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so app enums like
/// `WeeklyGoalReminder` are main-actor isolated.
@MainActor
final class SharedDefaultsTests: XCTestCase {
    private var legacyName = ""
    private var suiteName = ""
    private var legacy: UserDefaults!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        legacyName = "marble.tests.legacy.\(UUID().uuidString)"
        suiteName = "marble.tests.suite.\(UUID().uuidString)"
        legacy = UserDefaults(suiteName: legacyName)
        suite = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(legacy)
        XCTAssertNotNil(suite)
    }

    override func tearDown() {
        legacy?.removePersistentDomain(forName: legacyName)
        suite?.removePersistentDomain(forName: suiteName)
        legacy = nil
        suite = nil
        super.tearDown()
    }

    func testMigrationCopiesLegacyValues() {
        legacy.set(5, forKey: SharedDefaults.Key.weeklySessionTarget)
        legacy.set(false, forKey: SharedDefaults.Key.weeklyGoalReminderEnabled)

        SharedDefaults.migrate(from: legacy, to: suite)

        XCTAssertEqual(suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int, 5)
        XCTAssertEqual(suite.object(forKey: SharedDefaults.Key.weeklyGoalReminderEnabled) as? Bool, false)
        XCTAssertTrue(suite.bool(forKey: SharedDefaults.Key.didMigrateV1))
    }

    func testMigrationSkipsKeysAbsentFromLegacy() {
        legacy.set(4, forKey: SharedDefaults.Key.weeklySessionTarget)

        SharedDefaults.migrate(from: legacy, to: suite)

        XCTAssertEqual(suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int, 4)
        // Never invents a value for a key the user never set.
        XCTAssertNil(suite.object(forKey: SharedDefaults.Key.weeklyGoalReminderEnabled))
    }

    func testMigrationDoesNotClobberExistingSuiteValue() {
        legacy.set(2, forKey: SharedDefaults.Key.weeklySessionTarget)
        suite.set(6, forKey: SharedDefaults.Key.weeklySessionTarget)

        SharedDefaults.migrate(from: legacy, to: suite)

        XCTAssertEqual(suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int, 6)
    }

    func testMigrationIsIdempotent() {
        legacy.set(3, forKey: SharedDefaults.Key.weeklySessionTarget)
        SharedDefaults.migrate(from: legacy, to: suite)

        // The user then changes the target in the app, and the stale legacy
        // value is still sitting in `.standard`. A second run must not undo it.
        suite.set(7, forKey: SharedDefaults.Key.weeklySessionTarget)
        SharedDefaults.migrate(from: legacy, to: suite)

        XCTAssertEqual(suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int, 7)
    }

    func testMigrationStampsFlagEvenWithNothingToCopy() {
        SharedDefaults.migrate(from: legacy, to: suite)

        XCTAssertTrue(suite.bool(forKey: SharedDefaults.Key.didMigrateV1))
        XCTAssertNil(suite.object(forKey: SharedDefaults.Key.weeklySessionTarget))
    }

    func testKeysKeepTheirLegacyLiterals() {
        // These strings are load-bearing: change one and existing users
        // silently lose their setting.
        XCTAssertEqual(SharedDefaults.Key.weeklySessionTarget, "weeklySessionTarget")
        XCTAssertEqual(SharedDefaults.Key.weeklyGoalReminderEnabled, "weeklyGoalReminderEnabled")
        XCTAssertEqual(SharedDefaults.Key.preferredWeightUnit, "preferredWeightUnit")
        XCTAssertEqual(SharedDefaults.Key.didCompleteOnboarding, "didCompleteOnboarding")
        XCTAssertEqual(SharedDefaults.Key.didBeginOnboarding, "didBeginOnboarding")
        XCTAssertEqual(WeeklyGoalReminder.enabledDefaultsKey, "weeklyGoalReminderEnabled")
    }

    func testSuiteIsStandardAndStable() {
        // The App Group is gone: these preferences are per-process by design
        // (see `SharedDefaults.suite`). Must never be nil and must never
        // change identity mid-run.
        XCTAssertTrue(SharedDefaults.suite === UserDefaults.standard)
        XCTAssertTrue(SharedDefaults.suite === SharedDefaults.suite)
    }

    func testMigrateLeavesValuesAloneWhenBothSidesAreTheSameStore() {
        // This is the shape `migrateIfNeeded()` now always has: `suite` *is*
        // `.standard`, so there is nowhere to copy from and nothing to copy —
        // it only stamps the flag. Driven on a throwaway suite so `.standard`
        // stays clean.
        suite.set(9, forKey: SharedDefaults.Key.weeklySessionTarget)

        SharedDefaults.migrate(from: suite, to: suite)

        XCTAssertEqual(suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int, 9)
        XCTAssertTrue(suite.bool(forKey: SharedDefaults.Key.didMigrateV1))
    }
}

// MARK: - SharedKeychain

/// Pins the *pure* half of `SharedKeychain`: the literals and the query
/// dictionaries it hands to `SecItem*`.
///
/// **No case here calls `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/
/// `SecItemDelete`.** A unit test must never read or write the real login
/// keychain — it would prompt, leak between runs, and fail differently on CI
/// than on a developer machine. The thin `saveSnapshot`/`loadSnapshot`/
/// `removeSnapshot` wrappers are deliberately left untested; everything they
/// could get wrong lives in the dictionaries below.
final class SharedKeychainQueryTests: XCTestCase {
    func testAccessGroupMatchesTheEntitlement() {
        // `marble.entitlements` and `MarbleWidgets.entitlements` both declare
        // `$(AppIdentifierPrefix)Prism.marble.shared`. `$(AppIdentifierPrefix)`
        // is a build-time expansion Swift cannot see, so the team prefix is
        // hardcoded — change one, change all three.
        XCTAssertEqual(SharedKeychain.accessGroup, "L49MKXGVM4.Prism.marble.shared")
        XCTAssertTrue(SharedKeychain.accessGroup.hasSuffix("Prism.marble.shared"))
        XCTAssertTrue(SharedKeychain.accessGroup.hasPrefix("L49MKXGVM4."))
    }

    func testAccessibilitySurvivesALockedScreen() {
        // Load-bearing: Lock Screen widget families render while locked, so
        // `WhenUnlocked` would blank the accessory widgets. `ThisDeviceOnly`
        // keeps this regenerable cache out of iCloud Keychain sync.
        XCTAssertEqual(
            SharedKeychain.accessibility as String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertNotEqual(
            SharedKeychain.accessibility as String,
            kSecAttrAccessibleWhenUnlocked as String
        )
    }

    func testIdentityQueryNamesExactlyOneItem() {
        let query = SharedKeychain.identityQuery()

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "marble.widget.weeklyGoalSnapshot")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, SharedKeychain.account)
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, SharedKeychain.accessGroup)
        // Identity only — a value here would break `SecItemUpdate`'s query half.
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecReturnData as String])
    }

    func testLoadQueryAsksForOneItemsBytes() {
        let query = SharedKeychain.loadQuery()

        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
        // Still scoped to the one item.
        XCTAssertEqual(query[kSecAttrService as String] as? String, SharedKeychain.service)
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, SharedKeychain.accessGroup)
    }

    func testAddQueryCarriesTheValueAndAccessibility() {
        let payload = Data("snapshot".utf8)
        let query = SharedKeychain.addQuery(data: payload)

        XCTAssertEqual(query[kSecValueData as String] as? Data, payload)
        XCTAssertEqual(
            query[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, SharedKeychain.accessGroup)
    }

    func testUpdateAttributesCarryNoIdentityAttributes() {
        let payload = Data("snapshot".utf8)
        let attributes = SharedKeychain.updateAttributes(data: payload)

        XCTAssertEqual(attributes[kSecValueData as String] as? Data, payload)
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        // `SecItemUpdate`'s changes half must describe only what changes.
        XCTAssertNil(attributes[kSecClass as String])
        XCTAssertNil(attributes[kSecAttrService as String])
        XCTAssertNil(attributes[kSecAttrAccount as String])
        XCTAssertNil(attributes[kSecAttrAccessGroup as String])
    }

    func testQueriesAreStableAcrossCalls() {
        // The upsert issues `SecItemUpdate` then `SecItemDelete`/`SecItemAdd`
        // against separately built dictionaries — if they ever disagreed about
        // identity, a repeated publish would accumulate duplicate items.
        let first = SharedKeychain.identityQuery()
        let second = SharedKeychain.identityQuery()
        let fromAdd = SharedKeychain.addQuery(data: Data([0x01]))

        for key in [kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrAccessGroup] {
            let name = key as String
            XCTAssertEqual(first[name] as? String, second[name] as? String)
            XCTAssertEqual(first[name] as? String, fromAdd[name] as? String)
        }
    }
}
