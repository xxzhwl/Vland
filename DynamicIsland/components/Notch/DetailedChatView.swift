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
import SwiftUI

// MARK: - Detailed Chat View (Full Transcript)

struct DetailedChatView: View {
    @ObservedObject var session: AIAgentSession
    let style: AIAgentCardStyle
    @Default(.aiAgentShowThinkingBlocks) private var showThinkingBlocks
    @Default(.aiAgentShowToolDetails) private var showToolDetails
    @Default(.aiAgentShowToolOutput) private var showToolOutput
    @State private var cachedSegments: [ChatSegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.isTranscriptLoaded {
                if session.fullTranscript.isEmpty {
                    emptyTranscriptView
                } else {
                    transcriptListView
                }
            } else if let error = session.transcriptLoadError {
                transcriptErrorView(error)
            } else {
                loadingView
            }
        }
        .onChange(of: session.fullTranscript) { _, newTranscript in
            cachedSegments = buildChatSegments(from: newTranscript)
        }
        .onAppear {
            if cachedSegments.isEmpty, !session.fullTranscript.isEmpty {
                cachedSegments = buildChatSegments(from: session.fullTranscript)
            }
        }
    }

    /// Build chat segments from transcript messages (non-body computation)
    private func buildChatSegments(from transcript: [TranscriptMessage]) -> [ChatSegment] {
        var segments: [ChatSegment] = []
        var currentUserMessage: TranscriptMessage?
        var currentAssistantMessages: [TranscriptMessage] = []

        for message in transcript {
            switch message.role {
            case .user:
                if let userMsg = currentUserMessage, hasValidTextContent(userMsg), !currentAssistantMessages.isEmpty {
                    segments.append(ChatSegment(
                        id: userMsg.id,
                        userMessage: userMsg,
                        assistantMessages: currentAssistantMessages
                    ))
                }
                currentUserMessage = message
                currentAssistantMessages = []

            case .assistant:
                currentAssistantMessages.append(message)

            case .system, .tool:
                if currentUserMessage != nil {
                    currentAssistantMessages.append(message)
                } else if let lastSegment = segments.last {
                    var updatedSegment = lastSegment
                    updatedSegment.assistantMessages.append(message)
                    segments[segments.count - 1] = updatedSegment
                }
            }
        }

        if let userMsg = currentUserMessage, hasValidTextContent(userMsg) {
            segments.append(ChatSegment(
                id: userMsg.id,
                userMessage: userMsg,
                assistantMessages: currentAssistantMessages
            ))
        } else if !currentAssistantMessages.isEmpty, let lastSegment = segments.last {
            var updatedSegment = lastSegment
            updatedSegment.assistantMessages.append(contentsOf: currentAssistantMessages)
            segments[segments.count - 1] = updatedSegment
        }

        return segments
    }

    // MARK: - Transcript List with Chat-like Layout

    private var transcriptListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(cachedSegments) { segment in
                        ChatSegmentView(
                            segment: segment,
                            agentType: session.agentType,
                            style: style,
                            showThinkingBlocks: showThinkingBlocks,
                            showToolDetails: showToolDetails,
                            showToolOutput: showToolOutput
                        )
                        .equatable()
                        .id(segment.id)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: style.expandedContentMaxHeight)
            .onAppear {
                scrollToLatestChat(proxy: proxy)
            }
            .onChange(of: cachedSegments.count) { _, _ in
                scrollToLatestChat(proxy: proxy)
            }
        }
    }

    /// 检查消息是否有有效文本内容
    private func hasValidTextContent(_ message: TranscriptMessage) -> Bool {
        switch message.role {
        case .user:
            // 用户消息：使用 displayText（已过滤系统内容）
            return !message.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .assistant, .system, .tool:
            // AI/系统/工具消息：总是有意义的
            return true
        }
    }

    private func scrollToLatestChat(proxy: ScrollViewProxy) {
        if let lastSegment = cachedSegments.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastSegment.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty / Loading / Error

    private var emptyTranscriptView: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: style.scaled(22)))
                .foregroundColor(.gray.opacity(0.35))
                .symbolEffect(.pulse, options: .repeating)

            Text("暂无对话记录")
                .font(.system(size: style.scaled(10.5), weight: .medium))
                .foregroundColor(.gray.opacity(0.55))

            Text("会话产生对话后，完整记录将自动显示在此处")
                .font(.system(size: style.scaled(8.5)))
                .foregroundColor(.gray.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.gray.opacity(0.6))

            Text("加载对话记录...")
                .font(.system(size: style.scaled(10)))
                .foregroundColor(.gray.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private func transcriptErrorView(_ error: String) -> some View {
        let isPathMissing = session.transcriptPath == nil || session.transcriptPath?.isEmpty == true

        return VStack(spacing: 8) {
            Image(systemName: isPathMissing ? "doc.text.magnifyingglass" : "exclamationmark.triangle")
                .font(.system(size: style.scaled(16)))
                .foregroundColor(isPathMissing ? .gray.opacity(0.5) : .orange.opacity(0.7))

            if isPathMissing {
                Text("暂无完整记录")
                    .font(.system(size: style.scaled(10), weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
                Text("AI 助手尚未生成对话记录文件。会话产生对话后，详细模式将自动加载。")
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.gray.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                Text("💡 切换到「精简」模式可查看实时对话")
                    .font(.system(size: style.scaled(8.5)))
                    .foregroundColor(.gray.opacity(0.45))
            } else {
                Text("加载失败")
                    .font(.system(size: style.scaled(10), weight: .medium))
                    .foregroundColor(.orange.opacity(0.8))
                Text(error)
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.gray.opacity(0.6))
                    .lineLimit(5)
                    .multilineTextAlignment(.center)
                if let path = session.transcriptPath {
                    Text(path)
                        .font(.system(size: style.scaled(7.5), design: .monospaced))
                        .foregroundColor(.gray.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Single Transcript Message Row

struct TranscriptMessageRow: View {
    let message: TranscriptMessage
    let agentType: AIAgentType
    let style: AIAgentCardStyle
    let showThinkingBlocks: Bool
    let showToolDetails: Bool
    let showToolOutput: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Role header
            HStack(spacing: 5) {
                roleIcon
                    .frame(width: 12, height: 12)

                Text(roleLabel)
                    .font(.system(size: style.scaled(9), weight: .semibold))
                    .foregroundColor(roleColor.opacity(0.8))

                Spacer()

                if let timestamp = message.timestamp {
                    Text(timestamp, style: .time)
                        .font(.system(size: style.scaled(7.5), design: .monospaced))
                        .foregroundColor(.gray.opacity(0.35))
                }
            }

            // Content blocks - 先过滤掉要隐藏的类型
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(visibleContentBlocks(message.content).enumerated()), id: \.offset) { _, block in
                    contentBlockView(block)
                }
            }
            .padding(.leading, 17)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            roleBackgroundColor,
                            roleBackgroundColor.opacity(0.5)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(roleBackgroundColor.opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func contentBlockView(_ block: TranscriptMessage.ContentBlock) -> some View {
        switch block {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(markdownAttributedString(text))
                    .font(.system(size: style.scaled(10)))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
            }

        case .toolUse(let name, let input):
            if showToolDetails {
                toolUseView(name: name, input: input)
            }

        case .toolResult(let toolUseId, let content):
            if showToolOutput && !content.isEmpty {
                toolResultView(toolUseId: toolUseId, content: content)
            }

        case .thinking(let text):
            if showThinkingBlocks && !text.isEmpty {
                thinkingView(text: text)
            }
        }
    }

    /// 过滤出要显示的 content blocks（隐藏 thinking/toolUse/toolResult）
    private func visibleContentBlocks(_ blocks: [TranscriptMessage.ContentBlock]) -> [TranscriptMessage.ContentBlock] {
        blocks.filter { block in
            switch block {
            case .text(let text):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .toolUse:
                return showToolDetails
            case .toolResult(_, let content):
                return showToolOutput && !content.isEmpty
            case .thinking(let text):
                return showThinkingBlocks && !text.isEmpty
            }
        }
    }

    // MARK: - Content Block Subviews

    private func toolUseView(name: String, input: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: style.scaled(7)))
                    .foregroundColor(.cyan.opacity(0.7))

                Text(name)
                    .font(.system(size: style.scaled(9), weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.85))
            }

            if !input.isEmpty {
                Text(String(input.prefix(200)))
                    .font(.system(size: style.scaled(8.5), design: .monospaced))
                    .foregroundColor(.gray.opacity(0.55))
                    .lineLimit(3)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.cyan.opacity(0.06))
        )
    }

    private func toolResultView(toolUseId: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: style.scaled(7)))
                    .foregroundColor(.green.opacity(0.6))

                Text("输出")
                    .font(.system(size: style.scaled(8.5), weight: .medium))
                    .foregroundColor(.green.opacity(0.7))
            }

            Text(String(content.prefix(300)))
                .font(.system(size: style.scaled(8.5), design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
                .lineLimit(5)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.green.opacity(0.04))
        )
    }

    private func thinkingView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: style.scaled(7)))
                    .foregroundColor(.purple.opacity(0.6))

                Text("思考")
                    .font(.system(size: style.scaled(8.5), weight: .medium))
                    .foregroundColor(.purple.opacity(0.65))
            }

            Text(String(text.prefix(200)))
                .font(.system(size: style.scaled(8.5)))
                .foregroundColor(.gray.opacity(0.45))
                .italic()
                .lineLimit(4)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.purple.opacity(0.04))
        )
    }

    // MARK: - Role Helpers

    private var roleIcon: some View {
        Group {
            switch message.role {
            case .user:
                Image(systemName: "person.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.white.opacity(0.4))
            case .assistant:
                AgentTypeIconView(agentType: agentType, size: style.scaled(10))
            case .system:
                Image(systemName: "gearshape.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.gray.opacity(0.5))
            case .tool:
                Image(systemName: "wrench.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.cyan.opacity(0.5))
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "你"
        case .assistant: return agentType.displayName
        case .system: return "系统"
        case .tool: return "工具"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return agentType.accentColor
        case .system: return .gray
        case .tool: return .cyan
        }
    }

    private var roleBackgroundColor: Color {
        switch message.role {
        case .user: return .white.opacity(0.07)
        case .assistant: return agentType.accentColor.opacity(0.06)
        case .system: return .gray.opacity(0.04)
        case .tool: return .cyan.opacity(0.04)
        }
    }
}

// MARK: - Chat Segment (User + AI responses)

struct ChatSegment: Identifiable, Equatable {
    let id: String
    let userMessage: TranscriptMessage
    var assistantMessages: [TranscriptMessage]
}

// MARK: - Chat Segment View

struct ChatSegmentView: View, Equatable {
    let segment: ChatSegment
    let agentType: AIAgentType
    let style: AIAgentCardStyle
    let showThinkingBlocks: Bool
    let showToolDetails: Bool
    let showToolOutput: Bool

    static func == (lhs: ChatSegmentView, rhs: ChatSegmentView) -> Bool {
        lhs.segment.id == rhs.segment.id
            && lhs.showThinkingBlocks == rhs.showThinkingBlocks
            && lhs.showToolDetails == rhs.showToolDetails
            && lhs.showToolOutput == rhs.showToolOutput
    }

    @State private var isExpanded = true

    private var accentColor: Color {
        style.accentColor(for: agentType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // User bubble (right-aligned)
            userBubble

            // AI bubble (left-aligned)
            if isExpanded {
                aiBubble
            } else {
                collapsedPreview
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 40)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    if let timestamp = segment.userMessage.timestamp {
                        Text(formatTimestamp(timestamp))
                            .font(.system(size: style.scaled(7.5), design: .monospaced))
                            .foregroundColor(.gray.opacity(0.5))
                    }

                    Image(systemName: "person.fill")
                        .font(.system(size: style.scaled(8)))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(segment.userMessage.displayContent.enumerated()), id: \.offset) { _, block in
                        userContentBlockView(block)
                    }
                }
                .lineSpacing(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.06)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - AI Bubble

    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    AgentTypeIconView(agentType: agentType, size: 16)

                    Text(agentType.displayName)
                        .font(.system(size: style.scaled(10), weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.9))

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: style.scaled(8), weight: .semibold))
                            .foregroundColor(.gray.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 0 : 180))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(segment.assistantMessages) { message in
                        messageContentView(message)
                    }
                }
                .lineSpacing(2)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.08),
                                    accentColor.opacity(0.03)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.12), lineWidth: 0.5)
                )
            }
            .padding(.trailing, 20)
        }
    }

    // MARK: - Collapsed Preview

    private var collapsedPreview: some View {
        HStack(spacing: 6) {
            AgentTypeIconView(agentType: agentType, size: 12)

            Text("\(segment.assistantMessages.count) 条回复")
                .font(.system(size: style.scaled(9)))
                .foregroundColor(.gray.opacity(0.6))

            // Preview first message content
            if let firstText = segment.assistantMessages.first?.plainText, !firstText.isEmpty {
                Text("— " + String(firstText.prefix(30)))
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.gray.opacity(0.5))
                    .lineLimit(1)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: style.scaled(8)))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func userContentBlockView(_ block: TranscriptMessage.ContentBlock) -> some View {
        switch block {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(markdownAttributedString(text))
                    .font(.system(size: style.scaled(10)))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        case .toolUse, .toolResult, .thinking:
            EmptyView()
        }
    }

    @ViewBuilder
    private func messageContentView(_ message: TranscriptMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(visibleContentBlocks(message.content).enumerated()), id: \.offset) { _, block in
                contentBlockView(block)
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(_ block: TranscriptMessage.ContentBlock) -> some View {
        switch block {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(markdownAttributedString(text))
                    .font(.system(size: style.scaled(10)))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
            }

        case .toolUse(let name, let input):
            if showToolDetails {
                compactToolUseView(name: name, input: input)
            }

        case .toolResult(_, let content):
            if showToolOutput && !content.isEmpty {
                compactToolResultView(content: content)
            }

        case .thinking(let text):
            if showThinkingBlocks && !text.isEmpty {
                compactThinkingView(text: text)
            }
        }
    }

    private func visibleContentBlocks(_ blocks: [TranscriptMessage.ContentBlock]) -> [TranscriptMessage.ContentBlock] {
        blocks.filter { block in
            switch block {
            case .text(let text):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .toolUse:
                return showToolDetails
            case .toolResult(_, let content):
                return showToolOutput && !content.isEmpty
            case .thinking(let text):
                return showThinkingBlocks && !text.isEmpty
            }
        }
    }

    // MARK: - Compact Tool Views

    private func compactToolUseView(name: String, input: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: style.scaled(7)))
                .foregroundColor(.cyan.opacity(0.7))

            Text(name)
                .font(.system(size: style.scaled(9), weight: .medium, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.85))

            if !input.isEmpty {
                Text(String(input.prefix(60)))
                    .font(.system(size: style.scaled(8.5), design: .monospaced))
                    .foregroundColor(.gray.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.cyan.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func compactToolResultView(content: String) -> some View {
        Text(String(content.prefix(200)))
            .font(.system(size: style.scaled(8.5), design: .monospaced))
            .foregroundColor(.gray.opacity(0.5))
            .lineLimit(4)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.green.opacity(0.04))
            )
    }

    private func compactThinkingView(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: style.scaled(7)))
                .foregroundColor(.purple.opacity(0.5))

            Text(String(text.prefix(100)))
                .font(.system(size: style.scaled(8.5)))
                .foregroundColor(.gray.opacity(0.42))
                .italic()
                .lineLimit(3)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

