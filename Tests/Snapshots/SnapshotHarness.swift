import SnapshotTesting
import SwiftUI
import XCTest
@testable import marble

@MainActor
struct SnapshotDevice {
    let name: String
    let size: CGSize
    let safeArea: UIEdgeInsets
    let idiom: UIUserInterfaceIdiom
}

@MainActor
struct SnapshotVariant {
    let colorScheme: ColorScheme
    let sizeCategory: ContentSizeCategory
    let device: SnapshotDevice

    var suffix: String {
        let scheme = colorScheme == .dark ? "dark" : "light"
        let size = sizeCategory.isAccessibilityCategory ? "a11y" : "default"
        return "\(device.name)_\(scheme)_\(size)"
    }
}

@MainActor
enum SnapshotMatrix {
    static let devices: [SnapshotDevice] = [
        SnapshotDevice(name: "iPhoneSE", size: CGSize(width: 375, height: 667), safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0), idiom: .phone),
        SnapshotDevice(name: "iPhone15Pro", size: CGSize(width: 393, height: 852), safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), idiom: .phone)
    ]

    static let regularWidthDevice = SnapshotDevice(
        name: "iPadPro11",
        size: CGSize(width: 834, height: 1194),
        safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
        idiom: .pad
    )

    static let compactWidthLandscapeDevice = SnapshotDevice(
        name: "iPhone15ProLandscape",
        size: CGSize(width: 852, height: 393),
        safeArea: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59),
        idiom: .phone
    )

    static let regularWidthLandscapeDevice = SnapshotDevice(
        name: "iPadPro11Landscape",
        size: CGSize(width: 1194, height: 834),
        safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
        idiom: .pad
    )

    static let variants: [SnapshotVariant] = {
        let schemes: [ColorScheme] = [.light, .dark]
        let sizes: [ContentSizeCategory] = [.large, .accessibilityExtraExtraExtraLarge]
        var all: [SnapshotVariant] = []
        for device in devices {
            for scheme in schemes {
                for size in sizes {
                    all.append(SnapshotVariant(colorScheme: scheme, sizeCategory: size, device: device))
                }
            }
        }
        return all
    }()

    static let regularWidthVariants: [SnapshotVariant] = {
        let schemes: [ColorScheme] = [.light, .dark]
        let sizes: [ContentSizeCategory] = [.large, .accessibilityExtraExtraExtraLarge]
        return [regularWidthDevice, regularWidthLandscapeDevice].flatMap { device in
            schemes.flatMap { scheme in
                sizes.map { size in
                    SnapshotVariant(colorScheme: scheme, sizeCategory: size, device: device)
                }
            }
        }
    }()

    static let compactWidthLandscapeVariants: [SnapshotVariant] = {
        let schemes: [ColorScheme] = [.light, .dark]
        let sizes: [ContentSizeCategory] = [.large, .accessibilityExtraExtraExtraLarge]
        return schemes.flatMap { scheme in
            sizes.map { size in
                SnapshotVariant(
                    colorScheme: scheme,
                    sizeCategory: size,
                    device: compactWidthLandscapeDevice
                )
            }
        }
    }()
}

@MainActor
func assertSnapshot<V: View>(
    _ view: V,
    named name: String,
    variants: [SnapshotVariant] = SnapshotMatrix.variants,
    // `#filePath`, not `#file`: under the Swift 6 language mode `#file` is the
    // *concise* "Module/File.swift" form, which sent SnapshotTesting looking for
    // baselines at `/MarbleSnapshotTests/__Snapshots__/…` — a read-only volume.
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    for variant in variants {
        let activityName = "\(name)_\(variant.suffix)"
        XCTContext.runActivity(named: activityName) { _ in
            autoreleasepool {
                let configured = view
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.sizeCategory, variant.sizeCategory)
                    .environment(\.marbleActiveDay, DateHelper.startOfDay(for: SnapshotFixtures.now))
                    .transaction { $0.disablesAnimations = true }
                    .frame(width: variant.device.size.width, height: variant.device.size.height)
                    .background(Theme.backgroundColor(for: variant.colorScheme))

                let traits = UITraitCollection { mutableTraits in
                    mutableTraits.userInterfaceIdiom = variant.device.idiom
                    mutableTraits.userInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
                    mutableTraits.preferredContentSizeCategory = uiContentSizeCategory(from: variant.sizeCategory)
                }

                let config = ViewImageConfig(
                    safeArea: variant.device.safeArea,
                    size: variant.device.size,
                    traits: traits
                )

                RunLoop.main.run(until: Date().addingTimeInterval(0.05))

                let verify = {
                    verifySnapshot(
                        of: configured,
                        as: .image(
                            precision: 0.98,
                            layout: .device(config: config),
                            traits: traits
                        ),
                        named: activityName,
                        file: file,
                        testName: testName,
                        line: line
                    )
                }
                let failure = SnapshotRecording.isEnabled
                    ? withSnapshotTesting(record: .all, operation: verify)
                    : verify()

                if let failure, !shouldIgnoreSnapshotFailure() {
                    XCTFail(failure, file: file, line: line)
                }
            }
        }
    }
}

private func shouldIgnoreSnapshotFailure() -> Bool {
    SnapshotRecording.isEnabled
}

nonisolated private func uiContentSizeCategory(from sizeCategory: ContentSizeCategory) -> UIContentSizeCategory {
    switch sizeCategory {
    case .extraSmall:
        return .extraSmall
    case .small:
        return .small
    case .medium:
        return .medium
    case .large:
        return .large
    case .extraLarge:
        return .extraLarge
    case .extraExtraLarge:
        return .extraExtraLarge
    case .extraExtraExtraLarge:
        return .extraExtraExtraLarge
    case .accessibilityMedium:
        return .accessibilityMedium
    case .accessibilityLarge:
        return .accessibilityLarge
    case .accessibilityExtraLarge:
        return .accessibilityExtraLarge
    case .accessibilityExtraExtraLarge:
        return .accessibilityExtraExtraLarge
    case .accessibilityExtraExtraExtraLarge:
        return .accessibilityExtraExtraExtraLarge
    default:
        return .large
    }
}
