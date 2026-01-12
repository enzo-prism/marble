import SwiftUI

struct ToastView: View {
    let message: String
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Spacer(minLength: 8)
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Toast")
        .onTapGesture {
            onDismiss?()
        }
    }
}
