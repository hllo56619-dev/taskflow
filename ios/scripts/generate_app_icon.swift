import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate_app_icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = context
context.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.29, green: 0.20, blue: 0.91, alpha: 1)
])!
gradient.draw(in: bounds, angle: -35)

// A clean white checklist mark; iOS applies the final rounded icon mask.
let tile = NSBezierPath(
    roundedRect: NSRect(x: 235, y: 235, width: 554, height: 554),
    xRadius: 122,
    yRadius: 122
)
tile.lineWidth = 58
NSColor.white.setStroke()
tile.stroke()

let check = NSBezierPath()
check.move(to: NSPoint(x: 333, y: 510))
check.line(to: NSPoint(x: 450, y: 392))
check.line(to: NSPoint(x: 692, y: 632))
check.lineWidth = 72
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let pngData = bitmap.representation(using: .png, properties: [:])!
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)
print("Wrote TaskFlow app icon to \(outputURL.path)")
