#if DEBUG
import AppKit
import SwiftUI

/// Renders the UI in a few canned states to PNG files, for checking the design without a Pi-hole:
///
///     swift run PiholeSwitcher --snapshot <directory>
@MainActor
enum Snapshot {
    static func run(into directory: URL) {
        _ = NSApplication.shared
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
                write(MenuView().environment(model), appearance: appearance,
                      to: directory.appending(path: "menu-\(name)-\(suffix).png"))
            }
        }
        write(SettingsView().environment(states[0].1), appearance: .aqua,
              to: directory.appending(path: "settings-light.png"))
    }

    private static func write(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.layoutIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
