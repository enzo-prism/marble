import Foundation
import SwiftData
import UniformTypeIdentifiers

enum ProgressMediaKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    init(contentType: UTType) {
        if contentType.conforms(to: .movie) {
            self = .video
        } else {
            self = .photo
        }
    }

    var displayName: String {
        switch self {
        case .photo:
            return "Photo"
        case .video:
            return "Video"
        }
    }

    var accessibilityName: String {
        switch self {
        case .photo:
            return "progress photo"
        case .video:
            return "progress video"
        }
    }

    var systemImage: String {
        switch self {
        case .photo:
            return "photo"
        case .video:
            return "video"
        }
    }

    var defaultFileExtension: String {
        switch self {
        case .photo:
            return "jpg"
        case .video:
            return "mov"
        }
    }
}

@Model
final class ProgressMediaAttachment {
    // `attachedToDate` backs the per-day media query on the calendar sheet;
    // `updatedAt` backs the O(1) latest-edit lookup for memo signatures.
    #Index<ProgressMediaAttachment>([\.attachedToDate], [\.updatedAt])
    @Attribute(.unique) var id: UUID
    var attachedToDate: Date
    var kindRaw: String
    var originalFilename: String
    var thumbnailFilename: String?
    var photoCropX: Double?
    var photoCropY: Double?
    var photoCropWidth: Double?
    var photoCropHeight: Double?
    var fileSizeBytes: Int64?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        attachedToDate: Date,
        kind: ProgressMediaKind,
        originalFilename: String,
        thumbnailFilename: String? = nil,
        photoCrop: ProgressPhotoCrop? = nil,
        fileSizeBytes: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.attachedToDate = attachedToDate
        self.kindRaw = kind.rawValue
        self.originalFilename = originalFilename
        self.thumbnailFilename = thumbnailFilename
        self.photoCropX = photoCrop?.x
        self.photoCropY = photoCrop?.y
        self.photoCropWidth = photoCrop?.width
        self.photoCropHeight = photoCrop?.height
        self.fileSizeBytes = fileSizeBytes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ProgressMediaAttachment {
    var kind: ProgressMediaKind {
        get { ProgressMediaKind(rawValue: kindRaw) ?? .photo }
        set { kindRaw = newValue.rawValue }
    }

    var photoCrop: ProgressPhotoCrop? {
        get {
            guard
                let photoCropX,
                let photoCropY,
                let photoCropWidth,
                let photoCropHeight
            else {
                return nil
            }
            return ProgressPhotoCrop(
                x: photoCropX,
                y: photoCropY,
                width: photoCropWidth,
                height: photoCropHeight
            )
        }
        set {
            photoCropX = newValue?.x
            photoCropY = newValue?.y
            photoCropWidth = newValue?.width
            photoCropHeight = newValue?.height
        }
    }
}
