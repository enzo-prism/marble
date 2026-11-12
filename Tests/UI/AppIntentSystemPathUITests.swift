#if canImport(AppIntentsTesting)
import AppIntentsTesting
import XCTest

/// Runs in the UI-test process and invokes the installed app through Apple's
/// App Intents stack. No @testable import or shared model container.
@available(iOS 27.0, *)
@MainActor
final class AppIntentSystemPathUITests: MarbleUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MARBLE_SYSTEM_INTENTS"] == "1",
            "System-path tests require a development-signed device with Apple's App Intents testing service. Set MARBLE_SYSTEM_INTENTS=1 to run; simulator 27.0 rejects it as a Customer build.")
    }
    private var definitions: IntentDefinitions {
        // The UI launcher and system invocation share one explicit identifier.
        // A physical run can never fall back to the public app's bundle.
        IntentDefinitions(bundleIdentifier: Self.targetBundleIdentifier)
    }

    private func prepare() async throws -> [String: String] {
        #if !targetEnvironment(simulator)
        guard Self.targetBundleIdentifier == "Prism.marble.validation" else {
            XCTFail("Physical mutation tests must target Marble Validation.")
            throw NSError(domain: "MarbleTestTarget", code: 1)
        }
        #endif
        let result = try await definitions.intents["PrepareWorkoutIntentTests"].makeIntent().run()
        let value: String = try result.value
        return try JSONDecoder().decode([String: String].self, from: Data(value.utf8))
    }

    func testSystemLogRepeatFinishAndTypedQuery() async throws {
        launchApp(fixtureMode: "empty")
        let fixture = try await prepare()
        let started = try await definitions.intents["StartWorkoutIntent"].makeIntent().run()
        let session: AnyAppEntity = try started.value
        let originalCount: Int = try session.setCount

        let id = try XCTUnwrap(fixture["bench"].flatMap(UUID.init(uuidString:)))
        let exercises = try await definitions.entities["ExerciseEntity"].entities(identifiers: [id])
        let bench = try XCTUnwrap(exercises.first)
        let result = try await definitions.intents["LogSetIntent"].makeIntent(
            exercise: bench, reps: 5, weight: 185.0, unit: "lb"
        ).run()
        let set: AnyAppEntity = try result.value
        let summary: String = try set.summary
        XCTAssertTrue(summary.contains("185"))
        XCTAssertTrue(summary.contains("5"))

        let repeated = try await definitions.intents["LogLastSetAgainIntent"].makeIntent().run()
        let repeatedSet: AnyAppEntity = try repeated.value
        XCTAssertNotEqual(repeatedSet.identifier, set.identifier)

        let finished = try await definitions.intents["FinishWorkoutIntent"].makeIntent().run()
        let workout: AnyAppEntity = try finished.value
        let count: Int = try workout.setCount
        XCTAssertEqual(count, originalCount + 2)
        XCTAssertEqual(workout.identifier, session.identifier)

        let queried = try await definitions.entities["WorkoutSessionEntity"].suggestedEntities()
        XCTAssertTrue(queried.contains { $0.identifier.instanceIdentifier == workout.identifier.instanceIdentifier },
            "Expected \(workout.identifier); received \(queried.map(\.identifier))")
    }

    func testSystemTimedSetKeepsTenths() async throws {
        launchApp(fixtureMode: "empty")
        let fixture = try await prepare()
        let id = try XCTUnwrap(fixture["sprint"].flatMap(UUID.init(uuidString:)))
        let exercises = try await definitions.entities["ExerciseEntity"].entities(identifiers: [id])
        let sprint = try XCTUnwrap(exercises.first)
        let result = try await definitions.intents["LogSetIntent"].makeIntent(
            exercise: sprint, distance: 50.0, distanceUnit: "meters", durationSeconds: 7.4
        ).run()
        let logged: AnyAppEntity = try result.value
        let summary: String = try logged.summary
        XCTAssertTrue(summary.contains("7.4s"), summary)
    }
}
#endif
