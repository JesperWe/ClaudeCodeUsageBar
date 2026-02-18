import SwiftUI
import AppKit

struct DirectorySetupView: View {
    let monitor: UsageMonitor
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 16) {
            Text("This app needs a local folder that Claude Code has been told to trust.\nSelect any specific folder where you are currently running Claude Code.")
                .multilineTextAlignment(.center)

            if let dir = monitor.workingDirectory {
                Text(dir)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Button("Choose Folder…") {
                    chooseFolder()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder which has Claude Code trust activated."

        if panel.runModal() == .OK, let url = panel.url {
            monitor.workingDirectory = url.path
            dismissWindow(id: "setup")
        }
    }
}
