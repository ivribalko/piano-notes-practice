#!/usr/bin/env swift

import AppKit
import Foundation

/// Describes one Store screenshot, its panorama background, and its headline.
struct StoreScreenshotComposition {
    let screenshotName: String
    let backgroundName: String
    let headline: String
}

let compositions = [
    StoreScreenshotComposition(
        screenshotName: "01-Practice-Highlighted-C.png",
        backgroundName: "01-Aurora-Balloons.png",
        headline: "Practice by Playing"
    ),
    StoreScreenshotComposition(
        screenshotName: "02-Practice-Cue-Sounds.png",
        backgroundName: "02-Aurora-Balloons.png",
        headline: "Practice by Ear"
    ),
    StoreScreenshotComposition(
        screenshotName: "03-Practice-MIDI.png",
        backgroundName: "03-Aurora-Balloons.png",
        headline: "Practice with MIDI"
    ),
    StoreScreenshotComposition(
        screenshotName: "04-Practice-Dark-Mode.png",
        backgroundName: "04-Aurora-Balloons.png",
        headline: "Practice in Dark Mode"
    ),
    StoreScreenshotComposition(
        screenshotName: "05-Progress.png",
        backgroundName: "05-Aurora-Balloons.png",
        headline: "Track Your Progress"
    ),
    StoreScreenshotComposition(
        screenshotName: "06-Settings-Practice-Display.png",
        backgroundName: "06-Aurora-Balloons.png",
        headline: "Choose What You See"
    ),
    StoreScreenshotComposition(
        screenshotName: "07-Settings-Practice-Cue.png",
        backgroundName: "07-Aurora-Balloons.png",
        headline: "Choose What You Practice"
    ),
]

let canvasSize = NSSize(width: 1320, height: 2868)
let screenshotWidth: CGFloat = 1020
let screenshotHeight = screenshotWidth * canvasSize.height / canvasSize.width
let screenshotRect = NSRect(
    x: (canvasSize.width - screenshotWidth) / 2,
    y: 72,
    width: screenshotWidth,
    height: screenshotHeight
)
let headlineContainer = NSRect(x: 70, y: 2340, width: 1180, height: 330)
let screenshotCornerRadius: CGFloat = 76

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let storeAssets = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let screenshotDirectory = storeAssets.appendingPathComponent("Screenshots/6.9-inch", isDirectory: true)
let backgroundDirectory = storeAssets.appendingPathComponent("Backgrounds/6.9-inch", isDirectory: true)
let rendersIPadScreenshot = CommandLine.arguments.contains("--ipad")

/// Loads a required image or terminates with a useful path-specific error.
func loadImage(at url: URL) -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        fputs("Unable to load image: \(url.path)\n", stderr)
        exit(EXIT_FAILURE)
    }
    return image
}

/// Draws a background-filling image at the Store canvas dimensions.
func drawBackground(_ image: NSImage) {
    image.draw(
        in: NSRect(origin: .zero, size: canvasSize),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
}

/// Draws the screenshot as a rounded card with a soft frame and shadow.
func drawScreenshotCard(_ image: NSImage) {
    NSGraphicsContext.saveGraphicsState()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.08, alpha: 0.22)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()

    NSColor.white.setFill()
    NSBezierPath(
        roundedRect: screenshotRect,
        xRadius: screenshotCornerRadius,
        yRadius: screenshotCornerRadius
    ).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: screenshotRect,
        xRadius: screenshotCornerRadius,
        yRadius: screenshotCornerRadius
    ).addClip()
    image.draw(
        in: screenshotRect,
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.88).setStroke()
    let border = NSBezierPath(
        roundedRect: screenshotRect.insetBy(dx: 3, dy: 3),
        xRadius: screenshotCornerRadius - 3,
        yRadius: screenshotCornerRadius - 3
    )
    border.lineWidth = 6
    border.stroke()
}

/// Draws a centered single-line Store headline in the app's deep navy.
func drawHeadline(_ headline: String) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byClipping

    let headlineColor = NSColor(
        calibratedRed: 0.08,
        green: 0.12,
        blue: 0.19,
        alpha: 1
    )
    let maximumFontSize: CGFloat = 104
    let minimumFontSize: CGFloat = 72
    var fontSize = maximumFontSize
    var attributedHeadline: NSAttributedString

    repeat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: headlineColor,
            .paragraphStyle: paragraphStyle,
            .kern: -1.5,
        ]
        attributedHeadline = NSAttributedString(string: headline, attributes: attributes)
        let measuredBounds = attributedHeadline.boundingRect(
            with: NSSize(width: .greatestFiniteMagnitude, height: headlineContainer.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        if measuredBounds.width <= headlineContainer.width || fontSize <= minimumFontSize {
            break
        }
        fontSize -= 1
    } while true

    let measuredBounds = attributedHeadline.boundingRect(
        with: headlineContainer.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let drawRect = NSRect(
        x: headlineContainer.minX,
        y: headlineContainer.midY - measuredBounds.height / 2,
        width: headlineContainer.width,
        height: measuredBounds.height
    )
    attributedHeadline.draw(in: drawRect)
}

/// Renders one complete Store image and returns its PNG data.
func renderPNG(background: NSImage, screenshot: NSImage, headline: String) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Unable to create the Store screenshot canvas.\n", stderr)
        exit(EXIT_FAILURE)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.interpolationQuality = .high
    drawBackground(background)
    drawScreenshotCard(screenshot)
    drawHeadline(headline)
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let sourceImage = bitmap.cgImage,
          let opaqueContext = CGContext(
              data: nil,
              width: Int(canvasSize.width),
              height: Int(canvasSize.height),
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
        fputs("Unable to flatten the Store screenshot.\n", stderr)
        exit(EXIT_FAILURE)
    }
    opaqueContext.draw(sourceImage, in: NSRect(origin: .zero, size: canvasSize))

    guard let opaqueImage = opaqueContext.makeImage(),
          let pngData = NSBitmapImageRep(cgImage: opaqueImage).representation(
              using: .png,
              properties: [:]
          ) else {
        fputs("Unable to encode the Store screenshot as PNG.\n", stderr)
        exit(EXIT_FAILURE)
    }
    return pngData
}

