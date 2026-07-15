#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO

struct ScreenshotStory: Decodable {
    let rawName: String
    let headline: String
    let supportingText: String
}

struct ScreenshotManifest: Decodable {
    let screenshots: [ScreenshotStory]
}

enum ComposerError: LocalizedError {
    case usage
    case unreadableImage(String)
    case unableToCreateCanvas(String)
    case unableToEncode(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: compose_app_store_screenshots.swift MANIFEST INPUT_DIR OUTPUT_DIR"
        case .unreadableImage(let path):
            return "Unable to read screenshot: \(path)"
        case .unableToCreateCanvas(let name):
            return "Unable to create RGB canvas for: \(name)"
        case .unableToEncode(let path):
            return "Unable to encode PNG: \(path)"
        }
    }
}

func centeredParagraph(lineSpacing: CGFloat = 0) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = lineSpacing
    return style
}

func compose(story: ScreenshotStory, inputURL: URL, outputURL: URL) throws {
    guard
        let source = NSImage(contentsOf: inputURL),
        let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw ComposerError.unreadableImage(inputURL.path)
    }

    let width = sourceCG.width
    let height = sourceCG.height
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else {
        throw ComposerError.unableToCreateCanvas(story.rawName)
    }
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let isTablet = CGFloat(width) / CGFloat(height) > 0.70
    let horizontalInset = CGFloat(width) * (isTablet ? 0.09 : 0.08)
    let screenshotWidth = CGFloat(width) - horizontalInset * 2
    let screenshotHeight = screenshotWidth * CGFloat(height) / CGFloat(width)
    let screenshotRect = NSRect(
        x: horizontalInset,
        y: CGFloat(height) * 0.018,
        width: screenshotWidth,
        height: screenshotHeight
    )
    let cornerRadius = CGFloat(width) * (isTablet ? 0.020 : 0.038)
    let screenshotPath = NSBezierPath(roundedRect: screenshotRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = CGFloat(width) * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(height) * 0.006)
    shadow.set()
    NSColor.white.setFill()
    screenshotPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    screenshotPath.addClip()
    NSImage(cgImage: sourceCG, size: NSSize(width: width, height: height)).draw(
        in: screenshotRect,
        from: NSRect(x: 0, y: 0, width: width, height: height),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
    screenshotPath.lineWidth = max(1, CGFloat(width) * 0.001)
    screenshotPath.stroke()

    let headlineSize = CGFloat(width) * (isTablet ? 0.037 : 0.050)
    let supportSize = CGFloat(width) * (isTablet ? 0.020 : 0.026)
    let textWidth = CGFloat(width) * 0.88
    let headlineRect = NSRect(
        x: (CGFloat(width) - textWidth) / 2,
        y: CGFloat(height) - CGFloat(height) * 0.105,
        width: textWidth,
        height: CGFloat(height) * 0.075
    )
    let supportRect = NSRect(
        x: (CGFloat(width) - textWidth) / 2,
        y: CGFloat(height) - CGFloat(height) * 0.155,
        width: textWidth,
        height: CGFloat(height) * 0.050
    )

    NSAttributedString(
        string: story.headline,
        attributes: [
            .font: NSFont.systemFont(ofSize: headlineSize, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: centeredParagraph(lineSpacing: headlineSize * 0.02)
        ]
    ).draw(with: headlineRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

    NSAttributedString(
        string: story.supportingText,
        attributes: [
            .font: NSFont.systemFont(ofSize: supportSize, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.28, alpha: 1),
            .paragraphStyle: centeredParagraph(lineSpacing: supportSize * 0.08)
        ]
    ).draw(with: supportRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

    NSGraphicsContext.restoreGraphicsState()

    guard
        let composedImage = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil)
    else {
        throw ComposerError.unableToEncode(outputURL.path)
    }
    CGImageDestinationAddImage(destination, composedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ComposerError.unableToEncode(outputURL.path)
    }
}

do {
    guard CommandLine.arguments.count == 4 else { throw ComposerError.usage }
    let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let manifest = try JSONDecoder().decode(ScreenshotManifest.self, from: Data(contentsOf: manifestURL))

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for story in manifest.screenshots.sorted(by: { $0.rawName < $1.rawName }) {
        let inputURL = inputDirectory.appendingPathComponent(story.rawName).appendingPathExtension("png")
        let outputURL = outputDirectory.appendingPathComponent(story.rawName).appendingPathExtension("png")
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: outputURL.path])
        }
        try compose(story: story, inputURL: inputURL, outputURL: outputURL)
        print("composed \(outputURL.path)")
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
