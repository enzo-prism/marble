import SwiftUI

struct SprintPrescriptionEditorView: View {
    @Binding var isEnabled: Bool
    @Binding var distance: Double?
    @Binding var distanceUnit: DistanceUnit
    @Binding var repetitionCount: Int
    @Binding var targetMode: SprintTargetMode
    @Binding var targetSeconds: Int?
    @Binding var targetLowerSeconds: Int?
    @Binding var targetUpperSeconds: Int?
    @Binding var restSeconds: Int

    @Environment(\.colorScheme) private var colorScheme

    private let distancePresets: [Double] = [60, 100, 150, 200, 300, 400]

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            Toggle("Use a sprint prescription", isOn: $isEnabled)
                .tint(Theme.dividerColor(for: colorScheme))
                .accessibilityIdentifier("ExerciseEditor.Sprint.Enabled")

            Text("Set the distance, number of sprints, and the time you want to hit every rep.")
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if isEnabled {
                Divider()
                sprintDistanceSection
                Divider()
                repeatSection
                Divider()
                targetSection
                Divider()
                RestPicker(
                    restSeconds: $restSeconds,
                    presets: [0, 30, 60, 90, 120, 180, 300, 480, 600]
                )
                .accessibilityIdentifier("ExerciseEditor.Sprint.Rest")
            }
        }
        .accessibilityIdentifier("ExerciseEditor.SprintSetup")
    }

    private var sprintDistanceSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Sprint distance")
                .font(MarbleTypography.rowTitle)

            HStack {
                OptionalNumberField(
                    title: "Distance",
                    formatter: Formatters.distance,
                    value: $distance,
                    accessibilityIdentifier: "ExerciseEditor.Sprint.Distance"
                )

                Picker("Unit", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.symbol.uppercased()).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("ExerciseEditor.Sprint.DistanceUnit")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MarbleSpacing.xs) {
                    ForEach(distancePresets, id: \.self) { preset in
                        Button {
                            distance = preset
                            distanceUnit = .meters
                        } label: {
                            Text("\(Int(preset))m")
                                .font(MarbleTypography.rowMeta)
                                .padding(.horizontal, MarbleSpacing.s)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule().fill(
                                        distance == preset && distanceUnit == .meters
                                            ? Theme.primaryTextColor(for: colorScheme)
                                            : Theme.chipFillColor(for: colorScheme)
                                    )
                                )
                                .foregroundStyle(
                                    distance == preset && distanceUnit == .meters
                                        ? Theme.backgroundColor(for: colorScheme)
                                        : Theme.primaryTextColor(for: colorScheme)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ExerciseEditor.Sprint.DistancePreset.\(Int(preset))")
                    }
                }
            }
        }
    }

    private var repeatSection: some View {
        Stepper(value: $repetitionCount, in: 1...50) {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text("Sprints")
                    .font(MarbleTypography.rowTitle)
                Text("\(repetitionCount) reps")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .accessibilityIdentifier("ExerciseEditor.Sprint.RepeatCount")
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Target time")
                .font(MarbleTypography.rowTitle)

            Picker("Target style", selection: $targetMode) {
                ForEach(SprintTargetMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ExerciseEditor.Sprint.GoalMode")

            switch targetMode {
            case .time:
                targetTimeRow(title: "Goal", value: $targetSeconds, identifier: "ExerciseEditor.Sprint.GoalTime")
                Text("This means the goal time or faster.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            case .range:
                targetTimeRow(title: "Fast end", value: $targetLowerSeconds, identifier: "ExerciseEditor.Sprint.RangeFast")
                targetTimeRow(title: "Slow end", value: $targetUpperSeconds, identifier: "ExerciseEditor.Sprint.RangeSlow")
            }
        }
    }

    private func targetTimeRow(title: String, value: Binding<Int?>, identifier: String) -> some View {
        HStack {
            Text(title)
                .font(MarbleTypography.rowSubtitle)
            Spacer()
            DurationPicker(durationSeconds: value, identifierPrefix: identifier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
