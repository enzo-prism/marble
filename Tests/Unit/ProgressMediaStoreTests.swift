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
}
