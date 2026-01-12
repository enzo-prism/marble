import SwiftUI

enum Theme {
    static func backgroundColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func primaryTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func secondaryTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.7) : Color(white: 0.35)
    }

    static func dividerColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.25) : Color(white: 0.8)
    }

    static func chipFillColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.18) : Color(white: 0.92)
    }
}

