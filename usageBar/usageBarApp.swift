import SwiftUI
import AppKit

@main
struct usageBarApp: App {
    @State private var monitor = UsageMonitor()
    @State private var needsSetup: Bool

    init() {
        _needsSetup = State(initialValue: UserDefaults.standard.string(forKey: "workingDirectory") == nil)

        // Check that claude CLI is installed
        do {
            _ = try UsageMonitor.findClaudeBinary()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Claude Code Not Found"
            alert.informativeText = "Please install Claude Code first, then relaunch this app.\n\nhttps://docs.anthropic.com/en/docs/claude-code"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            MenuBarIcon(topProgress: monitor.sessionRemaining, bottomProgress: monitor.weeklyRemaining, hasData: monitor.hasData)
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage Setup", id: "setup") {
            DirectorySetupView(monitor: monitor)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(needsSetup ? .presented : .suppressed)
    }
}
