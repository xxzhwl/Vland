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

enum QuotaParsers {
    static func parseClaudeCodeSnapshot(
        from object: [String: Any],
        source: String,
        sourceDetail: String?
    ) -> QuotaSnapshot? {
        parseClaudeSnapshot(
            agent: .claudeCode,
            object: object,
            source: source,
            sourceDetail: sourceDetail
        )
    }

    static func parseCodexSnapshot(
        from jsonlTail: String,
        source: String,
        sourceDetail: String?
    ) -> QuotaSnapshot? {
        for line in jsonlTail.split(whereSeparator: \.isNewline).reversed() {
            guard line.contains("\"token_count\""), line.contains("\"rate_limits\"") else { continue }
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let payload = (object["payload"] as? [String: Any]) ?? object
            guard string(payload["type"]) == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else {
                continue
            }

            let timestamp = date(from: object["timestamp"])
            let windows = codexWindows(from: rateLimits, timestamp: timestamp, source: source, sourceDetail: sourceDetail)
            guard !windows.isEmpty else { continue }

            return QuotaSnapshot(
                agent: .codex,
                windows: windows.sorted(by: byWindowOrder),
                probeState: windows.contains(where: { !$0.isStale }) ? .available : .stale,
                updatedAt: windows.map(\.updatedAt).max(),
                sourceDescription: sourceDetail
            )
        }

        return nil
    }

    static func parseClaudeVSCodeSnapshot(
        from logTail: String,
        source: String,
        sourceDetail: String?
    ) -> QuotaSnapshot? {
        for block in extractRateLimitsBlocks(from: logTail).reversed() {
            guard let data = block.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let snapshot = parseClaudeSnapshot(
                agent: .claudeCode,
                object: object,
                source: source,
                sourceDetail: sourceDetail
            ) {
                return snapshot
            }
        }

        return nil
    }

    static func extractRateLimitsBlocks(from text: String) -> [String] {
        let anchors = ["\"rate_limits\"", "\"rate_limit\"", "\"ratelimits\""]
        var results: [String] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            var hitRange: Range<String.Index>?

            for anchor in anchors {
                guard let range = text.range(of: anchor, range: cursor..<text.endIndex) else { continue }
                if hitRange == nil || range.lowerBound < hitRange!.lowerBound {
                    hitRange = range
                }
            }

            guard let range = hitRange else { break }
            var index = range.upperBound

            while index < text.endIndex {
                let scalar = text[index].unicodeScalars.first?.value
                if scalar == 0x20 || scalar == 0x09 || scalar == 0x3A {
                    index = text.index(after: index)
                } else {
                    break
                }
            }

            guard index < text.endIndex, text[index] == "{" else {
                cursor = range.upperBound
                continue
            }

            var depth = 0
            var current = index
            var inString = false
            var escaped = false

            while current < text.endIndex {
                let character = text[current]
                if inString {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        inString = false
                    }
                } else {
                    if character == "\"" {
                        inString = true
                    } else if character == "{" {
                        depth += 1
                    } else if character == "}" {
                        depth -= 1
                        if depth == 0 {
                            results.append(String(text[index...current]))
                            cursor = text.index(after: current)
                            break
                        }
                    }
                }

                current = text.index(after: current)
            }

            if current >= text.endIndex {
                break
            }
        }

        return results
    }

    private static func codexWindows(
        from rateLimits: [String: Any],
        timestamp: Date?,
        source: String,
        sourceDetail: String?
    ) -> [QuotaWindow] {
        let updatedAt = timestamp ?? Date()
        let primary = rateLimits["primary"] as? [String: Any]
        let secondary = rateLimits["secondary"] as? [String: Any]

        let windows = [
            codexWindow(agent: .codex, raw: primary, updatedAt: updatedAt, source: source, sourceDetail: sourceDetail),
            codexWindow(agent: .codex, raw: secondary, updatedAt: updatedAt, source: source, sourceDetail: sourceDetail),
        ]

        return windows.compactMap { $0 }
    }

    private static func codexWindow(
        agent: AIAgentType,
        raw: [String: Any]?,
        updatedAt: Date,
        source: String,
        sourceDetail: String?
    ) -> QuotaWindow? {
        guard let raw,
              let usedPercent = double(raw["used_percent"]) ?? double(raw["used_percentage"]),
              let windowMinutes = int(raw["window_minutes"]) else {
            return nil
        }

        let kind: QuotaWindowKind = windowMinutes <= 300 ? .fiveHour : .weekly
        return QuotaWindow(
            id: "\(agent.rawValue)-\(kind.rawValue)",
            agent: agent,
            kind: kind,
            usedPercent: usedPercent,
            resetsAt: date(from: raw["resets_at"]),
            windowDescription: kind == .fiveHour ? "5h" : "7d",
            updatedAt: updatedAt,
            source: source,
            sourceDetail: sourceDetail
        )
    }

    private static func window(
        agent: AIAgentType,
        kind: QuotaWindowKind,
        raw: [String: Any]?,
        timestamp: Date,
        source: String,
        sourceDetail: String?,
        fallbackLabel: String
    ) -> QuotaWindow? {
        guard let raw,
              let usedPercent = double(raw["used_percentage"]) ?? double(raw["used_percent"]) else {
            return nil
        }

        return QuotaWindow(
            id: "\(agent.rawValue)-\(kind.rawValue)",
            agent: agent,
            kind: kind,
            usedPercent: usedPercent,
            resetsAt: date(from: raw["resets_at"]) ?? date(from: raw["reset_at"]),
            windowDescription: string(raw["window_description"]) ?? fallbackLabel,
            updatedAt: timestamp,
            source: source,
            sourceDetail: sourceDetail
        )
    }

    private static func parseClaudeSnapshot(
        agent: AIAgentType,
        object: [String: Any],
        source: String,
        sourceDetail: String?
    ) -> QuotaSnapshot? {
        let updatedAt = date(from: object["updated_at"]) ?? Date()
        let rateLimits = (object["rate_limits"] as? [String: Any]) ?? object

        let fiveHour = window(
            agent: agent,
            kind: .fiveHour,
            raw: rateLimits["five_hour"] as? [String: Any],
            timestamp: updatedAt,
            source: source,
            sourceDetail: sourceDetail,
            fallbackLabel: "5h"
        )

        let weekly = window(
            agent: agent,
            kind: .weekly,
            raw: rateLimits["seven_day"] as? [String: Any],
            timestamp: updatedAt,
            source: source,
            sourceDetail: sourceDetail,
            fallbackLabel: "7d"
        )

        let windows = [fiveHour, weekly].compactMap { $0 }.sorted(by: byWindowOrder)
        guard !windows.isEmpty else { return nil }

        return QuotaSnapshot(
            agent: agent,
            windows: windows,
            probeState: windows.contains(where: { !$0.isStale }) ? .available : .stale,
            updatedAt: windows.map(\.updatedAt).max(),
            sourceDescription: sourceDetail
        )
    }

    private static func byWindowOrder(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
        if lhs.kind.sortOrder != rhs.kind.sortOrder {
            return lhs.kind.sortOrder < rhs.kind.sortOrder
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty {
            return value
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        switch value {
        case let value as Date:
            return value
        case let value as NSNumber:
            return Date(timeIntervalSince1970: value.doubleValue)
        case let value as Int:
            return Date(timeIntervalSince1970: Double(value))
        case let value as Double:
            return Date(timeIntervalSince1970: value)
        case let value as String:
            if let numeric = Double(value) {
                return Date(timeIntervalSince1970: numeric)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        default:
            return nil
        }
    }
}
