import AVKit
import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ProgressMediaSection: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \ProgressMediaAttachment.createdAt, order: .reverse)
    private var attachments: [ProgressMediaAttachment]

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importError: String?

    private let calendar = Calendar.current

    var body: some View {
        Section {
            progressMediaControls
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .marbleRowInsets()

            if isImporting {
                HStack(spacing: MarbleSpacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Adding media")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                .frame(minHeight: 44, alignment: .leading)
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .marbleRowInsets()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Calendar.ProgressMedia.Importing")
            }

            if let importError {
                Text(importError)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                    .accessibilityIdentifier("Calendar.ProgressMedia.Error")
            }

            if !progressAttachments.isEmpty {
                ProgressMediaStrip(attachments: progressAttachments)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
            }

            if TestHooks.isUITesting && !TestHooks.isAccessibilityAudit {
                ProgressMediaTestControls(
                    addPhoto: { addTestMedia(.photo) },
                    addVideo: { addTestMedia(.video) }
                )
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .marbleRowInsets()
            }
        } header: {
            SectionHeaderView(title: "Progress")
        }
        .textCase(nil)
        .onChange(of: selectedItems) { _, items in
            importSelectedItems(items)
        }
    }

    @ViewBuilder
    private var progressMediaControls: some View {
        if progressAttachments.isEmpty {
            addMediaPicker(expandsHorizontally: true)
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                progressSummaryText
                addMediaPicker(expandsHorizontally: true)
            }
        } else {
            HStack(alignment: .center, spacing: MarbleSpacing.s) {
                progressSummaryText
                Spacer(minLength: MarbleSpacing.s)
                addMediaPicker(expandsHorizontally: false)
            }
        }
    }

    private var progressSummaryText: some View {
        Text(progressSummary)
            .font(MarbleTypography.rowSubtitle)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("Calendar.ProgressMedia.Summary")
    }

    private func addMediaPicker(expandsHorizontally: Bool) -> some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 8,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .automatic
        ) {
            Image(systemName: "plus")
                .frame(maxWidth: expandsHorizontally ? .infinity : nil)
                .accessibilityHidden(true)
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: expandsHorizontally, prominence: .standard))
        .disabled(isImporting)
        .accessibilityIdentifier("Calendar.ProgressMedia.Add")
        .accessibilityLabel("Add progress photo or video")
        .accessibilityHint("Choose photos or videos to attach to \(DateHelper.dayLabel(for: date)).")
    }

    private var progressAttachments: [ProgressMediaAttachment] {
        attachments
            .filter { calendar.isDate($0.attachedToDate, inSameDayAs: date) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var progressSummary: String {
        if progressAttachments.isEmpty {
            return "Attach physique progress photos or videos to this date."
        }
        let count = progressAttachments.count
        let itemLabel = count == 1 ? "item" : "items"
        return "\(count) progress \(itemLabel)"
    }

    @MainActor
    private func importSelectedItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        Task { @MainActor in
            isImporting = true
            importError = nil

            do {
                for item in items {
                    guard let pickedMedia = try await item.loadTransferable(type: PickedProgressMedia.self) else {
                        continue
                    }

                    defer {
                        try? FileManager.default.removeItem(at: pickedMedia.fileURL)
                    }

                    let contentType = preferredContentType(for: item, fallback: pickedMedia.contentType)
                    let kind = ProgressMediaKind(contentType: contentType)
                    let result = try ProgressMediaStore.importFile(
                        from: pickedMedia.fileURL,
                        contentType: contentType,
                        kind: kind
                    )
                    let attachment = ProgressMediaAttachment(
                        attachedToDate: calendar.startOfDay(for: date),
                        kind: result.kind,
                        originalFilename: result.originalFilename,
                        thumbnailFilename: result.thumbnailFilename,
                        fileSizeBytes: result.fileSizeBytes,
                        createdAt: AppEnvironment.now,
                        updatedAt: AppEnvironment.now
                    )
                    modelContext.insert(attachment)
                }

                try modelContext.save()
                selectedItems = []
            } catch {
                importError = "That media could not be added. Try another photo or video."
            }

            isImporting = false
        }
    }

    private func preferredContentType(for item: PhotosPickerItem, fallback: UTType) -> UTType {
        item.supportedContentTypes.first { contentType in
            contentType.conforms(to: .movie) || contentType.conforms(to: .image)
        } ?? fallback
    }

    @MainActor
    private func addTestMedia(_ kind: ProgressMediaKind) {
        do {
            let result = try ProgressMediaStore.makeTestImport(kind: kind)
            let attachment = ProgressMediaAttachment(
                attachedToDate: calendar.startOfDay(for: date),
                kind: result.kind,
                originalFilename: result.originalFilename,
                thumbnailFilename: result.thumbnailFilename,
                fileSizeBytes: result.fileSizeBytes,
                createdAt: AppEnvironment.now,
                updatedAt: AppEnvironment.now
            )
            modelContext.insert(attachment)
            try modelContext.save()
        } catch {
            importError = "The test media could not be added."
        }
    }
}

