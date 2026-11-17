import AppIntents
import Foundation
import SwiftData
import SwiftUI

// MARK: - Interactive logged-set snippet (iOS 26 SnippetIntent)
//
// Log a Set, Log Last Set Again and Correct Logged Set return this snippet next to
// their spoken dialog. Siri and Shortcuts show the card when there is a screen and
// fall back to the dialog in voice-only contexts. Each button is its own small
// intent that edits one set by its stable ID; when a button's intent finishes, the
// system performs the snippet intent again, so the card re-reads the store and
// re-renders with the updated values.

/// Which confirmed sets one snippet card presents, oldest first.
///
/// Every card gets its own random card ID, distinct from any set ID, so two cards
/// about the same set (say a log card and a later correction card) never share
/// state. A snippet intent's parameters are fixed when the card is first shown, but
/// "Same again" adds a new set that the card should then present (and that Undo
/// should remove first). This bounded list maps a card to the sets it presents. It
/// holds identifiers only — never workout values — and the card still resolves
/// every ID against the store, so a stale entry can only miss.
@MainActor
enum LoggedSetSnippetChains {
    static var defaults: UserDefaults = .standard
    static let storageKey = "marble.snippet.loggedSetCards"
    static let maximumChains = 16
    static let maximumChainLength = 50

    /// The sets `card` presents, oldest first. A card with no recorded history
    /// (new, or evicted) presents only the set it was created for.
    static func chain(forCard card: UUID, origin: UUID) -> [UUID] {
        let key = card.uuidString
        guard let record = stored().last(where: { $0.first == key }) else { return [origin] }
        return record.dropFirst().compactMap(UUID.init(uuidString:))
    }

    static func append(_ id: UUID, toCard card: UUID, origin: UUID) {
        save(chain(forCard: card, origin: origin).filter { $0 != id } + [id], for: card)
    }

    static func remove(_ id: UUID, fromCard card: UUID, origin: UUID) {
        save(chain(forCard: card, origin: origin).filter { $0 != id }, for: card)
    }

    /// Each record is `[card ID] + presented set IDs`; newest records last.
    private static func save(_ ids: [UUID], for card: UUID) {
        let key = card.uuidString
        var records = stored().filter { $0.first != key }
        records.append([key] + ids.suffix(maximumChainLength).map(\.uuidString))
        defaults.set(Array(records.suffix(maximumChains)), forKey: storageKey)
    }

    private static func stored() -> [[String]] {
        defaults.array(forKey: storageKey) as? [[String]] ?? []
    }
}

/// Everything the card shows, read from the store at render time.
struct LoggedSetSnippetCard: Equatable {
    struct WeightStep: Equatable {
        let title: String
        let accessibilityLabel: String
    }

    struct Details: Equatable {
        let setID: UUID
        let exerciseName: String
        let valueText: String
        let valueAccessibilityLabel: String
        let personalRecord: String?
        let personalRecordAccessibilityLabel: String?
        let weightStep: WeightStep?
        let showsAddRep: Bool
        /// Undo deletes the shown set, so it is offered only for sets this card's
        /// own action created — never for an existing set a correction card shows.
        let showsUndo: Bool
        let loggedCount: Int
    }

    let cardID: UUID
    /// The set the card was created for.
    let originSetID: UUID
    /// `true` when the card's action created its origin set (Log a Set, Log Last
    /// Set Again); `false` for a correction of an existing set.
    let allowsOriginUndo: Bool
    /// `nil` once every set this card presents has been undone or deleted.
    let details: Details?

    static func load(cardID: UUID, originSetID: UUID, allowsOriginUndo: Bool, in context: ModelContext) -> LoggedSetSnippetCard {
        let entries = LoggedSetSnippetChains.chain(forCard: cardID, origin: originSetID)
            .compactMap { WorkoutCommands.manualEntry(id: $0, in: context) }
        let details = entries.last.map { current in
            Self.details(for: current, loggedCount: entries.count,
                         showsUndo: current.id != originSetID || allowsOriginUndo, in: context)
        }
        return LoggedSetSnippetCard(cardID: cardID, originSetID: originSetID,
                                    allowsOriginUndo: allowsOriginUndo, details: details)
    }

