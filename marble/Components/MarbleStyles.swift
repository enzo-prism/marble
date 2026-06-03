import SwiftUI

enum MarbleFieldState {
    case normal
    case focused
    case error
}

struct MarbleFieldStyle: ViewModifier {
    let state: MarbleFieldState

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(MarbleTypography.body)
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xs)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .fill(Theme.surfaceColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .stroke(borderColor, lineWidth: state == .focused ? 2 : 1)
            )
    }

    private var borderColor: Color {
        switch state {
        case .normal:
            return Theme.subtleDividerColor(for: colorScheme)
        case .focused:
            return Theme.primaryTextColor(for: colorScheme)
        case .error:
            return Theme.dividerColor(for: colorScheme)
        }
    }
}

extension View {
    func marbleFieldStyle(_ state: MarbleFieldState = .normal) -> some View {
        modifier(MarbleFieldStyle(state: state))
    }

    func marbleRowInsets() -> some View {
        listRowInsets(MarbleLayout.rowInsets)
    }
}

struct MarbleChipLabel: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let isExpanded: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(MarbleTypography.chip)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: isExpanded ? .infinity : nil, minHeight: MarbleLayout.chipMinHeight)
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xxs)
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 1 : 0.75)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Theme.chipFillColor(for: colorScheme)
        }
        return Theme.surfaceColor(for: colorScheme)
    }

    private var textColor: Color {
        return Theme.primaryTextColor(for: colorScheme)
    }

    private var borderColor: Color {
        isSelected ? Theme.dividerColor(for: colorScheme) : Theme.subtleDividerColor(for: colorScheme)
    }
}

enum MarbleActionButtonProminence {
    case standard
    case primary
}

struct MarbleActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var environmentEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isEnabledOverride: Bool? = nil
    var expandsHorizontally: Bool = false
    var prominence: MarbleActionButtonProminence = .standard

    func makeBody(configuration: Configuration) -> some View {
        let isEnabled = isEnabledOverride ?? environmentEnabled
        let isPressed = isEnabled && configuration.isPressed

        configuration.label
            .font(MarbleTypography.button)
            .foregroundStyle(textColor(isEnabled: isEnabled))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: expandsHorizontally ? .infinity : nil, minHeight: minButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                    .fill(backgroundColor(isEnabled: isEnabled, isPressed: isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                    .stroke(borderColor(isEnabled: isEnabled), lineWidth: prominence == .primary ? 0 : 0.75)
            )
            .opacity(isEnabled ? 1.0 : 0.55)
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.16), value: isPressed)
    }

    private var minButtonHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 52 : 44
    }

    private var verticalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? MarbleSpacing.s : MarbleSpacing.xs
    }

    private func textColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return Theme.secondaryTextColor(for: colorScheme) }
        switch prominence {
        case .standard:
            return Theme.primaryTextColor(for: colorScheme)
        case .primary:
            return Theme.backgroundColor(for: colorScheme)
        }
    }

    private func backgroundColor(isEnabled: Bool, isPressed: Bool) -> Color {
        guard isEnabled else { return Theme.controlFillColor(for: colorScheme) }
        switch prominence {
        case .standard:
            return isPressed
                ? Theme.chipFillColor(for: colorScheme)
                : Theme.controlFillColor(for: colorScheme)
        case .primary:
            return Theme.primaryTextColor(for: colorScheme).opacity(isPressed ? 0.82 : 1.0)
        }
    }

    private func borderColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return Theme.subtleDividerColor(for: colorScheme) }
        return Theme.subtleDividerColor(for: colorScheme)
    }
}

struct MarbleCardBackground: ViewModifier {
    var cornerRadius: CGFloat = MarbleCornerRadius.large

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surfaceColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func marbleCardBackground(cornerRadius: CGFloat = MarbleCornerRadius.large) -> some View {
        modifier(MarbleCardBackground(cornerRadius: cornerRadius))
    }
}
