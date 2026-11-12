import Social
import ImageIO
import Vision
import UniformTypeIdentifiers
import UIKit

/// Uses the system share composer. No automatic journal writes or containing-app
/// launch tricks: saved text enters Marble's existing editable review flow.
final class ShareViewController: SLComposeServiceViewController {
    private var loading = true
    private var loadError: String?
    private var attachmentText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Save to Marble"
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Save"
        placeholder = "Workout text to review in Marble"
        Task { @MainActor in
            do { attachmentText = try await readAttachments() }
            catch { loadError = error.localizedDescription }
            loading = false
            reloadConfigurationItems()
            validateContent()
        }
    }

    override func isContentValid() -> Bool {
        !loading && loadError == nil && !combinedText.isEmpty && combinedText.utf8.count <= SharedWorkoutInbox.maximumBytes
    }

    private var combinedText: String {
        let typed = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = attachmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed == attached { return typed }
        return [typed, attached].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    override func didSelectPost() {
        switch SharedWorkoutInbox.SharePosting.disposition(saving: { try SharedWorkoutInbox.save(text: combinedText) }) {
        case .completeRequest:
            extensionContext?.completeRequest(returningItems: nil)
        case .cancelRequest(let error):
            extensionContext?.cancelRequest(withError: error)
        }
    }

    override func configurationItems() -> [Any]! {
        let item = SLComposeSheetConfigurationItem()!
        item.title = loadError ?? (loading ? "Reading workout…" : "Review in Marble before logging")
        item.tapHandler = { [weak self] in
            if let error = self?.loadError { self?.showError(error) }
        }
        return [item]
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Couldn't save workout", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @MainActor
    private func readAttachments() async throws -> String {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard providers.count <= 5 else { throw SharedWorkoutInbox.InboxError.tooLarge }
        var parts: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? SharedWorkoutInbox.InboxError.empty) }
                    }
                }
                guard data.count <= SharedWorkoutInbox.maximumBytes,
                      let text = String(data: data, encoding: .utf8) else { throw SharedWorkoutInbox.InboxError.tooLarge }
                parts.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let url: URL = try await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { value, error in
                        if let url = value as? URL { continuation.resume(returning: url) }
                        else { continuation.resume(throwing: error ?? SharedWorkoutInbox.InboxError.empty) }
                    }
                }
                guard url.isFileURL,
                      ["txt", "csv", "md", "text"].contains(url.pathExtension.lowercased()) else { continue }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= SharedWorkoutInbox.maximumBytes else { throw SharedWorkoutInbox.InboxError.tooLarge }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: SharedWorkoutInbox.maximumBytes + 1) ?? Data()
                guard data.count <= SharedWorkoutInbox.maximumBytes, let text = String(data: data, encoding: .utf8) else { throw SharedWorkoutInbox.InboxError.tooLarge }
                parts.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                        do {
                            guard let url else { throw error ?? SharedWorkoutInbox.InboxError.empty }
                            let handle = try FileHandle(forReadingFrom: url)
                            defer { try? handle.close() }
                            let data = try handle.read(upToCount: 8_000_001) ?? Data()
                            guard data.count <= 8_000_000 else { throw SharedWorkoutInbox.InboxError.tooLarge }
                            continuation.resume(returning: data)
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                let text = try await Task.detached { try Self.recognizeImage(data) }.value
                parts.append(text)
            }
            if parts.joined(separator: "\n").utf8.count > SharedWorkoutInbox.maximumBytes { throw SharedWorkoutInbox.InboxError.tooLarge }
        }
        return parts.joined(separator: "\n")
    }
    private nonisolated static func recognizeImage(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { throw SharedWorkoutInbox.InboxError.empty }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard text.utf8.count <= SharedWorkoutInbox.maximumBytes else { throw SharedWorkoutInbox.InboxError.tooLarge }
        return text
    }

}
