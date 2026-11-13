import SwiftUI

@main
enum Main {
    static func main() {
        #if DEBUG
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(flag + 1) {
            Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
            return
        }
        #endif
        PiholeSwitcherApp.main()
    }
}

struct PiholeSwitcherApp: App {
    @State private var model = AppModel()
    @AppStorage("showCountdown") private var showCountdown = true

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            HStack(spacing: 4) {
                if let logo = MenuBarIcon.image(blockingOn: model.status == .enabled) {
                    Image(nsImage: logo)
                        .accessibilityLabel("Pi-hole Switcher")
                } else {
                    Image(systemName: model.menuBarSymbol)
                }
                // Time left on a timed pause.
                if showCountdown, let countdown = model.countdownText {
                    Text(countdown).monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Pi-hole Switcher Settings", id: "settings") {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
