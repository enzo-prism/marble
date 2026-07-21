import XCTest
@testable import marble

/// Pins the one-time legacy-defaults migration into the App Group suite.
/// Every case drives throwaway suites — `.standard` is never mutated, because
/// a test that dirtied it would leak into the simulator and into every other
/// test in the run.
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
        XCTAssertEqual(SharedDefaults.suiteName, "group.Prism.marble")
        XCTAssertEqual(WeeklyGoalReminder.enabledDefaultsKey, "weeklyGoalReminderEnabled")
    }

    func testSuiteIsStableAndNonNil() {
        // Falls back to `.standard` when the group container is unavailable,
        // so this must never be nil and must never change identity mid-run.
        XCTAssertTrue(SharedDefaults.suite === SharedDefaults.suite)
    }
}
