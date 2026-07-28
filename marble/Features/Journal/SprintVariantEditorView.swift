import SwiftUI

/// Edits one sprint plan (`SprintVariantDraft`) inside the exercise editor —
/// the multi-plan successor of the retired `SprintPrescriptionEditorView`.
/// Target times are decimal seconds ("14.8"); tenths are the canon they
/// resolve to on save.
struct SprintVariantEditorView: View {
    @Binding var draft: SprintVariantDraft
    @Binding var distanceUnit: DistanceUnit
    /// Position in the plan list, for stable accessibility identifiers that
    /// survive deletes ("ExerciseEditor.Sprint.0.Distance").
    let index: Int
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let distancePresets: [Double] = [60, 100, 150, 200, 300, 400]

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack {
                TextField("Plan name (optional)", text: $draft.title)
                    .font(MarbleTypography.rowTitle)
                    .marbleFieldStyle()
                    .accessibilityLabel("Plan name")
                    .accessibilityIdentifier("ExerciseEditor.Sprint.\(index).Title")

                if canDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.destructiveActionColor(for: colorScheme))
                    .accessibilityLabel("Delete this sprint plan")
                    .accessibilityIdentifier("ExerciseEditor.Sprint.\(index).Delete")
                }
            }

            sprintDistanceSection
            Divider()
            repeatSection
            Divider()
            targetSection
        }
    }

    private var sprintDistanceSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Sprint distance")
                .font(MarbleTypography.rowTitle)

            HStack {
                OptionalNumberField(
                    title: "Distance",
                    formatter: Formatters.distance,
                    value: $draft.distance,
                    accessibilityIdentifier: "ExerciseEditor.Sprint.\(index).Distance"
                )

                Picker("Unit", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.symbol.uppercased()).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("ExerciseEditor.Sprint.\(index).DistanceUnit")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MarbleSpacing.xs) {
                    ForEach(distancePresets, id: \.self) { preset in
                        Button {
                            draft.distance = preset
                            distanceUnit = .meters
                        } label: {
                            Text("\(Int(preset))m")
                                .font(MarbleTypography.rowMeta)
                                .padding(.horizontal, MarbleSpacing.s)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule().fill(
                                        draft.distance == preset && distanceUnit == .meters
                                            ? Theme.primaryTextColor(for: colorScheme)
                                            : Theme.chipFillColor(for: colorScheme)
                                    )
                                )
                                .foregroundStyle(
                                    draft.distance == preset && distanceUnit == .meters
                                        ? Theme.backgroundColor(for: colorScheme)
                                        : Theme.primaryTextColor(for: colorScheme)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ExerciseEditor.Sprint.\(index).DistancePreset.\(Int(preset))")
                    }
                }
            }
        }
    }

    private var repeatSection: some View {
        Stepper(value: $draft.repetitionCount, in: 1...50) {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text("Sprints")
                    .font(MarbleTypography.rowTitle)
                Text("\(draft.repetitionCount) reps")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .accessibilityIdentifier("ExerciseEditor.Sprint.\(index).RepeatCount")
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Target time")
                .font(MarbleTypography.rowTitle)

            Picker("Target style", selection: $draft.targetMode) {
                ForEach(SprintTargetMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ExerciseEditor.Sprint.\(index).GoalMode")

            switch draft.targetMode {
            case .time:
                targetTimeRow(title: "Goal", value: $draft.targetSeconds, identifier: "ExerciseEditor.Sprint.\(index).GoalTime")
                Text("This means the goal time or faster. Tenths count — 14.8 beats 15.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            case .range:
                targetTimeRow(title: "Fast end", value: $draft.targetLowerSeconds, identifier: "ExerciseEditor.Sprint.\(index).RangeFast")
                targetTimeRow(title: "Slow end", value: $draft.targetUpperSeconds, identifier: "ExerciseEditor.Sprint.\(index).RangeSlow")
            }
        }
    }

    private func targetTimeRow(title: String, value: Binding<Double?>, identifier: String) -> some View {
        HStack {
            Text(title)
                .font(MarbleTypography.rowSubtitle)
            Spacer()
            OptionalNumberField(
                title: "Seconds",
                formatter: Formatters.sprintSeconds,
                value: value,
                accessibilityIdentifier: identifier
            )
            .frame(width: 84)
            Text("sec")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .accessibilityElement(children: .contain)
    }
}
