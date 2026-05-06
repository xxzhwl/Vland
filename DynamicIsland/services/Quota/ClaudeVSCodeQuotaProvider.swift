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

final class ClaudeVSCodeQuotaProvider: QuotaProviding {
    let agent: AIAgentType = .claudeCode
    let source = "vscode-log-tail"

    private let queue = DispatchQueue(label: "com.vland.quota.claude-vscode", qos: .utility)
    private let maxFiles = 30
    private let maxAgeDays = 14
    private let tailBytes: UInt64 = 512 * 1024
    private var snapshot: QuotaSnapshot?
    private var changeHandler: ((QuotaSnapshot) -> Void)?

    private lazy var logRoots: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Code/logs"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Code - Insiders/logs"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/logs"),
    ]

    func currentSnapshot() -> QuotaSnapshot? {
        snapshot
    }

    func onChange(_ handler: @escaping (QuotaSnapshot) -> Void) {
        changeHandler = handler
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let nextSnapshot = self.scanLatestSnapshot()
            DispatchQueue.main.async {
                self.snapshot = nextSnapshot
                self.changeHandler?(nextSnapshot)
            }
        }
    }

    func stop() {}

    private func scanLatestSnapshot() -> QuotaSnapshot {
        let existingRoots = logRoots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingRoots.isEmpty else {
            return QuotaSnapshot(
                agent: agent,
                windows: [],
                probeState: .notConfigured,
                updatedAt: nil,
                sourceDescription: nil
            )
        }

        var logs: [(URL, Date)] = []
        for root in existingRoots {
            logs.append(contentsOf: enumerateLogs(under: root))
        }

        for (url, _) in logs.sorted(by: { $0.1 > $1.1 }) {
            guard let tail = tailString(for: url, maxBytes: tailBytes) else { continue }
            if let snapshot = QuotaParsers.parseClaudeVSCodeSnapshot(
                from: tail,
                source: source,
                sourceDetail: url.path
            ) {
                return snapshot
            }
        }

        return QuotaSnapshot(
            agent: agent,
            windows: [],
            probeState: .unavailable,
            updatedAt: nil,
            sourceDescription: existingRoots.first?.path
        )
    }

    private func enumerateLogs(under root: URL) -> [(URL, Date)] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(URL, Date)] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "log",
                  url.path.contains("anthropic.claude-code"),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            let mtime = values.contentModificationDate ?? .distantPast
            guard mtime >= cutoff else { continue }
            files.append((url, mtime))
        }

        return Array(files.sorted(by: { $0.1 > $1.1 }).prefix(maxFiles))
    }

    private func tailString(for url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > maxBytes ? end - maxBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