    private static func details(for entry: SetEntry, loggedCount: Int, showsUndo: Bool, in context: ModelContext) -> Details {
        let exercise = entry.exercise
        let metrics = exercise.metrics
        let entryID = entry.id
        let tenths = (try? context.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { $0.setEntryID == entryID })).first)?.durationTenths
        let isPair = exercise.resistanceTrackingStyle == .singleDumbbellPair
        let value = valueText(
            usesWeight: metrics.usesWeight,
            inputWeight: exercise.displayedWeightInput(from: entry.weight),
            unit: entry.weightUnit,
            perDumbbell: isPair,
            reps: metrics.usesReps ? entry.reps : nil,
            distance: metrics.usesDistance ? entry.distance.map { exercise.formattedDistanceSummary($0, unit: entry.distanceUnit) } : nil,
            duration: metrics.usesDuration ? (tenths.map { SprintTiming.text(tenths: $0) }
                ?? entry.durationSeconds.map { DateHelper.formattedDuration(seconds: $0) }) : nil
        )
        let badge = PersonalRecords.badges(for: WorkoutCommands.history(for: exercise.id, in: context))[entryID] ?? []
        return Details(
            setID: entryID,
            exerciseName: exercise.name,
            valueText: value.text,
            valueAccessibilityLabel: value.accessibilityLabel,
            personalRecord: badge.isEmpty ? nil : badge.shortTitle,
            personalRecordAccessibilityLabel: badge.isEmpty ? nil : badge.accessibilityDescription,
            weightStep: metrics.usesWeight ? weightStep(unit: entry.weightUnit, perDumbbell: isPair) : nil,
            showsAddRep: metrics.usesReps,
            showsUndo: showsUndo,
            loggedCount: loggedCount
        )
    }

    /// "185 lb × 5", "40 lb each × 10", "12 reps", "50 m · 7.4s". Units are always
    /// written: a bare number on a lock-screen card is ambiguous.
    nonisolated static func valueText(
        usesWeight: Bool, inputWeight: Double?, unit: WeightUnit, perDumbbell: Bool,
        reps: Int?, distance: String?, duration: String?
    ) -> (text: String, accessibilityLabel: String) {
        var visible: [String] = []
        var spoken: [String] = []
        let repsText = reps.map { $0 == 1 ? "1 rep" : "\($0) reps" }
        if usesWeight, let inputWeight, inputWeight > 0 {
            let number = Formatters.weight.string(from: NSNumber(value: inputWeight)) ?? "\(inputWeight)"
            let load = "\(number) \(unit.symbol)\(perDumbbell ? " each" : "")"
            if let reps {
                visible.append("\(load) × \(reps)")
                spoken.append("\(load), \(repsText ?? "")")
            } else {
                visible.append(load)
                spoken.append(load)
            }
        } else if let repsText {
            visible.append(repsText)
            spoken.append(repsText)
        }
        if let distance { visible.append(distance); spoken.append(distance) }
        if let duration { visible.append(duration); spoken.append(duration) }
        guard !visible.isEmpty else { return ("Logged", "Logged") }
        return (visible.joined(separator: " · "), spoken.joined(separator: ", "))
    }

    nonisolated static func weightStep(unit: WeightUnit, perDumbbell: Bool) -> WeightStep {
        let step = WorkoutCommands.weightIncrement(for: unit)
        let number = Formatters.weight.string(from: NSNumber(value: step)) ?? "\(step)"
        let each = perDumbbell ? " each" : ""
        return WeightStep(title: "+\(number) \(unit.symbol)\(each)", accessibilityLabel: "Add \(number) \(unit.symbol)\(each)")
    }
}

