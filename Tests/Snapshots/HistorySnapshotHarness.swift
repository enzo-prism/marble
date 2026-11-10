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
    // Match the reference fixture's UTC clock independent of the Mac's zone.
    let previousTimeZone = Formatters.time.timeZone
    let previousLocale = Formatters.time.locale
    Formatters.time.timeZone = TimeZone(secondsFromGMT: 0)
    Formatters.time.locale = Locale(identifier: "en_US_POSIX")
    defer {
        Formatters.time.timeZone = previousTimeZone
        Formatters.time.locale = previousLocale
    }
    let partition = ProcessInfo.processInfo.environment["MARBLE_HISTORY_SNAPSHOT_CATEGORY"] ?? ""
    let variants: [SnapshotVariant]
    switch partition {
    case "default": variants = SnapshotMatrix.variants.filter { !$0.sizeCategory.isAccessibilityCategory }
    case "a11y": variants = SnapshotMatrix.variants.filter { $0.sizeCategory.isAccessibilityCategory }
    case "", "$(MARBLE_HISTORY_SNAPSHOT_CATEGORY)": variants = SnapshotMatrix.variants
    default:
        XCTFail("Unknown History snapshot category: \(partition)", file: file, line: line)
        return
    }
    for variant in variants {
        let expectedCategory: UIContentSizeCategory = variant.sizeCategory.isAccessibilityCategory
            ? .accessibilityExtraExtraExtraLarge : .large
        guard UIApplication.shared.preferredContentSizeCategory == expectedCategory else {
            XCTFail("History native search requires a matching system text size. Run make snapshot; the runner launches each category separately.", file: file, line: line)
            return
        }
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
                // The SwiftUI transaction does not disable UIKit's navigation
                // and search-bar transitions. Restore this process setting after
                // each capture, including early failures.
                let animationsWereEnabled = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
                let style: UIUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
                let category: UIContentSizeCategory = variant.sizeCategory.isAccessibilityCategory
                    ? .accessibilityExtraExtraExtraLarge : .large
                let root = UIViewController()
                root.overrideUserInterfaceStyle = style
                root.traitOverrides.preferredContentSizeCategory = category
                let host = UIHostingController(rootView: content()
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.sizeCategory, variant.sizeCategory)
                    .environment(\.marbleActiveDay, DateHelper.startOfDay(for: SnapshotFixtures.now))
                    .transaction { $0.disablesAnimations = true })
                let window = HistorySnapshotWindow(scene: scene, size: variant.device.size, insets: variant.device.safeArea)
                let opaqueBackground: UIColor = style == .dark ? .black : .white
                window.backgroundColor = opaqueBackground
                window.isOpaque = true
                window.overrideUserInterfaceStyle = style
                window.traitOverrides.preferredContentSizeCategory = category
                host.overrideUserInterfaceStyle = style
                host.traitOverrides.preferredContentSizeCategory = category
                root.view.backgroundColor = opaqueBackground
                host.view.backgroundColor = opaqueBackground
                root.addChild(host)
                root.view.addSubview(host.view)
                host.view.frame = CGRect(origin: .zero, size: variant.device.size)
                host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let traits = UITraitCollection { traits in
                    traits.userInterfaceIdiom = variant.device.idiom
                    traits.userInterfaceStyle = style
                    traits.preferredContentSizeCategory = category
                }
                root.setOverrideTraitCollection(traits, forChild: host)
                host.didMove(toParent: root)
                window.windowLevel = .statusBar + 1
                window.rootViewController = root
                window.makeKeyAndVisible()
                window.frame = CGRect(origin: .zero, size: variant.device.size)
                root.view.frame = window.bounds
                host.view.frame = root.view.bounds
                let coveredWindows = scene.windows.filter { $0 !== window }
                coveredWindows.forEach { $0.alpha = 0 }
                defer {
                    coveredWindows.forEach { $0.alpha = 1 }
                    window.isHidden = true
                    window.rootViewController = nil
                    window.windowScene = nil
                    previousKeyWindow?.makeKey()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                }
                // Let nav/search glass finish, then freeze. Disabling animations
                // before that first appearance captures both title layers at once.
                UIView.setAnimationsEnabled(true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.45))
                UIView.setAnimationsEnabled(false)
                root.view.layoutIfNeeded()
                host.view.layoutIfNeeded()
                CATransaction.flush()

                // Capture only after the mounted hierarchy has produced three
                // identical, non-ghosted frames.
                let earliestCapture = Date().addingTimeInterval(0.4)
                let deadline = Date().addingTimeInterval(6)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                let renderer = UIGraphicsImageRenderer(size: variant.device.size, format: format)
                var previousPixels: Data?
                var identicalFrames = 0
                var stableImage: UIImage?
                var lastRecognized = ""
                repeat {
                    root.view.setNeedsLayout()
                    root.view.layoutIfNeeded()
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    CATransaction.flush()
                    var rendered = false
                    let candidate = renderer.image { _ in
                        rendered = root.view.drawHierarchy(in: root.view.bounds, afterScreenUpdates: true)
                    }
                    guard rendered, let pixels = candidate.pngData() else {
                        identicalFrames = 0
                        previousPixels = nil
                        continue
                    }
                    identicalFrames = pixels == previousPixels ? identicalFrames + 1 : 1
                    previousPixels = pixels
                    guard Date() >= earliestCapture && identicalFrames >= 3 else { continue }
                    do {
                        lastRecognized = try historyRecognizedText(in: candidate)
                    } catch {
                        identicalFrames = 0
                        previousPixels = nil
                        continue
                    }
                    if historyCaptureLooksGhosted(lastRecognized) {
                        identicalFrames = 0
                        previousPixels = nil
                        continue
                    }
                    let normalized = normalizeHistoryText(lastRecognized)
                    guard !normalized.isEmpty,
                          expectedText.allSatisfy({ normalized.contains(normalizeHistoryText($0)) }) else {
                        continue
                    }
                    stableImage = candidate
                    break
                } while Date() < deadline
                guard let image = stableImage else {
                    XCTFail(
                        "History window did not reach three stable rendered frames. OCR: \(lastRecognized)",
                        file: file,
                        line: line
                    )
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

private func historyCaptureLooksGhosted(_ text: String) -> Bool {
    let words = text.split { !$0.isLetter }.map { String($0).lowercased() }.filter { $0.count >= 4 }
    return zip(words, words.dropFirst()).contains { $0 == $1 }
}

@MainActor
private final class HistorySnapshotWindow: UIWindow {
    private let snapshotInsets: UIEdgeInsets
    init(scene: UIWindowScene, size: CGSize, insets: UIEdgeInsets) {
        snapshotInsets = insets
        super.init(windowScene: scene)
        frame = CGRect(origin: .zero, size: size)
        isOpaque = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override var safeAreaInsets: UIEdgeInsets { snapshotInsets }
}
