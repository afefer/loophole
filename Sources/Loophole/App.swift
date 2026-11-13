import AppKit
import SwiftUI

@main
enum Main {
    @MainActor
    static func main() {
        #if DEBUG
        if let directory = argument(after: "--snapshot") {
            Snapshot.run(into: directory)
            return
        }
        if let directory = argument(after: "--capture-popover") {
            Snapshot.captureLivePopover(into: directory)
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// The live model — or, in debug builds started with `--demo`, one frozen with sample data.
    @MainActor
    static func makeModel() -> AppModel {
        #if DEBUG
        if CommandLine.arguments.contains("--demo") { return Snapshot.demoModel }
        #endif
        return AppModel()
    }

    private static func argument(after flag: String) -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = Main.makeModel()
    private var statusItem: StatusItemController?

    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusItem = StatusItemController(model: model) { [weak self] in self?.showSettings() }
        // First launch: there is nothing to control until a Pi-hole is entered.
        if model.status == .notConfigured { showSettings() }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(rootView: SettingsView().environment(model))
            )
            window.title = "Loophole Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        Task { await model.quit() }
    }

    /// A menu bar app shows no menus, but text fields in Settings still need the standard
    /// Edit commands for ⌘X/⌘C/⌘V/⌘A to work.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Loophole", action: #selector(quit), keyEquivalent: "q").target = self

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
