/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import os.log

/// Represents a tmux target (session:window.pane)
struct TmuxTarget {
    let session: String
    let window: Int
    let pane: Int

    var targetString: String {
        "\(session):\(window).\(pane)"
    }

    init?(from target: String) {
        let parts = target.components(separatedBy: ":")
        guard parts.count == 2 else { return nil }

        self.session = parts[0]

        let windowPane = parts[1].components(separatedBy: ".")
        guard windowPane.count == 2,
              let window = Int(windowPane[0]),
              let pane = Int(windowPane[1]) else { return nil }

        self.window = window
        self.pane = pane
    }

    init(session: String, window: Int, pane: Int) {
        self.session = session
        self.window = window
        self.pane = pane
    }
}

/// Controller for tmux operations
actor TmuxController {
    static let shared = TmuxController()

    private let logger = OSLog(subsystem: "com.Ebullioscopic.Vland", category: "Tmux")

    private init() {}

    /// Find tmux executable path
    func getTmuxPath() -> String? {
        // Common locations for tmux
        let paths = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try to find via which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "tmux"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !result.isEmpty {
                return result
            }
        } catch {
            // Ignore error
        }

        return nil
    }

    /// Find tmux target for a given TTY
    func findTarget(forTTY tty: String) -> TmuxTarget? {
        guard let tmuxPath = getTmuxPath() else {
            os_log(.error, log: logger, "tmux not found")
            return nil
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let normalizedTTY = tty.replacingOccurrences(of: "/dev/", with: "")

            for line in output.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneTty = parts[1].replacingOccurrences(of: "/dev/", with: "")

                if paneTty == normalizedTTY {
                    return TmuxTarget(from: target)
                }
            }
        } catch {
            os_log(.error, log: logger, "Error finding tmux target: %{public}@", error.localizedDescription)
        }

        return nil
    }

    /// Send a message to a tmux target
    func sendMessage(_ message: String, to target: TmuxTarget) -> Bool {
        guard let tmuxPath = getTmuxPath() else {
            os_log(.error, log: logger, "tmux not found")
            return false
        }

        let targetStr = target.targetString

        do {
            // Send text literally
            let textProcess = Process()
            textProcess.executableURL = URL(fileURLWithPath: tmuxPath)
            textProcess.arguments = ["send-keys", "-t", targetStr, "-l", message]

            try textProcess.run()
            textProcess.waitUntilExit()

            guard textProcess.terminationStatus == 0 else {
                os_log(.error, log: logger, "Failed to send text to tmux")
                return false
            }

            // Send Enter key
            let enterProcess = Process()
            enterProcess.executableURL = URL(fileURLWithPath: tmuxPath)
            enterProcess.arguments = ["send-keys", "-t", targetStr, "Enter"]

            try enterProcess.run()
            enterProcess.waitUntilExit()

            guard enterProcess.terminationStatus == 0 else {
                os_log(.error, log: logger, "Failed to send Enter to tmux")
                return false
            }

            os_log(.debug, log: logger, "Sent message to tmux target: %{public}@", targetStr)
            return true
        } catch {
            os_log(.error, log: logger, "Error sending message to tmux: %{public}@", error.localizedDescription)
            return false
        }
    }

    /// Check if tmux is available
    func isAvailable() -> Bool {
        getTmuxPath() != nil
    }
}
