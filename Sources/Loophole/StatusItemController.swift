import AppKit
import SwiftUI

/// Owns the menu bar item and the panel that drops down from it.
///
/// SwiftUI's `MenuBarExtra` always paints a solid backdrop behind its window, which rules out a
/// Liquid Glass panel — so the status item and its transparent panel are managed here directly.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let openSettings: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MenuPanel()
    private var topLeft = NSPoint.zero
    private var outsideClickMonitor: Any?
    private var lastClosed = Date.distantPast

    /// Transparent margin around the glass, so its soft shadow isn't cut off by the window edge.
    private static let margin: CGFloat = 24

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.setAccessibilityLabel("Loophole")
        }
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }

        trackModel()
        // The "show time remaining" setting lives in UserDefaults.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
    }

    // MARK: - Menu bar item

    /// Redraws the item now and again whenever the model state it reads changes.
    private func trackModel() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackModel() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(for: model.status)

        // Time left on a timed pause, unless switched off in Settings.
        let showCountdown = UserDefaults.standard.object(forKey: "showCountdown") as? Bool ?? true
        let title = showCountdown ? model.countdownText ?? "" : ""
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else if Date.now.timeIntervalSince(lastClosed) > 0.25 {
            // (Clicking the item while the panel is open closes it first; don't reopen on the same click.)
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let itemWindow = button.window,
              let screen = itemWindow.screen ?? NSScreen.main
        else { return }

        // A fresh view each time, so it reloads its data and starts with everything collapsed.
        let content = MenuView(onOpenSettings: { [weak self] in
            self?.closePanel()
            self?.openSettings()
        })
        .glassPanel()
        .padding(Self.margin)
        .environment(model)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host

        let size = host.view.fittingSize
        panel.setContentSize(size)
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 0)
        // Position the glass itself (the window is larger by the margin on every side).
        let glassWidth = size.width - 2 * Self.margin
        let x = max(bounds.minX, min(itemWindow.frame.minX, bounds.maxX - glassWidth))
        topLeft = NSPoint(x: x - Self.margin, y: itemWindow.frame.minY - 6 + Self.margin)
        panel.setFrameTopLeftPoint(topLeft)
        panel.makeKeyAndOrderFront(nil)

        // Keep the item highlighted while its panel is open (after AppKit finishes the click).
        DispatchQueue.main.async { button.highlight(true) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.contentViewController = nil
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        lastClosed = .now
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    /// The panel grows and shrinks with its content; keep it hanging from the same point.
    func windowDidResize(_ notification: Notification) {
        guard panel.isVisible, panel.frame.origin.x != topLeft.x || panel.frame.maxY != topLeft.y else { return }
        panel.setFrameTopLeftPoint(topLeft)
    }
}

/// A borderless, transparent panel that can take keyboard focus without activating the app.
private final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the glass casts its own; a window shadow would be a hard rectangle
        level = .popUpMenu
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes the panel.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
