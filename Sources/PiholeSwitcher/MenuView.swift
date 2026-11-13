import SwiftUI

/// The panel shown when the menu bar icon is clicked.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("customAmount") private var customAmount = 10
    @AppStorage("customUnit") private var customUnit = DurationUnit.minutes
    @State private var showsCustomDuration = false

    private static let presets: [(label: String, seconds: Int)] = [
        ("30 sec", 30),
        ("5 min", 5 * 60),
        ("15 min", 15 * 60),
        ("1 hour", 60 * 60),
    ]

    private static let inset: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 12)

            switch model.status {
            case .enabled, .disabled:
                separator
                VStack(alignment: .leading, spacing: 16) {
                    pauseSection
                    statusSection
                    if let summary = model.summary { statsSection(summary) }
                }
                .padding(Self.inset)
            case .notConfigured:
                separator
                message(
                    "Connect to your Pi-hole to turn blocking on and off from the menu bar.",
                    action: "Set Up…", prominent: true, perform: openSettings
                )
            case .failed(let reason):
                separator
                message(reason, action: "Try Again", prominent: false) {
                    Task { await model.refresh() }
                }
            case .unknown:
                EmptyView()
            }

            separator
            VStack(spacing: 0) {
                if let adminURL = model.adminURL {
                    Button { NSWorkspace.shared.open(adminURL) } label: {
                        MenuRowLabel(title: "Open Pi-hole Admin", shortcut: "")
                    }
                    .help(adminURL.absoluteString)
                }
                Button(action: openSettings) { MenuRowLabel(title: "Settings…", shortcut: "⌘,") }
                    .keyboardShortcut(",", modifiers: .command)
                Button { Task { await model.quit() } } label: {
                    MenuRowLabel(title: "Quit Pi-hole Switcher", shortcut: "⌘Q")
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(MenuRowButtonStyle())
            .padding(5)
        }
        .frame(width: 320)
        .animation(.snappy(duration: 0.25), value: model.status)
        .animation(.snappy(duration: 0.25), value: showsCustomDuration)
        .task {
            await model.refresh()
            await model.refreshDetails()
        }
    }

    private var separator: some View {
        Divider().padding(.horizontal, Self.inset)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(symbol: model.menuBarSymbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pi-hole")
                    .font(.headline)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            if isConnected {
                Toggle("Blocking", isOn: blocking)
                    .toggleStyle(.switch)
                    .tint(.green)
                    .labelsHidden()
                    .disabled(model.isBusy)
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch model.status {
        case .notConfigured:
            Text("Not Set Up")
        case .unknown:
            Text("Connecting…")
        case .enabled:
            Text("Blocking On")
        case .disabled(let until?):
            HStack(spacing: 0) {
                Text("Paused · ")
                Text(timerInterval: min(Date.now, until)...until, countsDown: true)
                    .monospacedDigit()
                Text(" left")
            }
        case .disabled(nil):
            Text("Blocking Off")
        case .failed:
            Text("Not Connected")
        }
    }

    private var isConnected: Bool {
        switch model.status {
        case .enabled, .disabled: true
        case .notConfigured, .unknown, .failed: false
        }
    }

    private var blocking: Binding<Bool> {
        Binding {
            model.status == .enabled
        } set: { isOn in
            Task { isOn ? await model.enable() : await model.disable() }
        }
    }

    private var tint: Color? {
        switch model.status {
        case .enabled: .green
        case .disabled(.some): .orange
        case .failed: .red
        case .disabled(nil), .notConfigured, .unknown: nil
        }
    }

    // MARK: - Sections

    private var pauseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Pause Blocking")
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.seconds) { preset in
                    Button(preset.label) {
                        Task { await model.disable(for: preset.seconds) }
                    }
                }
                Button("Other") { showsCustomDuration.toggle() }
                    .buttonStyle(PillButtonStyle(isSelected: showsCustomDuration))
            }
            .buttonStyle(PillButtonStyle())

            if showsCustomDuration {
                HStack(spacing: 8) {
                    TextField("Duration", value: $customAmount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .onSubmit(pauseForCustomDuration)
                    Stepper("Duration", value: $customAmount, in: customUnit.range)
                        .labelsHidden()
                    Picker("Unit", selection: $customUnit) {
                        ForEach(DurationUnit.allCases, id: \.self) { unit in
                            Text(unit.label(for: customAmount)).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button("Pause", action: pauseForCustomDuration)
                        .buttonStyle(.borderedProminent)
                        .disabled(!customUnit.range.contains(customAmount))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .disabled(model.isBusy)
    }

    /// The Status box from the admin page's sidebar: blocking state, query rate, load and memory.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Status")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    blockingStatusItem
                    if let load = model.system?.load, !load.isEmpty {
                        StatusItem(
                            symbol: "cpu",
                            text: "Load: " + load.map { $0.formatted(.number.precision(.fractionLength(2))) }
                                .joined(separator: " / ")
                        )
                    }
                }
                GridRow {
                    if let rate = model.summary?.queriesPerMinute {
                        StatusItem(
                            symbol: "gauge.with.dots.needle.67percent",
                            text: "\(rate.formatted(.number.precision(.fractionLength(0)))) q/min"
                        )
                    }
                    if let memory = model.system?.memoryUsedPercent {
                        StatusItem(
                            symbol: "memorychip",
                            text: "Memory: " + (memory / 100).formatted(.percent.precision(.fractionLength(1)))
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Card())
        }
    }

    private var blockingStatusItem: StatusItem {
        switch model.status {
        case .enabled: StatusItem(symbol: "circle.fill", text: "Active", color: .green)
        case .disabled(.some): StatusItem(symbol: "circle.fill", text: "Paused", color: .orange)
        default: StatusItem(symbol: "circle.fill", text: "Blocking off", color: .red)
        }
    }

    private func statsSection(_ summary: PiholeSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Last 24 Hours")
            // The same four tiles, in the same colours, as the top of the Pi-hole admin dashboard.
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    StatTile(
                        label: "Total Queries", value: summary.totalQueries.formatted(),
                        symbol: "globe.americas.fill", color: Color(red: 0.18, green: 0.47, blue: 0.60)
                    )
                    StatTile(
                        label: "Queries Blocked", value: summary.blockedQueries.formatted(),
                        symbol: "hand.raised.fill", color: Color(red: 0.53, green: 0.22, blue: 0.17)
                    )
                }
                GridRow {
                    StatTile(
                        label: "Percentage Blocked",
                        value: (summary.percentBlocked / 100).formatted(.percent.precision(.fractionLength(1))),
                        symbol: "chart.pie.fill", color: Color(red: 0.68, green: 0.47, blue: 0.16)
                    )
                    if let domains = summary.domainsOnLists {
                        StatTile(
                            label: "Domains on Lists", value: domains.formatted(),
                            symbol: "list.bullet.rectangle.fill", color: Color(red: 0.15, green: 0.37, blue: 0.20)
                        )
                    }
                }
            }
        }
    }

    /// A short explanation with one button, used when there is nothing to control yet.
    private func message(
        _ text: String,
        action: String,
        prominent: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if prominent {
                Button(action, action: perform).buttonStyle(.borderedProminent)
            } else {
                Button(action, action: perform)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.inset)
    }

    // MARK: - Actions

    private func pauseForCustomDuration() {
        guard customUnit.range.contains(customAmount) else { return }
        showsCustomDuration = false
        Task { await model.disable(for: customAmount * customUnit.seconds) }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Building blocks

/// The unit for a hand-entered pause duration.
private enum DurationUnit: String, CaseIterable {
    case minutes, hours

    var seconds: Int { self == .minutes ? 60 : 3600 }

    /// Up to a day either way.
    var range: ClosedRange<Int> { self == .minutes ? 1...1440 : 1...24 }

    func label(for amount: Int) -> String {
        switch self {
        case .minutes: amount == 1 ? "minute" : "minutes"
        case .hours: amount == 1 ? "hour" : "hours"
        }
    }
}

/// The round state indicator in the header, in the style of Control Center's toggles:
/// filled with colour when there is something to say, neutral otherwise.
private struct StatusBadge: View {
    let symbol: String
    let tint: Color?

    var body: some View {
        ZStack {
            Circle().fill(tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(.quaternary))
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.quaternary.opacity(0.6))
    }
}

/// One line of the Status section: a small coloured pictogram and a value.
private struct StatusItem: View {
    let symbol: String
    let text: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A coloured statistic tile modelled on the boxes at the top of the Pi-hole admin dashboard:
/// label, large figure, and a faint pictogram bleeding off the trailing edge.
private struct StatTile: View {
    let label: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .opacity(0.9)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            ZStack(alignment: .trailing) {
                color
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(.black.opacity(0.16))
                    .offset(x: 8, y: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Equal-width rounded buttons for the pause durations.
private struct PillButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, isSelected: isSelected)
    }

    private struct Pill: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(fillOpacity)))
                }
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }

        private var fillOpacity: Double {
            if configuration.isPressed { return 0.2 }
            return isHovered ? 0.13 : 0.08
        }
    }
}

private struct MenuRowLabel: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut).foregroundStyle(.tertiary)
        }
    }
}

/// Full-width rows that highlight under the pointer, like the footer of the Wi-Fi or Focus menus.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.1 : 0))
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
