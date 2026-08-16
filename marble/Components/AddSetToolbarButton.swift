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

/// Primary `+` in its own glass capsule. The zoom source lives on the
/// button view (same pattern as Import), so `ToolbarContent` does not
/// need its own `@Namespace`.
struct LogSetToolbarItems: ToolbarContent {
    @Environment(\.logSetZoomNamespace) private var logSetZoomNamespace

    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            AddSetToolbarButton()
                .modifier(LogSetZoomSource(namespace: logSetZoomNamespace))
        }
    }
}

private struct LogSetZoomSource: ViewModifier {
    var namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: "log-set", in: namespace)
        } else {
            content
        }
    }
}
