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

import Defaults
import Foundation
import SwiftUI

// MARK: - AI Agent Types

enum AIAgentType: String, Codable, CaseIterable, Identifiable {
    case codebuddy = "codebuddy"
    case claudeCode = "claude-code"
    case cursor = "cursor"
    case codex = "codex"
    case geminiCLI = "gemini-cli"
    case workbuddy = "workbuddy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codebuddy: return "CodeBuddy"
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .geminiCLI: return "Gemini CLI"
        case .workbuddy: return "WorkBuddy"
        }
    }

    var iconName: String {
        switch self {
        case .codebuddy: return "hammer.fill"
        case .claudeCode: return "terminal.fill"
        case .cursor: return "cursorarrow.rays"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: return "sparkles"
        case .workbuddy: return "briefcase.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .codebuddy: return .blue
        case .claudeCode: return .orange
        case .cursor: return .purple
        case .codex: return .green
        case .geminiCLI: return .cyan
        case .workbuddy: return .indigo
        }
    }

    /// Candidate macOS application bundle identifiers for activating the agent's window.
    /// Some agents ship different bundle IDs across channels/locales, so keep fallbacks.
    var bundleIdentifiers: [String] {
        switch self {
        case .codebuddy: return ["com.tencent.codebuddycn", "tencent-cloud.coding-copilot"]
        case .claudeCode: return []
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .codex: return ["com.openai.codex"]
        case .geminiCLI: return []
        case .workbuddy: return []
        }
    }

    /// Human-readable app names used as a fallback when bundle lookup is unavailable.
    var applicationNames: [String] {
        switch self {
        case .codebuddy: return ["CodeBuddy CN", "CodeBuddy"]
        case .claudeCode: return []
        case .cursor: return ["Cursor"]
        case .codex: return ["Codex"]
        case .geminiCLI: return []
        case .workbuddy: return ["WorkBuddy"]
        }
    }

    var bundleIdentifier: String? {
        bundleIdentifiers.first
    }

    /// 是否支持完整聊天历史读取（通过 transcript 文件）
    var supportsFullHistory: Bool {
        switch self {
        case .codebuddy, .claudeCode, .codex:
            return true
        case .cursor, .geminiCLI, .workbuddy:
            return false
        }
    }
}

// MARK: - Agent Status

enum AIAgentStatus: String, Codable {
    case idle = "idle"
    case thinking = "thinking"
    case coding = "coding"
    case running = "running"
    case waitingInput = "waiting_input"
    case completed = "completed"
    case error = "error"
    case sessionStart = "session_start"
    case sessionEnd = "session_end"

    var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .thinking: return "思考中..."
        case .coding: return "Writing Code"
        case .running: return "Running Tool"
        case .waitingInput: return "Waiting for Input"
        case .completed: return "Completed"
        case .error: return "Error"
        case .sessionStart: return "Session Started"
        case .sessionEnd: return "Session Ended"
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "moon.fill"
        case .thinking: return "brain.head.profile.fill"
        case .coding: return "curlybraces"
        case .running: return "gearshape.fill"
        case .waitingInput: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .sessionStart: return "play.circle.fill"
        case .sessionEnd: return "stop.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .thinking: return .yellow
        case .coding: return .cyan
        case .running: return .blue
        case .waitingInput: return .orange
        case .completed: return .green
        case .error: return .red
        case .sessionStart: return .green
        case .sessionEnd: return .gray
        }
    }

    var isActive: Bool {
        switch self {
        case .thinking, .coding, .running, .waitingInput:
            return true
        default:
            return false
        }
    }
}

enum AIAgentSessionPhase: String, Codable {
    case booting
    case active
    case waitingForInput
    case compacting
    case completed
    case failed
    case ended

    var isAttentionBlocking: Bool {
        self == .waitingForInput
    }
}

// MARK: - Todo Item Model

struct AIAgentTodoItem: Identifiable, Codable, Equatable {
    let id: String
    var status: TodoStatus
    let content: String

    enum TodoStatus: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = (try? container.decode(String.self))?.lowercased() ?? "pending"

            switch raw {
            case "in_progress", "in-progress", "inprogress":
                self = .inProgress
            case "completed", "complete", "done":
                self = .completed
            case "cancelled", "canceled":
                self = .cancelled
            default:
                self = .pending
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        var iconName: String {
            switch self {
            case .pending:
                return "circle"
            case .inProgress:
                return "play.circle.fill"
            case .completed:
                return "checkmark.circle.fill"
            case .cancelled:
                return "xmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .pending:
                return .gray
            case .inProgress:
                return .blue
            case .completed:
                return .green
            case .cancelled:
                return .red
            }
        }
    }
}

// MARK: - Unified Subtask Model

struct AIAgentSubtask: Identifiable, Codable, Equatable {
    let id: String
    let kind: Kind
    var status: Status
    let title: String
    let summary: String?
    let startedAt: TimeInterval?
    let completedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case status
        case title
        case summary
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    enum Kind: String, Codable {
        case transcriptTurn = "transcript_turn"
        case plan
        case todo
        case subagent
    }

    enum Status: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
        case cancelled

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = (try? container.decode(String.self))?.lowercased() ?? "pending"

            switch raw {
            case "in_progress", "in-progress", "inprogress", "running", "active":
                self = .inProgress
            case "completed", "complete", "done":
                self = .completed
            case "failed", "error", "aborted":
                self = .failed
            case "cancelled", "canceled":
                self = .cancelled
            default:
                self = .pending
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        var iconName: String {
            switch self {
            case .pending:
                return "circle"
            case .inProgress:
                return "ellipsis.circle.fill"
            case .completed:
                return "checkmark.circle.fill"
            case .failed:
                return "exclamationmark.circle.fill"
            case .cancelled:
                return "xmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .pending:
                return .gray
            case .inProgress:
                return .yellow
            case .completed:
                return .green
            case .failed:
                return .red
            case .cancelled:
                return .orange
            }
        }

        var isActive: Bool {
            self == .inProgress
        }
    }