/// Renders the 13-inch iPad Store image without stretching the panorama or capture.
func renderIPadPNG(background: NSImage, screenshot: NSImage, headline: String) -> Data {
    let ipadCanvasSize = NSSize(width: 2064, height: 2752)
    let ipadScreenshotRect = NSRect(x: 257, y: 80, width: 1550, height: 2067)
    let ipadHeadlineRect = NSRect(x: 120, y: 2260, width: 1824, height: 300)
    let ipadCornerRadius: CGFloat = 62

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(ipadCanvasSize.width),
        pixelsHigh: Int(ipadCanvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Unable to create the iPad Store screenshot canvas.\n", stderr)
        exit(EXIT_FAILURE)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.interpolationQuality = .high

    let backgroundSourceWidth = background.size.height * ipadCanvasSize.width / ipadCanvasSize.height
    let backgroundSource = NSRect(
        x: (background.size.width - backgroundSourceWidth) / 2,
        y: 0,
        width: backgroundSourceWidth,
        height: background.size.height
    )
    background.draw(
        in: NSRect(origin: .zero, size: ipadCanvasSize),
        from: backgroundSource,
        operation: .copy,
        fraction: 1
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.08, alpha: 0.22)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(
        roundedRect: ipadScreenshotRect,
        xRadius: ipadCornerRadius,
        yRadius: ipadCornerRadius
    ).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: ipadScreenshotRect,
        xRadius: ipadCornerRadius,
        yRadius: ipadCornerRadius
    ).addClip()
    screenshot.draw(
        in: ipadScreenshotRect,
        from: NSRect(origin: .zero, size: screenshot.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.88).setStroke()
    let border = NSBezierPath(
        roundedRect: ipadScreenshotRect.insetBy(dx: 3, dy: 3),
        xRadius: ipadCornerRadius - 3,
        yRadius: ipadCornerRadius - 3
    )
    border.lineWidth = 6
    border.stroke()

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    let headlineAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 112, weight: .bold),
        .foregroundColor: NSColor(
            calibratedRed: 0.08,
            green: 0.12,
            blue: 0.19,
            alpha: 1
        ),
        .paragraphStyle: paragraphStyle,
        .kern: -1.5,
    ]
    NSAttributedString(string: headline, attributes: headlineAttributes).draw(in: ipadHeadlineRect)

    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let sourceImage = bitmap.cgImage,
          let opaqueContext = CGContext(
              data: nil,
              width: Int(ipadCanvasSize.width),
              height: Int(ipadCanvasSize.height),
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
        fputs("Unable to flatten the iPad Store screenshot.\n", stderr)
        exit(EXIT_FAILURE)
    }
    opaqueContext.draw(sourceImage, in: NSRect(origin: .zero, size: ipadCanvasSize))

    guard let opaqueImage = opaqueContext.makeImage(),
          let pngData = NSBitmapImageRep(cgImage: opaqueImage).representation(
              using: .png,
              properties: [:]
          ) else {
        fputs("Unable to encode the iPad Store screenshot as PNG.\n", stderr)
        exit(EXIT_FAILURE)
    }
    return pngData
}

if rendersIPadScreenshot {
    let screenshotURL = storeAssets.appendingPathComponent("Screenshots/13-inch/01-Practice.png")
    let backgroundURL = storeAssets.appendingPathComponent("Backgrounds/aurora-party-balloons-panorama.png")
    let outputURL = storeAssets.appendingPathComponent("01-Practice-13-inch-iPad.png")
    let pngData = renderIPadPNG(
        background: loadImage(at: backgroundURL),
        screenshot: loadImage(at: screenshotURL),
        headline: "Practice by Playing on iPad"
    )

    do {
        try pngData.write(to: outputURL, options: .atomic)
        print("Created \(outputURL.path)")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Unable to write \(outputURL.path): \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

for composition in compositions {
    let screenshotURL = screenshotDirectory.appendingPathComponent(composition.screenshotName)
    let backgroundURL = backgroundDirectory.appendingPathComponent(composition.backgroundName)
    let outputURL = storeAssets.appendingPathComponent(composition.screenshotName)

    let screenshot = loadImage(at: screenshotURL)
    let background = loadImage(at: backgroundURL)
    let pngData = renderPNG(
        background: background,
        screenshot: screenshot,
        headline: composition.headline
    )

    do {
        try pngData.write(to: outputURL, options: .atomic)
        print("Created \(outputURL.path)")
    } catch {
        fputs("Unable to write \(outputURL.path): \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
