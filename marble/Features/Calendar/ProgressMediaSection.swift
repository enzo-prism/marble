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

    /// Scoped to this section's single day at init: the store does the
    /// filtering (instead of fetching every attachment ever and filtering
    /// per body pass), so a years-deep media library costs this sheet nothing.
    @Query private var attachments: [ProgressMediaAttachment]

    init(date: Date) {
        self.date = date
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        _attachments = Query(
            filter: #Predicate<ProgressMediaAttachment> {
                $0.attachedToDate >= dayStart && $0.attachedToDate < dayEnd
            },
            sort: \ProgressMediaAttachment.createdAt,
            order: .reverse
        )
    }

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

    /// The day-scoped query already filters and sorts; no per-body work left.
    private var progressAttachments: [ProgressMediaAttachment] {
        attachments
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
                    let result = try await ProgressMediaStore.importFile(
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
                .id(attachment.updatedAt)
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
    @State private var image: UIImage?

    /// Async-loaded thumbnail, except in deterministic test renders (snapshots capture
    /// synchronously and would otherwise pin the placeholder frame) where it decodes inline —
    /// the same gating used for decorative motion.
    private var displayImage: UIImage? {
        if let image { return image }
        if TestHooks.reduceDecorativeMotion {
            return ProgressMediaStore.thumbnailImage(for: attachment)
        }
        return nil
    }

    var body: some View {
        Group {
            if let image = displayImage {
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
        .task(id: attachment.updatedAt) {
            // Read the model's values on the main actor, then decode off it.
            let kind = attachment.kind
            let originalFilename = attachment.originalFilename
            let thumbnailFilename = attachment.thumbnailFilename
            let photoCrop = attachment.photoCrop
            image = await ProgressMediaStore.loadThumbnailImage(
                kind: kind,
                originalFilename: originalFilename,
                thumbnailFilename: thumbnailFilename,
                photoCrop: photoCrop
            )
        }
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
    @State private var isCropEditorPresented = false
    @State private var cropError: String?

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

            if attachment.kind == .photo {
                Section {
                    Button {
                        isCropEditorPresented = true
                    } label: {
                        Label("Edit Crop", systemImage: "crop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .standard))
                    .accessibilityIdentifier("Calendar.ProgressMedia.EditCrop")
                    .accessibilityLabel("Edit progress photo crop")

                    if let cropError {
                        Text(cropError)
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Error")
                    }
                } header: {
                    SectionHeaderView(title: "Photo")
                }
                .textCase(nil)
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .marbleRowInsets()
            }

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
        .sheet(isPresented: $isCropEditorPresented) {
            NavigationStack {
                ProgressPhotoCropEditorLoader(
                    attachment: attachment,
                    onSave: savePhotoCrop
                )
            }
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
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
                .id(attachment.updatedAt)
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

    private func savePhotoCrop(_ crop: ProgressPhotoCrop) async throws {
        do {
            let thumbnailFilename = try await ProgressMediaStore.updatePhotoThumbnail(for: attachment, crop: crop)
            attachment.thumbnailFilename = thumbnailFilename
            attachment.photoCrop = crop
            attachment.updatedAt = AppEnvironment.now
            try modelContext.save()
            cropError = nil
        } catch {
            cropError = "The crop could not be saved. Try again."
            throw error
        }
    }

    private func deleteAttachment() {
        ProgressMediaStore.deleteFiles(for: attachment)
        modelContext.delete(attachment)
        try? modelContext.save()
        dismiss()
    }
}

/// Loads the editor's display copy of the photo off the main actor before showing the
/// crop editor, so opening the sheet never blocks on a synchronous full-size decode.
private struct ProgressPhotoCropEditorLoader: View {
    let attachment: ProgressMediaAttachment
    let onSave: (ProgressPhotoCrop) async throws -> Void

    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let image {
                ProgressPhotoCropEditor(
                    attachment: attachment,
                    image: image,
                    onSave: onSave
                )
            } else if didFinishLoading {
                ProgressPhotoCropUnavailableView()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard attachment.kind == .photo else {
                didFinishLoading = true
                return
            }
            let originalFilename = attachment.originalFilename
            image = await ProgressMediaStore.loadCropEditorImage(originalFilename: originalFilename)
            didFinishLoading = true
        }
    }
}

private struct ProgressPhotoCropEditor: View {
    let attachment: ProgressMediaAttachment
    let image: UIImage
    let onSave: (ProgressPhotoCrop) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var crop: ProgressPhotoCrop
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        attachment: ProgressMediaAttachment,
        image: UIImage,
        onSave: @escaping (ProgressPhotoCrop) async throws -> Void
    ) {
        self.attachment = attachment
        self.image = image
        self.onSave = onSave

        let initialCrop = attachment.photoCrop ?? ProgressPhotoCrop.centeredSquare(for: image.size)
        _crop = State(initialValue: initialCrop.clamped(to: image.size))
    }

    var body: some View {
        VStack(spacing: MarbleSpacing.m) {
            ProgressPhotoCropCanvas(image: image, crop: $crop)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 560)
                .padding(.top, MarbleSpacing.m)

            cropControls

            if let saveError {
                Text(saveError)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("Calendar.ProgressMedia.Crop.SaveError")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, MarbleLayout.pagePadding)
        .padding(.bottom, MarbleSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Edit Crop")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Cancel")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveCrop()
                }
                .fontWeight(.semibold)
                .disabled(isSaving)
                .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Save")
            }
        }
        // Without `.contain`, the identifier is pushed down onto every descendant
        // (clobbering Crop.Reset / Crop.Zoom on iOS 26), instead of naming this container.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Editor")
    }

    private var cropControls: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .center, spacing: MarbleSpacing.s) {
                Text("Zoom")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Spacer(minLength: MarbleSpacing.s)

                Button("Reset") {
                    crop = ProgressPhotoCrop.centeredSquare(for: image.size)
                    saveError = nil
                }
                .buttonStyle(MarbleActionButtonStyle(prominence: .standard))
                .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Reset")
            }

            HStack(spacing: MarbleSpacing.s) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { crop.zoomLevel(for: image.size) },
                        set: { crop = crop.zoomed(to: $0, imageSize: image.size) }
                    ),
                    in: 1...ProgressPhotoCrop.maximumZoom
                )
                .tint(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Zoom")
                .accessibilityLabel("Progress photo crop zoom")

                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }
        }
        .padding(MarbleSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .fill(Theme.surfaceColor(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
        )
    }

    private func saveCrop() {
        isSaving = true
        saveError = nil

        Task {
            do {
                try await onSave(crop.clamped(to: image.size))
                dismiss()
            } catch {
                isSaving = false
                saveError = "The crop could not be saved. Try again."
            }
        }
    }
}

