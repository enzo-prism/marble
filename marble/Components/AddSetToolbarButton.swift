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

/// Primary `+` in its own glass capsule. The zoom source sits on the
/// `ToolbarItem` (not the button), matching the Import morph pattern.
struct LogSetToolbarItems: ToolbarContent {
    @Environment(\.logSetZoomNamespace) private var logSetZoomNamespace
    @Namespace private var fallbackNamespace

    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            AddSetToolbarButton()
        }
        .matchedTransitionSource(id: "log-set", in: logSetZoomNamespace ?? fallbackNamespace)
    }
}
