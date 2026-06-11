import SwiftUI

enum MarbleSpacing {
    static let xxxs: CGFloat = 4
    static let xxs: CGFloat = 6
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum MarbleCornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
}

enum MarbleLayout {
    static let pagePadding: CGFloat = MarbleSpacing.m
    static let rowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    static let rowIconSize: CGFloat = 26
    static let rowSpacing: CGFloat = MarbleSpacing.s
    static let rowInnerSpacing: CGFloat = MarbleSpacing.xxs
    static let chipMinHeight: CGFloat = 44
    static let quickLogCircleSize: CGFloat = 52
}

enum MarbleTypography {
    static let screenTitle = Font.title2.weight(.semibold)
    static let sectionTitle = Font.subheadline.weight(.semibold)
    static let rowTitle = Font.body.weight(.semibold)
    static let rowSubtitle = Font.subheadline
    static let rowMeta = Font.caption
    static let body = Font.body
    static let caption = Font.caption
    static let emptyTitle = Font.title3.weight(.semibold)
    static let emptyMessage = Font.subheadline
    static let chip = Font.subheadline.weight(.medium)
    static let button = Font.subheadline.weight(.semibold)
    static let smallLabel = Font.caption2.weight(.medium)
}