private struct ProgressPhotoCropCanvas: View {
    let image: UIImage
    @Binding var crop: ProgressPhotoCrop

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragStartCrop: ProgressPhotoCrop?
    @State private var magnificationStartCrop: ProgressPhotoCrop?

    var body: some View {
        GeometryReader { proxy in
            let viewportSide = min(proxy.size.width, proxy.size.height)
            let resolvedCrop = crop.clamped(to: image.size)

            ZStack {
                Theme.controlFillColor(for: colorScheme)

                Image(uiImage: ProgressMediaStore.thumbnailImage(from: image, crop: resolvedCrop))
                    .resizable()
                    .scaledToFill()

                ProgressPhotoCropGrid()
            }
            .frame(width: viewportSide, height: viewportSide)
            .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                    .stroke(Theme.primaryTextColor(for: colorScheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(viewportSide: viewportSide))
            .simultaneousGesture(magnificationGesture())
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress photo crop")
        .accessibilityHint("Adjusts the visible crop for this progress photo.")
        .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Canvas")
    }

    private func dragGesture(viewportSide: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartCrop == nil {
                    dragStartCrop = crop
                }
                crop = (dragStartCrop ?? crop).translated(
                    by: value.translation,
                    viewportSide: viewportSide,
                    imageSize: image.size
                )
            }
            .onEnded { _ in
                dragStartCrop = nil
            }
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnificationStartCrop == nil {
                    magnificationStartCrop = crop
                }
                crop = (magnificationStartCrop ?? crop).zoomed(
                    by: value,
                    imageSize: image.size
                )
            }
            .onEnded { _ in
                magnificationStartCrop = nil
            }
    }
}

private struct ProgressPhotoCropGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let path = gridPath(width: width, height: height)

            path
                .stroke(.black.opacity(0.35), lineWidth: 2)
                .overlay(
                    path.stroke(.white.opacity(0.72), lineWidth: 1)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func gridPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for index in 1...2 {
                let fraction = CGFloat(index) / 3
                let x = width * fraction
                let y = height * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
    }
}

private struct ProgressPhotoCropUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: MarbleSpacing.m) {
            Image(systemName: "photo")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityHidden(true)

            Text("Photo unavailable")
                .font(MarbleTypography.emptyTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            Button("Done") {
                dismiss()
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .standard))
            .accessibilityIdentifier("Calendar.ProgressMedia.Crop.UnavailableDone")
        }
        .padding(MarbleLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Edit Crop")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .accessibilityIdentifier("Calendar.ProgressMedia.Crop.Unavailable")
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
