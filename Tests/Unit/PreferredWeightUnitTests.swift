import XCTest
@testable import marble

/// Weight units are this repo's most expensive recurring bug class (four
/// production bugs), so the precedence rule for a new set's unit is pinned
/// rather than left implicit in the view.
///
/// The rule: the exercise's last logged unit always wins, the stored preference
/// is the fallback, and `.lb` is the last resort so nothing changes for users
/// who never expressed a preference.
final class PreferredWeightUnitTests: XCTestCase {
    /// Someone who upgraded without onboarding, logging an exercise for the
    /// first time: unchanged 2.1 behaviour.
    func testNoPreferenceAndNoPriorEntryFallsBackToPounds() {
        XCTAssertEqual(
            AddSetView.initialWeightUnit(preference: nil, lastEntryUnit: nil),
            .lb
        )
    }

    func testPreferenceIsUsedWhenThereIsNoPriorEntry() {
        XCTAssertEqual(
            AddSetView.initialWeightUnit(preference: .kg, lastEntryUnit: nil),
            .kg
        )
    }

    /// The per-exercise override that already shipped: a prior entry in pounds
    /// beats a kilogram preference, because the last thing you actually logged
    /// for this movement is the stronger signal.
    func testPriorEntryBeatsThePreference() {
        XCTAssertEqual(
            AddSetView.initialWeightUnit(preference: .kg, lastEntryUnit: .lb),
            .lb
        )
    }

    func testPriorEntryBeatsThePreferenceInTheOtherDirection() {
        XCTAssertEqual(
            AddSetView.initialWeightUnit(preference: .lb, lastEntryUnit: .kg),
            .kg
        )
    }

    /// No preference at all still defers to history rather than to `.lb`.
    func testPriorEntryWinsWithoutAnyPreference() {
        XCTAssertEqual(
            AddSetView.initialWeightUnit(preference: nil, lastEntryUnit: .kg),
            .kg
        )
    }

    /// The preference is persisted as a `WeightUnit` raw value; anything else on
    /// disk must decode to `nil` so the caller falls back instead of crashing.
    func testStoredRawValuesRoundTrip() {
        XCTAssertEqual(WeightUnit(rawValue: "lb"), .lb)
        XCTAssertEqual(WeightUnit(rawValue: "kg"), .kg)
        XCTAssertNil(WeightUnit(rawValue: "pounds"))
        XCTAssertNil(WeightUnit(rawValue: ""))
    }

    /// Guards the key the picker in onboarding and Settings both write.
    func testPreferenceKeyIsStable() {
        XCTAssertEqual(SharedDefaults.Key.preferredWeightUnit, "preferredWeightUnit")
    }
}
