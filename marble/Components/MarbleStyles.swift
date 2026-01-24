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
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .stroke(borderColor, lineWidth: state == .focused ? 2 : 1)
            )
    }

    private var borderColor: Color {
        switch state {
        case .normal:
            return Theme.dividerColor(for: colorScheme)
        case .focused:
            return Theme.primaryTextColor(for: colorScheme)
        case .error:
            return Theme.secondaryTextColor(for: colorScheme)
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
                    .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Theme.dividerColor(for: colorScheme)
        }
        return Theme.backgroundColor(for: colorScheme)
    }

    private var textColor: Color {
        if isSelected {
            return Theme.backgroundColor(for: colorScheme)
        }
        return Theme.primaryTextColor(for: colorScheme)
    }
}

struct MarbleActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var environmentEnabled
    var isEnabledOverride: Bool? = nil
    var expandsHorizontally: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let isEnabled = isEnabledOverride ?? environmentEnabled
        let textColor = Theme.primaryTextColor(for: colorScheme)
        let borderColor = isEnabled ? Theme.dividerColor(for: colorScheme) : Theme.secondaryTextColor(for: colorScheme)
        let isPressed = isEnabled && configuration.isPressed
        let backgroundColor = Theme.chipFillColor(for: colorScheme)

        configuration.label
            .font(MarbleTypography.button)
            .foregroundStyle(textColor)
            .padding(.horizontal, MarbleSpacing.m)
            .padding(.vertical, MarbleSpacing.xs)
            .frame(maxWidth: expandsHorizontally ? .infinity : nil, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(isEnabled ? (isPressed ? 0.85 : 1.0) : 0.5)
    }
}
