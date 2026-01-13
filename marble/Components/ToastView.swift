import SwiftUI

struct ToastView: View {
    let message: String
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            Text(message)
                .font(MarbleTypography.body)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Spacer(minLength: 8)
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .font(MarbleTypography.button)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            }
        }
        .padding(.horizontal, MarbleSpacing.m)
        .padding(.vertical, MarbleSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        )
        .padding(.horizontal, MarbleSpacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Toast")
        .onTapGesture {
            onDismiss?()
        }
    }
}
