import AVFoundation
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct ProgressPhotoCrop: Equatable {
    static let maximumZoom: Double = 4

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static func centeredSquare(for imageSize: CGSize) -> ProgressPhotoCrop {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return ProgressPhotoCrop(x: 0, y: 0, width: 1, height: 1)
        }

        let side = min(imageSize.width, imageSize.height)
        let rect = CGRect(
            x: (imageSize.width - side) / 2,
            y: (imageSize.height - side) / 2,
            width: side,
            height: side
        )
        return ProgressPhotoCrop(pixelRect: rect, imageSize: imageSize).clamped(to: imageSize)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(pixelRect: CGRect, imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            self.init(x: 0, y: 0, width: 1, height: 1)
            return
        }

        self.init(
            x: Double(pixelRect.minX / imageSize.width),
            y: Double(pixelRect.minY / imageSize.height),
            width: Double(pixelRect.width / imageSize.width),
            height: Double(pixelRect.height / imageSize.height)
        )
    }

    func pixelRect(in imageSize: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(x) * imageSize.width,
            y: CGFloat(y) * imageSize.height,
            width: CGFloat(width) * imageSize.width,
            height: CGFloat(height) * imageSize.height
        )
    }

    func clamped(to imageSize: CGSize) -> ProgressPhotoCrop {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return ProgressPhotoCrop(x: 0, y: 0, width: 1, height: 1)
        }

        let maxSide = min(imageSize.width, imageSize.height)
        let minSide = maxSide / CGFloat(Self.maximumZoom)
        let rect = pixelRect(in: imageSize)
        let proposedSide = min(rect.width, rect.height)
        let side = min(max(proposedSide, minSide), maxSide)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let origin = CGPoint(
            x: min(max(center.x - side / 2, 0), imageSize.width - side),
            y: min(max(center.y - side / 2, 0), imageSize.height - side)
        )

        return ProgressPhotoCrop(
            pixelRect: CGRect(origin: origin, size: CGSize(width: side, height: side)),
            imageSize: imageSize
        )
    }

    func translated(by translation: CGSize, viewportSide: CGFloat, imageSize: CGSize) -> ProgressPhotoCrop {
        guard viewportSide > 0 else { return clamped(to: imageSize) }

        let rect = pixelRect(in: imageSize)
        guard rect.width > 0 else { return clamped(to: imageSize) }

        let imageScale = viewportSide / rect.width
        let origin = CGPoint(
            x: rect.minX - translation.width / imageScale,
            y: rect.minY - translation.height / imageScale
        )
        let moved = CGRect(origin: origin, size: rect.size)
        return ProgressPhotoCrop(pixelRect: moved, imageSize: imageSize).clamped(to: imageSize)
    }

    func zoomed(by magnification: CGFloat, imageSize: CGSize) -> ProgressPhotoCrop {
        let zoom = zoomLevel(for: imageSize) * Double(magnification)
        return zoomed(to: zoom, imageSize: imageSize)
    }

    func zoomed(to zoom: Double, imageSize: CGSize) -> ProgressPhotoCrop {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return ProgressPhotoCrop(x: 0, y: 0, width: 1, height: 1)
        }

        let maxSide = min(imageSize.width, imageSize.height)
        let resolvedZoom = min(max(zoom, 1), Self.maximumZoom)
        let side = maxSide / resolvedZoom
        let rect = pixelRect(in: imageSize)
        let centered = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
        return ProgressPhotoCrop(pixelRect: centered, imageSize: imageSize).clamped(to: imageSize)
    }

    func zoomLevel(for imageSize: CGSize) -> Double {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let maxSide = min(imageSize.width, imageSize.height)
        let rect = clamped(to: imageSize).pixelRect(in: imageSize)
        guard rect.width > 0 else { return 1 }
        return min(max(maxSide / rect.width, 1), Self.maximumZoom)
    }
}

enum ProgressMediaStore {
    enum StoreError: Error {
        case originalPhotoMissing
        case unsupportedCropKind
        case thumbnailEncodingFailed
    }

    struct ImportResult {
        let kind: ProgressMediaKind
        let originalFilename: String
        let thumbnailFilename: String?
        let fileSizeBytes: Int64?
    }

    /// Copies the picked file into the store and renders its thumbnail. Async so the file
    /// copy, decode, and JPEG encode run on the global executor, never blocking the main
    /// thread mid-import (callers only hop back to the main actor to insert the model).
    static func importFile(from sourceURL: URL, contentType: UTType, kind: ProgressMediaKind) async throws -> ImportResult {
        try ensureDirectory()

        let id = UUID()
        let fileExtension = preferredFileExtension(for: sourceURL, contentType: contentType, kind: kind)
        let originalFilename = "\(id.uuidString).\(fileExtension)"
        let destinationURL = fileURL(named: originalFilename)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let thumbnailFilename = try await makeThumbnail(for: destinationURL, kind: kind, id: id)
        return ImportResult(
            kind: kind,
            originalFilename: originalFilename,
            thumbnailFilename: thumbnailFilename,
            fileSizeBytes: fileSizeBytes(for: destinationURL)
        )
    }

