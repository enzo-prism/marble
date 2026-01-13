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
        } else if #available(iOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
                .background(.ultraThinMaterial)
        }
    }
}

struct GlassPillBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        } else if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(.clear)
                .glassEffect()
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 0.5)
                )
        }
    }
}

struct GlassTileBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

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
        } else if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect()
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 0.5)
                )
        }
    }
}

private struct NavigationBarGlassBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    func body(content: Content) -> some View {
        let base = content.toolbarBackground(.visible, for: .navigationBar)
        if reduceTransparency {
            base.toolbarBackground(Theme.backgroundColor(for: colorScheme), for: .navigationBar)
        } else {
            base.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
        let base = content.toolbarBackground(.visible, for: .tabBar)
        if reduceTransparency {
            base.toolbarBackground(Theme.backgroundColor(for: colorScheme), for: .tabBar)
        } else {
            base.toolbarBackground(.ultraThinMaterial, for: .tabBar)
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
            content.presentationBackground(.ultraThinMaterial)
        }
    }
}

extension View {
    @ViewBuilder
    func navigationGlassBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect()
        } else {
            self
                .background(.ultraThinMaterial)
        }
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
}
