import SwiftUI

struct AddSetToolbarButton: View {
    @EnvironmentObject private var quickLog: QuickLogCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            quickLog.open()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("QuickLog.Button")
        .accessibilityLabel("Log Set")
    }
}
