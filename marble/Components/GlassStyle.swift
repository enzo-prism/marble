import SwiftUI

struct GlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        } else if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.clear)
                .glassEffect()
        } else {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 0.5)
                )
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

    @ViewBuilder
    func navigationBarGlassBackground() -> some View {
        self
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    @ViewBuilder
    func tabBarGlassBackground() -> some View {
        self
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }

    @ViewBuilder
    func sheetGlassBackground() -> some View {
        self
            .presentationBackground(.ultraThinMaterial)
    }
}
