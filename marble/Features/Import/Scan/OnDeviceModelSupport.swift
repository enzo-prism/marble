import CoreGraphics
import Foundation
import ImageIO

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Model version

/// Which on-device model is answering. iOS 27 ships new system models
/// (`SystemLanguageModel.Variant` `.core3` / `.coreAdvanced3`) with larger
/// context windows and, on some devices, image input; iOS 26 has one base
/// model. Diagnostics, the live eval and the input budget key off this.
nonisolated struct OnDeviceModelVersion: Equatable, Sendable {
    nonisolated enum Kind: String, Equatable, Sendable, CaseIterable {
        /// The single iOS 26 system model (4,096-token context, text only).
        case base26
        /// iOS 27 Apple Foundation Model 3, Core.
        case core3
        /// iOS 27 Apple Foundation Model 3, Core Advanced.
        case coreAdvanced3
        /// A variant this build doesn't know by name.
        case other
    }

    static let iOS26BaseModelName = "iOS 26 base model"

    var kind: Kind
    var displayName: String
    var contextSize: Int
    var supportsVision: Bool

    /// One line for logs and the live-eval report.
    var summary: String {
        "\(displayName) · \(contextSize)-token context\(supportsVision ? " · image input" : "")"
    }

    /// Reads the system model. Cheap: no model call, no asset load.
    static var current: OnDeviceModelVersion {
        #if canImport(FoundationModels)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let model = SystemLanguageModel.default
            let variant = model.variant
            let kind: Kind
            if variant == .core3 {
                kind = .core3
            } else if variant == .coreAdvanced3 {
                kind = .coreAdvanced3
            } else {
                kind = .other
            }
            let name = variant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return OnDeviceModelVersion(
                kind: kind,
                displayName: name.isEmpty ? kind.rawValue : name,
                contextSize: model.contextSize,
                supportsVision: model.capabilities.contains(.vision)
            )
        }
        #endif
        if #available(iOS 26.0, *) {
            return OnDeviceModelVersion(
                kind: .base26,
                displayName: iOS26BaseModelName,
                contextSize: SystemLanguageModel.default.contextSize,
                supportsVision: false
            )
        }
        #endif
        return OnDeviceModelVersion(kind: .base26, displayName: iOS26BaseModelName, contextSize: 4096, supportsVision: false)
    }
}

// MARK: - Availability copy

/// `SystemLanguageModel.Availability` flattened into what the UI needs to say.
/// Copy branches on the actual reason instead of one generic line: an
/// ineligible iPhone, a model still downloading, and Apple Intelligence being
/// off are different situations with different (or no) user actions.
nonisolated enum ModelAvailabilityStatus: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown

    static var current: ModelAvailabilityStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return ModelAvailabilityStatus(SystemLanguageModel.default.availability)
        }
        #endif
        return .unknown
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: self = .deviceNotEligible
            case .appleIntelligenceNotEnabled: self = .appleIntelligenceNotEnabled
            case .modelNotReady: self = .modelNotReady
            @unknown default: self = .unknown
            }
        }
    }
    #endif

    /// iOS 27 removed the switch that turns Apple Intelligence off, so copy
    /// must never send an iOS 27 user to Settings to turn it on.
    static var canTurnOnAppleIntelligence: Bool {
        if #available(iOS 27.0, *) { return false }
        return true
    }

    /// The privacy / availability line under the workout editor.
    func privacyCaption(canTurnOnAppleIntelligence: Bool = Self.canTurnOnAppleIntelligence) -> String {
        switch self {
        case .available:
            return "Read on your device with Apple Intelligence — nothing is uploaded."
        case .appleIntelligenceNotEnabled where canTurnOnAppleIntelligence:
            return "Turn on Apple Intelligence in Settings to read prose. Gym notation still works on device — nothing is uploaded."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence isn't ready on this iPhone yet. Gym notation still works on device — nothing is uploaded."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Gym notation still works on device — nothing is uploaded."
        case .deviceNotEligible:
            return "This iPhone doesn't support Apple Intelligence. Gym notation still works on device — nothing is uploaded."
        case .unknown:
            return "Read on your device — nothing is uploaded."
        }
    }

    /// Why only notation was read, for a parse whose model reading was
    /// unavailable. nil when the reason isn't an availability state (a
    /// cool-down after a failure, for example) so the caller keeps its
    /// generic copy.
    func unavailableNote(canTurnOnAppleIntelligence: Bool = Self.canTurnOnAppleIntelligence) -> String? {
        switch self {
        case .deviceNotEligible:
            return "This iPhone doesn't support Apple Intelligence, so only gym notation was read."
        case .appleIntelligenceNotEnabled where canTurnOnAppleIntelligence:
            return "Apple Intelligence is turned off, so only gym notation was read. Turn it on in Settings to read prose."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence isn't ready on this iPhone yet, so only gym notation was read."
        case .modelNotReady:
            return "Apple Intelligence is still downloading, so only gym notation was read. Try again once it's ready."
        case .available, .unknown:
            return nil
        }
    }
}

// MARK: - Page images

/// One captured notebook page, kept alongside its OCR so an iOS 27 model with
/// image input can see the layout. The OCR text stays authoritative; the image
/// only disambiguates rows, columns, crossed-out or checked sets, and
/// handwriting. Nothing here leaves the device.
nonisolated struct WorkoutScanPageImage: Sendable {
    var cgImage: CGImage
    var orientation: CGImagePropertyOrientation

    init(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.cgImage = cgImage
        self.orientation = orientation
    }

    /// Longest edge sent to the model. A phone photo is 4,000+ px; the model
    /// needs layout, not pixels, and every pixel costs tokens and latency.
    static let maximumModelDimension = 1024
    /// Pages attached to one request. More pages than this are read from OCR
    /// alone rather than overflowing the context window with images.
    static let maximumModelPages = 3

    /// Size that fits `maxDimension` on the longest edge, aspect preserved,
    /// never upscaled.
    static func scaledSize(width: Int, height: Int, maxDimension: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxDimension > 0 else { return (0, 0) }
        let longest = max(width, height)
        guard longest > maxDimension else { return (width, height) }
        let scale = Double(maxDimension) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// A copy no larger than `maxDimension` on its longest edge; nil when the
    /// image can't be redrawn (the page is then read from OCR alone).
    func downscaled(maxDimension: Int = Self.maximumModelDimension) -> WorkoutScanPageImage? {
        let size = Self.scaledSize(width: cgImage.width, height: cgImage.height, maxDimension: maxDimension)
        guard size.width > 0, size.height > 0 else { return nil }
        if size.width == cgImage.width, size.height == cgImage.height { return self }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else { return nil }
        return WorkoutScanPageImage(cgImage: scaled, orientation: orientation)
    }

    /// The pages worth attaching: at most `maximumModelPages`, each downscaled.
    static func modelReady(_ pages: [WorkoutScanPageImage]) -> [WorkoutScanPageImage] {
        guard pages.count <= maximumModelPages else { return [] }
        return pages.compactMap { $0.downscaled() }
    }
}
