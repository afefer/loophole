import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The things a global keyboard shortcut can trigger.
enum HotKeyAction: String, CaseIterable, Sendable {
    case pause, resume

    fileprivate var id: UInt32 { self == .pause ? 1 : 2 }
    private var defaultsKey: String { "shortcut.\(rawValue)" }

    func loadCombo() -> KeyCombo? {
        UserDefaults.standard.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
    }

    func saveCombo(_ combo: KeyCombo?) {
        UserDefaults.standard.set(combo.flatMap { try? JSONEncoder().encode($0) }, forKey: defaultsKey)
    }
}

struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// Human-readable form captured when the shortcut was recorded, e.g. "⌃⌥P".
    var display: String

    /// `nil` unless the key press includes ⌘, ⌃ or ⌥ — a bare key would hijack normal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var modifiers: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = modifiers
        display = symbols + Self.keyName(for: event)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(for event: NSEvent) -> String {
        specialKeys[Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "Key \(event.keyCode)"
    }
}

/// Registers system-wide hot keys through Carbon, which needs no accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static let signature: OSType = 0x5048_5357 // "PHSW"

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey
            )
            guard status == noErr else { return status }
            let id = hotKey.id
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Replaces the shortcut for `action`. Returns `false` if macOS refused it (usually: already taken).
    @discardableResult
    func register(_ combo: KeyCombo?, for action: HotKeyAction, handler: @escaping @MainActor () -> Void) -> Bool {
        let id = action.id
        if let existing = references.removeValue(forKey: id) { UnregisterEventHotKey(existing) }
        handlers[id] = nil
        guard let combo else { return true }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return false }
        references[id] = reference
        handlers[id] = handler
        return true
    }
}

/// A button that records the next key press as a shortcut. Esc cancels.
struct ShortcutRecorder: View {
    let title: String
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Button(isRecording ? "Press shortcut…" : combo?.display ?? "Record Shortcut") {
                    isRecording ? stop() : start()
                }
                if combo != nil, !isRecording {
                    Button {
                        onChange(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove shortcut")
                }
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let recorded = KeyCombo(event: event) {
                stop()
                onChange(recorded)
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
