import Foundation
import os

@Observable
final class UsageMonitor {
    private static let workingDirectoryKey = "workingDirectory"

    var sessionRemaining: Double = 0.0
    var weeklyRemaining: Double = 0.0
    var hasData: Bool = false
    var lastError: String?
    var lastUpdated: Date?
    var rawOutput: String?
    var debugLog: String = ""

    var workingDirectory: String? {
        get { UserDefaults.standard.string(forKey: Self.workingDirectoryKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.workingDirectoryKey)
            // Start polling when directory is first set
            if newValue != nil && !started {
                startIfNeeded()
            }
        }
    }

    var hasWorkingDirectory: Bool { workingDirectory != nil }

    private var started = false
    private var timer: Timer?
    private let pollInterval: TimeInterval = 600 // 10 minutes

    init() {
        print("[UsageMonitor] init")
        
        // Only auto-start if a working directory is already configured
        if workingDirectory != nil {
            DispatchQueue.main.async { [weak self] in
                self?.startIfNeeded()
            }
        }
    }

    func startIfNeeded() {
        guard !started, workingDirectory != nil else { return }
        started = true
        print("[UsageMonitor] starting")
        fetchUsage()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchUsage()
        }
    }

    func fetchUsage() {
        print("[UsageMonitor] fetchUsage called")
        appendDebug("fetchUsage called")
        guard let dir = workingDirectory else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let output = try await self.runClaude(workingDirectory: dir)
                print("[UsageMonitor] runClaude returned \(output.count) chars")
                self.appendDebug("runClaude returned \(output.count) chars")

                let (session, weekly) = self.parseOutput(output)
                print("[UsageMonitor] Parsed: session=\(session), weekly=\(weekly)")
                self.appendDebug("Parsed: session=\(session), weekly=\(weekly)")

                let clean = self.stripANSI(output)
                let hasPercentage = clean.contains("% used") || clean.contains("% left")

                if !hasPercentage {
                    throw UsageError.parseFailed(output: output)
                }

                await MainActor.run {
                    self.rawOutput = output
                    self.sessionRemaining = session
                    self.weeklyRemaining = weekly
                    self.hasData = true
                    self.lastError = nil
                    self.lastUpdated = Date()
                }
            } catch {
                print("[UsageMonitor] Error: \(error)")
                self.appendDebug("Error: \(error)")
                let capturedOutput: String?
                switch error {
                case UsageError.timeout(let output), UsageError.parseFailed(let output):
                    capturedOutput = output
                default:
                    capturedOutput = nil
                }
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    if let output = capturedOutput {
                        self.rawOutput = output
                    }
                }
            }
        }
    }

    nonisolated private func appendDebug(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)"
        Task { @MainActor in
            self.debugLog += "\n\(line)"
        }
    }

    // MARK: - Claude CLI Invocation

    nonisolated private func runClaude(workingDirectory: String) async throws -> String {
        let claudePath = try Self.findClaudeBinary()
        print("[UsageMonitor] Found claude at: \(claudePath)")

        // claude /usage requires a PTY (interactive mode)
        var primary: Int32 = 0
        var replica: Int32 = 0
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
            throw UsageError.ptyFailed
        }
        print("[UsageMonitor] PTY created: primary=\(primary), replica=\(replica)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["/usage"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color",
        ]) { _, new in new }

        let replicaHandle = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        process.standardInput = replicaHandle
        process.standardOutput = replicaHandle
        process.standardError = replicaHandle

        print("[UsageMonitor] Launching: \(claudePath) /usage (with PTY)")
        try process.run()
        let pid = process.processIdentifier
        print("[UsageMonitor] Process launched, pid=\(pid)")

        // Close replica in the parent
        close(replica)

        // Set primary fd to non-blocking
        let flags = fcntl(primary, F_GETFL)
        _ = fcntl(primary, F_SETFL, flags | O_NONBLOCK)

        // Read output on a background thread, return via continuation
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [self] in
                var outputData = Data()
                let deadline = Date().addingTimeInterval(30)
                let stallTimeout: TimeInterval = 10
                var lastDataTime = Date()
                var foundUsageData = false

                func readPTY() -> Data {
                    var buffer = [UInt8](repeating: 0, count: 65536)
                    let n = Darwin.read(primary, &buffer, buffer.count)
                    if n > 0 { return Data(buffer[..<n]) }
                    return Data()
                }

                while Date() < deadline {
                    let available = readPTY()

                    if available.isEmpty && !process.isRunning {
                        print("[UsageMonitor] Process exited naturally")
                        break
                    }

                    if !available.isEmpty {
                        outputData.append(available)
                        lastDataTime = Date()
                        let raw = String(data: outputData, encoding: .utf8) ?? ""
                        let cleaned = self.stripANSI(raw)
                        print("[UsageMonitor] PTY chunk: \(available.count) bytes (total: \(outputData.count))")

                        if cleaned.contains("% used") || cleaned.contains("% left") {
                            print("[UsageMonitor] Found percentage marker, waiting 1s for rest")
                            Thread.sleep(forTimeInterval: 1.0)
                            while true {
                                let more = readPTY()
                                if more.isEmpty { break }
                                outputData.append(more)
                            }
                            foundUsageData = true
                            break
                        }
                    } else if !outputData.isEmpty && process.isRunning &&
                                Date().timeIntervalSince(lastDataTime) > stallTimeout {
                        // Got some output then stalled — likely waiting for input
                        print("[UsageMonitor] Stall detected, likely waiting for input")
                        break
                    }

                    Thread.sleep(forTimeInterval: 0.3)
                }

                let output = String(data: outputData, encoding: .utf8) ?? ""
                print("[UsageMonitor] Got \(output.count) chars, cleaning up process")

                // Clean up process before resuming
                close(primary)
                kill(pid, SIGKILL)
                DispatchQueue.global().async {
                    var status: Int32 = 0
                    waitpid(pid, &status, 0)
                    print("[UsageMonitor] Process \(pid) reaped")
                }

                if foundUsageData {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UsageError.timeout(output: output))
                }
            }
        }
    }

    nonisolated static func findClaudeBinary() throws -> String {
        let home = NSHomeDirectory()
        let candidates = ["claude", "claude-bun"]
        let searchPaths = [
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/current/bin",
        ]

        for candidate in candidates {
            for dir in searchPaths {
                let path = "\(dir)/\(candidate)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    print("[UsageMonitor] Found: \(path)")
                    return path
                }
            }
        }
        throw UsageError.claudeNotFound
    }

    // MARK: - Output Parsing

    nonisolated func parseOutput(_ rawOutput: String) -> (session: Double, weekly: Double) {
        let clean = stripANSI(rawOutput)
        let quotas = parseQuotas(clean)
        print("[UsageMonitor] Found \(quotas.count) quotas")

        var session: Double?
        var weekly: Double?

        for quota in quotas {
            print("[UsageMonitor] Quota: remaining=\(quota.percentRemaining)")
            switch quota.type {
            case .session:
                session = (100.0 - quota.percentRemaining) / 100.0
            case .weekly:
                weekly = (100.0 - quota.percentRemaining) / 100.0
            case .modelSpecific:
                break
            }
        }

        return (session ?? 0.0, weekly ?? 0.0)
    }

    nonisolated func stripANSI(_ text: String) -> String {
        let cursorForwardRegex = try! NSRegularExpression(pattern: "\\x1B\\[(\\d*)C")
        var result = text
        let matches = cursorForwardRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            let fullRange = Range(match.range, in: result)!
            var count = 1
            if let digitRange = Range(match.range(at: 1), in: result), !result[digitRange].isEmpty {
                count = max(1, Int(result[digitRange]) ?? 1)
            }
            let spaces = String(repeating: " ", count: min(count, 4))
            result.replaceSubrange(fullRange, with: spaces)
        }

        let ansiRegex = try! NSRegularExpression(pattern: "\\x1B(?:[@-Z\\\\\\-_]|\\[[0-?]*[ -/]*[@-~]|\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\))")
        result = ansiRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

        return result
    }

    nonisolated private func parseQuotas(_ text: String) -> [Quota] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var quotas: [Quota] = []

        let quotaLabels: [(pattern: String, type: QuotaType, model: String?)] = [
            ("current session", .session, nil),
            ("current week (all models)", .weekly, nil),
            ("current week (opus)", .modelSpecific, "opus"),
            ("current week (opus only)", .modelSpecific, "opus"),
            ("current week (sonnet)", .modelSpecific, "sonnet"),
            ("current week (sonnet only)", .modelSpecific, "sonnet"),
            ("opus usage", .modelSpecific, "opus"),
            ("sonnet usage", .modelSpecific, "sonnet"),
        ]

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            for label in quotaLabels {
                if lower.contains(label.pattern) {
                    let searchRange = lines[i..<min(i + 5, lines.count)]
                    let searchText = searchRange.joined(separator: "\n")
                    print("[UsageMonitor] Matched '\(label.pattern)' on line \(i)")

                    if let percent = parsePercentage(searchText) {
                        print("[UsageMonitor]   -> remaining: \(percent)%")
                        quotas.append(Quota(type: label.type, model: label.model, percentRemaining: percent))
                    } else {
                        print("[UsageMonitor]   -> no percentage found nearby")
                    }
                    break
                }
            }
        }

        return quotas
    }

    nonisolated private func parsePercentage(_ text: String) -> Double? {
        let regex = try! NSRegularExpression(pattern: "(\\d{1,3})\\s*%\\s*(used|left)")
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let num = Double(text[numRange]),
              let dirRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        return String(text[dirRange]) == "used" ? 100.0 - num : num
    }
}

// MARK: - Types

enum QuotaType {
    case session, weekly, modelSpecific
}

struct Quota {
    let type: QuotaType
    let model: String?
    let percentRemaining: Double
}

enum UsageError: LocalizedError {
    case claudeNotFound
    case ptyFailed
    case timeout(output: String)
    case parseFailed(output: String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound: "Could not find claude CLI binary"
        case .ptyFailed: "Failed to create pseudo-terminal"
        case .timeout: "Claude timed out (possibly waiting for input)"
        case .parseFailed: "Could not parse usage data from output"
        }
    }
}
