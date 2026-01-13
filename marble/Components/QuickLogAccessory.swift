import SwiftUI

struct QuickLogTile: View {
    let hint: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                GlassCircleBackground()
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
            }
            .frame(width: MarbleLayout.quickLogCircleSize, height: MarbleLayout.quickLogCircleSize)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .contentShape(Circle())
        .accessibilityIdentifier("QuickLog.Button")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        hint.map { "Log Set, last used \($0)" } ?? "Log Set"
    }
}

struct QuickLogAccessoryModifier: ViewModifier {
    @Binding var isPresented: Bool
    var hint: String?

    func body(content: Content) -> some View {
        let inset = content
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer(minLength: 0)
                    QuickLogTile(hint: hint) {
                        isPresented = true
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, MarbleSpacing.xs)
            }

        if #available(iOS 26.0, *) {
            inset
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            inset
        }
    }
}

extension View {
    func quickLogAccessory(isPresented: Binding<Bool>, hint: String?) -> some View {
        modifier(QuickLogAccessoryModifier(isPresented: isPresented, hint: hint))
    }
}
