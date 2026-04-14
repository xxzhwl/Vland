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

enum TranscriptReaderError: Error, LocalizedError {
    case noPath
    case noSessionId
    case unsupportedAgent
    case fileNotFound(String)
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .noPath: return "No transcript path available"
        case .noSessionId: return "No session ID available"
        case .unsupportedAgent: return "This agent does not support full history"
        case .fileNotFound(let path): return "Transcript file not found: \(path)"
        case .readError(let msg): return "Failed to read transcript: \(msg)"
        }
    }
}

/// 从 AI Agent 的本地 transcript 文件中读取完整对话历史
final class TranscriptReader {
    private let tailByteLimit = 1024 * 1024
    private let tailLineLimit = 2000

    /// 统一入口：根据 agent 类型选择解析方式
    static func readTranscript(
        agentType: AIAgentType,
        transcriptPath: String?,
        sessionId: String? = nil
    ) async throws -> [TranscriptMessage] {
        // Run heavy file I/O on a background thread
        try await Task.detached(priority: .utility) {
            let reader = TranscriptReader()

            switch agentType {
            case .codebuddy:
                // 索引文件 + messages 目录
                guard let path = transcriptPath, !path.isEmpty else {
                    throw TranscriptReaderError.noPath
                }
                return try reader.readIndexedTranscript(from: path)

            case .claudeCode:
                // Claude Code uses single-file JSONL at ~/.claude/projects/<hash>/<session-id>.jsonl
                guard let path = transcriptPath, !path.isEmpty else {
                    throw TranscriptReaderError.noPath
                }
                return try reader.readClaudeCodeTranscript(from: path)

            case .codex:
                // 单文件 JSONL
                let path = try reader.resolveCodexPath(
                    transcriptPath: transcriptPath,
                    sessionId: sessionId
                )
                return try reader.readCodexTranscript(from: path)

            case .cursor, .geminiCLI, .workbuddy:
                throw TranscriptReaderError.unsupportedAgent
            }
        }.value
    }

    // MARK: - CodeBuddy / Claude Code (indexed format)

    private func readIndexedTranscript(from path: String) throws -> [TranscriptMessage] {
        let normalizedPath = URL(fileURLWithPath: path).standardized.path
        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            throw TranscriptReaderError.fileNotFound(normalizedPath)
        }

        let messagesDir = (normalizedPath as NSString)
            .deletingLastPathComponent
            .appending("/messages")

        // 1. 尝试读取索引文件
        let index = readIndex(path: normalizedPath)

        // 2. 如果有 messages 目录，按索引读取每条消息
        if !index.isEmpty && FileManager.default.fileExists(atPath: messagesDir) {
            return readMessagesFromDirectory(index: index, messagesDir: messagesDir)
        }