typealias AgentIconView = AgentTypeIconView

// MARK: - Unified Conversation View

/// A natural conversation view that shows user ↔ AI exchanges.
/// Tool calls and thinking blocks are collapsed by default — tap to expand.
struct UnifiedConversationView: View {
    @ObservedObject var session: AIAgentSession
    let style: AIAgentCardStyle
    @ObservedObject var agentManager: AIAgentManager
    @Default(.aiAgentShowThinkingBlocks) private var showThinkingBlocks
    @Default(.aiAgentShowToolDetails) private var showToolDetails
    @Default(.aiAgentShowToolOutput) private var showToolOutput

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Pending interaction (already shown in expandedContent, but keep for scroll continuity)
                // Subagents
                if !session.subagentToolCalls.isEmpty {
                    SubagentCompactSection(toolCalls: session.subagentToolCalls, style: style)
                }

                // Structured subtasks
                if !session.structuredSubtasks.isEmpty {
                    TasksCompactSection(tasks: session.structuredSubtasks, accentColor: accentColor, style: style)
                }

                if session.conversationTurns.isEmpty {
                    // No conversation yet — show recent event log
                    recentActivitySummary
                } else {
                    ForEach(session.conversationTurns) { turn in
                        UnifiedTurnView(
                            turn: turn,
                            agentType: session.agentType,
                            style: style,
                            accentColor: accentColor,
                            showThinkingBlocks: showThinkingBlocks,
                            showToolDetails: showToolDetails,
                            showToolOutput: showToolOutput
                        )
                    }
                }
            }
            .padding(10)
        }
    }

    private var accentColor: Color {
        style.accentColor(for: session.agentType)
    }

    private var recentActivitySummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(session.eventLog.suffix(10).reversed()) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text(entry.timeString)
                        .font(.system(size: style.scaled(8), design: .monospaced))
                        .foregroundColor(.gray.opacity(0.4))
                        .frame(width: 45, alignment: .leading)

                    Circle()
                        .fill(colorForHookType(entry.hookType))
                        .frame(width: 4, height: 4)
                        .padding(.top, 4)

                    Text(entry.description)
                        .font(.system(size: style.scaled(9)))
                        .foregroundColor(.gray.opacity(0.65))
                        .lineLimit(2)
                }
            }
        }
    }

    private func colorForHookType(_ type: String) -> Color {
        switch type {
        case "UserPromptSubmit": return .blue
        case "PreToolUse": return .cyan
        case "PostToolUse": return .green
        case "Stop": return .orange
        case "SessionStart": return .green
        case "SessionEnd": return .red
        default: return .gray
        }
    }
}

