#if DEBUG
import AppKit
import SwiftUI

/// Renders the UI in a few canned states to PNG files — for checking the design without a Pi-hole,
/// and for the README screenshots:
///
///     swift run Loophole --snapshot <directory>
///
/// Each panel is shown on screen for a moment and captured with `screencapture`, because Liquid Glass
/// and focused control colours only exist in the window server's composited output.
@MainActor
enum Snapshot {
    static func run(into directory: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        app.activate(ignoringOtherApps: true)
        pump(for: 1)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let summary = PiholeSummary(
            totalQueries: 143_828, blockedQueries: 22_635, percentBlocked: 15.7, domainsOnLists: 78_216,
            queriesPerMinute: 68
        )
        let system = PiholeSystem(load: [0.26, 0.14, 0.13], memoryUsedPercent: 11.1)
        let states: [(String, AppModel)] = [
            ("on", .preview(status: .enabled, summary: summary, system: system)),
            ("paused", .preview(status: .disabled(until: .now.addingTimeInterval(272)), summary: summary, system: system)),
            ("off", .preview(status: .disabled(until: nil))),
            ("error", .preview(status: .failed("The request timed out."))),
            ("setup", .preview(status: .notConfigured)),
        ]
        for (name, model) in states {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                write(MenuView().environment(model), onGlass: true, appearance: appearance,
                      to: directory.appending(path: "menu-\(name)-\(suffix).png"))
            }
        }
        writeMenuBarIcons(to: directory.appending(path: "menu-bar-icons.png"))
        write(SettingsView().environment(states[0].1), onGlass: false, appearance: .aqua,
              to: directory.appending(path: "settings-light.png"))
    }

    /// Sample data for `--demo`: the real app, menu bar item and all, without a Pi-hole.
    static var demoModel: AppModel {
        .preview(
            // `--demo --paused` shows a timed pause, with the countdown in the menu bar.
            status: CommandLine.arguments.contains("--paused") ? .disabled(until: .now.addingTimeInterval(272)) : .enabled,
            summary: PiholeSummary(
                totalQueries: 143_828, blockedQueries: 22_635, percentBlocked: 15.7, domainsOnLists: 78_216,
                queriesPerMinute: 68
            ),
            system: PiholeSystem(load: [0.26, 0.14, 0.13], memoryUsedPercent: 11.1)
        )
    }

    /// With `--demo --capture-popover <directory>`: opens the real menu bar panel by clicking the
    /// status item, captures it, and quits. Shows what the panel looks like in its actual window.
    static func captureLivePopover(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let statusWindows = NSApp.windows.filter { $0.frame.minY >= 0 && statusButton(in: $0.contentView) != nil }
            guard let statusWindow = statusWindows.first, let button = statusButton(in: statusWindow.contentView) else {
                log("no on-screen status item"); exit(1)
            }
            // The menu bar item itself, with a little of the bar around it.
            let itemFrame = statusWindow.frame.insetBy(dx: -30, dy: 0)
            let item = Process()
            item.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            item.arguments = ["-x", "-R", "\(Int(itemFrame.minX)),0,\(Int(itemFrame.width)),\(Int(itemFrame.height))",
                              directory.appending(path: "menu-bar-item.png").path]
            try? item.run()
            item.waitUntilExit()
            button.performClick(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if panels.isEmpty {
                    // The button ignores synthetic clicks; post a real one at the status item.
                    let screenHeight = NSScreen.screens[0].frame.height
                    let point = CGPoint(x: statusWindow.frame.midX, y: screenHeight - statusWindow.frame.midY)
                    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                            .post(tap: .cghidEventTap)
                    }
                    log("posted a real click at \(point)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    for window in panels {
                        log("panel: \(type(of: window)) opaque=\(window.isOpaque) bg=\(window.backgroundColor.debugDescription) \(window.frame)")
                        dump(window.contentView?.superview, depth: 0)
                        log("hasShadow=\(window.hasShadow) style=\(window.styleMask.rawValue) layerRadius=\(window.contentView?.superview?.layer?.cornerRadius ?? -1)")
                        let capture = Process()
                        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        capture.arguments = ["-x", "-l", String(window.windowNumber),
                                             directory.appending(path: "popover.png").path]
                        try? capture.run()
                        capture.waitUntilExit()

                        // Also what is actually on screen, to judge the glass against what's behind it.
                        let frame = window.frame
                        let top = NSScreen.screens[0].frame.height - frame.maxY
                        let region = Process()
                        region.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        region.arguments = ["-x", "-R", "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))",
                                            directory.appending(path: "on-screen.png").path]
                        try? region.run()
                        region.waitUntilExit()
                    }
                    if panels.isEmpty { log("the panel did not open") }
                    exit(0)
                }
            }
        }
    }

    private static var panels: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.frame.height > 100 }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func dump(_ view: NSView?, depth: Int) {
        guard let view, depth < 3 else { return }
        log(String(repeating: "  ", count: depth) + "\(type(of: view)) \(Int(view.frame.width))x\(Int(view.frame.height))")
        view.subviews.forEach { dump($0, depth: depth + 1) }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { statusButton(in: $0) }.first
    }

    /// The three menu bar glyphs, enlarged, tinted as they would be on a light and a dark menu bar.
    private static func writeMenuBarIcons(to url: URL) {
        let statuses: [AppModel.Status] = [.enabled, .disabled(until: nil), .unknown]
        let scale: CGFloat = 8, cell: CGFloat = 220, rowHeight: CGFloat = 200
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(cell) * statuses.count, pixelsHigh: Int(rowHeight) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (row, ink) in [NSColor.black, NSColor.white].enumerated() {
            let band = NSRect(x: 0, y: CGFloat(1 - row) * rowHeight, width: cell * CGFloat(statuses.count), height: rowHeight)
            (row == 0 ? NSColor(white: 0.88, alpha: 1) : NSColor(white: 0.16, alpha: 1)).setFill()
            band.fill()
            for (column, status) in statuses.enumerated() {
                let glyph = MenuBarIcon.image(for: status)
                let size = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
                let tinted = NSImage(size: size, flipped: false) { rect in
                    glyph.draw(in: rect)
                    ink.set()
                    rect.fill(using: .sourceIn)
                    return true
                }
                tinted.draw(in: NSRect(
                    x: CGFloat(column) * cell + (cell - size.width) / 2, y: band.midY - size.height / 2,
                    width: size.width, height: size.height
                ))
            }
        }
        NSGraphicsContext.current = nil
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Captures the view from a real window. The menu panel is drawn as it appears in use — a sheet of
    /// Liquid Glass — over a stand-in wallpaper; Settings is drawn as a plain rounded window.
    private static func write(_ view: some View, onGlass: Bool, appearance: NSAppearance.Name, to url: URL) {
        let framed: AnyView
        if onGlass {
            framed = AnyView(
                view
                    .glassPanel()
                    .padding(36)
                    .background { Wallpaper() }
            )
        } else {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            framed = AnyView(
                view
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.12)))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    .padding(28)
            )
        }

        let host = NSHostingView(rootView: framed)
        host.appearance = NSAppearance(named: appearance)
        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = host
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        pump(for: 0.3)
        window.setContentSize(host.fittingSize)
        window.center()
        pump(for: 0.5)

        // Capture only this window (-l), without the system shadow (-o) or the shutter sound (-x).
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try? capture.run()
        capture.waitUntilExit()
        window.orderOut(nil)
    }

    /// Runs the real event loop for a moment, so activation and layout actually happen.
    private static func pump(for seconds: TimeInterval) {
        let deadline = Date.now.addingTimeInterval(seconds)
        while let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }

    /// A soft, colourful backdrop for the glass to refract, in place of someone's real desktop.
    private struct Wallpaper: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.10, green: 0.09, blue: 0.24), Color(red: 0.33, green: 0.10, blue: 0.30)]
                        : [Color(red: 0.55, green: 0.75, blue: 0.98), Color(red: 0.98, green: 0.72, blue: 0.78)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle().fill(Color(red: 0.98, green: 0.55, blue: 0.25).opacity(0.75))
                    .frame(width: 260).blur(radius: 70).offset(x: 110, y: 170)
                Circle().fill(Color(red: 0.35, green: 0.45, blue: 0.98).opacity(0.7))
                    .frame(width: 240).blur(radius: 70).offset(x: -120, y: -150)
            }
        }
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
#endif
