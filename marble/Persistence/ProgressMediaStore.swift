import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

enum ProgressMediaStore {
    struct ImportResult {
        let kind: ProgressMediaKind
        let originalFilename: String
        let thumbnailFilename: String?
        let fileSizeBytes: Int64?
    }

    static func importFile(from sourceURL: URL, contentType: UTType, kind: ProgressMediaKind) throws -> ImportResult {
        try ensureDirectory()

        let id = UUID()
        let fileExtension = preferredFileExtension(for: sourceURL, contentType: contentType, kind: kind)
        let originalFilename = "\(id.uuidString).\(fileExtension)"
        let destinationURL = fileURL(named: originalFilename)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let thumbnailFilename = try makeThumbnail(for: destinationURL, kind: kind, id: id)
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
        if let thumbnailURL = thumbnailURL(for: attachment),
           let image = UIImage(contentsOfFile: thumbnailURL.path) {
            return image
        }
        if attachment.kind == .photo {
            return UIImage(contentsOfFile: fileURL(for: attachment).path)
        }
        return nil
    }

    static func deleteFiles(for attachment: ProgressMediaAttachment) {
        try? FileManager.default.removeItem(at: fileURL(for: attachment))
        if let thumbnailURL = thumbnailURL(for: attachment) {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
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

    private static func makeThumbnail(for url: URL, kind: ProgressMediaKind, id: UUID) throws -> String? {
        let thumbnail: UIImage?
        switch kind {
        case .photo:
            thumbnail = UIImage(contentsOfFile: url.path)
        case .video:
            thumbnail = videoThumbnail(for: url)
        }

        guard let image = thumbnail?.croppedThumbnail(),
              let data = image.jpegData(compressionQuality: 0.82)
        else {
            return nil
        }

        let filename = "\(id.uuidString)-thumb.jpg"
        try data.write(to: fileURL(named: filename), options: .atomic)
        return filename
    }

    private static func videoThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
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

    private static func makeTestImage(title: String) -> UIImage {
        let size = CGSize(width: 360, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.label.setStroke()
            let border = UIBezierPath(roundedRect: CGRect(x: 22, y: 22, width: 316, height: 436), cornerRadius: 24)
            border.lineWidth = 8
            border.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor.label,
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
    func croppedThumbnail() -> UIImage {
        let targetSize = CGSize(width: 480, height: 480)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            let scale = max(targetSize.width / size.width, targetSize.height / size.height)
            let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2
            )
            draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}
