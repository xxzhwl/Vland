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

struct AIAgentTranscriptSnapshot {
    let transcriptPath: String
    let reconciledAt: Date
    let lastAgentOutput: String?
    let lastAgentOutputAt: Date?
    let subtasks: [AIAgentSubtask]
    let indicatesCompletion: Bool

    var fingerprint: String {
        let taskFingerprint = subtasks.map {
            "\($0.id)|\($0.status.rawValue)|\($0.title)|\($0.summary ?? "")"
        }.joined(separator: "||")
        return [
            transcriptPath,
            lastAgentOutput ?? "",
            lastAgentOutputAt?.ISO8601Format() ?? "",
            indicatesCompletion ? "complete" : "active",
            taskFingerprint,
        ].joined(separator: "###")
    }
}

final class AIAgentTranscriptReconciler {
    private let tailByteLimit = 1024 * 1024
    private let tailLineLimit = 2000

    func reconcile(source: AIAgentType, transcriptPath: String) -> AIAgentTranscriptSnapshot? {
        let normalizedPath = URL(fileURLWithPath: transcriptPath).standardized.path
        guard FileManager.default.fileExists(atPath: normalizedPath) else { return nil }

        let now = Date()
        let jsonlEntries = loadJSONLEntries(from: normalizedPath)
        let latestAgentMessage = latestAgentMessage(from: jsonlEntries)
            ?? latestLegacyAgentMessage(from: normalizedPath)
        let subtasks = latestPlanSubtasks(source: source, entries: jsonlEntries)
        let indicatesCompletion = jsonlEntries.contains { entry in
            guard let payload = entry.payload else { return false }
            return entry.type == "event_msg" && payload["type"] as? String == "task_complete"
        }

        if latestAgentMessage == nil && subtasks.isEmpty && !indicatesCompletion {
            return nil
        }

        return AIAgentTranscriptSnapshot(
            transcriptPath: normalizedPath,
            reconciledAt: now,
            lastAgentOutput: latestAgentMessage?.message,
            lastAgentOutputAt: latestAgentMessage?.timestamp,
            subtasks: subtasks,
            indicatesCompletion: indicatesCompletion
        )
    }

