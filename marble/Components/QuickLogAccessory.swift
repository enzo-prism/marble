import SwiftUI

struct QuickLogPill: View {
    let hint: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            buttonContent
                .buttonStyle(.glass)
                .contentShape(Capsule(style: .continuous))
        } else {
            buttonContent
                .buttonStyle(.plain)
                .background(GlassPillBackground())
        }
    }

    private var buttonContent: some View {
        Button(action: action) {
            HStack(spacing: MarbleSpacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Log Set")
                    .font(MarbleTypography.button)
                if let hint {
                    Text(hint)
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, MarbleSpacing.m)
            .padding(.vertical, MarbleSpacing.s)
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("QuickLog.Button")
        .accessibilityLabel(hint == nil ? "Log Set" : "Log Set, last used \(hint ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

struct QuickLogAccessoryModifier: ViewModifier {
    @Binding var isPresented: Bool
    var hint: String?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if TestHooks.isUITesting {
                content
                    .tabViewBottomAccessory {
                        GlassEffectContainer {
                            QuickLogPill(hint: hint) {
                                isPresented = true
                            }
                            .padding(.vertical, MarbleSpacing.xxs)
                        }
                    }
            } else {
                content
                    .tabViewBottomAccessory {
                        GlassEffectContainer {
                            QuickLogPill(hint: hint) {
                                isPresented = true
                            }
                            .padding(.vertical, MarbleSpacing.xxs)
                        }
                    }
                    .tabBarMinimizeBehavior(.onScrollDown)
            }
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
