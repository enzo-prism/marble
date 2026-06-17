import CoreImage
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import marble

final class ProgressMediaStoreTests: XCTestCase {
    func testProgressMediaKindFollowsContentType() {
        XCTAssertEqual(ProgressMediaKind(contentType: .movie), .video)
        XCTAssertEqual(ProgressMediaKind(contentType: .mpeg4Movie), .video)
        XCTAssertEqual(ProgressMediaKind(contentType: .jpeg), .photo)
    }

    func testTestImportsCreateDurableFilesAndThumbnails() throws {
        let date = Date(timeIntervalSince1970: 1_735_732_800)

        let photoResult = try ProgressMediaStore.makeTestImport(kind: .photo)
        let photo = ProgressMediaAttachment(
            attachedToDate: date,
            kind: photoResult.kind,
            originalFilename: photoResult.originalFilename,
            thumbnailFilename: photoResult.thumbnailFilename,
            fileSizeBytes: photoResult.fileSizeBytes
        )

        let videoResult = try ProgressMediaStore.makeTestImport(kind: .video)
        let video = ProgressMediaAttachment(
            attachedToDate: date,
            kind: videoResult.kind,
            originalFilename: videoResult.originalFilename,
            thumbnailFilename: videoResult.thumbnailFilename,
            fileSizeBytes: videoResult.fileSizeBytes
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: ProgressMediaStore.fileURL(for: photo).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProgressMediaStore.fileURL(for: video).path))
        XCTAssertNotNil(ProgressMediaStore.thumbnailImage(for: photo))
        XCTAssertNotNil(ProgressMediaStore.thumbnailImage(for: video))

        ProgressMediaStore.deleteFiles(for: photo)
        ProgressMediaStore.deleteFiles(for: video)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ProgressMediaStore.fileURL(for: photo).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProgressMediaStore.fileURL(for: video).path))
    }

    func testPhotoCropUpdateRewritesThumbnailFromOriginalImage() async throws {
        let sourceImage = makeSplitColorImage()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let sourceData = try XCTUnwrap(sourceImage.pngData())
        try sourceData.write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result = try await ProgressMediaStore.importFile(from: sourceURL, contentType: .png, kind: .photo)
        let attachment = ProgressMediaAttachment(
            attachedToDate: Date(timeIntervalSince1970: 1_735_732_800),
            kind: result.kind,
            originalFilename: result.originalFilename,
            thumbnailFilename: result.thumbnailFilename,
            fileSizeBytes: result.fileSizeBytes
        )
        defer { ProgressMediaStore.deleteFiles(for: attachment) }

        let topCrop = ProgressPhotoCrop(x: 0, y: 0, width: 1, height: 0.5)
        attachment.thumbnailFilename = try await ProgressMediaStore.updatePhotoThumbnail(for: attachment, crop: topCrop)
        attachment.photoCrop = topCrop
        let topAverage = try averageColor(of: XCTUnwrap(ProgressMediaStore.thumbnailImage(for: attachment)))

        let bottomCrop = ProgressPhotoCrop(x: 0, y: 0.5, width: 1, height: 0.5)
        attachment.thumbnailFilename = try await ProgressMediaStore.updatePhotoThumbnail(for: attachment, crop: bottomCrop)
        attachment.photoCrop = bottomCrop
        let bottomAverage = try averageColor(of: XCTUnwrap(ProgressMediaStore.thumbnailImage(for: attachment)))

        XCTAssertGreaterThan(topAverage.red, topAverage.blue)
        XCTAssertGreaterThan(bottomAverage.blue, bottomAverage.red)
        XCTAssertEqual(attachment.photoCrop, bottomCrop)
    }

    private func makeSplitColorImage() -> UIImage {
        let size = CGSize(width: 120, height: 240)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
        }
    }

    private func averageColor(of image: UIImage) throws -> (red: CGFloat, blue: CGFloat) {
        let ciImage = try XCTUnwrap(CIImage(image: image))
        let filter = try XCTUnwrap(CIFilter(name: "CIAreaAverage"))
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        let outputImage = try XCTUnwrap(filter.outputImage)
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (red: CGFloat(bitmap[0]) / 255, blue: CGFloat(bitmap[2]) / 255)
    }
}