    var subtitleText: String? {
        guard let summary, !summary.isEmpty else { return nil }
        return summary
    }

    init(
        id: String,
        kind: Kind,
        status: Status,
        title: String,
        summary: String? = nil,
        startedAt: TimeInterval? = nil,
        completedAt: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    init(todoItem: AIAgentTodoItem) {
        self.id = todoItem.id
        self.kind = .todo
        self.status = Status(todoStatus: todoItem.status)
        self.title = todoItem.content
        self.summary = nil
        self.startedAt = nil
        self.completedAt = nil
    }

    init(toolCall: AIAgentToolCall) {
        self.id = toolCall.id.uuidString
        self.kind = .subagent
        self.status = toolCall.output == nil ? .inProgress : .completed
        self.title = toolCall.displayDescription
        self.summary = toolCall.output
        self.startedAt = toolCall.timestamp.timeIntervalSince1970
        self.completedAt = toolCall.output == nil ? nil : toolCall.timestamp.timeIntervalSince1970
    }
}

private extension AIAgentSubtask.Status {
    init(todoStatus: AIAgentTodoItem.TodoStatus) {
        switch todoStatus {
        case .pending:
            self = .pending
        case .inProgress:
            self = .inProgress
        case .completed:
            self = .completed
        case .cancelled:
            self = .cancelled
        }
    }
}

// MARK: - Hook Event (from bridge)

/// The JSON event sent by the bridge script via Unix Socket
struct AIAgentHookEvent: Codable {
    let source: String          // "codebuddy", "claude-code", etc.
    let hookType: String        // "PreToolUse", "PostToolUse", "SessionStart", etc.
    let timestamp: TimeInterval
    let sessionId: String?
    let pid: Int?
    let tty: String?
    let needsResponse: Bool?
    let toolName: String?       // e.g. "read_file", "write_to_file", "execute_command"
    let toolInput: String?      // brief description of what the tool is doing
    let filePath: String?       // current file being worked on
    let project: String?        // project directory
    let transcriptPath: String?
    let message: String?        // any additional message
    let userPrompt: String?     // the user's original question/prompt
    let agentOutput: String?    // agent's response/output text
    let toolOutput: String?     // output/result from a tool call
    let todoItems: [AIAgentTodoItem]?  // parsed todo_write items
    let subtasks: [AIAgentSubtask]?    // normalized task plan items (e.g. update_plan)
    let interaction: HookInteraction?  // structured interaction data (questions, choices)
    let toolUseId: String?
    let agentId: String?
    let parentToolId: String?
    let rawHookType: String?
    let contextWindow: Int?
    let contextUsed: Int?
    let model: String?

    struct HookInteraction: Codable {
        let type: String?                // "question", "confirmation"
        let title: String?
        let responseMode: String?
        let bridgeResponseKind: String?
        let bridgeResponseContext: String?
        let questions: [HookQuestion]?

        struct HookQuestion: Codable {
            let id: String?
            let question: String?
            let options: [String]?
            let multiSelect: Bool?
        }

        enum CodingKeys: String, CodingKey {
            case type
            case title
            case responseMode
            case bridgeResponseKind = "bridgeResponseKind"
            case bridgeResponseContext = "bridgeResponseContext"
            case questions
        }
    }

    enum CodingKeys: String, CodingKey {
        case source
        case hookType = "hook_type"
        case timestamp
        case sessionId = "session_id"
        case pid
        case tty
        case needsResponse = "needs_response"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case filePath = "file_path"
        case project
        case transcriptPath = "transcript_path"
        case message
        case userPrompt = "user_prompt"
        case agentOutput = "agent_output"
        case toolOutput = "tool_output"
        case todoItems = "todo_items"
        case subtasks
        case interaction
        case toolUseId = "tool_use_id"
        case agentId = "agent_id"
        case parentToolId = "parent_tool_id"
        case rawHookType = "raw_hook_type"
        case contextWindow = "context_window"
        case contextUsed = "context_used"
        case model
    }

    var occurredAt: Date {
        guard timestamp.isFinite, timestamp > 0 else { return Date() }
        return Date(timeIntervalSince1970: timestamp)
    }
}

// MARK: - Conversation Turn (user prompt + agent response pair)

class AIAgentConversationTurn: Identifiable, ObservableObject {
    let id = UUID()
    let timestamp: Date
    let userPrompt: String
    @Published var agentResponse: String?
    @Published var toolCalls: [AIAgentToolCall]
    @Published var interactions: [AIAgentInteraction]
    @Published var isComplete: Bool

