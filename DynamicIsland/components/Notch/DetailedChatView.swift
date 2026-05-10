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

// MARK: - Unified Conversation View (inverted scroll)

/// A natural conversation view inspired by vibe-notch.
/// Uses inverted ScrollView so the view stays at the bottom when new content arrives.
struct UnifiedConversationView: View {
    @ObservedObject var session: AIAgentSession
    let style: AIAgentCardStyle
    @ObservedObject var agentManager: AIAgentManager
    @Default(.aiAgentShowThinkingBlocks) private var showThinkingBlocks
    @Default(.aiAgentShowToolDetails) private var showToolDetails
    @Default(.aiAgentShowToolOutput) private var showToolOutput

    @State private var previousTurnCount = 0

    private var accentColor: Color {
        style.accentColor(for: session.agentType)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Processing indicator at bottom of content
                    if session.status == .thinking || session.status == .running || session.status == .coding {
                        let lastTurnHasResponse = session.conversationTurns.last?.agentResponse != nil
                        if lastTurnHasResponse || !session.conversationTurns.isEmpty {
                            ProcessingDotsView(accentColor: accentColor, style: style)
                                .padding(.horizontal, 10)
                        }
                    }

                    // Subagents section
                    if !session.subagentToolCalls.isEmpty {
                        SubagentCompactSection(toolCalls: session.subagentToolCalls, style: style)
                    }

                    // Structured subtasks
                    if !session.structuredSubtasks.isEmpty {
                        TasksCompactSection(tasks: session.structuredSubtasks, accentColor: accentColor, style: style)
                    }

                    // Conversation turns (most recent last, at the bottom)
                    if session.conversationTurns.isEmpty {
                        recentActivitySummary
                    } else {
                        ForEach(session.conversationTurns) { turn in
                            conversationTurnView(turn)
                        }
                    }

                    // Bottom anchor for scrollTo
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 12)
            }
            .onChange(of: session.conversationTurns.count) { newCount, _ in
                guard newCount > previousTurnCount else { return }
                previousTurnCount = newCount
                // Use a small delay to let LazyVStack settle before scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.none) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                previousTurnCount = session.conversationTurns.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.none) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func conversationTurnView(_ turn: AIAgentConversationTurn) -> some View {
        UnifiedTurnView(
            turn: turn,
            agentType: session.agentType,
            style: style,
            accentColor: accentColor,
            showThinkingBlocks: showThinkingBlocks,
            showToolDetails: showToolDetails,
            showToolOutput: showToolOutput
        )
        .id(turn.id)
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

// MARK: - Processing Dots View

private struct ProcessingDotsView: View {
    let accentColor: Color
    let style: AIAgentCardStyle
    @State private var dotCount = 1

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accentColor.opacity(0.6))
                .frame(width: 5, height: 5)

            Text("Processing" + dots)
                .font(.system(size: style.scaled(10)))
                .foregroundColor(accentColor.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

// MARK: - Unified Turn View (vibe-notch style)

/// A single user → AI exchange with vibe-notch inspired styling.
/// - User: right-aligned rounded bubble
/// - AI: left-aligned with dot indicator + accent color
/// - Tool calls: per-tool status dots with pulsing when running
/// - Processing: animated "Processing..." dots
struct UnifiedTurnView: View {
    @ObservedObject var turn: AIAgentConversationTurn
    let agentType: AIAgentType
    let style: AIAgentCardStyle
    let accentColor: Color
    let showThinkingBlocks: Bool
    let showToolDetails: Bool
    let showToolOutput: Bool

    @State private var toolCallsExpanded = false
    @State private var isHoveringToolSection = false

    private var hasEditTool: Bool {
        turn.toolCalls.contains { call in
            let name = call.toolName.lowercased()
            return name == "replace_in_file" || name == "edit" || name == "replaceinfile"
                || name == "write_to_file" || name == "write" || name == "writetofile"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // User message (right-aligned rounded bubble)
            if !turn.userPrompt.isEmpty {
                userBubble
            }

            // AI response area
            VStack(alignment: .leading, spacing: 0) {
                // Agent header
                HStack(spacing: 5) {
                    AgentTypeIconView(agentType: agentType, size: style.scaled(10))
                    Text(agentType.displayName)
                        .font(.system(size: style.scaled(9), weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.85))
                    Spacer()
                }
                .padding(.bottom, 6)

                // Agent response text
                if let response = turn.agentResponse, !response.isEmpty {
                    Text(markdownAttributedString(response))
                        .font(.system(size: style.scaled(10)))
                        .foregroundColor(.white.opacity(0.82))
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .padding(.bottom, turn.toolCalls.isEmpty ? 0 : 6)
                } else if !turn.isComplete {
                    TypingIndicator(accentColor: accentColor, style: style)
                        .padding(.bottom, turn.toolCalls.isEmpty ? 0 : 6)
                }

                // Tool calls with status dots
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
            .padding(.trailing, 24)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: turn.agentResponse?.count)
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
                    .font(.system(size: style.scaled(10)))
                    .foregroundColor(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .frame(maxWidth: style.fontScale > 1 ? 360 : 280, alignment: .trailing)
        }
    }

    // MARK: - Tool Calls (per-tool status dots)

    private var toolCallsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Summary row (always visible)
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    toolCallsExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    // Status indicators for recent/active tools
                    let runningTools = turn.toolCalls.filter { $0.output == nil }
                    let completedTools = turn.toolCalls.filter { $0.output != nil }

                    ZStack {
                        if !runningTools.isEmpty {
                            ToolStatusDot(color: accentColor, isPulsing: true)
                        } else {
                            ToolStatusDot(color: .green, isPulsing: false)
                        }
                    }
                    .frame(width: 12)

                    Text("\(turn.toolCalls.count) tool\(turn.toolCalls.count != 1 ? "s" : "")")
                        .font(.system(size: style.scaled(8.5), weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    if !runningTools.isEmpty {
                        Text("(\(runningTools.count) running)")
                            .font(.system(size: style.scaled(8), design: .monospaced))
                            .foregroundColor(accentColor.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: style.scaled(7)))
                        .foregroundColor(.gray.opacity(0.4))
                        .rotationEffect(.degrees(toolCallsExpanded ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: toolCallsExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded tool details
            if toolCallsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(turn.toolCalls) { call in
                        ToolCallRow(call: call, style: style, showOutput: showToolOutput)
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(toolCallsExpanded && isHoveringToolSection ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHoveringToolSection = $0 }
        .animation(.easeOut(duration: 0.15), value: isHoveringToolSection)
        .onChange(of: turn.toolCalls.count) { _, newCount in
            guard newCount > 0, !toolCallsExpanded, hasEditTool else { return }
            withAnimation(.spring(response: 0.3)) {
                toolCallsExpanded = true
            }
        }
    }
}

// MARK: - Tool Call Row

private struct ToolCallRow: View {
    let call: AIAgentToolCall
    let style: AIAgentCardStyle
    let showOutput: Bool

    @State private var pulseOpacity: Double = 0.6
    @State private var isExpanded = false
    @State private var isHovering = false

    private var statusColor: Color {
        if call.output == nil { return .yellow }
        return .green
    }

    private var canExpand: Bool {
        call.output != nil || !(call.input?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Status dot
                ToolStatusDot(color: statusColor, isPulsing: call.output == nil)
                    .frame(width: 8)

                Text(call.displayDescription)
                    .font(.system(size: style.scaled(9), design: .monospaced))
                    .foregroundColor(.white.opacity(call.output != nil ? 0.65 : 0.8))
                    .lineLimit(1)

                Spacer()

                if canExpand {
                    Image(systemName: "chevron.right")
                        .font(.system(size: style.scaled(6)))
                        .foregroundColor(.gray.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if canExpand {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            }

            if isExpanded {
                let name = call.toolName.lowercased()
                let isEditOrWrite = name == "replace_in_file" || name == "edit" || name == "replaceinfile"
                    || name == "write_to_file" || name == "write" || name == "writetofile"
                if isEditOrWrite, let diffData = extractDiffStrings(from: call) {
                    LCSDiffView(old: diffData.old, new: diffData.new, filePath: diffData.filePath)
                        .padding(.leading, 14)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let input = call.input, !input.isEmpty {
                    Text(input)
                        .font(.system(size: style.scaled(8), design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                        .lineLimit(4)
                        .padding(.leading, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Non-expanded edit/write tools always show diff while running (like vibe-notch)
            if !isExpanded {
                let name = call.toolName.lowercased()
                if (name == "replace_in_file" || name == "edit" || name == "replaceinfile"
                    || name == "write_to_file" || name == "write" || name == "writetofile"),
                   let diffData = extractDiffStrings(from: call) {
                    LCSDiffView(old: diffData.old, new: diffData.new, filePath: diffData.filePath)
                        .padding(.leading, 14)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(canExpand && isHovering ? Color.white.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Tool Status Dot

private struct ToolStatusDot: View {
    let color: Color
    let isPulsing: Bool

    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        Circle()
            .fill(color.opacity(pulseOpacity))
            .frame(width: 6, height: 6)
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        pulseOpacity = 0.15
                    }
                }
            }
            .id(isPulsing) // Cancel previous animation on state change
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

// MARK: - Typing Indicator (animated dots)

/// Animated bouncing dots indicating the agent is thinking/typing.
struct TypingIndicator: View {
    let accentColor: Color
    let style: AIAgentCardStyle
    @State private var dotOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(accentColor.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .offset(y: dotOffset)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: dotOffset
                        )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.1))
            )

            Text("思考中...")
                .font(.system(size: style.scaled(9)))
                .foregroundColor(.gray.opacity(0.55))
        }
        .onAppear { dotOffset = -3.5 }
    }
}

// MARK: - Markdown Rendering Helper

// MARK: - Diff Display (LCS-based, inspired by vibe-notch)

private enum DiffLineType {
    case added, removed, context

    var textColor: Color {
        switch self {
        case .added: return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .removed: return Color(red: 0.95, green: 0.45, blue: 0.45)
        case .context: return Color.white.opacity(0.55)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        case .context: return Color.clear
        }
    }
}

private struct DiffResultLine: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffLineType
    let lineNumber: Int
}

/// Extract old_string and new_string from tool call for diff display.
/// Priority: 1. bridge tool_input_raw fields, 2. parse input JSON, 3. parse output unified diff
/// Supports camelCase tool names (Edit, ReplaceInFile, WriteToFile like vibe-notch).
private func extractDiffStrings(from call: AIAgentToolCall) -> (old: String, new: String, filePath: String?)? {
    let name = call.toolName.lowercased()
    let isEdit = name == "replace_in_file" || name == "edit" || name == "replaceinfile"
    let isWrite = name == "write_to_file" || name == "write" || name == "writetofile"

    if isEdit {
        // Priority 1: directly from bridge tool_input_raw (oldString/newString or full toolInputRaw dict)
        if let old = call.oldString, let new = call.newString {
            return (old, new, call.filePath)
        }
        if let raw = call.toolInputRaw,
           let old = raw["old_string"], let new = raw["new_string"] {
            return (old, new, raw["file_path"] ?? call.filePath)
        }
        // Priority 2: parse input as JSON fallback
        if let input = call.input, let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let oldStr = json["old_string"] as? String
            let newStr = json["new_string"] as? String
            let path = json["file_path"] as? String ?? call.filePath
            if let o = oldStr, let n = newStr {
                return (o, n, path)
            }
        }
        // Priority 3: try to extract from output (unified diff format)
        if let output = call.output {
            let lines = output.components(separatedBy: "\n")
            var oldParts: [String] = []
            var newParts: [String] = []
            var inDiff = false
            for line in lines {
                if line.hasPrefix("@@") && line.contains("@@") {
                    inDiff = true
                    continue
                }
                if !inDiff { continue }
                if line.hasPrefix("-") && !line.hasPrefix("---") {
                    oldParts.append(String(line.dropFirst()))
                } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    newParts.append(String(line.dropFirst()))
                }
            }
            if !oldParts.isEmpty || !newParts.isEmpty {
                return (oldParts.joined(separator: "\n"), newParts.joined(separator: "\n"), call.filePath)
            }
        }
        return nil
    }

    // For write_to_file, "old" is empty, "new" is the content
    if isWrite {
        // Priority 1: from input raw if available (for vibe-notch-style data)
        if let raw = call.toolInputRaw, let content = raw["content"] ?? raw["new_string"], !content.isEmpty {
            return ("", content, call.filePath)
        }
        // Priority 2: from output
        if let output = call.output, !output.isEmpty {
            return ("", output, call.filePath)
        }
        return nil
    }

    return nil
}

/// Compute LCS-based diff lines (like vibe-notch's SimpleDiffView)
private func computeDiffLines(old: String, new: String, maxLines: Int = 16) -> [DiffResultLine] {
    let oldLines = old.components(separatedBy: "\n")
    let newLines = new.components(separatedBy: "\n")

    let lcs = computeLCS(oldLines, newLines)

    var result: [DiffResultLine] = []
    var oldIdx = 0
    var newIdx = 0
    var lcsIdx = 0
    var oldLineNum = 1
    var newLineNum = 1

    while (oldIdx < oldLines.count || newIdx < newLines.count) && result.count < maxLines {
        let lcsLine = lcsIdx < lcs.count ? lcs[lcsIdx] : nil

        if oldIdx < oldLines.count && (lcsLine == nil || oldLines[oldIdx] != lcsLine) {
            result.append(DiffResultLine(text: oldLines[oldIdx], type: .removed, lineNumber: oldLineNum))
            oldIdx += 1
            oldLineNum += 1
        } else if newIdx < newLines.count && (lcsLine == nil || newLines[newIdx] != lcsLine) {
            result.append(DiffResultLine(text: newLines[newIdx], type: .added, lineNumber: newLineNum))
            newIdx += 1
            newLineNum += 1
        } else {
            oldIdx += 1
            newIdx += 1
            lcsIdx += 1
            oldLineNum += 1
            newLineNum += 1
        }
    }

    return result
}

/// LCS algorithm for two string arrays
private func computeLCS(_ a: [String], _ b: [String]) -> [String] {
    let m = a.count
    let n = b.count
    guard m > 0 && n > 0 else { return [] }

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 1...m {
        for j in 1...n {
            if a[i - 1] == b[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    var lcs: [String] = []
    var i = m, j = n
    while i > 0 && j > 0 {
        if a[i - 1] == b[j - 1] {
            lcs.append(a[i - 1])
            i -= 1
            j -= 1
        } else if dp[i - 1][j] > dp[i][j - 1] {
            i -= 1
        } else {
            j -= 1
        }
    }

    return lcs.reversed()
}

/// Detect changes count (for overflow indicator)
private func diffChangeCount(old: String, new: String) -> Int {
    let oldLines = old.components(separatedBy: "\n")
    let newLines = new.components(separatedBy: "\n")
    let lcs = computeLCS(oldLines, newLines)
    return (oldLines.count - lcs.count) + (newLines.count - lcs.count)
}

// MARK: - LCS Diff View (like vibe-notch's SimpleDiffView)

private struct LCSDiffView: View {
    let diffLines: [DiffResultLine]
    let filePath: String?
    let totalChanges: Int

    init(old: String, new: String, filePath: String?, maxLines: Int = 16) {
        self.filePath = filePath
        self.diffLines = computeDiffLines(old: old, new: new, maxLines: maxLines)
        self.totalChanges = diffChangeCount(old: old, new: new)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filename header
            if let name = filePath.map({ ($0 as NSString).lastPathComponent }) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    Text(name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
            }

            // Top overflow
            if totalChanges > diffLines.count {
                Text("...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 42)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
            }

            // Diff lines
            ForEach(diffLines) { line in
                HStack(spacing: 0) {
                    // Line number
                    Text("\(line.lineNumber)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(line.type.textColor.opacity(0.5))
                        .frame(width: 24, alignment: .trailing)
                        .padding(.trailing, 3)

                    // +/- indicator
                    Text(line.type == .added ? "+" : "−")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(line.type.textColor)
                        .frame(width: 12)

                    // Line content
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(line.type.textColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
                .padding(.vertical, 1.5)
                .background(line.type.backgroundColor)
            }

            // Bottom overflow
            if totalChanges > diffLines.count {
                Text("... 还有 \(totalChanges - diffLines.count) 处变更")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 42)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
            }
        }
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

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