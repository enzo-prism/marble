import PhotosUI
import SwiftData
import SwiftUI

/// The end-to-end "scan a handwritten workout" flow: capture → on-device read →
/// review/edit → add to journal. Presented as a sheet from the import screen.
struct WorkoutScanView: View {
    @StateObject private var viewModel = WorkoutScanViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingScanner = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            content
                .background(Theme.backgroundColor(for: colorScheme))
                .navigationTitle("Scan Workout")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarGlassBackground()
                .toolbar { toolbarContent }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView { outcome in
                showingScanner = false
                handleScan(outcome)
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .capture: captureView
        case .processing: processingView
        case .review: reviewView
        case .imported: importedView
        }
    }

    private var captureView: some View {
        ScrollView {
            VStack(spacing: MarbleSpacing.l) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .padding(.top, MarbleSpacing.xl)

                VStack(spacing: MarbleSpacing.xs) {
                    Text("Scan a handwritten workout")
                        .font(MarbleTypography.emptyTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .multilineTextAlignment(.center)
                    Text("Capture your notebook or whiteboard. Marble reads it on your device and turns it into sets you can review before logging.")
                        .font(MarbleTypography.emptyMessage)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, MarbleSpacing.l)

                VStack(spacing: MarbleSpacing.s) {
                    if DocumentScannerView.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan with Camera", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                        .accessibilityIdentifier("Scan.Camera")
                    }

                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose a Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .standard))
                    .accessibilityIdentifier("Scan.ChoosePhoto")
                }
                .padding(.horizontal, MarbleSpacing.l)

                Label("Read on your device — nothing is uploaded.", systemImage: "lock.fill")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MarbleSpacing.l)

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MarbleSpacing.l)
                        .accessibilityIdentifier("Scan.Error")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("Scan.Capture")
    }

    private var processingView: some View {
        VStack(spacing: MarbleSpacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("Reading your workout…")
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("Scan.Processing")
    }

    private var reviewView: some View {
        List {
            Section {
                TextField("Workout title", text: $viewModel.draft.title)
                    .font(MarbleTypography.rowTitle)
                    .accessibilityIdentifier("Scan.Title")
                DatePicker("Date", selection: performedAtBinding, displayedComponents: .date)
                    .accessibilityIdentifier("Scan.Date")
            } header: {
                SectionHeaderView(title: "Workout")
            }

            if viewModel.alreadyImported {
                Section {
                    Label("This scan was already added to your journal. Importing again will add the sets a second time.", systemImage: "exclamationmark.triangle")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Scan.AlreadyImported")
                }
            }

            ForEach($viewModel.draft.exercises) { $exercise in
                ScanExerciseSection(
                    exercise: $exercise,
                    onAddSet: { viewModel.addSet(toExerciseWithID: exercise.id) },
                    onRemoveExercise: { viewModel.removeExercise(withID: exercise.id) },
                    onRemoveSets: { offsets in viewModel.removeSets(fromExerciseWithID: exercise.id, at: offsets) }
                )
            }

            Section {
                Button {
                    viewModel.addExercise()
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("Scan.AddExercise")
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Scan.Error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .safeAreaInset(edge: .bottom) {
            importButton
        }
        .accessibilityIdentifier("Scan.Review")
    }

    private var importButton: some View {
        Button {
            viewModel.commit(into: modelContext)
        } label: {
            Text(importButtonTitle)
        }
        .buttonStyle(MarbleActionButtonStyle(
            isEnabledOverride: viewModel.draft.hasContent,
            expandsHorizontally: true,
            prominence: .primary
        ))
        .disabled(!viewModel.draft.hasContent)
        .padding(.horizontal, MarbleSpacing.m)
        .padding(.bottom, MarbleSpacing.s)
        .accessibilityIdentifier("Scan.Import")
    }

    private var importButtonTitle: String {
        let count = viewModel.draft.totalSetCount
        guard count > 0 else { return "Add to Journal" }
        return "Add \(count) set\(count == 1 ? "" : "s") to Journal"
    }

    private var importedView: some View {
        VStack(spacing: MarbleSpacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            if let summary = viewModel.lastSummary {
                Text("Added \(summary.importedSets) set\(summary.importedSets == 1 ? "" : "s")")
                    .font(MarbleTypography.emptyTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                if summary.skipped > 0 {
                    Text("This scan was already imported.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            Button("Done") { dismiss() }
                .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
                .accessibilityIdentifier("Scan.ImportedDone")
                .padding(.top, MarbleSpacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MarbleSpacing.l)
        .accessibilityIdentifier("Scan.Imported")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(viewModel.phase == .review ? "Cancel" : "Done") { dismiss() }
                .accessibilityIdentifier("Scan.Dismiss")
        }
        if viewModel.phase == .review {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan") { viewModel.reset() }
                    .accessibilityIdentifier("Scan.Rescan")
            }
        }
    }

    // MARK: - Bindings & actions

    private var performedAtBinding: Binding<Date> {
        Binding(
            get: { viewModel.draft.performedAt ?? AppEnvironment.now },
            set: { viewModel.draft.performedAt = $0 }
        )
    }

    private func handleScan(_ outcome: DocumentScannerView.Outcome) {
        switch outcome {
        case .scanned(let image):
            Task { await viewModel.process(image: image, in: modelContext) }
        case .cancelled:
            break
        case .failed:
            viewModel.errorMessage = "The scan didn't complete. Please try again."
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            viewModel.errorMessage = "That photo couldn't be opened. Try another one."
            return
        }
        await viewModel.process(image: image, in: modelContext)
    }
}

// MARK: - Exercise section

private struct ScanExerciseSection: View {
    @Binding var exercise: ParsedExerciseDraft
    var onAddSet: () -> Void
    var onRemoveExercise: () -> Void
    var onRemoveSets: (IndexSet) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            TextField("Exercise name", text: $exercise.name)
                .font(MarbleTypography.rowTitle)
                .accessibilityIdentifier("Scan.Exercise.Name")

            ForEach($exercise.sets) { $set in
                ScanSetRow(set: $set, metrics: exercise.metricsProfile)
            }
            .onDelete(perform: onRemoveSets)

            Button(action: onAddSet) {
                Label("Add set", systemImage: "plus")
                    .font(MarbleTypography.rowMeta)
            }
            .accessibilityIdentifier("Scan.Exercise.AddSet")
        } header: {
            HStack {
                SectionHeaderView(title: "Exercise")
                Spacer()
                Button(role: .destructive, action: onRemoveExercise) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(MarbleTypography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Scan.Exercise.Remove")
            }
        }
    }
}

// MARK: - Set row

private struct ScanSetRow: View {
    @Binding var set: ParsedSetDraft
    let metrics: ExerciseMetricsProfile

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            if metrics.usesWeight {
                HStack {
                    OptionalNumberField(
                        title: "Weight",
                        formatter: Formatters.weight,
                        value: $set.weight,
                        accessibilityIdentifier: "Scan.Set.Weight"
                    )
                    Picker("Unit", selection: $set.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("Scan.Set.WeightUnit")
                }
            }

            if metrics.usesReps {
                OptionalIntegerField(
                    title: "Reps",
                    value: $set.reps,
                    accessibilityIdentifier: "Scan.Set.Reps"
                )
            }

            if metrics.usesDistance {
                HStack {
                    OptionalNumberField(
                        title: "Distance",
                        formatter: Formatters.distance,
                        value: $set.distance,
                        accessibilityIdentifier: "Scan.Set.Distance"
                    )
                    Picker("Unit", selection: $set.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.symbol.uppercased()).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("Scan.Set.DistanceUnit")
                }
            }

            if metrics.usesDuration {
                HStack {
                    Text("Duration")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Spacer()
                    DurationPicker(durationSeconds: $set.durationSeconds)
                        .accessibilityIdentifier("Scan.Set.Duration")
                }
            }
        }
        .padding(.vertical, MarbleSpacing.xs)
    }
}
