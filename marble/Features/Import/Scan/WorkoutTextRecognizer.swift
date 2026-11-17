import CoreGraphics
import CryptoKit
import Foundation
import Vision

/// Reads text out of a captured image. Abstracted so the scan view model can be
/// driven by a stub in tests without touching the Vision framework.
protocol WorkoutTextRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> String
}

/// On-device OCR via the Vision framework. Everything stays on device — no
/// network, consistent with Marble's local-only privacy posture.
///
/// Prefers iOS 26's structured `RecognizeDocumentsRequest`, which understands
/// tables and paragraphs: a program grid ("Bench | 3 | 8 | 185") keeps each row on
/// one line instead of being scattered cell by cell, which is what the workout
/// parser needs. Falls back to the line-based `VNRecognizeTextRequest` (accurate,
/// language-corrected, handwriting-capable) when the document request throws or
/// reads nothing.
nonisolated struct VisionWorkoutTextRecognizer: WorkoutTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> String {
        if let structured = try? await Self.recognizeDocument(in: image),
           !structured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return structured
        }
        return try await Self.recognizeLines(in: image)
    }

    static func recognizeDocument(in image: CGImage) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        let observations = try await request.perform(on: image)
        let blocks = observations.flatMap { DocumentTextLayout.blocks(from: $0.document) }
        return DocumentTextLayout.lines(from: blocks).joined(separator: "\n")
    }

    static func recognizeLines(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Turns a recognized document into parser-ready lines. The assembly is a pure
/// function over plain values so it is unit-testable without Vision.
nonisolated enum DocumentTextLayout {
    struct Cell: Equatable, Sendable {
        /// First row/column the cell occupies. A spanning cell is emitted once,
        /// in its first row.
        var row: Int
        var column: Int
        var text: String
    }

    enum Content: Equatable, Sendable {
        /// Paragraph (or title) lines in Vision's reading order.
        case text([String])
        /// List items in order.
        case list([String])
        case table([Cell])
    }

    struct Block: Equatable, Sendable {
        var content: Content
        /// Normalized bounds with Vision's lower-left origin (larger `maxY` is
        /// higher on the page).
        var bounds: CGRect
    }

    /// Lines in reading order:
    ///   • a table emits one line per row, its cells joined with spaces in column order;
    ///   • a list emits one line per item;
    ///   • paragraphs emit their lines in Vision's reading order.
    /// Structured containers win over paragraphs that overlap them, so text Vision
    /// reports both as a paragraph and as a table/list is not read twice. Tables and
    /// lists are placed before the first paragraph that starts below their top edge.
    static func lines(from blocks: [Block]) -> [String] {
        let structured = blocks.filter { if case .text = $0.content { return false }; return true }
        var paragraphs: [Block] = []
        for block in blocks {
            guard case .text(let lines) = block.content else { continue }
            let center = CGPoint(x: block.bounds.midX, y: block.bounds.midY)
            if structured.contains(where: { $0.bounds.contains(center) }) { continue }
            // A title Vision also reports as a paragraph would otherwise repeat.
            if paragraphs.contains(where: {
                guard case .text(let kept) = $0.content else { return false }
                return kept == lines && $0.bounds.contains(center)
            }) { continue }
            paragraphs.append(block)
        }

        var ordered: [Block] = []
        var pending = structured.sorted { $0.bounds.maxY > $1.bounds.maxY }
        for paragraph in paragraphs {
            while let next = pending.first, next.bounds.maxY > paragraph.bounds.maxY {
                ordered.append(next)
                pending.removeFirst()
            }
            ordered.append(paragraph)
        }
        ordered.append(contentsOf: pending)

        return ordered.flatMap { block -> [String] in
            switch block.content {
            case .text(let lines), .list(let lines):
                return lines.map(clean).filter { !$0.isEmpty }
            case .table(let cells):
                return tableRows(cells)
            }
        }
    }

    /// One line per table row: the row's cells in column order, joined with spaces.
    static func tableRows(_ cells: [Cell]) -> [String] {
        var seen = Set<[Int]>()
        let unique = cells.filter { seen.insert([$0.row, $0.column]).inserted }
        let rows = Dictionary(grouping: unique, by: \.row)
        return rows.keys.sorted().compactMap { row in
            let text = (rows[row] ?? [])
                .sorted { $0.column < $1.column }
                .map { clean($0.text) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return text.isEmpty ? nil : text
        }
    }

    /// Collapses a multi-line cell or line into single-spaced text.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func blocks(from document: DocumentObservation.Container) -> [Block] {
        var blocks: [Block] = []
        if let title = document.title {
            blocks.append(Block(content: .text(lines(of: title)), bounds: title.boundingRegion.boundingBox.cgRect))
        }
        for paragraph in document.paragraphs {
            blocks.append(Block(content: .text(lines(of: paragraph)), bounds: paragraph.boundingRegion.boundingBox.cgRect))
        }
        for list in document.lists {
            blocks.append(Block(content: .list(list.items.map(\.itemString)), bounds: list.boundingRegion.boundingBox.cgRect))
        }
        for table in document.tables {
            let cells = table.rows.flatMap { $0 }.map { cell in
                Cell(row: cell.rowRange.lowerBound, column: cell.columnRange.lowerBound, text: cell.content.text.transcript)
            }
            blocks.append(Block(content: .table(cells), bounds: table.boundingRegion.boundingBox.cgRect))
        }
        if blocks.isEmpty, !document.text.transcript.isEmpty {
            blocks.append(Block(content: .text(lines(of: document.text)), bounds: document.text.boundingRegion.boundingBox.cgRect))
        }
        return blocks
    }

    private static func lines(of text: DocumentObservation.Container.Text) -> [String] {
        let lines = text.lines.map(\.transcript)
        return lines.isEmpty ? text.transcript.components(separatedBy: .newlines) : lines
    }
}

/// Stable content identity for a captured image, used as the scan's dedup key so
/// importing the identical photo twice is a no-op.
nonisolated enum WorkoutScanImageHash {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