/// The interactive card. Not discoverable on its own: it only exists as the
/// result of a logging or correction intent.
struct LoggedSetSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Logged Set"
    static let isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Card ID", description: "This card's own identity, distinct from any set.")
    var cardID: String

    @Parameter(title: "Set ID", description: "The confirmed set this card was created for.")
    var setID: String

    @Parameter(title: "Allows Undo", description: "Whether this card's action created the set, so Undo may remove it.")
    var allowsUndo: Bool

    init() {}

    /// - Parameter createdSet: `true` when the presenting intent just logged
    ///   `setID`; `false` for a correction, whose card never offers to delete it.
    init(setID: UUID, createdSet: Bool, cardID: UUID = UUID()) {
        self.cardID = cardID.uuidString
        self.setID = setID.uuidString
        self.allowsUndo = createdSet
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let card = try LoggedSetButtonSupport.id(cardID)
        let origin = try LoggedSetButtonSupport.id(setID)
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        return .result(view: LoggedSetSnippetView(card: .load(
            cardID: card, originSetID: origin, allowsOriginUndo: allowsUndo, in: context)))
    }
}

// MARK: - Button intents

/// Adds 5 lb / 2.5 kg (in the set's own unit) to exactly one confirmed set.
struct AddWeightToLoggedSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Weight to Logged Set"
    static let description = IntentDescription("Adds one load step (5 lb or 2.5 kg) to the specific confirmed set.")
    static let isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Set ID") var setID: String

    init() {}
    init(setID: UUID) { self.setID = setID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await WorkoutCommands.addWeightStep(toEntryID: try LoggedSetButtonSupport.id(setID))
        return .result()
    }
}

/// Adds one rep to exactly one confirmed set.
struct AddRepToLoggedSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Rep to Logged Set"
    static let description = IntentDescription("Adds one rep to the specific confirmed set.")
    static let isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Set ID") var setID: String

    init() {}
    init(setID: UUID) { self.setID = setID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await WorkoutCommands.addRep(toEntryID: try LoggedSetButtonSupport.id(setID))
        return .result()
    }
}

/// Logs another set identical to the confirmed set the card shows ("Same again").
/// A `LiveActivityIntent` so the rest timer the new set starts can begin from a
/// background launch, exactly like Log Last Set Again.
struct RepeatLoggedSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log Same Set Again"
    static let description = IntentDescription("Logs another set identical to the specific confirmed set.")
    static let isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Card ID") var cardID: String
    @Parameter(title: "Card Set ID") var originSetID: String
    @Parameter(title: "Set ID") var setID: String

    init() {}
    init(cardID: UUID, originSetID: UUID, setID: UUID) {
        self.cardID = cardID.uuidString
        self.originSetID = originSetID.uuidString
        self.setID = setID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let card = try LoggedSetButtonSupport.id(cardID)
        let origin = try LoggedSetButtonSupport.id(originSetID)
        let duplicate = try await WorkoutCommands.repeatConfirmedSet(entryID: try LoggedSetButtonSupport.id(setID))
        LoggedSetSnippetChains.append(duplicate.id, toCard: card, origin: origin)
        return .result()
    }
}