    static func makeTestImport(kind: ProgressMediaKind) throws -> ImportResult {
        try ensureDirectory()

        let id = UUID()
        let originalFilename = "\(id.uuidString).\(kind.defaultFileExtension)"
        let originalURL = fileURL(named: originalFilename)

        switch kind {
        case .photo:
            let image = makeTestImage(title: "PHOTO")
            try image.jpegData(compressionQuality: 0.86)?.write(to: originalURL, options: .atomic)
        case .video:
            try Data("Marble progress video fixture".utf8).write(to: originalURL, options: .atomic)
        }

        let thumbnailFilename = "\(id.uuidString)-thumb.jpg"
        let thumbnailURL = fileURL(named: thumbnailFilename)
        let thumbnail = makeTestImage(title: kind == .photo ? "PHOTO" : "VIDEO")
        try thumbnail.jpegData(compressionQuality: 0.82)?.write(to: thumbnailURL, options: .atomic)

        return ImportResult(
            kind: kind,
            originalFilename: originalFilename,
            thumbnailFilename: thumbnailFilename,
            fileSizeBytes: fileSizeBytes(for: originalURL)
        )
    }

    static func fileURL(for attachment: ProgressMediaAttachment) -> URL {
        fileURL(named: attachment.originalFilename)
    }

    static func thumbnailURL(for attachment: ProgressMediaAttachment) -> URL? {
        guard let thumbnailFilename = attachment.thumbnailFilename else { return nil }
        return fileURL(named: thumbnailFilename)
    }

    static func thumbnailImage(for attachment: ProgressMediaAttachment) -> UIImage? {
        thumbnailImage(
            kind: attachment.kind,
            originalFilename: attachment.originalFilename,
            thumbnailFilename: attachment.thumbnailFilename,
            photoCrop: attachment.photoCrop
        )
    }

    /// Value-based core so async callers can decode without carrying the SwiftData model
    /// across actors. Falls back to a downsampled decode of the original photo when no
    /// rendered thumbnail file exists yet.
    static func thumbnailImage(
        kind: ProgressMediaKind,
        originalFilename: String,
        thumbnailFilename: String?,
        photoCrop: ProgressPhotoCrop?
    ) -> UIImage? {
        if let thumbnailFilename,
           let image = UIImage(contentsOfFile: fileURL(named: thumbnailFilename).path) {
            return image
        }
        if kind == .photo {
            guard let image = downsampledImage(
                at: fileURL(named: originalFilename),
                maxPixelSize: thumbnailDecodeMaxPixelSize
            ) else {
                return nil
            }
            if let photoCrop {
                return thumbnailImage(from: image, crop: photoCrop)
            }
            return image
        }
        return nil
    }

    /// Async variant for view code: nonisolated, so the disk read and decode run on the
    /// global executor instead of blocking the main thread during scrolling.
    static func loadThumbnailImage(
        kind: ProgressMediaKind,
        originalFilename: String,
        thumbnailFilename: String?,
        photoCrop: ProgressPhotoCrop?
    ) async -> UIImage? {
        thumbnailImage(
            kind: kind,
            originalFilename: originalFilename,
            thumbnailFilename: thumbnailFilename,
            photoCrop: photoCrop
        )
    }

    static func originalImage(for attachment: ProgressMediaAttachment) -> UIImage? {
        guard attachment.kind == .photo else { return nil }
        return UIImage(contentsOfFile: fileURL(for: attachment).path)?.normalizedForProgressCrop()
    }

    /// Display copy of the original photo for the crop editor: full fidelity is not needed
    /// for on-screen crop framing (the saved thumbnail re-renders from the original on
    /// disk), so decode at a bounded size off the main actor.
    static func loadCropEditorImage(originalFilename: String) async -> UIImage? {
        downsampledImage(at: fileURL(named: originalFilename), maxPixelSize: cropEditorDecodeMaxPixelSize)
    }

    @MainActor
    static func updatePhotoThumbnail(for attachment: ProgressMediaAttachment, crop: ProgressPhotoCrop) async throws -> String {
        guard attachment.kind == .photo else {
            throw StoreError.unsupportedCropKind
        }
        return try await renderPhotoThumbnail(
            originalFilename: attachment.originalFilename,
            thumbnailFilename: attachment.thumbnailFilename ?? "\(attachment.id.uuidString)-thumb.jpg",
            crop: crop
        )
    }

