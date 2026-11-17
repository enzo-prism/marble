import AppIntents
import Foundation
import SwiftData
import XCTest
@testable import marble

/// The interactive logged-set card's buttons write real rows. These assert against
/// the store: every button must edit exactly the set it was rendered for.
@MainActor
final class LoggedSetSnippetTests: MarbleTestCase {
    private static let suiteName = "LoggedSetSnippetTests"

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            UserDefaults().removePersistentDomain(forName: Self.suiteName)
            LoggedSetSnippetChains.defaults = UserDefaults(suiteName: Self.suiteName)!
            WeeklyGoalWidgetPublisher.deliver = { _ in }
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppIntentsSupport.container = nil
            RestActivityController.shared.cancelRest()
            LoggedSetSnippetChains.defaults = .standard
            UserDefaults().removePersistentDomain(forName: Self.suiteName)
            WeeklyGoalWidgetPublisher.deliver = WeeklyGoalWidgetPublisher.defaultDeliver
        }
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeContext() -> ModelContext {
        let container = makeInMemoryContainer()
        AppIntentsSupport.register(container: container)
        return container.mainContext
    }

    private func exercise(_ name: String, metrics: ExerciseMetricsProfile = .weightAndRepsRequired,
                          style: ResistanceTrackingStyle = .totalLoad, in context: ModelContext) -> Exercise {
        let value = Exercise(name: name, category: .chest, resistanceTrackingStyle: style, metrics: metrics,
                             defaultRestSeconds: 90, createdAt: now)
        context.insert(value)
        try? context.save()
        return value
    }

    private func log(_ exercise: Exercise, weight: Double? = nil, unit: WeightUnit? = nil, reps: Int? = nil,
                     distance: Double? = nil, duration: Double? = nil) async throws -> SetEntry {
        let outcome = try await WorkoutCommands.log(.init(
            exerciseID: exercise.id, exerciseName: exercise.name, reps: reps, weight: weight, unit: unit,
            distance: distance, distanceUnit: distance == nil ? nil : .meters, durationSeconds: duration))
        return try XCTUnwrap(outcome.entry, outcome.message)
    }

    private func entry(_ id: UUID, in context: ModelContext) -> SetEntry? {
        try? context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Weight and reps

    func testAddWeightAddsFivePoundsToExactlyThatSet() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let first = try await log(bench, weight: 185, unit: .lb, reps: 5)
        let second = try await log(bench, weight: 185, unit: .lb, reps: 5)

        _ = try await AddWeightToLoggedSetIntent(setID: first.id).perform()

        XCTAssertEqual(entry(first.id, in: context)?.weight, 190)
        XCTAssertEqual(entry(first.id, in: context)?.weightUnit, .lb)
        XCTAssertEqual(entry(first.id, in: context)?.reps, 5)
        XCTAssertEqual(entry(second.id, in: context)?.weight, 185, "Only the card's set may change.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 2)
    }

    func testAddWeightUsesTwoAndAHalfKilogramsForKilogramSets() async throws {
        let context = makeContext()
        let squat = exercise("Back Squat", in: context)
        let set = try await log(squat, weight: 100, unit: .kg, reps: 3)

        _ = try await AddWeightToLoggedSetIntent(setID: set.id).perform()

        XCTAssertEqual(try XCTUnwrap(entry(set.id, in: context)?.weight), 102.5, accuracy: 0.0001)
        XCTAssertEqual(entry(set.id, in: context)?.weightUnit, .kg, "The set's unit is never relabelled.")
    }

    func testAddWeightOnDumbbellPairStepsOneDumbbell() async throws {
        let context = makeContext()
        let curl = exercise("Dumbbell Curl", style: .singleDumbbellPair, in: context)
        let set = try await log(curl, weight: 40, unit: .lb, reps: 10)
        XCTAssertEqual(set.weight, 80)

        _ = try await AddWeightToLoggedSetIntent(setID: set.id).perform()

        XCTAssertEqual(entry(set.id, in: context)?.weight, 90, "45 lb each is 90 lb total.")
    }

    func testAddRepAddsOneRep() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let set = try await log(bench, weight: 135, unit: .lb, reps: 8)

        _ = try await AddRepToLoggedSetIntent(setID: set.id).perform()

        XCTAssertEqual(entry(set.id, in: context)?.reps, 9)
        XCTAssertEqual(entry(set.id, in: context)?.weight, 135)
    }

    func testWeightButtonIsRefusedAndHiddenForRepsOnlyExercise() async throws {
        let context = makeContext()
        let pullUps = exercise("Pull-Up", metrics: .repsOnlyRequired, in: context)
        let set = try await log(pullUps, reps: 10)

        do {
            _ = try await AddWeightToLoggedSetIntent(setID: set.id).perform()
            XCTFail("A reps-only exercise must not gain a weight")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertNil(entry(set.id, in: context)?.weight)

        let details = try XCTUnwrap(LoggedSetSnippetCard.load(chainID: set.id, in: context).details)
        XCTAssertNil(details.weightStep)
        XCTAssertTrue(details.showsAddRep)
        XCTAssertEqual(details.valueText, "10 reps")
    }

    func testSprintCardHidesWeightAndRepButtonsAndKeepsTenths() async throws {
        let context = makeContext()
        let sprint = exercise("Sprint", metrics: .distanceAndDurationRequired, in: context)
        let set = try await log(sprint, distance: 50, duration: 7.4)

        let details = try XCTUnwrap(LoggedSetSnippetCard.load(chainID: set.id, in: context).details)
        XCTAssertNil(details.weightStep)
        XCTAssertFalse(details.showsAddRep)
        XCTAssertTrue(details.valueText.contains("50 m"), details.valueText)
        XCTAssertTrue(details.valueText.contains("7.4s"), details.valueText)
    }

    // MARK: - Same again and Undo

    func testSameAgainLogsAnIdenticalSetAndTheCardFollowsIt() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let session = try XCTUnwrap(WorkoutCommands.start(in: context))
        let set = try await log(bench, weight: 185, unit: .lb, reps: 5)

        _ = try await RepeatLoggedSetIntent(cardID: set.id, setID: set.id).perform()

        let all = try context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(all.count, 2)
        let duplicate = try XCTUnwrap(all.first { $0.id != set.id })
        XCTAssertEqual(duplicate.weight, 185)
        XCTAssertEqual(duplicate.reps, 5)
        XCTAssertEqual(duplicate.weightUnit, .lb)
        XCTAssertTrue(session.entries.contains { $0.id == duplicate.id }, "The repeat joins the running workout.")

        let details = try XCTUnwrap(LoggedSetSnippetCard.load(chainID: set.id, in: context).details)
        XCTAssertEqual(details.setID, duplicate.id)
        XCTAssertEqual(details.loggedCount, 2)
    }

    func testUndoDeletesExactlyTheCardsSetAndNeverTheLatest() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let set = try await log(bench, weight: 185, unit: .lb, reps: 5)
        // A later set logged elsewhere is the "latest" — Undo must not touch it.
        let later = try await log(bench, weight: 205, unit: .lb, reps: 3)

        _ = try await UndoLoggedSetIntent(cardID: set.id, setID: set.id).perform()

        XCTAssertNil(entry(set.id, in: context))
        XCTAssertNotNil(entry(later.id, in: context))
        XCTAssertNil(LoggedSetSnippetCard.load(chainID: set.id, in: context).details, "The card shows the removed state.")
    }

    func testUndoAfterSameAgainRemovesTheRepeatAndReturnsToTheOriginal() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let set = try await log(bench, weight: 185, unit: .lb, reps: 5)
        _ = try await RepeatLoggedSetIntent(cardID: set.id, setID: set.id).perform()
        let repeated = try XCTUnwrap(LoggedSetSnippetCard.load(chainID: set.id, in: context).details?.setID)
        XCTAssertNotEqual(repeated, set.id)

        _ = try await UndoLoggedSetIntent(cardID: set.id, setID: repeated).perform()

        XCTAssertNil(entry(repeated, in: context))
        XCTAssertNotNil(entry(set.id, in: context))
        let details = try XCTUnwrap(LoggedSetSnippetCard.load(chainID: set.id, in: context).details)
        XCTAssertEqual(details.setID, set.id)
        XCTAssertEqual(details.loggedCount, 1)
    }

    func testUndoRemovesSprintCompanionRows() async throws {
        let context = makeContext()
        let sprint = exercise("Sprint", metrics: .distanceAndDurationRequired, in: context)
        let set = try await log(sprint, distance: 50, duration: 7.4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintRepDetail>()), 1)

        _ = try await UndoLoggedSetIntent(cardID: set.id, setID: set.id).perform()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintRepDetail>()), 0)
    }

    func testUndoOfAnAlreadyRemovedSetTouchesNothingElse() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let kept = try await log(bench, weight: 185, unit: .lb, reps: 5)
        let missing = UUID()

        _ = try await UndoLoggedSetIntent(cardID: missing, setID: missing).perform()

        XCTAssertNotNil(entry(kept.id, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 1)
    }

    func testEditsOfAMissingSetFailWithoutWriting() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let kept = try await log(bench, weight: 185, unit: .lb, reps: 5)

        do {
            _ = try await AddRepToLoggedSetIntent(setID: UUID()).perform()
            XCTFail("A missing set must not resolve to another set")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(entry(kept.id, in: context)?.reps, 5)
    }

    // MARK: - Card content

    func testCardShowsTheLoggedValuesAndAPersonalRecordHint() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        _ = try await log(bench, weight: 185, unit: .lb, reps: 5)
        let heavier = try await log(bench, weight: 205, unit: .lb, reps: 5)

        let details = try XCTUnwrap(LoggedSetSnippetCard.load(chainID: heavier.id, in: context).details)
        XCTAssertEqual(details.exerciseName, "Bench Press")
        XCTAssertEqual(details.valueText, "205 lb × 5")
        XCTAssertEqual(details.valueAccessibilityLabel, "205 lb, 5 reps")
        XCTAssertNotNil(details.personalRecord)
        XCTAssertEqual(details.weightStep?.title, "+5 lb")
        XCTAssertTrue(details.showsAddRep)
    }

    func testValueTextKeepsUnitsAndDumbbellWording() {
        XCTAssertEqual(LoggedSetSnippetCard.valueText(usesWeight: true, inputWeight: 40, unit: .lb, perDumbbell: true,
                                                      reps: 10, distance: nil, duration: nil).text, "40 lb each × 10")
        XCTAssertEqual(LoggedSetSnippetCard.valueText(usesWeight: true, inputWeight: 102.5, unit: .kg, perDumbbell: false,
                                                      reps: nil, distance: nil, duration: nil).text, "102.5 kg")
        XCTAssertEqual(LoggedSetSnippetCard.valueText(usesWeight: false, inputWeight: nil, unit: .lb, perDumbbell: false,
                                                      reps: 1, distance: nil, duration: nil).text, "1 rep")
        XCTAssertEqual(LoggedSetSnippetCard.weightStep(unit: .kg, perDumbbell: true).title, "+2.5 kg each")
    }

    func testCardFromAnIntentResultUsesTheLoggedSetID() async throws {
        let context = makeContext()
        let bench = exercise("Bench Press", in: context)
        let intent = LogSetIntent()
        intent.exercise = ExerciseEntity(bench)
        intent.reps = 5
        intent.weight = 100
        intent.unit = .kg
        _ = try await intent.perform()
        let logged = try XCTUnwrap(try context.fetch(FetchDescriptor<SetEntry>()).first)

        let snippet = LoggedSetSnippetIntent(setID: logged.id)
        XCTAssertEqual(snippet.setID, logged.id.uuidString)
        XCTAssertEqual(LoggedSetSnippetCard.load(chainID: logged.id, in: context).details?.valueText, "100 kg × 5")
    }

    func testChainStoreIsBoundedAndKeepsCardsSeparate() {
        let first = UUID(), second = UUID(), added = UUID()
        LoggedSetSnippetChains.append(added, toChain: first)
        XCTAssertEqual(LoggedSetSnippetChains.chain(for: first), [first, added])
        XCTAssertEqual(LoggedSetSnippetChains.chain(for: second), [second])
        LoggedSetSnippetChains.remove(first, fromChain: first)
        XCTAssertEqual(LoggedSetSnippetChains.chain(for: first), [added])

        for _ in 0..<(LoggedSetSnippetChains.maximumChains + 4) {
            LoggedSetSnippetChains.append(UUID(), toChain: UUID())
        }
        let stored = LoggedSetSnippetChains.defaults.array(forKey: LoggedSetSnippetChains.storageKey) ?? []
        XCTAssertEqual(stored.count, LoggedSetSnippetChains.maximumChains)
        XCTAssertEqual(LoggedSetSnippetChains.chain(for: first), [first], "An evicted card falls back to its origin.")
    }
}
