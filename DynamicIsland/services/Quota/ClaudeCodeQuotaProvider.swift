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

final class ClaudeCodeQuotaProvider: QuotaProviding {
    let agent: AIAgentType = .claudeCode
    let source = "status-line-hook"

    private let queue = DispatchQueue(label: "com.vland.quota.claude-cli", qos: .utility)
    private let usageFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vland/quota/claude-usage.json")
    private var snapshot: QuotaSnapshot?
    private var changeHandler: ((QuotaSnapshot) -> Void)?

    func currentSnapshot() -> QuotaSnapshot? {
        snapshot
    }

    func onChange(_ handler: @escaping (QuotaSnapshot) -> Void) {
        changeHandler = handler
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let nextSnapshot = self.readSnapshot()
            DispatchQueue.main.async {
                self.snapshot = nextSnapshot
                self.changeHandler?(nextSnapshot)
            }
        }
    }

    func stop() {}

    private func readSnapshot() -> QuotaSnapshot {
        guard FileManager.default.fileExists(atPath: usageFile.path) else {
            return QuotaSnapshot(
                agent: agent,
                windows: [],
                probeState: .notConfigured,
                updatedAt: nil,
                sourceDescription: usageFile.path
            )
        }

        guard let data = try? Data(contentsOf: usageFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshot = QuotaParsers.parseClaudeCodeSnapshot(
                from: object,
                source: source,
                sourceDetail: usageFile.path
              ) else {
            return QuotaSnapshot(
                agent: agent,
                windows: [],
                probeState: .unavailable,
                updatedAt: nil,
                sourceDescription: usageFile.path
            )
        }

        return snapshot
    }
}

