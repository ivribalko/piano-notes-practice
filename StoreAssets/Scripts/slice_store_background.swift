#!/usr/bin/env swift

import AppKit
import Foundation

let outputSize = NSSize(width: 1320, height: 2868)
let panoramaCapacity = 10
let requiredSliceCount = 7
// App Store Connect displays screenshot cards with a gutter between them. Skip
// the matching panorama width so objects continue at the correct visual offset
// instead of appearing as two adjacent, disconnected halves across that gap.
let galleryGutterWidth: CGFloat = 120

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let storeAssets = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let backgroundRoot = storeAssets.appendingPathComponent("Backgrounds", isDirectory: true)
let panoramaURL = backgroundRoot.appendingPathComponent("aurora-party-balloons-panorama.png")
let outputDirectory = backgroundRoot.appendingPathComponent("6.9-inch", isDirectory: true)

guard let panorama = NSImage(contentsOf: panoramaURL) else {
    fputs("Unable to load panorama: \(panoramaURL.path)\n", stderr)
    exit(EXIT_FAILURE)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let sourceWidth = panorama.size.height * outputSize.width / outputSize.height
let sourceStep = sourceWidth + galleryGutterWidth
let requiredSourceWidth = sourceWidth
    + CGFloat(requiredSliceCount - 1) * sourceStep

guard requiredSourceWidth <= panorama.size.width else {
    fputs("Panorama is not wide enough for the required slices and gallery gutters.\n", stderr)
    exit(EXIT_FAILURE)
}

let sequenceOriginX = (panorama.size.width - requiredSourceWidth) / 2

for index in 0..<requiredSliceCount {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(outputSize.width),
        pixelsHigh: Int(outputSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Unable to create background slice \(index + 1).\n", stderr)
        exit(EXIT_FAILURE)
    }

    let sourceX = sequenceOriginX + CGFloat(index) * sourceStep
    let sourceRect = NSRect(
        x: sourceX,
        y: 0,
        width: sourceWidth,
        height: panorama.size.height
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    panorama.draw(
        in: NSRect(origin: .zero, size: outputSize),
        from: sourceRect,
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Unable to encode background slice \(index + 1).\n", stderr)
        exit(EXIT_FAILURE)
    }

    let filename = String(format: "%02d-Aurora-Balloons.png", index + 1)
    let outputURL = outputDirectory.appendingPathComponent(filename)
    try data.write(to: outputURL, options: .atomic)
    print("Created \(outputURL.path)")
}