    init(timestamp: Date = Date(), userPrompt: String) {
        self.timestamp = timestamp
        self.userPrompt = userPrompt
        self.agentResponse = nil
        self.toolCalls = []
        self.interactions = []
        self.isComplete = false
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Agent Interaction (questions, confirmations, choices from agent)

struct AIAgentInteraction: Identifiable {
    enum ResponseMode {
        case pasteReply
        case approvalSelection
    }

    enum ResolutionState: Equatable {
        case pending
        case submitted(String)
        case timedOut
        case failed(String)
    }

    let id = UUID()
    let timestamp: Date
    let type: InteractionType
    let title: String?
    let message: String
    let options: [String]?
    let responseMode: ResponseMode
    let bridgeResponseKind: String?
    let bridgeResponseContext: String?
    var resolutionState: ResolutionState = .pending

    enum InteractionType {
        case question       // ask_followup_question — agent asking user to choose
        case confirmation   // agent asking user to confirm (yes/no)
        case info           // informational message from agent
    }

    var isResolved: Bool {
        switch resolutionState {
        case .pending:
            return false
        case .submitted, .timedOut, .failed:
            return true
        }
    }

    var isApprovalSelection: Bool {
        responseMode == .approvalSelection
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    init(
        timestamp: Date,
        type: InteractionType,
        title: String?,
        message: String,
        options: [String]?,
        responseMode: ResponseMode,
        bridgeResponseKind: String? = nil,
        bridgeResponseContext: String? = nil,
        resolutionState: ResolutionState = .pending
    ) {
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.message = message
        self.options = options
        self.responseMode = responseMode
        self.bridgeResponseKind = bridgeResponseKind
        self.bridgeResponseContext = bridgeResponseContext
        self.resolutionState = resolutionState
    }
}

// MARK: - Tool Call Record

struct AIAgentToolCall: Identifiable {
    let id = UUID()
    let timestamp: Date
    let toolName: String
    let input: String?       // what the tool received (file path, command, etc.)
    var output: String?      // what the tool returned
    let filePath: String?

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    /// Human-friendly description of the tool action
    var displayDescription: String {
        switch toolName {
        case "read_file":
            if let path = filePath ?? input { return "Read \((path as NSString).lastPathComponent)" }
            return "Read file"
        case "write_to_file":
            if let path = filePath ?? input { return "Write \((path as NSString).lastPathComponent)" }
            return "Write file"
        case "replace_in_file":
            if let path = filePath ?? input { return "Edit \((path as NSString).lastPathComponent)" }
            return "Edit file"
        case "execute_command":
            if let cmd = input { return "Run: \(String(cmd.prefix(60)))" }
            return "Run command"
        case "search_content", "search_file":
            if let q = input { return "Search: \(String(q.prefix(40)))" }
            return "Search codebase"
        case "list_dir":
            if let dir = input { return "List \((dir as NSString).lastPathComponent)" }
            return "Browse directory"
        case "web_search":
            if let q = input { return "Search web: \(String(q.prefix(40)))" }
            return "Search web"
        case "web_fetch":
            if let url = input { return "Fetch: \(String(url.prefix(50)))" }
            return "Fetch URL"
        case "task":
            if let description = input, !description.isEmpty {
                return "Subagent: \(String(description.prefix(60)))"
            }
            return "Run subagent"
        default:
            if let inp = input { return "\(toolName): \(String(inp.prefix(40)))" }
            return "Using \(toolName)"
        }
    }
}

// MARK: - Chat Display Mode

enum AIAgentChatMode: String, Codable, CaseIterable, Defaults.Serializable, Identifiable {
    case compact   // 简洁模式：5 轮 + 工具列表
    case detailed  // 详细模式：完整 transcript + Markdown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "简洁模式"
        case .detailed: return "详细模式"
        }
    }

    var description: String {
        switch self {
        case .compact: return "最近 5 轮对话 + 工具调用列表"
        case .detailed: return "完整聊天历史 + Markdown 渲染"
        }
    }

    var iconName: String {
        switch self {
        case .compact: return "list.bullet"
        case .detailed: return "book.pages"
        }
    }
}

// MARK: - Transcript Message (from transcript files)

/// 来自 transcript 文件的完整消息，用于详细模式显示
struct TranscriptMessage: Identifiable {
    let id: String           // message id from transcript
    let role: MessageRole
    let timestamp: Date?
    let content: [ContentBlock]

    enum MessageRole: String {
        case user
        case assistant
        case system
        case tool
    }

    enum ContentBlock {
        case text(String)
        case toolUse(name: String, input: String)
        case toolResult(toolUseId: String, content: String)
        case thinking(String)     // Claude 的 <thinking> 块
    }

    /// 提取纯文本内容（用于搜索和摘要）
    var plainText: String {
        content.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined(separator: "\n")
    }

    /// Markdown 格式的完整内容
    var markdownContent: String {
        content.map { block in
            switch block {
            case .text(let t): return t
            case .toolUse(let name, let input):
                return "🔧 **\(name)**\n```\n\(input.prefix(200))\n```"
            case .toolResult(_, let content):
                return "```\n\(content.prefix(500))\n```"
            case .thinking(let t):
                return "> 💭 \(t.prefix(200))..."
            }
        }.joined(separator: "\n\n")
    }

    /// 提取用户消息的实际查询内容（过滤掉系统注入的 user_info、rules 等）
    /// 用于在 UI 中显示干净的用户消息
    var displayText: String {
        guard role == .user else {
            return plainText  // 非用户消息直接返回原文
        }

        // 优先尝试提取 <user_query> 标签内的内容
        if let extracted = Self.extractUserQuery(from: plainText) {
            return extracted
        }

        // 后备：过滤掉常见的系统注入内容
        return Self.filterSystemContent(from: plainText)
    }

    /// 获取用于显示的内容块（对用户消息进行过滤处理）
    var displayContent: [ContentBlock] {
        guard role == .user else { return content }

        let displayStr = displayText
        if displayStr.isEmpty { return [] }
        return [.text(displayStr)]
    }

