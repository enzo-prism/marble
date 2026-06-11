import SwiftUI

struct GlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(Theme.backgroundColor(for: colorScheme))
        } else {
            GlassEffectContainer {
                content
            }
        }
    }
}

struct GlassPillBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    var isInteractive = false

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        if reduceTransparency {
            shape
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    shape
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        } else {
            shape
                .fill(.clear)
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

struct GlassTileBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    var isInteractive = false

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
        if reduceTransparency {
            shape
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    shape
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        } else {
            shape
                .fill(.clear)
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

struct GlassCircleBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    var isInteractive = false

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        let shape = Circle()
        if reduceTransparency {
            shape
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    shape
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        } else {
            shape
                .fill(.clear)
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

// Navigation surfaces only override the system Liquid Glass treatment when
// Reduce Transparency asks for solid backgrounds; otherwise the system bars
// keep their native glass and scroll edge effects.

private struct NavigationBarGlassBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Theme.backgroundColor(for: colorScheme), for: .navigationBar)
        } else {
            content
        }
    }
}

private struct TabBarGlassBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(Theme.backgroundColor(for: colorScheme), for: .tabBar)
        } else {
            content
        }
    }
}

private struct SheetGlassBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.presentationBackground(Theme.backgroundColor(for: colorScheme))
        } else {
            content
        }
    }
}

extension View {
    func navigationGlassBackground() -> some View {
        glassEffect()
    }

    func navigationBarGlassBackground() -> some View {
        modifier(NavigationBarGlassBackgroundModifier())
    }

    func tabBarGlassBackground() -> some View {
        modifier(TabBarGlassBackgroundModifier())
    }

    func sheetGlassBackground() -> some View {
        modifier(SheetGlassBackgroundModifier())
    }

    func applyGlassButtonStyle() -> some View {
        buttonStyle(.glass)
    }

    /// Minimizes the tab bar while scrolling content. Disabled under UI
    /// testing so element hit targets stay deterministic.
    @ViewBuilder
    func marbleTabBarMinimizeBehavior() -> some View {
        if TestHooks.isUITesting {
            self
        } else {
            self.tabBarMinimizeBehavior(.onScrollDown)
        }
    }
}
