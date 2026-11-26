import SwiftUI

struct ExerciseTrackingPicker: View {
    let selection: ExerciseKind
    let onSelect: (ExerciseKind) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            options("Strength", [.strength, .dualDumbbell, .bodyweight, .weightedBodyweight])
            options("Running", [.run, .sprint])
            options("Other tracking", [.plyometric, .timed, .custom])
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle("Tracking type")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func options(_ title: String, _ kinds: [ExerciseKind]) -> some View {
        Section(title) {
            ForEach(kinds) { kind in
                Button {
                    onSelect(kind)
                    dismiss()
                } label: {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                                ExerciseTrackingLabel(kind: kind, emphasized: false)
                                if kind == selection {
                                    Label("Selected", systemImage: "checkmark")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        } else {
                            HStack(spacing: MarbleSpacing.s) {
                                ExerciseTrackingLabel(kind: kind, emphasized: false)
                                Spacer(minLength: 0)
                                if kind == selection {
                                    Image(systemName: "checkmark")
                                        .font(.body.bold())
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title), \(kind.subtitle)")
                .accessibilityAddTraits(kind == selection ? .isSelected : [])
                .accessibilityIdentifier("ExerciseEditor.Template.\(kind.id)")
            }
        }
        .listRowBackground(Theme.controlFillColor(for: colorScheme))
    }
}

struct ExerciseTrackingLabel: View {
    let kind: ExerciseKind
    let emphasized: Bool

    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: kind.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(emphasized ? Theme.backgroundColor(for: colorScheme) : Theme.primaryTextColor(for: colorScheme))
                    .frame(width: emphasized ? 44 : 32, height: 44)
                    .background {
                        if emphasized {
                            RoundedRectangle(cornerRadius: MarbleCornerRadius.large)
                                .fill(Theme.primaryTextColor(for: colorScheme))
                        }
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(kind.title)
                    .font(emphasized ? .title3.weight(.semibold) : MarbleTypography.rowTitle)
                Text(kind.subtitle)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, MarbleSpacing.xxxs)
    }
}
