import SwiftData
import SwiftUI

/// "Ask your journal": a private, on-device question box over the lifter's
/// own history, presented from Workout History. The answer sentence is a
/// summary; the cards under it are the engine's facts, each tappable to the
/// workout or exercise it came from, so every answer can be checked.
struct AskJournalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    @State private var question = ""
    @State private var phase: Phase
    @State private var examples: [String]
    @State private var askTask: Task<Void, Never>?
    @State private var exerciseDestination: ExerciseDestination?
    @FocusState private var fieldFocused: Bool
    private let isLive: Bool

    enum Phase: Equatable {
        case idle
        case answering
        case answered(AskJournalAnswer)
    }

    private struct ExerciseDestination: Identifiable {
        let id: UUID
    }

    init() {
        _phase = State(initialValue: .idle)
        _examples = State(initialValue: [])
        isLive = true
    }

    /// Deterministic presentation seam for snapshot tests: no fetches, no model.
    init(snapshotQuestion: String = "", answer: AskJournalAnswer?, examples: [String]) {
        _question = State(initialValue: snapshotQuestion)
        _phase = State(initialValue: answer.map(Phase.answered) ?? .idle)
        _examples = State(initialValue: examples)
        isLive = false
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb }
    private var engine: JournalQueryEngine { JournalQueryEngine(context: modelContext, unit: weightUnit) }
    private var trimmedQuestion: String {
        question.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var primary: Color { Theme.primaryTextColor(for: colorScheme) }
    private var secondary: Color { Theme.secondaryTextColor(for: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                    questionField
                    switch phase {
                    case .idle:
                        examplesSection(title: "Try asking")
                        footer(AskJournalAnswer.Source.template)
                    case .answering:
                        answeringView
                    case .answered(let answer):
                        answerView(answer)
                    }
                }
                .padding(MarbleLayout.pagePadding)
                .frame(maxWidth: MarbleLayout.formMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Ask Your Journal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("Ask.Done")
                }
            }
            .navigationDestination(for: UUID.self) { sessionID in
                sessionDestination(sessionID)
            }
        }
        .task {
            guard isLive else { return }
            examples = engine.exampleQuestions()
        }
        .onDisappear { askTask?.cancel() }
        .sheet(item: $exerciseDestination) { destination in
            exerciseDestinationView(destination.id)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Question

    /// Field and send button side by side; at accessibility text sizes the
    /// button drops below as a full-width, labelled control so neither the
    /// question nor the glyph is clipped.
    @ViewBuilder
    private var questionField: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                // Wraps instead of truncating at the largest sizes.
                textField(axis: .vertical)
                Button(action: ask) {
                    Text("Ask")
                        .font(MarbleTypography.button)
                        .frame(maxWidth: .infinity, minHeight: MarbleLayout.minimumTouchTarget)
                        .background(Capsule().fill(primary))
                        .foregroundStyle(Theme.backgroundColor(for: colorScheme))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canAsk)
                .opacity(canAsk ? 1 : 0.4)
                .accessibilityIdentifier("Ask.Submit")
            }
        } else {
            HStack(spacing: MarbleSpacing.xs) {
                textField(axis: .horizontal)
                Button(action: ask) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: MarbleLayout.minimumTouchTarget, height: MarbleLayout.minimumTouchTarget)
                        .background(Circle().fill(primary))
                        .foregroundStyle(Theme.backgroundColor(for: colorScheme))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canAsk)
                .opacity(canAsk ? 1 : 0.4)
                .accessibilityLabel("Ask")
                .accessibilityIdentifier("Ask.Submit")
            }
        }
    }

    private var canAsk: Bool { !trimmedQuestion.isEmpty && phase != .answering }

    private func textField(axis: Axis) -> some View {
        TextField("Ask about your training", text: $question, axis: axis)
            .lineLimit(1...4)
            .font(MarbleTypography.body)
            .foregroundStyle(primary)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.search)
            .focused($fieldFocused)
            .onSubmit(ask)
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xs)
            .frame(minHeight: MarbleLayout.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                    .fill(Theme.controlFillColor(for: colorScheme))
            )
            .accessibilityLabel("Question")
            .accessibilityHint("Ask about your logged sets and workouts")
            .accessibilityIdentifier("Ask.Field")
    }

    // MARK: - Phases

    private func examplesSection(title: String) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text(title)
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(primary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                Button {
                    question = example
                    ask()
                } label: {
                    HStack(spacing: MarbleSpacing.xs) {
                        Text(example)
                            .font(MarbleTypography.rowSubtitle)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                            .font(MarbleTypography.rowMeta)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(primary)
                    .padding(.horizontal, MarbleSpacing.s)
                    .padding(.vertical, MarbleSpacing.xs)
                    .frame(maxWidth: .infinity, minHeight: MarbleLayout.minimumTouchTarget, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                            .fill(Theme.chipFillColor(for: colorScheme))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(phase == .answering)
                .accessibilityHint("Asks this question")
                .accessibilityIdentifier("Ask.Example.\(index)")
            }
        }
    }

    private var answeringView: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(spacing: MarbleSpacing.s) {
                ProgressView()
                Text("Looking through your journal…")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button("Cancel") {
                askTask?.cancel()
                askTask = nil
                phase = .idle
            }
            .font(MarbleTypography.button)
            .foregroundStyle(primary)
            .frame(minHeight: MarbleLayout.minimumTouchTarget)
            .accessibilityIdentifier("Ask.Cancel")
        }
    }

    private func answerView(_ answer: AskJournalAnswer) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            // Echo the question only once the field has moved on from it.
            if !answer.question.isEmpty, answer.question != trimmedQuestion {
                Text(answer.question)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("You asked: \(answer.question)")
            }
            Text(answer.sentence)
                .font(.title3.weight(.semibold))
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(answer.kind == .unanswerable ? "Ask.Unanswerable" : "Ask.Answer")

            ForEach(Array(answer.cards.enumerated()), id: \.element.id) { index, card in
                cardView(card, index: index)
            }

            if answer.kind == .unanswerable {
                examplesSection(title: "You can ask")
            }

            footer(answer.source)
        }
    }

    private func footer(_ source: AskJournalAnswer.Source) -> some View {
        let text = AskJournalAnswer(question: "", sentence: "", cards: [], source: source, kind: .answered).footer
        return Text(text)
            .font(MarbleTypography.caption)
            .foregroundStyle(secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("Ask.Footer")
    }

    // MARK: - Cards

    @ViewBuilder
    private func cardView(_ card: JournalCard, index: Int) -> some View {
        switch card.destination {
        case .session(let sessionID):
            NavigationLink(value: sessionID) {
                cardLabel(card, isTappable: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens this workout")
            .accessibilityIdentifier("Ask.Card.\(index)")
        case .exercise(let exerciseID):
            Button {
                exerciseDestination = ExerciseDestination(id: exerciseID)
            } label: {
                cardLabel(card, isTappable: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens this exercise's progress")
            .accessibilityIdentifier("Ask.Card.\(index)")
        case nil:
            cardLabel(card, isTappable: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Ask.Card.\(index)")
        }
    }

    private func cardLabel(_ card: JournalCard, isTappable: Bool) -> some View {
        HStack(alignment: .center, spacing: MarbleSpacing.s) {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(card.label)
                    .font(MarbleTypography.smallLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(secondary)
                Text(card.title)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.detail.isEmpty {
                    Text(card.detail)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if isTappable {
                Image(systemName: "chevron.right")
                    .font(MarbleTypography.rowMeta.weight(.semibold))
                    .foregroundStyle(secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, minHeight: MarbleLayout.minimumTouchTarget, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .contentShape(Rectangle())
    }

    // MARK: - Destinations

    @ViewBuilder
    private func sessionDestination(_ id: UUID) -> some View {
        if let session = fetch(WorkoutSession.self, id: id) {
            WorkoutSessionDetailView(session: session)
        } else {
            ContentUnavailableView("Workout unavailable", systemImage: "exclamationmark.circle", description: Text("This workout may have been deleted."))
        }
    }

    @ViewBuilder
    private func exerciseDestinationView(_ id: UUID) -> some View {
        if let exercise = fetch(Exercise.self, id: id) {
            ExerciseProgressView(exercise: exercise)
        } else {
            ContentUnavailableView("Exercise unavailable", systemImage: "exclamationmark.circle", description: Text("This exercise may have been deleted."))
        }
    }

    private func fetch(_ type: WorkoutSession.Type, id: UUID) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetch(_ type: Exercise.Type, id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Asking

    private func ask() {
        let text = trimmedQuestion
        guard !text.isEmpty, isLive else { return }
        fieldFocused = false
        askTask?.cancel()
        phase = .answering
        let engine = engine
        askTask = Task {
            let answer = await AskJournalResponder.answer(text, engine: engine)
            guard !Task.isCancelled else { return }
            phase = .answered(answer)
            AccessibilityNotification.Announcement(answer.sentence).post()
        }
    }
}