        // 3. 如果没有索引或没有 messages 目录，尝试作为 JSONL 读取
        return readJSONLTranscript(from: normalizedPath)
    }

    /// 解析索引文件
    private func readIndex(path: String) -> [MessageMeta] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return []
        }

        // 尝试 JSON 格式 (CodeBuddy legacy)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msgs = json["messages"] as? [[String: Any]] {
            return msgs.compactMap { MessageMeta(from: $0) }
        }

        // 尝试 JSONL 格式 (Claude Code / CodeBuddy new)
        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []
        return lines.compactMap { line in
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return nil }
            return MessageMeta(from: json)
        }
    }

    /// 按 index + messages 目录读取完整消息
    private func readMessagesFromDirectory(index: [MessageMeta], messagesDir: String) -> [TranscriptMessage] {
        var messages: [TranscriptMessage] = []

        for entry in index {
            let msgFile = (messagesDir as NSString)
                .appendingPathComponent("\(entry.id).json")
            if let msg = readMessageFile(path: msgFile, meta: entry) {
                messages.append(msg)
            }
        }

        return messages
    }

    /// 解析单条消息文件
    private func readMessageFile(path: String, meta: MessageMeta) -> TranscriptMessage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // 消息内容可能嵌套在 "message" 字段中（JSON 字符串）
        let messageBody: [String: Any]
        if let rawMsg = json["message"] as? String,
           let msgData = rawMsg.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any] {
            messageBody = parsed
        } else {
            messageBody = json
        }

        let role = TranscriptMessage.MessageRole(
            rawValue: messageBody["role"] as? String ?? "assistant"
        ) ?? .assistant

        let content = parseContent(messageBody["content"])

        return TranscriptMessage(
            id: meta.id,
            role: role,
            timestamp: meta.timestamp,
            content: content
        )
    }

    // MARK: - JSONL format (CodeBuddy new / Claude Code)

    // MARK: - Claude Code (single-file JSONL)

    /// Read Claude Code transcript from `~/.claude/projects/<hash>/<session-id>.jsonl`
    ///
    /// Each line is a JSON object with a `type` field:
    /// - `type: "user"` → `{type: "user", message: {role: "user", content: [...]}, uuid, timestamp, ...}`
    /// - `type: "assistant"` → `{type: "assistant", message: {role: "assistant", content: [...]}, uuid, timestamp, ...}`
    /// Content blocks: `text`, `tool_use` (with `id`, `name`, `input`), `tool_result` (with `tool_use_id`, `content`), `thinking`
    private func readClaudeCodeTranscript(from path: String) throws -> [TranscriptMessage] {
        let normalizedPath = URL(fileURLWithPath: path).standardized.path
        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            throw TranscriptReaderError.fileNotFound(normalizedPath)
        }

        let lines = readTailLines(from: normalizedPath)
        var messages: [TranscriptMessage] = []

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let entryType = json["type"] as? String ?? ""

            // Only process user and assistant message entries
            guard entryType == "user" || entryType == "assistant" else { continue }

            // The message content is in the "message" field
            guard let messageDict = json["message"] as? [String: Any] else { continue }

            let role = TranscriptMessage.MessageRole(
                rawValue: messageDict["role"] as? String ?? "assistant"
            ) ?? .assistant

            let content = parseContent(messageDict["content"])
            guard !content.isEmpty else { continue }

            // Timestamp from ISO8601 string
            let timestamp: Date?
            if let ts = json["timestamp"] as? String {
                timestamp = parseISO8601(ts)
            } else if let ts = json["timestamp"] as? TimeInterval {
                timestamp = Date(timeIntervalSince1970: ts)
            } else {
                timestamp = nil
            }

            let msgId = json["uuid"] as? String ?? json["id"] as? String ?? "claude-\(index)"

            messages.append(TranscriptMessage(
                id: msgId,
                role: role,
                timestamp: timestamp,
                content: content
            ))
        }

        return messages
    }

    // MARK: - JSONL format (CodeBuddy new / Claude Code legacy)

    private func readJSONLTranscript(from path: String) -> [TranscriptMessage] {
        let lines = readTailLines(from: path)
        var messages: [TranscriptMessage] = []

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""

            // CodeBuddy/Claude Code format: direct message entries
            if let role = json["role"] as? String,
               role == "user" || role == "assistant" {
                let content = parseContent(json["content"])
                let timestamp = (json["timestamp"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
                let msgId = json["id"] as? String ?? "jsonl-\(index)"

                if !content.isEmpty {
                    messages.append(TranscriptMessage(
                        id: msgId,
                        role: role == "user" ? .user : .assistant,
                        timestamp: timestamp,
                        content: content
                    ))
                }
                continue
            }

            // Codex-style: type == "response_item"
            if type == "response_item",
               let payload = json["payload"] as? [String: Any] {
                let role = payload["role"] as? String ?? ""
                guard role == "user" || role == "assistant" else { continue }

                let content = parseCodexContent(payload["content"])
                let timestamp = (json["timestamp"] as? String).flatMap(parseISO8601)
                let msgId = payload["id"] as? String ?? "codex-\(index)"

                if !content.isEmpty {
                    messages.append(TranscriptMessage(
                        id: msgId,
                        role: role == "user" ? .user : .assistant,
                        timestamp: timestamp,
                        content: content
                    ))
                }
            }
        }

        return messages
    }

    // MARK: - Codex (single-file JSONL)

    private func resolveCodexPath(transcriptPath: String?, sessionId: String?) throws -> String {
        // If transcript_path is provided, use it directly
        if let path = transcriptPath, !path.isEmpty {
            let normalizedPath = URL(fileURLWithPath: path).standardized.path
            if FileManager.default.fileExists(atPath: normalizedPath) {
                return normalizedPath
            }
        }

        // Fallback: try to find by session_id via SQLite or glob
        guard let sid = sessionId, !sid.isEmpty else {
            throw TranscriptReaderError.noSessionId
        }

        // Try glob matching
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = (homeDir as NSString).appendingPathComponent(".codex/sessions")

        if let foundPath = findCodexRollout(in: sessionsDir, sessionId: sid) {
            return foundPath
        }

        throw TranscriptReaderError.noPath
    }

    private func readCodexTranscript(from path: String) throws -> [TranscriptMessage] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw TranscriptReaderError.fileNotFound(path)
        }

        let lines = readTailLines(from: path)
        var messages: [TranscriptMessage] = []

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String,
                  let payload = json["payload"] as? [String: Any]
            else { continue }

            let timestamp = (json["timestamp"] as? String).flatMap(parseISO8601)

            guard type == "response_item" else { continue }

            let role = payload["role"] as? String ?? ""
            guard role == "user" || role == "assistant" else { continue }

            let content = parseCodexContent(payload["content"])
            guard !content.isEmpty else { continue }

            messages.append(TranscriptMessage(
                id: "codex-\(index)",
                role: role == "user" ? .user : .assistant,
                timestamp: timestamp,
                content: content
            ))
        }

        return messages
    }

    private func findCodexRollout(in sessionsDir: String, sessionId: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: sessionsDir) else { return nil }

        for case let path as String in enumerator {
            if path.hasSuffix("-\(sessionId).jsonl") || path.hasSuffix("\(sessionId).jsonl") {
                let fullPath = (sessionsDir as NSString).appendingPathComponent(path)
                if fm.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }

        return nil
    }

    // MARK: - Content Parsing

    /// 解析 content 字段（CodeBuddy / Claude Code 格式）
    private func parseContent(_ raw: Any?) -> [TranscriptMessage.ContentBlock] {
        if let text = raw as? String {
            return [.text(text)]
        }
        guard let blocks = raw as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            let type = block["type"] as? String ?? ""
            switch type {
            case "text":
                if let t = block["text"] as? String { return .text(t) }
            case "tool_use":
                let name = block["name"] as? String ?? "unknown"
                let input = (block["input"] as? [String: Any])
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                return .toolUse(name: name, input: input)
            case "tool-call":
                // CodeBuddy format: toolName + args
                let name = block["toolName"] as? String ?? block["name"] as? String ?? "unknown"
                let input: String
                if let args = block["args"] as? [String: Any] {
                    input = (try? JSONSerialization.data(withJSONObject: args))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                } else if let argsStr = block["arguments"] as? String {
                    input = argsStr
                } else {
                    input = ""
                }
                return .toolUse(name: name, input: input)
            case "tool_result":
                let toolUseId = block["tool_use_id"] as? String ?? ""
                let content = block["content"] as? String
                    ?? (block["content"] as? [[String: Any]])?
                        .compactMap { $0["text"] as? String }.joined(separator: "\n")
                    ?? ""
                return .toolResult(toolUseId: toolUseId, content: content)
            case "tool-result":
                // CodeBuddy format: toolCallId + result
                let toolUseId = block["toolCallId"] as? String ?? block["tool_use_id"] as? String ?? ""
                let content: String
                if let result = block["result"] {
                    if let resultStr = result as? String {
                        content = resultStr
                    } else if let resultDict = result as? [String: Any] {
                        content = (try? JSONSerialization.data(withJSONObject: resultDict, options: [.prettyPrinted]))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    } else {
                        content = String(describing: result)
                    }
                } else if let c = block["content"] as? String {
                    content = c
                } else {
                    content = ""
                }
                return .toolResult(toolUseId: toolUseId, content: String(content.prefix(2000)))
            case "thinking":
                if let t = block["thinking"] as? String ?? block["text"] as? String {
                    return .thinking(t)
                }
            default:
                break
            }
            return nil
        }
    }

    /// 解析 Codex 格式的 content 字段
    private func parseCodexContent(_ raw: Any?) -> [TranscriptMessage.ContentBlock] {
        guard let blocks = raw as? [[String: Any]] else {
            if let text = raw as? String {
                return [.text(text)]
            }
            return []
        }

        return blocks.compactMap { block in
            let blockType = block["type"] as? String ?? ""
            switch blockType {
            case "input_text", "output_text":
                if let text = block["text"] as? String { return .text(text) }
            case "function_call":
                let name = block["name"] as? String ?? "unknown"
                let args = block["arguments"] as? String ?? ""
                return .toolUse(name: name, input: args)
            case "function_call_output":
                let output = block["output"] as? String ?? ""
                return .toolResult(toolUseId: "", content: output)
            default:
                break
            }
            return nil
        }
    }

    // MARK: - Helpers

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

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

/// 索引条目
private struct MessageMeta {
    let id: String
    let role: String?
    let timestamp: Date?

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        self.role = dict["role"] as? String
        self.timestamp = (dict["timestamp"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
    }
}