    /// 从文本中提取 <user_query> 标签的内容
    private static func extractUserQuery(from text: String) -> String? {
        let pattern = "<user_query>([\\s\\S]*?)</user_query>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let extracted = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    /// 过滤掉系统注入的内容
    private static func filterSystemContent(from text: String) -> String {
        var result = text

        // 要过滤的系统标签列表
        let systemTags = [
            "user_info", "rules", "agent_requestable_workspace_rules",
            "git_status", "project_context", "project_layout",
            "cb_summary", "additional_data", "system_reminder",
            "content_policy", "communication", "tool_calling",
            "maximize_parallel_tool_calls", "maximize_context_understanding",
            "code-explorer_subagent_usage", "making_code_changes",
            "automations", "citing_code", "inline_line_numbers",
            "task_management", "mcp_protocol", "integrations_protocol",
            "response_language", "agent_skills", "available_skills",
            "available_knowledge_bases",
        ]

        // 移除所有系统标签及其内容
        for tag in systemTags {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // 清理多余空行
        return result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Agent Session

class AIAgentSession: ObservableObject, Identifiable {
    let id: UUID
    let agentType: AIAgentType
    let startTime: Date
    let sessionId: String?

    @Published var status: AIAgentStatus
    @Published var phase: AIAgentSessionPhase
    @Published var currentTask: String
    @Published var currentTool: String?
    @Published var currentFile: String?
    @Published var project: String?
    @Published var lastActivity: Date
    @Published var lastUserPromptAt: Date?
    @Published var lastMeaningfulOutputAt: Date?
    @Published var lastNotificationAt: Date?
    @Published var lastAttentionRequestAt: Date?
    @Published var lastTranscriptReconciledAt: Date?
    @Published var pid: Int?
    @Published var tty: String?
    @Published var transcriptPath: String?
    @Published var toolUseId: String?
    @Published var agentInstanceId: String?
    @Published var parentToolId: String?
    @Published var rawHookType: String?
    @Published var isArchived: Bool
    @Published var eventLog: [AIAgentActivityEntry]

    /// Context window tracking
    @Published var modelName: String?
    @Published var contextWindowSize: Int?
    @Published var contextUsedTokens: Int?
    @Published var compactCount: Int = 0

    /// Conversation history: each user prompt → agent response cycle
    @Published var conversationTurns: [AIAgentConversationTurn]

    /// Latest user prompt text (for display in card)
    @Published var lastUserPrompt: String?

    /// Latest agent output text (for display in card)
    @Published var lastAgentOutput: String?

    /// todo_write task list for this session
    @Published var todoItems: [AIAgentTodoItem]
    @Published var subtasks: [AIAgentSubtask]

    /// 完整 transcript 消息列表（详细模式使用）
    @Published var fullTranscript: [TranscriptMessage] = []

    /// 是否已加载完整 transcript
    @Published var isTranscriptLoaded: Bool = false

    /// 加载状态错误信息
    @Published var transcriptLoadError: String?

    init(
        agentType: AIAgentType,
        project: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = UUID()
        self.agentType = agentType
        self.startTime = Date()
        self.sessionId = sessionId
        self.status = .sessionStart
        self.phase = .booting
        self.currentTask = "启动会话中..."
        self.project = project
        self.lastActivity = Date()
        self.eventLog = []
        self.conversationTurns = []
        self.todoItems = []
        self.subtasks = []
        self.isArchived = false
    }

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var elapsedTimeString: String {
        let elapsed = Int(elapsedTime)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var projectName: String? {
        guard let project = project else { return nil }
        return (project as NSString).lastPathComponent
    }

    var isCLIBacked: Bool {
        agentType.bundleIdentifiers.isEmpty
    }

    var canArchiveManually: Bool {
        switch status {
        case .completed, .error, .sessionEnd, .idle:
            return true
        case .sessionStart:
            return phase == .ended || phase == .completed || phase == .failed
        case .thinking, .coding, .running, .waitingInput:
            return false
        }
    }

    /// Context usage ratio (0.0 ~ 1.0), nil if unknown
    var contextUsageRatio: Double? {
        guard let window = contextWindowSize, let used = contextUsedTokens, window > 0 else { return nil }
        return Double(used) / Double(window)
    }

    /// Whether context usage is >= 80%
    var isNearContextLimit: Bool {
        guard let ratio = contextUsageRatio else { return false }
        return ratio >= 0.8
    }

    /// Human-readable context usage label (e.g., "170K/200K (85%)")
    var contextUsageLabel: String? {
        guard let ratio = contextUsageRatio else { return nil }
        let windowStr = formatTokenCount(contextWindowSize ?? 0)
        let pct = Int(ratio * 100)
        return "\(windowStr) (\(pct)%)"
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    /// Infer context window size from model name
    static func inferContextWindow(from model: String?) -> Int? {
        guard let model = model?.lowercased() else { return nil }

        // Claude series: 200K
        if model.contains("claude") {
            return 200_000
        }
        // GPT-4 series: 128K
        if model.contains("gpt-4") || model.contains("gpt4") {
            return 128_000
        }
        // GPT-5 series: 1M
        if model.contains("gpt-5") || model.contains("gpt5") {
            return 1_000_000
        }
        // o1/o3/o4 series: 200K
        if model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") {
            return 200_000
        }
        // Gemini series: 1M
        if model.contains("gemini") {
            return 1_000_000
        }
        return nil
    }

    var expandedSortAnchor: Date {
        if phase.isAttentionBlocking, let lastAttentionRequestAt {
            return lastAttentionRequestAt
        }
        return lastUserPromptAt ?? lastMeaningfulOutputAt ?? lastActivity
    }

    var collapsedSortAnchor: Date {
        if phase.isAttentionBlocking {
            return lastAttentionRequestAt ?? lastActivity
        }
        return lastActivity
    }

    /// The current (most recent) conversation turn
    var currentTurn: AIAgentConversationTurn? {
        conversationTurns.last
    }

    var latestInteraction: AIAgentInteraction? {
        conversationTurns
            .flatMap(\.interactions)
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    var latestPendingInteraction: AIAgentInteraction? {
        conversationTurns
            .flatMap(\.interactions)
            .sorted { $0.timestamp > $1.timestamp }
            .first(where: { !$0.isResolved })
    }

    var hasPendingInteraction: Bool {
        latestPendingInteraction != nil
    }

    var subagentToolCalls: [AIAgentToolCall] {
        currentTurn?
            .toolCalls
            .filter { $0.toolName.lowercased() == "task" } ?? []
    }

    var activeSubagentCall: AIAgentToolCall? {
        subagentToolCalls.last(where: { $0.output == nil }) ?? subagentToolCalls.last
    }

    var activeTodoItem: AIAgentTodoItem? {
        todoItems.first(where: { $0.status == .inProgress })
    }

    var nextPendingTodoItem: AIAgentTodoItem? {
        todoItems.first(where: { $0.status == .pending })
    }

    var currentTodoDisplayItem: AIAgentTodoItem? {
        activeTodoItem ?? (status.isActive ? nextPendingTodoItem : nil)
    }

    var currentTodoStepIndex: Int? {
        guard let item = currentTodoDisplayItem,
              let idx = todoItems.firstIndex(where: { $0.id == item.id }) else {
            if !todoItems.isEmpty, todoItems.allSatisfy({ $0.status == .completed }) {
                return todoItems.count
            }
            return nil
        }
        return idx + 1
    }

    var currentTodoProgressLabel: String? {
        guard !todoItems.isEmpty, let step = currentTodoStepIndex else { return nil }
        return "\(step)/\(todoItems.count)"
    }

    var currentTodoDisplayText: String? {
        currentTodoDisplayItem?.content
    }

    var structuredSubtasks: [AIAgentSubtask] {
        subtasks.filter { $0.kind != .transcriptTurn }
    }

    var displaySubtasks: [AIAgentSubtask] {
        if !structuredSubtasks.isEmpty {
            return structuredSubtasks
        }
        if !todoItems.isEmpty {
            return todoItems.map(AIAgentSubtask.init(todoItem:))
        }
        if !subagentToolCalls.isEmpty {
            return subagentToolCalls.map(AIAgentSubtask.init(toolCall:))
        }
        return []
    }

    var activeDisplaySubtask: AIAgentSubtask? {
        let tasks = displaySubtasks
        return tasks.last(where: { $0.status.isActive })
            ?? tasks.first(where: { $0.status == .pending })
            ?? tasks.last
    }

    var currentSubtaskStepIndex: Int? {
        let tasks = displaySubtasks
        guard !tasks.isEmpty else { return nil }

        if let activeTask = activeDisplaySubtask,
           let idx = tasks.firstIndex(where: { $0.id == activeTask.id }) {
            return idx + 1
        }

        if tasks.allSatisfy({ $0.status == .completed }) {
            return tasks.count
        }

        return nil
    }

    var currentSubtaskProgressLabel: String? {
        let tasks = displaySubtasks
        guard !tasks.isEmpty, let step = currentSubtaskStepIndex else { return nil }
        return "\(step)/\(tasks.count)"
    }

    var currentSubtaskDisplayText: String? {
        activeDisplaySubtask?.title
    }

    func applyEvent(_ event: AIAgentHookEvent) {
        let eventDate = event.occurredAt
        lastActivity = max(lastActivity, eventDate)
        applyMetadata(from: event)

        if let eventSubtasks = event.subtasks, !eventSubtasks.isEmpty {
            applyIncomingSubtasks(eventSubtasks)
        }

        // Map hook types to status
        switch event.hookType {
        case "SessionStart":
            status = .sessionStart
            phase = .booting
            currentTask = "会话已启动"
            if let proj = event.project, proj != "/" { project = proj }
            // Extract model and context info
            if let model = event.model {
                modelName = model
                contextWindowSize = event.contextWindow ?? AIAgentSession.inferContextWindow(from: model)
            }
            if let used = event.contextUsed {
                contextUsedTokens = used
            }

        case "SessionEnd":
            status = .sessionEnd
            phase = .ended
            currentTask = "会话已结束"
            finalizeTrackedItemsForCompletion()
            // Mark last turn as complete
            currentTurn?.isComplete = true

        case "PermissionRequest":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            status = .waitingInput
            phase = .waitingForInput
            lastAttentionRequestAt = eventDate
            currentTool = event.toolName
            if let file = event.filePath { currentFile = file }

            if let interactionData = event.interaction,
               appendInteractionRecords(from: interactionData) {
                currentTask = interactionData.title ?? latestPendingInteraction?.message ?? "等待权限审批..."
            } else {
                let interaction = AIAgentInteraction(
                    timestamp: Date(),
                    type: .confirmation,
                    title: "Permission Required",
                    message: event.toolInput ?? event.message ?? "等待权限审批...",
                    options: ["Allow", "Block"],
                    responseMode: .approvalSelection
                )
                currentTurn?.interactions.append(interaction)
                currentTask = interaction.message
            }

        case "PreToolUse":
            status = .running
            phase = .active
            currentTool = event.toolName
            if let tool = event.toolName {
                currentTask = describeToolAction(tool: tool, input: event.toolInput)
                ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))

                if isTodoWriteTool(tool), let items = event.todoItems, !items.isEmpty {
                    let merge = shouldMergeTodoItems(from: event.toolInput)
                    applyTodoItems(items, merge: merge)
                }

                // Detect interactive tools (agent asking user for input)
                if tool.lowercased().contains("follow") || tool.lowercased().contains("question") || event.interaction != nil {
                    status = .waitingInput
                    phase = .waitingForInput
                    lastAttentionRequestAt = eventDate

                    // Use structured interaction data if available
                    if let interactionData = event.interaction,
                       appendInteractionRecords(from: interactionData) {
                        currentTask = interactionData.title ?? latestPendingInteraction?.message ?? "等待输入..."
                    } else {
                        // Fallback: try to parse from tool_input string
                        let interaction = AIAgentInteraction(
                            timestamp: Date(),
                            type: .question,
                            title: nil,
                            message: event.toolInput ?? event.message ?? "助手提问中...",
                            options: parseOptions(from: event.toolInput),
                            responseMode: .pasteReply
                        )
                        currentTurn?.interactions.append(interaction)
                        currentTask = event.toolInput ?? "等待输入..."
                    }
                } else {
                    // Record tool call in current conversation turn
                    let toolCall = AIAgentToolCall(
                        timestamp: Date(),
                        toolName: tool,
                        input: event.toolInput,
                        output: nil,
                        filePath: event.filePath
                    )
                    currentTurn?.toolCalls.append(toolCall)
                }
            }
            if let file = event.filePath { currentFile = file }

        case "SubagentStart":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            status = .running
            phase = .active
            currentTool = "subagent"
            currentTask = event.subtasks?.first?.title ?? event.message ?? "子代理已启动"

        case "PostToolUse":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            if let tool = event.toolName {
                currentTask = "完成: \(describeToolAction(tool: tool, input: event.toolInput))"
                // Update the matching tool call with its output
                if let turn = currentTurn,
                   let idx = turn.toolCalls.lastIndex(where: { $0.toolName == tool && $0.output == nil }) {
                    turn.toolCalls[idx].output = event.toolOutput ?? event.message
                }
            }
            status = .thinking
            phase = .active
            recordMeaningfulOutput(event.toolOutput ?? event.message, at: eventDate)

        case "UserPromptSubmit":
            status = .thinking
            phase = .active
            let prompt = event.userPrompt ?? event.message ?? "处理用户请求..."
            currentTask = prompt
            lastUserPrompt = prompt
            lastUserPromptAt = eventDate
            todoItems = []
            subtasks = []

            // Update project path if available and meaningful
            if let proj = event.project, proj != "/" { project = proj }

            // Mark previous turn as complete
            currentTurn?.isComplete = true

            // Start a new conversation turn
            let turn = AIAgentConversationTurn(userPrompt: prompt)
            conversationTurns.append(turn)
            // Keep at most 5 turns
            if conversationTurns.count > 5 {
                conversationTurns.removeFirst(conversationTurns.count - 5)
            }

        case "Notification":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            lastNotificationAt = eventDate
            if let msg = event.message {
                currentTask = msg
            }
            // If the notification carries agent output, record it
            if let output = event.agentOutput {
                lastAgentOutput = output
                currentTurn?.agentResponse = output
                recordMeaningfulOutput(output, at: eventDate)
            }

        case "SubagentStop":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            status = .thinking
            phase = .active
            currentTask = event.subtasks?.first?.title ?? event.message ?? "子代理完成"
            recordMeaningfulOutput(event.message, at: eventDate)

        case "Stop":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            status = .completed
            phase = .completed
            currentTask = event.message ?? "任务完成"
            finalizeTrackedItemsForCompletion()
            // Capture final agent output if present
            if let output = event.agentOutput {
                lastAgentOutput = output
                currentTurn?.agentResponse = output
            }
            recordMeaningfulOutput(event.agentOutput ?? event.message, at: eventDate)
            currentTurn?.isComplete = true

        case "PreCompact":
            phase = .compacting
            currentTask = "压缩上下文..."
            compactCount += 1
            // Estimate 95% usage when compacting
            if let window = contextWindowSize {
                contextUsedTokens = Int(Double(window) * 0.95)
            }

        case "AgentResponse":
            ensureConversationTurnIfNeeded(seedPrompt: inferredPromptSeed(from: event))
            // Dedicated event for agent text output
            if let output = event.agentOutput ?? event.message {
                lastAgentOutput = output
                currentTurn?.agentResponse = output
                currentTask = String(output.prefix(80))
                phase = .active
                recordMeaningfulOutput(output, at: eventDate)
            }

        default:
            if let msg = event.message {
                currentTask = msg
            }
            if let output = event.agentOutput {
                lastAgentOutput = output
                currentTurn?.agentResponse = output
                phase = .active
                recordMeaningfulOutput(output, at: eventDate)
            }
        }

        // Add to event log (keep last 50 entries)
        let entry = AIAgentActivityEntry(
            timestamp: Date(),
            hookType: event.hookType,
            toolName: event.toolName,
            description: currentTask,
            detail: event.toolInput ?? event.agentOutput ?? event.userPrompt
        )
        eventLog.append(entry)
        if eventLog.count > 50 {
            eventLog.removeFirst(eventLog.count - 50)
        }
    }

    func applyTranscriptSnapshot(_ snapshot: AIAgentTranscriptSnapshot) {
        lastTranscriptReconciledAt = snapshot.reconciledAt
        transcriptPath = snapshot.transcriptPath

        if !snapshot.subtasks.isEmpty {
            applyIncomingSubtasks(snapshot.subtasks)
        }

        if let output = normalizedMetadataText(snapshot.lastAgentOutput) {
            let outputDate = snapshot.lastAgentOutputAt ?? snapshot.reconciledAt
            let currentOutputDate = lastMeaningfulOutputAt ?? .distantPast
            let isNewerOutput = outputDate >= currentOutputDate || lastAgentOutput != output

            if isNewerOutput {
                ensureConversationTurnIfNeeded(seedPrompt: lastUserPrompt)
                lastAgentOutput = output
                currentTurn?.agentResponse = output
                recordMeaningfulOutput(output, at: outputDate)
                if status.isActive || status == .sessionStart {
                    currentTask = String(output.prefix(80))
                }
            }
        }

        if snapshot.indicatesCompletion, status != .completed {
            status = .completed
            phase = .completed
            currentTask = lastAgentOutput.map { String($0.prefix(80)) } ?? "任务完成"
            finalizeTrackedItemsForCompletion()
            currentTurn?.isComplete = true
        }

        lastActivity = max(lastActivity, snapshot.lastAgentOutputAt ?? snapshot.reconciledAt)
    }

    private func applyMetadata(from event: AIAgentHookEvent) {
        if let proj = event.project, proj != "/" {
            project = proj
        }
        if let pid = event.pid {
            self.pid = pid
        }
        if let tty = normalizedMetadataText(event.tty) {
            self.tty = tty
        }
        if let transcriptPath = normalizedMetadataText(event.transcriptPath) {
            self.transcriptPath = transcriptPath
        }
        if let toolUseId = normalizedMetadataText(event.toolUseId) {
            self.toolUseId = toolUseId
        }
        if let agentId = normalizedMetadataText(event.agentId) {
            self.agentInstanceId = agentId
        }
        if let parentToolId = normalizedMetadataText(event.parentToolId) {
            self.parentToolId = parentToolId
        }
        if let rawHookType = normalizedMetadataText(event.rawHookType) {
            self.rawHookType = rawHookType
        }
        // Context tracking
        if let model = event.model {
            self.modelName = model
            if self.contextWindowSize == nil {
                self.contextWindowSize = event.contextWindow ?? AIAgentSession.inferContextWindow(from: model)
            }
        }
        if let window = event.contextWindow {
            self.contextWindowSize = window
        }
        if let used = event.contextUsed {
            self.contextUsedTokens = used
        }
    }

    private func normalizedMetadataText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func recordMeaningfulOutput(_ text: String?, at date: Date) {
        guard normalizedMetadataText(text) != nil else { return }
        lastMeaningfulOutputAt = max(lastMeaningfulOutputAt ?? date, date)
    }

    private func describeToolAction(tool: String, input: String?) -> String {
        switch tool.lowercased() {
        case "read_file", "read file", "read":
            if let path = input { return "读取 \((path as NSString).lastPathComponent)" }
            return "读取文件"
        case "write_to_file", "write file", "write":
            if let path = input { return "写入 \((path as NSString).lastPathComponent)" }
            return "写入文件"
        case "replace_in_file", "edit file", "edit":
            if let path = input { return "编辑 \((path as NSString).lastPathComponent)" }
            return "编辑文件"
        case "execute_command", "bash":
            if let cmd = input { return "执行: \(String(cmd.prefix(50)))" }
            return "执行命令"
        case "search_content", "search_file", "grep":
            if let q = input { return "搜索: \(String(q.prefix(30)))" }
            return "搜索代码"
        case "list_dir", "list directory":
            return "浏览目录"
        case "web_search":
            if let q = input { return "网页搜索: \(String(q.prefix(30)))" }
            return "搜索网页"
        case "web_fetch":
            return "获取网页"
        case "task", "agent":
            if let inp = input, !inp.isEmpty {
                return "运行子代理: \(String(inp.prefix(40)))"
            }
            return "运行子代理"
        case "update_plan", "updateplan", "taskcreated", "taskcompleted":
            return "更新任务计划"
        case "ask_followup_question", "askfollowupquestion", "askuserquestion":
            return "等待确认..."
        case "todo_write":
            return "更新任务列表"
        default:
            if let inp = input { return "\(tool): \(String(inp.prefix(40)))" }
            return tool
        }
    }

    private func isTodoWriteTool(_ tool: String) -> Bool {
        let normalized = tool.lowercased()
        return normalized == "todo_write" || normalized == "todowrite"
            || normalized == "update_plan" || normalized == "updateplan"
    }

    private func interactionType(from rawValue: String?) -> AIAgentInteraction.InteractionType {
        switch rawValue?.lowercased() {
        case "confirmation":
            return .confirmation
        case "info":
            return .info
        default:
            return .question
        }
    }

    private func interactionResponseMode(from rawValue: String?) -> AIAgentInteraction.ResponseMode {
        switch rawValue?.lowercased() {
        case "approval_selection", "approvalselection":
            return .approvalSelection
        default:
            return .pasteReply
        }
    }

    private func shouldMergeTodoItems(from toolInput: String?) -> Bool {
        guard let toolInput, !toolInput.isEmpty else { return false }

        if let data = toolInput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let merge = json["merge"] as? Bool {
            return merge
        }

        let compact = toolInput.replacingOccurrences(of: " ", with: "").lowercased()
        return compact.contains("\"merge\":true")
    }

    private func applyTodoItems(_ items: [AIAgentTodoItem], merge: Bool) {
        if merge {
            for item in items {
                if let idx = todoItems.firstIndex(where: { $0.id == item.id }) {
                    todoItems[idx] = item
                } else {
                    todoItems.append(item)
                }
            }
        } else {
            todoItems = items
        }
    }

    private func applyIncomingSubtasks(_ incoming: [AIAgentSubtask]) {
        guard !incoming.isEmpty else { return }

        var updated = subtasks
        let grouped = Dictionary(grouping: incoming, by: \.kind)

        for (kind, tasks) in grouped {
            switch kind {
            case .subagent:
                for task in tasks {
                    if let idx = updated.firstIndex(where: { $0.kind == .subagent && $0.id == task.id }) {
                        var merged = task
                        let existing = updated[idx]
                        if merged.summary == nil { merged = AIAgentSubtask(
                            id: merged.id,
                            kind: merged.kind,
                            status: merged.status,
                            title: merged.title,
                            summary: existing.summary,
                            startedAt: merged.startedAt ?? existing.startedAt,
                            completedAt: merged.completedAt ?? existing.completedAt
                        ) }
                        else {
                            merged = AIAgentSubtask(
                                id: merged.id,
                                kind: merged.kind,
                                status: merged.status,
                                title: merged.title,
                                summary: merged.summary,
                                startedAt: merged.startedAt ?? existing.startedAt,
                                completedAt: merged.completedAt ?? existing.completedAt
                            )
                        }
                        updated[idx] = merged
                    } else {
                        updated.append(task)
                    }
                }
            default:
                updated.removeAll { $0.kind == kind }
                updated.append(contentsOf: tasks)
            }
        }

        subtasks = updated
    }

    @discardableResult
    private func appendInteractionRecords(from interactionData: AIAgentHookEvent.HookInteraction) -> Bool {
        guard let questions = interactionData.questions, !questions.isEmpty else { return false }

        let interactionType = interactionType(from: interactionData.type)
        let responseMode = interactionResponseMode(from: interactionData.responseMode)
        var appended = false

        for q in questions {
            let interaction = AIAgentInteraction(
                timestamp: Date(),
                type: interactionType,
                title: interactionData.title,
                message: q.question ?? "助手提问中...",
                options: q.options,
                responseMode: responseMode,
                bridgeResponseKind: interactionData.bridgeResponseKind,
                bridgeResponseContext: interactionData.bridgeResponseContext
            )
            currentTurn?.interactions.append(interaction)
            appended = true
        }

        return appended
    }

    private func finalizeTrackedItemsForCompletion() {
        if !todoItems.isEmpty {
            todoItems = todoItems.map { item in
                guard item.status == .pending || item.status == .inProgress else { return item }
                var updated = item
                updated.status = .completed
                return updated
            }
        }

        if !subtasks.isEmpty {
            subtasks = subtasks.map { task in
                guard task.status == .pending || task.status == .inProgress else { return task }
                var updated = task
                updated.status = .completed
                return updated
            }
        }
    }

    /// Try to parse options from ask_followup_question JSON input
    private func parseOptions(from input: String?) -> [String]? {
        guard let input = input else { return nil }
        // The input might be JSON with a "questions" array containing "options"
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Try parsing questions array
        if let questions = json["questions"] as? String,
           let qData = questions.data(using: .utf8),
           let qArr = try? JSONSerialization.jsonObject(with: qData) as? [[String: Any]],
           let first = qArr.first,
           let options = first["options"] as? [String] {
            return options
        }
        if let options = json["options"] as? [String] {
            return options
        }
        return nil
    }

    private func ensureConversationTurnIfNeeded(seedPrompt: String?) {
        if let turn = currentTurn, !turn.isComplete {
            return
        }

        let prompt = normalizedPromptSeed(seedPrompt)
            ?? normalizedPromptSeed(lastUserPrompt)
            ?? normalizedPromptSeed(currentTask)
            ?? "继续任务"

        let turn = AIAgentConversationTurn(userPrompt: prompt)
        conversationTurns.append(turn)

        if conversationTurns.count > 5 {
            conversationTurns.removeFirst(conversationTurns.count - 5)
        }
    }

    private func inferredPromptSeed(from event: AIAgentHookEvent) -> String? {
        normalizedPromptSeed(event.userPrompt)
            ?? normalizedPromptSeed(lastUserPrompt)
            ?? normalizedPromptSeed(event.message)
            ?? normalizedPromptSeed(event.toolInput)
    }

    private func normalizedPromptSeed(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if trimmed == "会话已启动" || trimmed == "启动会话中..." {
            return nil
        }

        return String(trimmed.prefix(120))
    }

    func resolveInteraction(
        id interactionID: UUID,
        state: AIAgentInteraction.ResolutionState,
        taskOverride: String? = nil,
        statusOverride: AIAgentStatus? = nil
    ) {
        for turn in conversationTurns {
            guard let index = turn.interactions.firstIndex(where: { $0.id == interactionID }) else {
                continue
            }

            var interactions = turn.interactions
            interactions[index].resolutionState = state
            turn.interactions = interactions

            lastActivity = Date()
            if let taskOverride {
                currentTask = taskOverride
            }

            if latestPendingInteraction == nil {
                status = statusOverride ?? .thinking
                phase = phaseForResolvedStatus(status)
            }
            return
        }
    }

    private func phaseForResolvedStatus(_ status: AIAgentStatus) -> AIAgentSessionPhase {
        switch status {
        case .completed:
            return .completed
        case .error:
            return .failed
        case .sessionEnd:
            return .ended
        case .waitingInput:
            return .waitingForInput
        case .sessionStart:
            return .booting
        default:
            return .active
        }
    }
}

// MARK: - Activity Log Entry

struct AIAgentActivityEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let hookType: String
    let toolName: String?
    let description: String
    let detail: String?     // additional context (tool input, agent output, etc.)

    init(timestamp: Date, hookType: String, toolName: String?, description: String, detail: String? = nil) {
        self.timestamp = timestamp
        self.hookType = hookType
        self.toolName = toolName
        self.description = description
        self.detail = detail
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
