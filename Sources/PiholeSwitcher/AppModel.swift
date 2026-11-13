import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case notConfigured
        case unknown
        case enabled
        /// `until` is when Pi-hole will switch blocking back on by itself; `nil` means it stays off.
        case disabled(until: Date?)
        case failed(String)
    }

    private(set) var status: Status = .unknown
    private(set) var isBusy = false

    /// Dashboard totals and system health; loaded when the popover opens.
    private(set) var summary: PiholeSummary?
    private(set) var system: PiholeSystem?
    /// Time left on a timed pause, e.g. "4:32", for the menu bar.
    private(set) var countdownText: String?
    private(set) var shortcuts: [HotKeyAction: KeyCombo] = [:]

    private(set) var address: String
    private(set) var allowSelfSigned: Bool
    private(set) var password: String

    @ObservationIgnored private var client: PiholeClient?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    private static let pollInterval: Duration = .seconds(30)

    /// - Parameter live: `false` builds an inert model (no keychain, network, shortcuts or polling) for snapshots.
    init(live: Bool = true) {
        guard live else {
            address = ""
            allowSelfSigned = false
            password = ""
            return
        }
        let defaults = UserDefaults.standard
        let savedAddress = defaults.string(forKey: "address") ?? ""
        address = savedAddress
        allowSelfSigned = defaults.bool(forKey: "allowSelfSigned")
        password = savedAddress.isEmpty ? "" : Keychain.loadPassword()
        rebuildClient()
        for action in HotKeyAction.allCases {
            shortcuts[action] = action.loadCombo()
            registerShortcut(for: action)
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    /// The Pi-hole's web dashboard, once an address is configured.
    var adminURL: URL? {
        PiholeClient.normalizedBaseURL(from: address)?.appending(path: "admin/")
    }

    var menuBarSymbol: String {
        switch status {
        case .enabled: "shield.lefthalf.filled"
        case .disabled: "shield.slash"
        case .notConfigured, .unknown: "shield"
        case .failed: "exclamationmark.shield"
        }
    }

    // MARK: - Actions

    func refresh() async {
        guard let client else { return }
        await run(showsActivity: false) { try await client.blockingStatus() }
    }

    func enable() async {
        guard let client else { return }
        showOptimistically(.enabled)
        await run { try await client.setBlocking(true) }
    }

    /// Turns blocking off. With `seconds`, Pi-hole turns it back on by itself afterwards.
    func disable(for seconds: Int? = nil) async {
        guard let client else { return }
        showOptimistically(.disabled(until: seconds.map { Date.now.addingTimeInterval(TimeInterval($0)) }))
        await run { try await client.setBlocking(false, for: seconds) }
    }

    /// Loads the extras shown in the popover. Failures are ignored: the status line already reports them.
    func refreshDetails() async {
        guard let client else { return }
        let summary = try? await client.summary()
        let system = try? await client.systemInfo()
        guard client === self.client else { return }
        if let summary { self.summary = summary }
        if let system { self.system = system }
    }

    /// Sets or removes a global shortcut. Returns `false` if macOS refused it (already in use elsewhere).
    @discardableResult
    func setShortcut(_ combo: KeyCombo?, for action: HotKeyAction) -> Bool {
        shortcuts[action] = combo
        if registerShortcut(for: action) {
            action.saveCombo(combo)
            return true
        }
        shortcuts[action] = nil
        action.saveCombo(nil)
        return false
    }

    func saveSettings(address: String, password: String, allowSelfSigned: Bool) async {
        let oldClient = client
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.allowSelfSigned = allowSelfSigned
        UserDefaults.standard.set(self.address, forKey: "address")
        UserDefaults.standard.set(allowSelfSigned, forKey: "allowSelfSigned")
        Keychain.savePassword(password)
        rebuildClient()
        isBusy = true
        defer { isBusy = false }
        await oldClient?.logout()
        await refresh()
        await refreshDetails()
    }

    func quit() async {
        pollTask?.cancel()
        await client?.logout()
        NSApp.terminate(nil)
    }

    // MARK: - Internals

    @discardableResult
    private func registerShortcut(for action: HotKeyAction) -> Bool {
        HotKeyCenter.shared.register(shortcuts[action], for: action) { [weak self] in
            Task { await self?.perform(action) }
        }
    }

    private func perform(_ action: HotKeyAction) async {
        switch action {
        case .pause:
            let minutes = UserDefaults.standard.integer(forKey: "shortcutPauseMinutes")
            await disable(for: (minutes > 0 ? minutes : 5) * 60)
        case .resume:
            await enable()
        }
    }

    private static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private func rebuildClient() {
        expiryTask?.cancel()
        countdownText = nil
        summary = nil
        system = nil
        guard let url = PiholeClient.normalizedBaseURL(from: address) else {
            client = nil
            status = address.isEmpty ? .notConfigured : .failed("“\(address)” isn't a valid address.")
            return
        }
        client = PiholeClient(baseURL: url, password: password, allowSelfSigned: allowSelfSigned)
        status = .unknown
    }

    /// Shows the expected result of a switch immediately, so the UI doesn't lag behind the click.
    /// The Pi-hole's answer replaces it a moment later.
    private func showOptimistically(_ expected: Status) {
        expiryTask?.cancel()
        countdownText = nil
        status = expected
    }

    /// - Parameter showsActivity: whether to show a spinner; background refreshes stay silent.
    private func run(showsActivity: Bool = true, _ operation: () async throws -> BlockingStatus) async {
        let requestClient = client
        if showsActivity { isBusy = true }
        defer { if showsActivity { isBusy = false } }
        let result: Status
        do {
            let blocking = try await operation()
            let secondsRemaining = blocking.isEnabled ? nil : blocking.secondsRemaining
            var until = secondsRemaining.map { Date.now.addingTimeInterval($0) }
            // Keep the end time we already show unless it really moved, so the countdown doesn't jitter.
            if case .disabled(let shown?) = status, let reported = until, abs(shown.timeIntervalSince(reported)) < 2 {
                until = shown
            }
            result = blocking.isEnabled ? .enabled : .disabled(until: until)
        } catch {
            result = .failed(error.localizedDescription)
        }
        // Settings changed while the request was in flight: this answer is about the old Pi-hole.
        guard requestClient === client else { return }
        status = result
        expiryTask?.cancel()
        if case .disabled(let end?) = result {
            // Tick the menu bar countdown, then check back right after the timer runs out
            // so the icon flips promptly.
            countdownText = Self.countdown(end.timeIntervalSinceNow)
            expiryTask = Task { [weak self] in
                while !Task.isCancelled, end.timeIntervalSinceNow > 0 {
                    self?.countdownText = Self.countdown(end.timeIntervalSinceNow)
                    // Wake just after each whole-second boundary so the display never skips a beat.
                    let fraction = end.timeIntervalSinceNow.truncatingRemainder(dividingBy: 1)
                    try? await Task.sleep(for: .seconds(max(fraction, 0.05) + 0.01))
                }
                guard !Task.isCancelled else { return }
                self?.countdownText = nil
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        } else {
            countdownText = nil
        }
    }
}

#if DEBUG
extension AppModel {
    /// An inert model frozen in a given state, for rendering snapshots of the UI.
    static func preview(
        status: Status,
        summary: PiholeSummary? = nil,
        system: PiholeSystem? = nil
    ) -> AppModel {
        let model = AppModel(live: false)
        model.address = "http://pi.hole"
        model.status = status
        model.summary = summary
        model.system = system
        return model
    }
}
#endif
