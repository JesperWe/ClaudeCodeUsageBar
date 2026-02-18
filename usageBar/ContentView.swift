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
                TimelineView(PeriodicTimelineSchedule(from: .now, by: 1)) { _ in
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                TooltipButton(icon: "arrow.clockwise", tooltip: "Refresh") {
                    monitor.fetchUsage()
                }
                .disabled(!monitor.hasWorkingDirectory || monitor.isFetching)

                TooltipButton(icon: "gearshape", tooltip: "Change Folder…") {
                    chooseFolder()
                }

                TooltipButton(icon: "xmark.circle.fill", tooltip: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
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

struct TooltipButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(maxWidth: .infinity)
        }
        .onHover { hovering in
            if hovering {
                FloatingTooltip.show(tooltip)
            } else {
                FloatingTooltip.hide()
            }
        }
    }
}

final class FloatingTooltip {
    private static var window: NSWindow?

    static func show(_ text: String) {
        hide()

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        label.textColor = .secondaryLabelColor
        label.backgroundColor = .windowBackgroundColor
        label.isBezeled = false
        label.sizeToFit()

        let padding: CGFloat = 6
        let size = NSSize(width: label.frame.width + padding * 2, height: label.frame.height + padding)
        label.frame.origin = NSPoint(x: padding, y: padding / 2)

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .popUpMenu
        win.hasShadow = true

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .popover
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.addSubview(label)

        win.contentView = container

        let mouseLocation = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: mouseLocation.x - size.width / 2,
                                    y: mouseLocation.y - size.height - 8))
        win.orderFront(nil)
        window = win
    }

    static func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