    /// Re-renders the persisted square thumbnail from the full-resolution original.
    /// Nonisolated async: the decode + render + JPEG encode happen off the main actor.
    private static func renderPhotoThumbnail(
        originalFilename: String,
        thumbnailFilename: String,
        crop: ProgressPhotoCrop
    ) async throws -> String {
        guard let image = UIImage(contentsOfFile: fileURL(named: originalFilename).path)?.normalizedForProgressCrop() else {
            throw StoreError.originalPhotoMissing
        }
        guard let data = thumbnailImage(from: image, crop: crop).jpegData(compressionQuality: 0.82) else {
            throw StoreError.thumbnailEncodingFailed
        }

        try ensureDirectory()
        try data.write(to: fileURL(named: thumbnailFilename), options: .atomic)
        return thumbnailFilename
    }

    static func deleteFiles(for attachment: ProgressMediaAttachment) {
        try? FileManager.default.removeItem(at: fileURL(for: attachment))
        if let thumbnailURL = thumbnailURL(for: attachment) {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private static var directoryURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Marble", isDirectory: true)
            .appendingPathComponent("ProgressMedia", isDirectory: true)
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func fileURL(named filename: String) -> URL {
        directoryURL.appendingPathComponent(filename)
    }

    private static func preferredFileExtension(for sourceURL: URL, contentType: UTType, kind: ProgressMediaKind) -> String {
        let pathExtension = sourceURL.pathExtension
        if !pathExtension.isEmpty {
            return pathExtension.lowercased()
        }
        return contentType.preferredFilenameExtension ?? kind.defaultFileExtension
    }

    /// Pixel budget for thumbnail source decodes. Large enough that the 480pt square crop
    /// never upscales, small enough that a multi-megapixel photo is never fully decoded.
    private static let thumbnailDecodeMaxPixelSize: CGFloat = 1024

    /// Pixel budget for the crop editor's display copy — generous enough to frame a crop
    /// at maximum zoom on screen without decoding the full original.
    private static let cropEditorDecodeMaxPixelSize: CGFloat = 2400

    private static func makeThumbnail(for url: URL, kind: ProgressMediaKind, id: UUID) async throws -> String? {
        let thumbnail: UIImage?
        switch kind {
        case .photo:
            thumbnail = downsampledImage(at: url, maxPixelSize: thumbnailDecodeMaxPixelSize)
        case .video:
            thumbnail = await videoThumbnail(for: url)
        }

        guard let image = thumbnail?.defaultCroppedThumbnail(),
              let data = image.jpegData(compressionQuality: 0.82)
        else {
            return nil
        }

        let filename = "\(id.uuidString)-thumb.jpg"
        try data.write(to: fileURL(named: filename), options: .atomic)
        return filename
    }

    /// Decodes at most `maxPixelSize` pixels on the long edge via ImageIO, with EXIF
    /// orientation baked in — avoids materialising the full-resolution bitmap just to
    /// produce a thumbnail.
    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func videoThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailDecodeMaxPixelSize, height: thumbnailDecodeMaxPixelSize)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func fileSizeBytes(for url: URL) -> Int64? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    static func thumbnailImage(from image: UIImage, crop: ProgressPhotoCrop) -> UIImage {
        let targetSize = CGSize(width: 480, height: 480)
        let normalizedImage = image.normalizedForProgressCrop()
        let sourceSize = normalizedImage.size
        let cropRect = crop.clamped(to: sourceSize).pixelRect(in: sourceSize)
        let imageScale = targetSize.width / cropRect.width
        let drawRect = CGRect(
            x: -cropRect.minX * imageScale,
            y: -cropRect.minY * imageScale,
            width: sourceSize.width * imageScale,
            height: sourceSize.height * imageScale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            normalizedImage.draw(in: drawRect)
        }
    }

    private static func makeTestImage(title: String) -> UIImage {
        // Resolve against a fixed appearance: dynamic colors would otherwise follow the
        // simulator's ambient light/dark setting at fixture-creation time, making the
        // rendered fixture (and every snapshot containing it) machine-dependent. Dark
        // matches the committed snapshot baselines.
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        let background = UIColor.systemBackground.resolvedColor(with: traits)
        let foreground = UIColor.label.resolvedColor(with: traits)

        let size = CGSize(width: 360, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            foreground.setStroke()
            let border = UIBezierPath(roundedRect: CGRect(x: 22, y: 22, width: 316, height: 436), cornerRadius: 24)
            border.lineWidth = 8
            border.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: foreground,
                .paragraphStyle: paragraph
            ]
            NSString(string: title).draw(
                in: CGRect(x: 32, y: 206, width: 296, height: 68),
                withAttributes: attributes
            )
        }
    }
}

private extension UIImage {
    func normalizedForProgressCrop() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func defaultCroppedThumbnail() -> UIImage {
        ProgressMediaStore.thumbnailImage(
            from: self,
            crop: ProgressPhotoCrop.centeredSquare(for: size)
        )
    }
}