private struct ProgressMediaStrip: View {
    let attachments: [ProgressMediaAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MarbleSpacing.s) {
                ForEach(attachments) { attachment in
                    NavigationLink {
                        ProgressMediaDetailView(attachment: attachment)
                    } label: {
                        ProgressMediaTile(attachment: attachment)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Calendar.ProgressMedia.Item.\(attachment.kind.rawValue)")
                    .accessibilityLabel(accessibilityLabel(for: attachment))
                    .accessibilityHint("Opens this progress \(attachment.kind.displayName.lowercased()).")
                }
            }
            .padding(.vertical, MarbleSpacing.xxs)
        }
        .accessibilityIdentifier("Calendar.ProgressMedia.Scroll")
    }

    private func accessibilityLabel(for attachment: ProgressMediaAttachment) -> String {
        "\(attachment.kind.accessibilityName), \(DateHelper.dayLabel(for: attachment.attachedToDate))"
    }
}

private struct ProgressMediaTile: View {
    let attachment: ProgressMediaAttachment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ProgressMediaThumbnail(attachment: attachment)
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))

            if attachment.kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.backgroundColor(for: colorScheme))
                    .padding(7)
                    .background(
                        Circle()
                            .fill(Theme.primaryTextColor(for: colorScheme).opacity(0.88))
                    )
                    .padding(MarbleSpacing.xs)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    private let tileSize: CGFloat = 104
}

private struct ProgressMediaThumbnail: View {
    let attachment: ProgressMediaAttachment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = ProgressMediaStore.thumbnailImage(for: attachment) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.surfaceColor(for: colorScheme)
                    Image(systemName: attachment.kind.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
        )
    }
}

private struct ProgressMediaTestControls: View {
    let addPhoto: () -> Void
    let addVideo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: MarbleSpacing.xs) {
                    controls
                }
            } else {
                HStack(spacing: MarbleSpacing.xs) {
                    controls
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        Button("Add Test Photo", action: addPhoto)
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .standard))
            .accessibilityIdentifier("Calendar.ProgressMedia.AddTestPhoto")
            .accessibilityLabel("Add test progress photo")

        Button("Add Test Video", action: addVideo)
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .standard))
            .accessibilityIdentifier("Calendar.ProgressMedia.AddTestVideo")
            .accessibilityLabel("Add test progress video")
    }
}

struct ProgressMediaDetailView: View {
    let attachment: ProgressMediaAttachment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var player: AVPlayer?
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        List {
            Section {
                progressPreview
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
            }

            Section {
                ProgressMediaMetadataRow(title: "Type", value: attachment.kind.displayName)
                ProgressMediaMetadataRow(title: "Date", value: Formatters.day.string(from: attachment.attachedToDate))
                if let fileSize = formattedFileSize {
                    ProgressMediaMetadataRow(title: "Size", value: fileSize)
                }
            } header: {
                SectionHeaderView(title: "Details")
            }
            .textCase(nil)

            Section {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .standard))
                .accessibilityIdentifier("Calendar.ProgressMedia.Delete")
                .accessibilityLabel("Delete progress media")
            }
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .marbleRowInsets()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle(attachment.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .accessibilityIdentifier("Calendar.ProgressMedia.Detail")
        .confirmationDialog(
            "Delete this progress \(attachment.kind.displayName.lowercased())?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteAttachment()
            }
            .accessibilityIdentifier("Calendar.ProgressMedia.ConfirmDelete")

            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if attachment.kind == .video {
                player = AVPlayer(url: ProgressMediaStore.fileURL(for: attachment))
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var progressPreview: some View {
        switch attachment.kind {
        case .photo:
            ProgressMediaThumbnail(attachment: attachment)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                .accessibilityLabel("Progress photo preview")
        case .video:
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                            .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
                    )
                    .accessibilityLabel("Progress video player")
            } else {
                ProgressMediaThumbnail(attachment: attachment)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                    .accessibilityLabel("Progress video preview")
            }
        }
    }

    private var formattedFileSize: String? {
        guard let bytes = attachment.fileSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func deleteAttachment() {
        ProgressMediaStore.deleteFiles(for: attachment)
        modelContext.delete(attachment)
        try? modelContext.save()
        dismiss()
    }
}

private struct ProgressMediaMetadataRow: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
            Text(title)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Spacer(minLength: MarbleSpacing.s)
            Text(value)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .multilineTextAlignment(.trailing)
                .lineLimit(nil)
        }
        .frame(minHeight: 44)
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
        .marbleRowInsets()
    }
}

private struct PickedProgressMedia: Transferable {
    let fileURL: URL
    let contentType: UTType

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: false) { received in
            try Self(importing: received, contentType: .image)
        }
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: false) { received in
            try Self(importing: received, contentType: .movie)
        }
    }

    private init(importing received: ReceivedTransferredFile, contentType: UTType) throws {
        let fileExtension = received.file.pathExtension.isEmpty
            ? contentType.preferredFilenameExtension ?? "media"
            : received.file.pathExtension
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: received.file, to: destinationURL)
        self.fileURL = destinationURL
        self.contentType = contentType
    }
}
