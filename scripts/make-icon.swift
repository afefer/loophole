#!/usr/bin/env swift
// Regenerates Support/AppIcon.icns from Support/pi-hole.svg:
//   swift scripts/make-icon.swift
// The logo is drawn on a white rounded-square plate following the macOS icon grid.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let support = root.appending(path: "Support")
guard let logo = NSImage(contentsOf: support.appending(path: "pi-hole.svg")) else {
    fatalError("Could not load Support/pi-hole.svg")
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Work in the 1024pt icon grid: an 824pt plate with 100pt margins.
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let plateRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: 185, yRadius: 185)
    NSGradient(starting: .white, ending: NSColor(white: 0.93, alpha: 1))!.draw(in: plate, angle: -90)

    let logoHeight: CGFloat = 600
    let logoWidth = logoHeight * logo.size.width / logo.size.height
    logo.draw(in: NSRect(
        x: (1024 - logoWidth) / 2, y: (1024 - logoHeight) / 2,
        width: logoWidth, height: logoHeight
    ))

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
