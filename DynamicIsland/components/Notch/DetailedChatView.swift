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
    }

    // MARK: - Transcript List with Chat-like Layout

    private var transcriptListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chatSegments) { segment in
                        ChatSegmentView(
                            segment: segment,
                            agentType: session.agentType,
                            style: style,
                            showThinkingBlocks: showThinkingBlocks,
                            showToolDetails: showToolDetails,
                            showToolOutput: showToolOutput
                        )
                        .id(segment.id)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: style.expandedContentMaxHeight)
            .onAppear {
                scrollToLatestChat(proxy: proxy)
            }
            .onChange(of: session.fullTranscript.count) { _, _ in
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

    /// 将 transcript 消息分组为用户-AI 对话的片段
    /// 每个片段包含一个有效的用户消息和其对应的 AI 回复
    private var chatSegments: [ChatSegment] {
        var segments: [ChatSegment] = []
        var currentUserMessage: TranscriptMessage?
        var currentAssistantMessages: [TranscriptMessage] = []

        for message in session.fullTranscript {
            switch message.role {
            case .user:
                // 保存之前的片段（只有当用户消息有有效内容时才保存）
                if let userMsg = currentUserMessage, hasValidTextContent(userMsg), !currentAssistantMessages.isEmpty {
                    segments.append(ChatSegment(
                        id: userMsg.id,
                        userMessage: userMsg,
                        assistantMessages: currentAssistantMessages
                    ))
                }
                // 开始新的片段（不管用户消息是否有内容）
                currentUserMessage = message
                currentAssistantMessages = []

            case .assistant:
                currentAssistantMessages.append(message)

            case .system, .tool:
                // 系统和工具消息附加到当前片段的 assistant 消息中
                if currentUserMessage != nil {
                    currentAssistantMessages.append(message)
                } else if let lastSegment = segments.last {
                    // 附加到最后一个片段
                    var updatedSegment = lastSegment
                    updatedSegment.assistantMessages.append(message)
                    segments[segments.count - 1] = updatedSegment
                }
                // 如果没有任何片段，忽略这些消息

            }
        }

        // 保存最后一个片段（只有当用户消息有有效内容时才保存）
        if let userMsg = currentUserMessage, hasValidTextContent(userMsg) {
            segments.append(ChatSegment(
                id: userMsg.id,
                userMessage: userMsg,
                assistantMessages: currentAssistantMessages
            ))
        } else if !currentAssistantMessages.isEmpty, let lastSegment = segments.last {
            // 如果最后的用户消息没有有效内容，但有 assistant 消息，附加到前一个片段
            var updatedSegment = lastSegment
            updatedSegment.assistantMessages.append(contentsOf: currentAssistantMessages)
            segments[segments.count - 1] = updatedSegment
        }

        return segments
    }

    private func scrollToLatestChat(proxy: ScrollViewProxy) {
        if let lastSegment = chatSegments.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastSegment.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty / Loading / Error

    private var emptyTranscriptView: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: style.scaled(20)))
                .foregroundColor(.gray.opacity(0.5))
            Text("暂无对话记录")
                .font(.system(size: style.scaled(10)))
                .foregroundColor(.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }

    private var loadingView: some View {
        VStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("加载对话记录...")
                .font(.system(size: style.scaled(10)))
                .foregroundColor(.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
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
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(roleBackgroundColor)
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
                if let image = AIAgentIconResolver.image(for: agentType) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Image(systemName: agentType.iconName)
                        .font(.system(size: style.scaled(8)))
                        .foregroundColor(agentType.accentColor.opacity(0.6))
                }
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

struct ChatSegment: Identifiable {
    let id: String
    let userMessage: TranscriptMessage
    var assistantMessages: [TranscriptMessage]
}

// MARK: - Chat Segment View

struct ChatSegmentView: View {
    let segment: ChatSegment
    let agentType: AIAgentType
    let style: AIAgentCardStyle
    let showThinkingBlocks: Bool
    let showToolDetails: Bool
    let showToolOutput: Bool

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
            Spacer(minLength: 40)  // Push to right side

            VStack(alignment: .trailing, spacing: 4) {
                // Timestamp + avatar
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

                // Message content in bubble (使用 displayContent 过滤系统注入内容)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(segment.userMessage.displayContent.enumerated()), id: \.offset) { _, block in
                        userContentBlockView(block)
                    }
                }
                .lineSpacing(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - AI Bubble

    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Agent header with collapse button
                HStack(spacing: 5) {
                    AgentIconView(agentType: agentType, size: 16)
                        .frame(width: 16, height: 16)

                    Text(agentType.displayName)
                        .font(.system(size: style.scaled(10), weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.9))

                    Spacer()

                    // Collapse button with rotation animation
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

                // All assistant messages merged in one bubble
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(segment.assistantMessages) { message in
                        messageContentView(message)
                    }
                }
                .lineSpacing(2)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.1), lineWidth: 0.5)
                )
            }
            .padding(.trailing, 20)  // Right padding to prevent full-width
        }
    }

    // MARK: - Collapsed Preview

    private var collapsedPreview: some View {
        HStack(spacing: 6) {
            AgentIconView(agentType: agentType, size: 12)
                .foregroundColor(accentColor.opacity(0.7))

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

struct AgentIconView: View {
    let agentType: AIAgentType
    let size: CGFloat

    var body: some View {
        if let image = AIAgentIconResolver.image(for: agentType) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        } else {
            Image(systemName: agentType.iconName)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(agentType.accentColor)
        }
    }
}

// MARK: - Markdown Rendering Helper

/// Parse markdown text into AttributedString for native rendering
private func markdownAttributedString(_ markdown: String) -> AttributedString {
    do {
        var attributed = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return attributed
    } catch {
        return AttributedString(markdown)
    }
}