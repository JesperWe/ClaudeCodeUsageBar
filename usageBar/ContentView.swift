import SwiftUI

struct ContentView: View {
    let monitor: UsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Usage")
                .font(.headline)

            if monitor.hasData {
                HStack {
                    Text("Session")
                    Spacer()
                    Text("\(Int(monitor.sessionRemaining * 100))%")
                }

                HStack {
                    Text("Weekly")
                    Spacer()
                    Text("\(Int(monitor.weeklyRemaining * 100))%")
                }
            } else if !monitor.hasWorkingDirectory {
                Text("No folder selected")
                    .foregroundStyle(.secondary)
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            }

            if let error = monitor.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                if let raw = monitor.rawOutput {
                    let cleaned = monitor.stripANSI(raw)
                    let lines = cleaned.components(separatedBy: .newlines)
                        .filter { line in
                            let readable = line.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.punctuationCharacters.contains($0) }
                            return readable.count >= 10
                        }
                    if !lines.isEmpty {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let updated = monitor.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Refresh") {
                monitor.fetchUsage()
            }
            .disabled(!monitor.hasWorkingDirectory)

            Button("Change Folder…") {
                chooseFolder()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder which has Claude Code trust activated."

        if panel.runModal() == .OK, let url = panel.url {
            monitor.workingDirectory = url.path
        }
    }
}
