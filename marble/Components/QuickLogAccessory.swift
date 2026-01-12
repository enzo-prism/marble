import SwiftUI

struct QuickLogPill: View {
    let hint: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(iOS 26.0, *) {
            buttonContent
                .buttonStyle(.glass)
        } else {
            buttonContent
                .buttonStyle(.plain)
        }
    }

    private var buttonContent: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text("Log Set")
                    .font(.headline)
                if let hint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .background(GlassPillBackground())
        .accessibilityLabel(hint == nil ? "Log Set" : "Log Set, last used \(hint ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

struct QuickLogAccessoryModifier: ViewModifier {
    @Binding var isPresented: Bool
    var hint: String?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .tabViewBottomAccessory {
                    GlassEffectContainer {
                        QuickLogPill(hint: hint) {
                            isPresented = true
                        }
                        .padding(.bottom, 4)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
                .safeAreaInset(edge: .bottom) {
                    QuickLogPill(hint: hint) {
                        isPresented = true
                    }
                    .padding(.bottom, 8)
                }
        }
    }
}

extension View {
    func quickLogAccessory(isPresented: Binding<Bool>, hint: String?) -> some View {
        modifier(QuickLogAccessoryModifier(isPresented: isPresented, hint: hint))
    }
}