// MARK: - Unified Turn View

/// A single user → AI exchange in the conversation.
/// User message is right-aligned; AI response is left-aligned with avatar.
struct UnifiedTurnView: View {
    @ObservedObject var turn: AIAgentConversationTurn
    let agentType: AIAgentType
    let style: AIAgentCardStyle
    let accentColor: Color
    let showThinkingBlocks: Bool
    let showToolDetails: Bool
    let showToolOutput: Bool

    @State private var toolCallsExpanded = false
    @State private var thinkingExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // User message (right-aligned) — only show when there's real user content
            if !turn.userPrompt.isEmpty {
                userBubble
            }

            // AI response area (left-aligned with avatar)
            VStack(alignment: .leading, spacing: 6) {
                // Agent header
                HStack(spacing: 5) {
                    AgentTypeIconView(agentType: agentType, size: style.scaled(12))
                    Text(agentType.displayName)
                        .font(.system(size: style.scaled(9), weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 6) {
                    // Agent response text (always visible)
                    if let response = turn.agentResponse, !response.isEmpty {
                        Text(markdownAttributedString(response))
                            .font(.system(size: style.scaled(10)))
                            .foregroundColor(.white.opacity(0.82))
                            .textSelection(.enabled)
                    } else if !turn.isComplete {
                        // Still processing
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                            Text("AI 回复中...")
                                .font(.system(size: style.scaled(9)))
                                .foregroundColor(.gray.opacity(0.55))
                        }
                    }

                    // Tool calls — collapsed by default
                    if !turn.toolCalls.isEmpty {
                        toolCallsSection
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.08), lineWidth: 0.5)
                )
            }
            .padding(.trailing, 24)
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    Text(turn.timeString)
                        .font(.system(size: style.scaled(7.5), design: .monospaced))
                        .foregroundColor(.gray.opacity(0.45))
                    Image(systemName: "person.fill")
                        .font(.system(size: style.scaled(7)))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                Text(turn.userPrompt)
                    .font(.system(size: style.scaled(10), weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            }
            .frame(maxWidth: style.fontScale > 1 ? 360 : 280, alignment: .trailing)
        }
    }

    // MARK: - Tool Calls (Expandable)

    private var toolCallsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Collapsed indicator — always visible
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    toolCallsExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: toolCallsExpanded ? "gearshape.2.fill" : "gearshape.fill")
                        .font(.system(size: style.scaled(8)))
                        .foregroundColor(.cyan.opacity(0.7))

                    Text(toolCallsExpanded ? "隐藏工具详情" : "执行了 \(turn.toolCalls.count) 个操作")
                        .font(.system(size: style.scaled(8.5), weight: .medium))
                        .foregroundColor(.cyan.opacity(0.8))

                    Spacer()

                    Text(toolCallsExpanded ? "收起" : "详情")
                        .font(.system(size: style.scaled(8)))
                        .foregroundColor(.gray.opacity(0.5))

                    Image(systemName: "chevron.down")
                        .font(.system(size: style.scaled(7)))
                        .foregroundColor(.gray.opacity(0.4))
                        .rotationEffect(.degrees(toolCallsExpanded ? 180 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.cyan.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            // Expanded tool details
            if toolCallsExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(turn.toolCalls) { call in
                        HStack(spacing: 5) {
                            Image(systemName: call.output != nil ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                                .font(.system(size: style.scaled(7)))
                                .foregroundColor(call.output != nil ? .green.opacity(0.6) : .yellow.opacity(0.6))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(call.displayDescription)
                                    .font(.system(size: style.scaled(9), design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)

                                if showToolOutput, let output = call.output, !output.isEmpty {
                                    Text(output.prefix(120))
                                        .font(.system(size: style.scaled(8)))
                                        .foregroundColor(.gray.opacity(0.5))
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Compact Subagent Section

private struct SubagentCompactSection: View {
    let toolCalls: [AIAgentToolCall]
    let style: AIAgentCardStyle
    @State private var isExpanded = false

    private var activeCount: Int {
        toolCalls.filter { $0.output == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: style.scaled(8)))
                        .foregroundColor(.purple.opacity(0.8))

                    Text(activeCount > 0
                         ? "子代理运行中 \(activeCount)/\(toolCalls.count) 个"
                         : "子代理 \(toolCalls.count) 个")
                        .font(.system(size: style.scaled(9), weight: .semibold))
                        .foregroundColor(.purple.opacity(0.8))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: style.scaled(7)))
                        .foregroundColor(.gray.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(toolCalls) { call in
                        HStack(spacing: 6) {
                            Image(systemName: call.output == nil ? "ellipsis.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: style.scaled(8)))
                                .foregroundColor(call.output == nil ? .yellow.opacity(0.7) : .green.opacity(0.75))

                            Text(call.displayDescription)
                                .font(.system(size: style.scaled(9.5)))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.purple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.14), lineWidth: 0.5)
        )
    }
}

// MARK: - Compact Tasks Section

private struct TasksCompactSection: View {
    let tasks: [AIAgentSubtask]
    let accentColor: Color
    let style: AIAgentCardStyle
    @State private var isExpanded = false

    private var activeCount: Int {
        tasks.filter { $0.status.isActive }.count
    }

    private var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: style.scaled(8)))
                        .foregroundColor(accentColor.opacity(0.85))

                    Text(activeCount > 0
                         ? "任务进行中 \(completedCount)/\(tasks.count)"
                         : "任务 \(tasks.count)")
                        .font(.system(size: style.scaled(9), weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.85))

                    Spacer(minLength: 4)

                    Text("\(completedCount)/\(tasks.count)")
                        .font(.system(size: style.scaled(8), weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))

                    Image(systemName: "chevron.down")
                        .font(.system(size: style.scaled(7)))
                        .foregroundColor(.gray.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tasks) { task in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: task.status.iconName)
                                    .font(.system(size: style.scaled(8)))
                                    .foregroundColor(task.status.color.opacity(0.85))
                                    .frame(width: 10, alignment: .center)

                                Text(task.title)
                                    .font(.system(size: style.scaled(9.5)))
                                    .foregroundColor(.white.opacity(task.status == .completed ? 0.58 : 0.8))
                                    .lineLimit(2)
                                    .strikethrough(task.status == .completed)
                            }
                            if let subtitle = task.subtitleText {
                                Text(subtitle)
                                    .font(.system(size: style.scaled(8.5)))
                                    .foregroundColor(.gray.opacity(0.55))
                                    .lineLimit(2)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(accentColor.opacity(0.14), lineWidth: 0.5)
        )
    }
}

// MARK: - Markdown Rendering Helper

/// Cache for parsed AttributedString results to avoid repeated markdown parsing.
private let mdCache = NSCache<NSString, NSAttributedString>()

private func markdownAttributedString(_ markdown: String) -> AttributedString {
    if let cached = mdCache.object(forKey: markdown as NSString) {
        return AttributedString(cached)
    }
    do {
        var attributed = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        // Cache the NSAttributedString representation
        mdCache.setObject(NSAttributedString(attributed), forKey: markdown as NSString)
        return attributed
    } catch {
        let fallback = AttributedString(markdown)
        mdCache.setObject(NSAttributedString(fallback), forKey: markdown as NSString)
        return fallback
    }
}