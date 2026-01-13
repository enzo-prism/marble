import SwiftUI

struct QuickLogTile: View {
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
                .contentShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous))
        } else {
            buttonContent
                .buttonStyle(.plain)
                .background(GlassTileBackground())
        }
    }

    private var buttonContent: some View {
        Button(action: action) {
            VStack(spacing: MarbleSpacing.xxxs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text("Log Set")
                    .font(MarbleTypography.sectionTitle)
                if let hint {
                    Text(hint)
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: MarbleLayout.quickLogHintMaxWidth)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.s)
            .frame(minWidth: MarbleLayout.quickLogMinWidth, minHeight: MarbleLayout.quickLogMinHeight)
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
                        HStack {
                            Spacer(minLength: 0)
                            GlassEffectContainer {
                                QuickLogTile(hint: hint) {
                                    isPresented = true
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, MarbleSpacing.xxs)
                    }
            } else {
                content
                    .tabViewBottomAccessory {
                        HStack {
                            Spacer(minLength: 0)
                            GlassEffectContainer {
                                QuickLogTile(hint: hint) {
                                    isPresented = true
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, MarbleSpacing.xxs)
                    }
                    .tabBarMinimizeBehavior(.onScrollDown)
            }
        } else {
            content
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
        }
    }
}

extension View {
    func quickLogAccessory(isPresented: Binding<Bool>, hint: String?) -> some View {
        modifier(QuickLogAccessoryModifier(isPresented: isPresented, hint: hint))
    }
}