    private func loadJSONLEntries(from transcriptPath: String) -> [TranscriptEntry] {
        let lines = readTailLines(from: transcriptPath)
        return lines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return TranscriptEntry(json: json)
        }
    }

    private func readTailLines(from path: String) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = max(0, Int64(fileSize) - Int64(tailByteLimit))
        try? handle.seek(toOffset: UInt64(offset))

        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if lines.count > tailLineLimit {
            return Array(lines.suffix(tailLineLimit))
        }
        return lines
    }

    private func latestAgentMessage(from entries: [TranscriptEntry]) -> ReconcilerMessage? {
        for entry in entries.reversed() {
            guard let payload = entry.payload else { continue }

            if entry.type == "event_msg" {
                let payloadType = payload["type"] as? String
                if payloadType == "agent_message",
                   let message = nonEmptyString(payload["message"]) {
                    return ReconcilerMessage(
                        message: message,
                        timestamp: entry.timestamp
                    )
                }

                if payloadType == "task_complete",
                   let message = nonEmptyString(payload["last_agent_message"]) {
                    return ReconcilerMessage(
                        message: message,
                        timestamp: entry.timestamp
                    )
                }
            }

            if entry.type == "response_item",
               payload["type"] as? String == "message",
               payload["role"] as? String == "assistant",
               let content = payload["content"] as? [[String: Any]] {
                let texts = content.compactMap { block -> String? in
                    guard block["type"] as? String == "output_text" else { return nil }
                    return nonEmptyString(block["text"])
                }
                if !texts.isEmpty {
                    return ReconcilerMessage(
                        message: texts.joined(separator: "\n"),
                        timestamp: entry.timestamp
                    )
                }
            }
        }

        return nil
    }

    private func latestLegacyAgentMessage(from transcriptPath: String) -> ReconcilerMessage? {
        let transcriptURL = URL(fileURLWithPath: transcriptPath)
        let messagesDirectory = transcriptURL.deletingLastPathComponent().appendingPathComponent("messages")
        guard FileManager.default.fileExists(atPath: messagesDirectory.path),
              let data = try? Data(contentsOf: transcriptURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return nil
        }

        for metadata in messages.reversed() {
            guard metadata["role"] as? String == "assistant",
                  let messageID = nonEmptyString(metadata["id"]) else {
                continue
            }

            let messageURL = messagesDirectory.appendingPathComponent("\(messageID).json")
            guard let messageData = try? Data(contentsOf: messageURL),
                  let messageJSON = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
                  let rawMessage = nonEmptyString(messageJSON["message"]),
                  let payloadData = rawMessage.data(using: .utf8),
                  let payloadJSON = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }

            if let content = payloadJSON["content"] as? String, !content.isEmpty {
                return ReconcilerMessage(message: content, timestamp: nil)
            }

            if let content = payloadJSON["content"] as? [[String: Any]] {
                let texts = content.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return nonEmptyString(block["text"])
                }
                if !texts.isEmpty {
                    return ReconcilerMessage(message: texts.joined(separator: "\n"), timestamp: nil)
                }
            }
        }

        return nil
    }

    private func latestPlanSubtasks(source: AIAgentType, entries: [TranscriptEntry]) -> [AIAgentSubtask] {
        guard !entries.isEmpty else { return [] }

        var currentTurnStart = 0
        for (index, entry) in entries.enumerated() {
            guard let payload = entry.payload else { continue }

            if entry.type == "event_msg",
               let payloadType = payload["type"] as? String,
               payloadType == "task_started" || payloadType == "user_message" {
                currentTurnStart = index
            }

            if source == .codebuddy || source == .workbuddy,
               entry.type == "response_item",
               payload["role"] as? String == "user" {
                currentTurnStart = index
            }
        }

        let currentTurnPayload = latestUpdatePlanPayload(
            in: Array(entries[currentTurnStart...])
        )
        let fallbackPayload = currentTurnStart > 0 ? latestUpdatePlanPayload(in: entries) : nil
        return normalizePlanSubtasks(from: currentTurnPayload ?? fallbackPayload)
    }

    private func latestUpdatePlanPayload(in entries: [TranscriptEntry]) -> [String: Any]? {
        var latestPayload: [String: Any]?

        for entry in entries {
            guard let payload = entry.payload else { continue }

            if entry.type == "response_item",
               payload["type"] as? String == "function_call",
               payload["name"] as? String == "update_plan",
               let arguments = parseJSONObject(payload["arguments"]) {
                latestPayload = arguments
            }

            if entry.type == "event_msg",
               payload["type"] as? String == "update_plan" {
                if let plan = payload["plan"] as? [String: Any] {
                    latestPayload = plan
                } else if let data = payload["data"] as? [String: Any] {
                    latestPayload = data
                } else if let planArray = payload["plan"] as? [[String: Any]] {
                    latestPayload = ["plan": planArray]
                }
            }
        }

        return latestPayload
    }

    private func normalizePlanSubtasks(from payload: [String: Any]?) -> [AIAgentSubtask] {
        guard let payload,
              let plan = payload["plan"] as? [[String: Any]] else {
            return []
        }

        let sharedSummary = nonEmptyString(payload["explanation"])

        return plan.enumerated().compactMap { index, item in
            let rawTitle = item["step"] ?? item["title"] ?? item["content"]
            guard let title = nonEmptyString(rawTitle) else { return nil }

            let summary = nonEmptyString(item["summary"])
                ?? (status(from: item["status"]) == .inProgress ? sharedSummary : nil)

            return AIAgentSubtask(
                id: nonEmptyString(item["id"]) ?? String(index + 1),
                kind: .plan,
                status: status(from: item["status"]),
                title: title,
                summary: summary
            )
        }
    }

    private func parseJSONObject(_ value: Any?) -> [String: Any]? {
        if let json = value as? [String: Any] {
            return json
        }

        guard let raw = value as? String,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    private func status(from rawValue: Any?) -> AIAgentSubtask.Status {
        let stringValue = (rawValue as? String) ?? "pending"
        switch stringValue.lowercased() {
        case "in_progress", "in-progress", "inprogress", "running", "active":
            return .inProgress
        case "completed", "complete", "done":
            return .completed
        case "failed", "error", "aborted":
            return .failed
        case "cancelled", "canceled":
            return .cancelled
        default:
            return .pending
        }
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TranscriptEntry {
    let type: String
    let timestamp: Date?
    let payload: [String: Any]?

    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        self.type = type

        if let rawTimestamp = json["timestamp"] as? TimeInterval, rawTimestamp > 0 {
            self.timestamp = Date(timeIntervalSince1970: rawTimestamp)
        } else {
            self.timestamp = nil
        }

        self.payload = json["payload"] as? [String: Any]
    }
}

private struct ReconcilerMessage {
    let message: String
    let timestamp: Date?
}
