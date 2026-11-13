#!/usr/bin/env swift
// Regenerates Support/AppIcon.icns — the Loophole mark, a shield with a hole punched through it:
//   swift scripts/make-icon.swift
// The shield shape is the same one the app draws in the menu bar (Sources/Loophole/MenuBarIcon.swift).
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let support = root.appending(path: "Support")

/// The shield outline in `rect`, with the hole as a second subpath (fill with the even-odd rule).
func shieldPath(in rect: CGRect) -> NSBezierPath {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
    let path = NSBezierPath()
    path.move(to: point(0.50, 0.97))
    path.curve(to: point(0.89, 0.81), controlPoint1: point(0.62, 0.90), controlPoint2: point(0.76, 0.84))
    path.line(to: point(0.89, 0.50))
    path.curve(to: point(0.50, 0.03), controlPoint1: point(0.89, 0.27), controlPoint2: point(0.72, 0.11))
    path.curve(to: point(0.11, 0.50), controlPoint1: point(0.28, 0.11), controlPoint2: point(0.11, 0.27))
    path.line(to: point(0.11, 0.81))
    path.curve(to: point(0.50, 0.97), controlPoint1: point(0.24, 0.84), controlPoint2: point(0.38, 0.90))
    path.close()
    let hole = rect.width * 0.34
    path.appendOval(in: CGRect(x: rect.midX - hole / 2, y: rect.minY + rect.height * 0.53 - hole / 2, width: hole, height: hole))
    path.windingRule = .evenOdd
    path.lineJoinStyle = .round
    return path
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Work in the 1024pt icon grid: an 824pt plate with 100pt margins.
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()

    // Graphite plate with a faint highlight along the top edge.
    let plateRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: 185, yRadius: 185)
    NSGradient(
        starting: NSColor(red: 0.34, green: 0.36, blue: 0.43, alpha: 1),
        ending: NSColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
    )!.draw(in: plate, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), .clear], atLocations: [0, 0.35], colorSpace: .deviceRGB)!
        .draw(in: plateRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The shield: soft shadow below, then a white-to-silver fill with the hole showing the plate.
    let shield = shieldPath(in: NSRect(x: 262, y: 232, width: 500, height: 560))
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 36 * CGFloat(pixels) / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -14 * CGFloat(pixels) / 1024)
    shadow.set()
    NSColor.white.setFill()
    shield.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shield.addClip()
    NSGradient(starting: .white, ending: NSColor(white: 0.80, alpha: 1))!.draw(in: shield.bounds, angle: -90)
    // Two-tone facets, as in the menu bar: shade the right half.
    NSColor.black.withAlphaComponent(0.15).setFill()
    NSRect(x: shield.bounds.midX, y: shield.bounds.minY, width: shield.bounds.width / 2, height: shield.bounds.height).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", support.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Support/AppIcon.icns")