/// Deletes exactly the confirmed set the card shows. Never "the latest set": if
/// that set is already gone, nothing else is touched. Only sets the card's own
/// action created can be removed; a correction card cannot delete the set it
/// corrected.
struct UndoLoggedSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Logged Set"
    static let description = IntentDescription("Removes the specific confirmed set this card logged from the journal.")
    static let isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Card ID") var cardID: String
    @Parameter(title: "Card Set ID") var originSetID: String
    @Parameter(title: "Set ID") var setID: String
    @Parameter(title: "Allows Undo") var allowsOriginUndo: Bool

    init() {}
    init(cardID: UUID, originSetID: UUID, setID: UUID, allowsOriginUndo: Bool) {
        self.cardID = cardID.uuidString
        self.originSetID = originSetID.uuidString
        self.setID = setID.uuidString
        self.allowsOriginUndo = allowsOriginUndo
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let card = try LoggedSetButtonSupport.id(cardID)
        let origin = try LoggedSetButtonSupport.id(originSetID)
        let id = try LoggedSetButtonSupport.id(setID)
        guard LoggedSetSnippetChains.chain(forCard: card, origin: origin).contains(id),
              id != origin || allowsOriginUndo else {
            throw WorkoutIntentFailure(message: "This card can't remove that set. Open Marble to edit your journal.")
        }
        try await WorkoutCommands.deleteConfirmedSet(entryID: id)
        LoggedSetSnippetChains.remove(id, fromCard: card, origin: origin)
        return .result()
    }
}

nonisolated enum LoggedSetButtonSupport {
    static func id(_ string: String) throws -> UUID {
        guard let id = UUID(uuidString: string) else {
            throw WorkoutIntentFailure(message: "That set is no longer available. Open Marble to choose a set.")
        }
        return id
    }
}

// MARK: - View

/// Compact monochrome card. Snippets render out of process like widgets, so every
/// control is a `Button(intent:)`; there is no glass on this content surface.
struct LoggedSetSnippetView: View {
    let card: LoggedSetSnippetCard

    var body: some View {
        Group {
            if let details = card.details {
                loaded(details)
            } else {
                Label("Set removed", systemImage: "arrow.uturn.backward")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("LoggedSetSnippet.Removed")
            }
        }
        .padding()
    }

    private func loaded(_ details: LoggedSetSnippetCard.Details) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(details.exerciseName)
                        .font(.headline)
                        .accessibilityIdentifier("LoggedSetSnippet.Exercise")
                    Text(details.valueText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel(details.valueAccessibilityLabel)
                        .accessibilityIdentifier("LoggedSetSnippet.Value")
                }
                Spacer(minLength: 8)
                if let record = details.personalRecord {
                    Text(record)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(.primary, lineWidth: 1))
                        .accessibilityLabel(details.personalRecordAccessibilityLabel ?? record)
                        .accessibilityIdentifier("LoggedSetSnippet.PersonalRecord")
                }
            }
            if details.loggedCount > 1 {
                Text("\(details.loggedCount) sets logged from this card")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                if details.weightStep != nil || details.showsAddRep {
                    GridRow {
                        if let step = details.weightStep {
                            action(step.title, systemImage: "plus", label: step.accessibilityLabel,
                                   identifier: "LoggedSetSnippet.AddWeight",
                                   intent: AddWeightToLoggedSetIntent(setID: details.setID))
                        }
                        if details.showsAddRep {
                            action("+1 rep", systemImage: "plus", label: "Add 1 rep",
                                   identifier: "LoggedSetSnippet.AddRep",
                                   intent: AddRepToLoggedSetIntent(setID: details.setID))
                        }
                    }
                }
                GridRow {
                    action("Same again", systemImage: "arrow.clockwise", label: "Log the same set again",
                           identifier: "LoggedSetSnippet.SameAgain",
                           intent: RepeatLoggedSetIntent(cardID: card.cardID, originSetID: card.originSetID,
                                                         setID: details.setID))
                    if details.showsUndo {
                        action("Undo", systemImage: "arrow.uturn.backward", label: "Undo this set",
                               identifier: "LoggedSetSnippet.Undo",
                               intent: UndoLoggedSetIntent(cardID: card.cardID, originSetID: card.originSetID,
                                                           setID: details.setID, allowsOriginUndo: card.allowsOriginUndo))
                    }
                }
            }
        }
    }

    private func action(_ title: String, systemImage: String, label: String, identifier: String,
                        intent: some AppIntent) -> some View {
        Button(intent: intent) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
