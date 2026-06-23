import SwiftUI

struct AddSetToolbarButton: View {
    @Environment(QuickLogCoordinator.self) private var quickLog
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            quickLog.open()
        } label: {
            ScaledSymbol(systemName: "plus", size: 17, weight: .semibold)
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("QuickLog.Button")
        .accessibilityLabel("Log Set")
    }
}
