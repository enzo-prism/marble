import SnapshotTesting
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import marble

/// History's lazy List needs an appearance/layout cycle before capture. Keep
/// this mounted strategy scoped here until other suites deliberately migrate.
@MainActor
func assertHistorySnapshot<V: View>(
    named name: String,
    expectedText: [String] = [],
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    @ViewBuilder content: () -> V
) {
    for variant in SnapshotMatrix.variants {
        let activityName = "\(name)_\(variant.suffix)"
        XCTContext.runActivity(named: activityName) { _ in
            autoreleasepool {
                guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) else {
                    XCTFail("History snapshots require an active UIWindowScene", file: file, line: line)
                    return
                }
                let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
                let root = UIViewController()
                let host = UIHostingController(rootView: content()
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.sizeCategory, variant.sizeCategory)
                    .environment(\.marbleActiveDay, DateHelper.startOfDay(for: SnapshotFixtures.now))
                    .transaction { $0.disablesAnimations = true })
                let window = HistorySnapshotWindow(scene: scene, size: variant.device.size, insets: variant.device.safeArea)
                let style: UIUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
                window.overrideUserInterfaceStyle = style
                root.addChild(host)
                root.view.addSubview(host.view)
                host.view.frame = CGRect(origin: .zero, size: variant.device.size)
                host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let traits = UITraitCollection { traits in
                    traits.userInterfaceIdiom = variant.device.idiom
                    traits.userInterfaceStyle = style
                    traits.preferredContentSizeCategory = variant.sizeCategory.isAccessibilityCategory
                        ? .accessibilityExtraExtraExtraLarge : .large
                }
                root.setOverrideTraitCollection(traits, forChild: host)
                host.didMove(toParent: root)
                window.rootViewController = root
                window.makeKeyAndVisible()
                window.frame = CGRect(origin: .zero, size: variant.device.size)
                root.view.frame = window.bounds
                host.view.frame = root.view.bounds
                root.beginAppearanceTransition(true, animated: false)
                root.endAppearanceTransition()
                defer {
                    root.beginAppearanceTransition(false, animated: false)
                    root.endAppearanceTransition()
                    window.isHidden = true
                    window.rootViewController = nil
                    previousKeyWindow?.makeKey()
                }

                // Unlike the shared pre-host delay, these turns happen after
                // List and NavigationStack have joined a visible window.
                let settleUntil = Date().addingTimeInterval(0.75)
                repeat {
                    root.view.setNeedsLayout()
                    root.view.layoutIfNeeded()
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                } while Date() < settleUntil
                root.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                let renderer = UIGraphicsImageRenderer(size: variant.device.size, format: format)
                var rendered = false
                let image = renderer.image { _ in
                    rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                guard rendered else {
                    XCTFail("History window failed to render", file: file, line: line)
                    return
                }
                do {
                    let recognized = try historyRecognizedText(in: image)
                    let normalized = normalizeHistoryText(recognized)
                    guard !normalized.isEmpty,
                          expectedText.allSatisfy({ normalized.contains(normalizeHistoryText($0)) }) else {
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "MissingContent_\(activityName)"
                        attachment.lifetime = .keepAlways
                        XCTContext.runActivity(named: "Inspect failed History capture") { $0.add(attachment) }
                        XCTFail("History capture is blank or missing expected text \(expectedText). OCR: \(recognized)", file: file, line: line)
                        return
                    }
                } catch {
                    XCTFail("History capture OCR failed: \(error)", file: file, line: line)
                    return
                }
                let verify = {
                    verifySnapshot(of: image, as: .image(precision: 0.98), named: activityName,
                                   file: file, testName: testName, line: line)
                }
                let failure = SnapshotRecording.isEnabled
                    ? withSnapshotTesting(record: .all, operation: verify) : verify()
                if let failure, !SnapshotRecording.isEnabled {
                    XCTFail(failure, file: file, line: line)
                }
            }
        }
    }
}

@MainActor
private func historyRecognizedText(in image: UIImage) throws -> String {
    guard let cgImage = image.cgImage else { return "" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
}

private func normalizeHistoryText(_ text: String) -> String {
    text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
}

@MainActor
private final class HistorySnapshotWindow: UIWindow {
    private let snapshotInsets: UIEdgeInsets
    init(scene: UIWindowScene, size: CGSize, insets: UIEdgeInsets) {
        snapshotInsets = insets
        super.init(windowScene: scene)
        frame = CGRect(origin: .zero, size: size)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override var safeAreaInsets: UIEdgeInsets { snapshotInsets }
}
