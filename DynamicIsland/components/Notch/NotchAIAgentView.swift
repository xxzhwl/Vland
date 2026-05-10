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

// MARK: - Main Notch AI Agent View

struct NotchAIAgentView: View {
    @ObservedObject var agentManager = AIAgentManager.shared
    @Default(.aiAgentCardFontScale) private var aiAgentCardFontScale
    @Default(.aiAgentCardExpandedMaxHeight) private var aiAgentCardExpandedMaxHeight

    private var orderedSessions: [AIAgentSession] {
        agentManager.displayedSessions
    }

    private var visibleSessions: [AIAgentSession] {
        agentManager.isShowingArchivedSessions ? agentManager.archivedSessions : orderedSessions
    }

    private var style: AIAgentCardStyle {
        let saved = Defaults[.aiAgentCardTheme]
        return AIAgentCardStyle(
            fontScale: CGFloat(aiAgentCardFontScale),
            expandedContentMaxHeight: CGFloat(aiAgentCardExpandedMaxHeight),
            theme: ResolvedCardTheme(from: saved)
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if let detailSession = agentManager.selectedDetailSession {
                AIAgentSessionDetailView(session: detailSession, style: style)
            } else {
                overviewHeader

                if visibleSessions.isEmpty {
                    emptyStateView(style: style)
                } else {
                    AIAgentSessionListView(sessions: visibleSessions, style: style)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var overviewHeader: some View {
        HStack(spacing: 0) {
            tabButton(
                title: "会话",
                count: agentManager.displayedSessions.count,
                icon: "bolt.fill",
                isSelected: !agentManager.isShowingArchivedSessions
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    agentManager.isShowingArchivedSessions = false
                }
            }

            tabButton(
                title: "归档",
                count: agentManager.archivedSessions.count,
                icon: "archivebox.fill",
                isSelected: agentManager.isShowingArchivedSessions
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    agentManager.isShowingArchivedSessions = true
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func tabButton(title: String, count: Int, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: style.scaled(9), weight: .semibold))
                Text(title)
                    .font(.system(size: style.scaled(10), weight: .medium))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: style.scaled(8), weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.95) : .gray.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
                        )
                }
            }
            .foregroundColor(isSelected ? .white.opacity(0.95) : .gray.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func emptyStateView(style: AIAgentCardStyle) -> some View {
        VStack(spacing: 8) {
            Image(systemName: agentManager.isShowingArchivedSessions
                  ? "archivebox"
                  : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: style.scaled(28)))
                .foregroundColor(.gray.opacity(0.5))

            Text(agentManager.isShowingArchivedSessions
                 ? "暂无归档会话"
                 : "暂无活跃的 AI 助手")
                .font(.system(size: style.scaled(12), weight: .medium))
                .foregroundColor(.gray)

            Text(agentManager.isShowingArchivedSessions
                 ? "已结束的会话将自动归档到这里"
                 : "在设置中配置 hooks 来启用 AI 助手监控")
                .font(.system(size: style.scaled(10)))
                .foregroundColor(.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}

struct AIAgentSessionListView: View {
    let sessions: [AIAgentSession]
    let style: AIAgentCardStyle

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(sessions) { session in
                    AIAgentSessionCard(session: session, style: style)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .identity
                        ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sessions.count)
        }
    }
}

// MARK: - Session Card

struct AIAgentSessionCard: View {
    @ObservedObject var session: AIAgentSession
    let style: AIAgentCardStyle
    @State private var isExpanded = false
    @State private var lastAutoExpandedInteractionID: UUID?
    @ObservedObject var agentManager = AIAgentManager.shared
    @ObservedObject private var quotaMonitor = QuotaMonitorManager.shared
    @Default(.aiAgentQuotaMonitorEnabled) private var quotaMonitorEnabled
    @Default(.aiAgentQuotaShowRing) private var quotaShowRing
    @Default(.aiAgentQuotaShowInlineBar) private var quotaShowInlineBar

    private var totalTodoCount: Int {
        session.todoItems.count
    }

    private var completedTodoCount: Int {
        session.todoItems.filter { $0.status == .completed }.count
    }

    private var todoCompletionRatio: CGFloat {
        guard totalTodoCount > 0 else { return 0 }
        return CGFloat(completedTodoCount) / CGFloat(totalTodoCount)
    }

    private var todoProgressColor: Color {
        totalTodoCount > 0 && completedTodoCount == totalTodoCount ? .green : .blue
    }

    private var requiresInput: Bool {
        session.status == .waitingInput && session.latestPendingInteraction != nil
    }

    private var latestInteractionID: UUID? {
        session.latestPendingInteraction?.id
    }

    private var sessionStartTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.startTime)
    }

    private var headerTaskText: String {
        session.currentTodoDisplayText
        ?? session.currentSubtaskDisplayText
        ?? session.activeSubagentCall?.displayDescription
        ?? session.currentTask
    }

    private var headerTaskIconName: String {
        if session.currentTodoDisplayText != nil {
            return "list.bullet.rectangle.portrait.fill"
        }
        if session.currentSubtaskDisplayText != nil {
            return "square.stack.3d.up.fill"
        }
        if session.activeSubagentCall != nil {
            return "square.stack.3d.up.fill"
        }
        return session.status.iconName
    }

    private var headerTaskIconColor: Color {
        if session.currentTodoDisplayText != nil {
            return todoProgressColor.opacity(0.8)
        }
        if session.currentSubtaskDisplayText != nil {
            return style.accentColor(for: session.agentType).opacity(0.8)
        }
        if session.activeSubagentCall != nil {
            return .purple.opacity(0.8)
        }
        return session.status.color.opacity(0.7)
    }

    private var headerProgressLabel: String? {
        session.currentTodoProgressLabel ?? session.currentSubtaskProgressLabel
    }

    private var headerProgressTint: Color {
        if session.currentTodoProgressLabel != nil {
            return todoProgressColor
        }
        return style.accentColor(for: session.agentType)
    }

    private var agentIconImage: NSImage? {
        AIAgentIconResolver.image(for: session.agentType)
    }

    private var quotaSnapshot: QuotaSnapshot? {
        quotaMonitor.snapshot(for: session.agentType)
    }

    private var primaryQuotaWindow: QuotaWindow? {
        quotaSnapshot?.primaryWindow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            // Expanded detail
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: style.theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(style.theme.cardBackgroundOpacity))
        )
        .overlay(alignment: .center) {
            let isAwaitingInput = requiresInput
            RoundedRectangle(cornerRadius: style.theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    style.accentColor(for: session.agentType)
                        .opacity(isAwaitingInput ? attentionGlow : style.theme.cardBorderOpacity),
                    lineWidth: isAwaitingInput ? 1.5 : 0.5
                )
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: attentionGlow)
        }
        .onAppear {
            autoExpandForLatestInteractionIfNeeded()
            if requiresInput { startAttentionGlow() }
        }
        .onChange(of: latestInteractionID) { _, _ in
            autoExpandForLatestInteractionIfNeeded()
            if requiresInput { startAttentionGlow() }
        }
    }

    @State private var attentionGlow: CGFloat = 0.5

    private func startAttentionGlow() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            attentionGlow = 1.0
        }
    }

    // MARK: - Card Header
    // Layout: [StatusDot AgentName | UserQuestion ...      projectDir ▼]
    //         [  小字: agent 当前在做什么                                 ]

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    // Top row: agent | user question | directory
                    HStack(spacing: 0) {
                        // Status dot
                        Group {
                            if session.status.isActive || session.status == .completed {
                                StatusPulse(color: session.status == .completed ? .green : session.status.color)
                            } else {
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .frame(width: 12, height: 12)
                            .padding(.trailing, 6)

                        agentIdentityIcon
                            .padding(.trailing, 6)

                        // Agent name
                        Text(session.agentType.displayName)
                            .font(.system(size: style.scaled(12), weight: .bold))
                            .foregroundColor(style.accentColor(for: session.agentType))

                        // Separator
                        if session.lastUserPrompt != nil {
                            Text("｜")
                                .font(.system(size: style.scaled(11)))
                                .foregroundColor(.gray.opacity(0.4))
                                .padding(.horizontal, 3)
                        }

                        // User question preview
                        if let prompt = session.lastUserPrompt {
                            Text(prompt)
                                .font(.system(size: style.scaled(11)))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if let projectName = session.projectName {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: style.scaled(8)))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text(projectName)
                                    .font(.system(size: style.scaled(10)))
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        }

                        if let progress = headerProgressLabel {
                            statusChip(text: progress, tint: headerProgressTint)
                                .padding(.leading, 6)
                        }

                        if requiresInput {
                            statusChip(text: "需要输入", tint: .orange)
                                .padding(.leading, 6)
                        }

                        // Context usage warning badge
                        if let ratio = session.contextUsageRatio, ratio >= 0.8 {
                            let pct = Int(ratio * 100)
                            let tint: Color = ratio >= 0.95 ? .red : .yellow
                            statusChip(text: "CTX \(pct)%", tint: tint)
                                .padding(.leading, 6)
                        } else if session.compactCount > 0 {
                            statusChip(text: "已压缩×\(session.compactCount)", tint: .yellow)
                                .padding(.leading, 6)
                        }

                        if quotaMonitorEnabled,
                           quotaShowRing,
                           let primaryQuotaWindow {
                            QuotaRingBadge(
                                window: primaryQuotaWindow,
                                style: style,
                                fallbackTint: style.accentColor(for: session.agentType)
                            )
                            .padding(.leading, 6)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: style.scaled(8), weight: .semibold))
                            .foregroundColor(.gray.opacity(0.4))
                            .padding(.leading, 6)
                    }

                    // Bottom row: what the agent is currently doing
                    HStack(spacing: 4) {
                        Image(systemName: headerTaskIconName)
                            .font(.system(size: style.scaled(8)))
                            .foregroundColor(headerTaskIconColor)

                        Text(headerTaskText)
                            .font(.system(size: style.scaled(10)))
                            .foregroundColor(.gray.opacity(0.7))
                            .lineLimit(1)

                        Spacer()

                        // Start time + Elapsed time
                        Text(sessionStartTimeString)
                            .font(.system(size: style.scaled(8.5), design: .monospaced))
                            .foregroundColor(.gray.opacity(0.35))
                        Text(session.elapsedTimeString)
                            .font(.system(size: style.scaled(9), design: .monospaced))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    .padding(.leading, 13) // align with text after dot

                    if !session.todoItems.isEmpty {
                        todoProgressSection
                            .padding(.leading, 13)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起任务详情" : "展开任务详情")

            Button(action: openAssociatedAgent) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: style.scaled(11), weight: .semibold))
                    .foregroundColor(style.accentColor(for: session.agentType).opacity(0.95))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(style.accentColor(for: session.agentType).opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("打开关联的 AI 助手窗口")

            Button(action: showSessionDetail) {
                Image(systemName: "info.circle")
                    .font(.system(size: style.scaled(11), weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help("查看会话详情")

            if session.isArchived {
                Button(action: restoreSession) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: style.scaled(11), weight: .semibold))
                        .foregroundColor(.green.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help("恢复会话")
            } else if session.canArchiveManually {
                Button(action: archiveSession) {
                    Image(systemName: "archivebox")
                        .font(.system(size: style.scaled(11), weight: .semibold))
                        .foregroundColor(.orange.opacity(0.88))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help("归档会话")
            }
        }
        .padding(.horizontal, style.theme.cardPaddingH)
        .padding(.vertical, style.theme.cardPaddingV)
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3)) {
            isExpanded.toggle()
        }
    }

    private func openAssociatedAgent() {
        agentManager.activateAgentApp(session: session)
    }

    private func showSessionDetail() {
        agentManager.presentSessionDetail(session)
    }

    private func archiveSession() {
        agentManager.archiveSession(session)
    }

    private func restoreSession() {
        agentManager.restoreSession(session)
    }

    private func autoExpandForLatestInteractionIfNeeded() {
        guard requiresInput, let interactionID = latestInteractionID else { return }
        guard interactionID != lastAutoExpandedInteractionID else { return }

        lastAutoExpandedInteractionID = interactionID
        if !isExpanded {
            withAnimation(.spring(response: 0.3)) {
                isExpanded = true
            }
        }
    }

    private func statusChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: style.scaled(8), weight: .semibold, design: .monospaced))
            .foregroundColor(tint.opacity(0.95))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
            )
    }

    private var todoProgressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))

                        Capsule()
                            .fill(todoProgressColor)
                            .frame(width: geo.size.width * todoCompletionRatio)
                    }
                }
                .frame(height: 4)

                Text("\(completedTodoCount)/\(totalTodoCount)")
                    .font(.system(size: style.scaled(9), weight: .medium, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(session.todoItems) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: item.status.iconName)
                            .font(.system(size: style.scaled(9)))
                            .foregroundColor(item.status.color)
                            .frame(width: 10, alignment: .center)

                        Text(item.content)
                            .font(.system(size: style.scaled(9.5)))
                            .foregroundColor(.white.opacity(item.status == .completed ? 0.55 : 0.78))
                            .lineLimit(1)
                            .strikethrough(item.status == .completed, color: item.status.color.opacity(0.8))
                    }
                }
            }
        }
    }

    // MARK: - Expanded Content: unified conversation flow

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            if quotaMonitorEnabled,
               quotaShowInlineBar,
               let quotaSnapshot {
                QuotaInlineBar(
                    snapshot: quotaSnapshot,
                    style: style,
                    accentColor: style.accentColor(for: session.agentType)
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            // Pending interaction banner (always visible)
            if let latestInteraction = session.latestPendingInteraction, requiresInput {
                InteractionView(
                    interaction: latestInteraction,
                    accentColor: style.accentColor(for: session.agentType),
                    session: session,
                    prominent: true,
                    style: style
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            // Unified conversation view
            UnifiedConversationView(
                session: session,
                style: style,
                agentManager: agentManager
            )
            .frame(maxHeight: style.expandedContentMaxHeight)

            // Chat input bar for bridge-based agents
            // Reply mode: show when there's a pending pasteReply interaction
            // Proactive mode: show for active CLI-backed sessions (like vibe-notch)
            let hasPendingPasteReply = session.latestPendingInteraction?.responseMode == .pasteReply
            if hasPendingPasteReply, let interaction = session.latestPendingInteraction {
                ChatInputBar(
                    pendingInteraction: interaction,
                    session: session,
                    style: style
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else if session.isCLIBacked, session.status.isActive {
                // Show input bar for active CLI sessions
                ChatInputBar(
                    pendingInteraction: nil,
                    session: session,
                    style: style
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var agentIdentityIcon: some View {
        if let image = agentIconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            AgentTypeIconView(agentType: session.agentType, size: style.scaled(12))
                .frame(width: 14, height: 14)
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(style.accentColor(for: session.agentType).opacity(0.12))
                )
        }
    }

}

// MARK: - Turn View (one user→agent cycle)

struct TurnView: View {
    @ObservedObject var turn: AIAgentConversationTurn
    let session: AIAgentSession
    let hiddenInteractionID: UUID?
    let style: AIAgentCardStyle

    private var visibleInteractions: [AIAgentInteraction] {
        turn.interactions.filter { $0.id != hiddenInteractionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // User question — only show when there's real user content
            if !turn.userPrompt.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "person.fill")
                        .font(.system(size: style.scaled(8)))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 12, height: 12)

                    Text(turn.userPrompt)
                        .font(.system(size: style.scaled(10), weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .textSelection(.enabled)

                    Spacer()

                    Text(turn.timeString)
                        .font(.system(size: style.scaled(8), design: .monospaced))
                        .foregroundColor(.gray.opacity(0.35))
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            }

            // Tool calls (compact)
            if !turn.toolCalls.isEmpty {
                CompactToolCallsView(toolCalls: turn.toolCalls, style: style)
                    .padding(.leading, 17)
            }

            // Agent interactions (questions, options)
            ForEach(visibleInteractions) { interaction in
                InteractionView(
                    interaction: interaction,
                    accentColor: style.accentColor(for: session.agentType),
                    session: session,
                    style: style
                )
                    .padding(.leading, 17)
            }

            // Agent response
            if let response = turn.agentResponse {
                HStack(alignment: .top, spacing: 5) {
                    AgentInlineIcon(agentType: session.agentType, style: style)
                        .frame(width: 12, height: 12)

                    Text(markdownAttributedString(response))
                        .font(.system(size: style.scaled(10)))
                        .foregroundColor(.white.opacity(0.75))
                        .textSelection(.enabled)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(style.accentColor(for: session.agentType).opacity(style.theme.interactionBackgroundOpacity))
                )
            } else if !turn.isComplete {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("执行中...")
                        .font(.system(size: style.scaled(9)))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .padding(.leading, 17)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Compact Tool Calls

struct CompactToolCallsView: View {
    let toolCalls: [AIAgentToolCall]
    let style: AIAgentCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(toolCalls) { call in
                HStack(spacing: 4) {
                    Image(systemName: call.output != nil ? "checkmark.circle.fill" : "gearshape")
                        .font(.system(size: style.scaled(7)))
                        .foregroundColor(call.output != nil ? .green.opacity(0.5) : .yellow.opacity(0.5))

                    Text(call.displayDescription)
                        .font(.system(size: style.scaled(9)))
                        .foregroundColor(.gray.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Interaction View (agent questions/options)

struct InteractionView: View {
    private enum SubmissionState: Equatable {
        case idle
        case submitting(String)
        case submitted(String)
        case copiedForManualSend(String)
        case needsAccessibility(String)
        case timedOut
        case failed(String)
    }

    let interaction: AIAgentInteraction
    let accentColor: Color
    var session: AIAgentSession? = nil
    var prominent: Bool = false
    let style: AIAgentCardStyle
    @ObservedObject private var agentManager = AIAgentManager.shared
    @State private var submissionState: SubmissionState = .idle
    @State private var localIsResolved: Bool = false

    private var isResolved: Bool {
        interaction.isResolved || localIsResolved
    }

    private var actionableOptions: [String] {
        interaction.options ?? []
    }

    private var selectedOption: String? {
        switch effectiveSubmissionState {
        case .idle, .timedOut, .failed:
            return nil
        case .submitting(let option),
                .submitted(let option),
                .copiedForManualSend(let option),
                .needsAccessibility(let option):
            return option
        }
    }

    private var isSubmitting: Bool {
        if case .submitting = submissionState {
            return true
        }
        return false
    }

    private var effectiveSubmissionState: SubmissionState {
        if case .idle = submissionState {
            return submissionState(for: interaction)
        }
        return submissionState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Interaction header
            HStack(spacing: 4) {
                Image(systemName: interactionIcon)
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.orange.opacity(0.7))

                Text(interactionLabel)
                    .font(.system(size: style.scaled(9), weight: .medium))
                    .foregroundColor(.orange.opacity(0.7))

                Spacer()

                Text(interaction.timeString)
                    .font(.system(size: style.scaled(7), design: .monospaced))
                    .foregroundColor(.gray.opacity(0.3))
            }

            // Message
            Text(interaction.message)
                .font(.system(size: style.scaled(10)))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(prominent ? 5 : 3)
                .textSelection(.enabled)

            // Options (if any)
            if !actionableOptions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if interaction.isResolved && selectedOption == nil {
                        HStack(spacing: 6) {
                            Image(systemName: unresolvedStatusIcon)
                                .font(.system(size: style.scaled(10), weight: .semibold))
                                .foregroundColor(unresolvedStatusColor)

                            Text(unresolvedStatusTitle)
                                .font(.system(size: style.scaled(9), weight: .medium))
                                .foregroundColor(unresolvedStatusColor)

                            Spacer()

                            Text(unresolvedStatusSubtitle)
                                .font(.system(size: style.scaled(8)))
                                .foregroundColor(.gray.opacity(0.4))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    } else {
                        ForEach(Array(actionableOptions.enumerated()), id: \.offset) { idx, option in
                            if let session {
                                Button(action: {
                                    guard !isSubmitting else { return }
                                    localIsResolved = true
                                    submissionState = .submitting(option)

                                    Task {
                                        let result = await agentManager.submitInteractionResponse(
                                            session: session,
                                            interaction: interaction,
                                            option: option
                                        )

                                        await MainActor.run {
                                            submissionState = mapSubmissionState(result, option: option)
                                        }
                                    }
                                }) {
                                    HStack(spacing: 7) {
                                        Text("\(idx + 1)")
                                            .font(.system(size: style.scaled(8), weight: .bold, design: .monospaced))
                                            .foregroundColor(accentColor.opacity(0.85))
                                            .frame(width: 16, height: 16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(accentColor.opacity(0.16))
                                            )

                                        Text(option)
                                            .font(.system(size: style.scaled(9.5), weight: .medium))
                                            .foregroundColor(.white.opacity(0.88))
                                            .lineLimit(2)

                                        Spacer(minLength: 4)

                                        trailingIndicator(for: option)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selectedOption == option ? accentColor.opacity(0.16) : Color.white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(selectedOption == option ? accentColor.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(PressScaleStyle())
                                .disabled(isSubmitting || interaction.isResolved)
                            } else {
                                HStack(spacing: 5) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: style.scaled(8), weight: .bold, design: .monospaced))
                                        .foregroundColor(accentColor.opacity(0.7))
                                        .frame(width: 14, height: 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(accentColor.opacity(0.12))
                                        )

                                    Text(option)
                                        .font(.system(size: style.scaled(9)))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(2)
                                }
                            }
                        } // end ForEach
                    } // end else (resolved vs active)
                }

                if session != nil {
                    Text(footerMessage)
                        .font(.system(size: style.scaled(8.5)))
                        .foregroundColor(footerColor)
                        .padding(.top, 2)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var interactionIcon: String {
        switch interaction.type {
        case .question: return "questionmark.bubble.fill"
        case .confirmation: return "hand.raised.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var interactionLabel: String {
        switch interaction.type {
        case .question: return "助手提问"
        case .confirmation: return "需要确认"
        case .info: return "信息"
        }
    }

    @ViewBuilder
    private func trailingIndicator(for option: String) -> some View {
        switch effectiveSubmissionState {
        case .submitting(let selected) where selected == option:
            ProgressView()
                .controlSize(.mini)
        case .submitted(let selected) where selected == option:
            Image(systemName: "paperplane.fill")
                .font(.system(size: style.scaled(8), weight: .semibold))
                .foregroundColor(.green.opacity(0.8))
        case .copiedForManualSend(let selected) where selected == option,
             .needsAccessibility(let selected) where selected == option:
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: style.scaled(8), weight: .semibold))
                .foregroundColor(.orange.opacity(0.8))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: style.scaled(8), weight: .semibold))
                .foregroundColor(.red.opacity(0.8))
        case .timedOut:
            Image(systemName: "clock.badge.xmark.fill")
                .font(.system(size: style.scaled(8), weight: .semibold))
                .foregroundColor(.red.opacity(0.8))
        default:
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: style.scaled(8), weight: .semibold))
                .foregroundColor(accentColor.opacity(0.75))
        }
    }

    private var footerMessage: String {
        switch effectiveSubmissionState {
        case .idle:
            if agentManager.hasPendingBridgeResponse(for: interaction.id) {
                return "可直接在 Vland 中批准或阻止。"
            }
            return "点击选项发送回复给助手。"
        case .submitting:
            if agentManager.hasPendingBridgeResponse(for: interaction.id) {
                return "正在将决定回传给 Hook..."
            }
            return "正在打开助手窗口并提交回复..."
        case .submitted:
            if agentManager.hasPendingBridgeResponse(for: interaction.id) || interaction.responseMode == .approvalSelection {
                return "决定已发送，助手可以继续。"
            }
            return "回复已发送，剪贴板已恢复。"
        case .copiedForManualSend:
            return "回复已复制。如果自动提交失败，请手动粘贴。"
        case .needsAccessibility:
            return "回复已复制。启用辅助功能可一键提交。"
        case .timedOut:
            return "交互超时，未能发送回复。"
        case .failed(let message):
            return message
        }
    }

    private var footerColor: Color {
        switch effectiveSubmissionState {
        case .submitted:
            return .green.opacity(0.7)
        case .copiedForManualSend, .needsAccessibility:
            return .orange.opacity(0.7)
        case .timedOut, .failed:
            return .red.opacity(0.7)
        default:
            return .gray.opacity(0.55)
        }
    }

    private func mapSubmissionState(
        _ result: InteractionResponseResult,
        option: String
    ) -> SubmissionState {
        switch result {
        case .submitted:
            return .submitted(option)
        case .copiedForManualSend:
            return .copiedForManualSend(option)
        case .requiresAccessibility:
            return .needsAccessibility(option)
        case .failed(let message):
            return .failed(message)
        }
    }

    private func submissionState(for interaction: AIAgentInteraction) -> SubmissionState {
        switch interaction.resolutionState {
        case .pending:
            return .idle
        case .submitted(let option):
            return .submitted(option)
        case .timedOut:
            return .timedOut
        case .failed(let message):
            return .failed(message)
        }
    }

    private var unresolvedStatusIcon: String {
        switch effectiveSubmissionState {
        case .timedOut:
            return "clock.badge.xmark.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var unresolvedStatusColor: Color {
        switch effectiveSubmissionState {
        case .timedOut, .failed:
            return .red.opacity(0.8)
        default:
            return .green.opacity(0.8)
        }
    }

    private var unresolvedStatusTitle: String {
        switch effectiveSubmissionState {
        case .timedOut:
            return "已超时"
        case .failed:
            return "发送失败"
        default:
            return "已回复"
        }
    }

    private var unresolvedStatusSubtitle: String {
        switch effectiveSubmissionState {
        case .timedOut:
            return "Hook 在审批前断开连接。"
        case .failed:
            return "请在下一次提示时重试。"
        default:
            return "助手可以继续。"
        }
    }
}

struct SubagentTasksView: View {
    let toolCalls: [AIAgentToolCall]
    let accentColor: Color
    let style: AIAgentCardStyle

    private var activeCount: Int {
        toolCalls.filter { $0.output == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.purple.opacity(0.8))

                Text(activeCount > 0 ? "子代理任务 \(activeCount)/\(toolCalls.count)" : "子代理任务 \(toolCalls.count)")
                    .font(.system(size: style.scaled(9), weight: .semibold))
                    .foregroundColor(.purple.opacity(0.8))
            }

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

struct SessionTasksView: View {
    let tasks: [AIAgentSubtask]
    let accentColor: Color
    let style: AIAgentCardStyle

    private var activeCount: Int {
        tasks.filter { $0.status.isActive }.count
    }

    private var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    private var progressTint: Color {
        completedCount == tasks.count ? .green : accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(accentColor.opacity(0.85))

                Text(activeCount > 0 ? "任务 \(activeCount)/\(tasks.count)" : "任务 \(tasks.count)")
                    .font(.system(size: style.scaled(9), weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.85))

                Spacer(minLength: 4)

                Text("\(completedCount)/\(tasks.count)")
                    .font(.system(size: style.scaled(8), weight: .medium, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    Capsule()
                        .fill(progressTint.opacity(0.9))
                        .frame(width: geo.size.width * completionRatio)
                }
            }
            .frame(height: 4)

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
                                .strikethrough(task.status == .completed, color: task.status.color.opacity(0.8))
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

    private var completionRatio: CGFloat {
        guard !tasks.isEmpty else { return 0 }
        return CGFloat(completedCount) / CGFloat(tasks.count)
    }
}

// MARK: - Helper Views

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct StatusPulse: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.3))
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            )
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - AI Agent Music Wing Indicator (shown in closed notch right wing)

struct AIAgentMusicWingIndicator: View {
    @State private var isAnimating = false
    @State private var gearRotation: Double = 0

    var body: some View {
        ZStack {
            // Pulsing glow background
            Circle()
                .fill(Color.cyan.opacity(0.15))
                .frame(width: 20, height: 20)
                .scaleEffect(isAnimating ? 1.4 : 0.9)
                .opacity(isAnimating ? 0.3 : 0.6)

            // Rotating gear (work indicator)
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.cyan.opacity(0.82))
                .rotationEffect(.degrees(gearRotation))
                .offset(x: 5, y: -5)

            // Brain/bot icon
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.cyan)
                .scaleEffect(isAnimating ? 1.05 : 0.95)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                gearRotation = 360
            }
        }
    }
}

struct AIAgentGearWingIndicator: View {
    @State private var isAnimating = false
    @State private var gearRotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 18, height: 18)
                .scaleEffect(isAnimating ? 1.25 : 0.9)
                .opacity(isAnimating ? 0.35 : 0.7)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.cyan.opacity(0.9))
                .rotationEffect(.degrees(gearRotation))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                gearRotation = 360
            }
        }
    }
}

struct AIAgentWingAgentIcon: View {
    let agentType: AIAgentType

    var body: some View {
        ZStack {
            Circle()
                .fill(agentType.accentColor.opacity(0.16))
                .frame(width: 18, height: 18)

            if let image = AIAgentIconResolver.image(for: agentType) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                AgentTypeIconView(agentType: agentType, size: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AIAgentPendingLeadingWing: View {
    @ObservedObject var session: AIAgentSession

    private var accentColor: Color {
        session.latestPendingInteraction?.isApprovalSelection == true ? .orange : session.agentType.accentColor
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 18, height: 18)

                if let image = AIAgentIconResolver.image(for: session.agentType) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    AgentTypeIconView(agentType: session.agentType, size: 12)
                        .foregroundStyle(accentColor)
                }
            }

            Text("待操作")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct AIAgentPendingTrailingWing: View {
    let pendingCount: Int

    private var displayCount: String {
        pendingCount > 9 ? "9+" : "\(max(1, pendingCount))"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.orange.opacity(0.9))
                .frame(width: 6, height: 6)

            Text("\(displayCount) 个待操作")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.95))
                .lineLimit(1)
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

private struct AgentInlineIcon: View {
    let agentType: AIAgentType
    let style: AIAgentCardStyle

    var body: some View {
        if let image = AIAgentIconResolver.image(for: agentType) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            AgentTypeIconView(agentType: agentType, size: style.scaled(9))
        }
    }
}

// MARK: - Markdown Rendering Helper

private let markdownCache = NSCache<NSString, NSAttributedString>()

private func markdownAttributedString(_ markdown: String) -> AttributedString {
    if let cached = markdownCache.object(forKey: markdown as NSString) {
        return AttributedString(cached)
    }
    do {
        var attributed = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        markdownCache.setObject(NSAttributedString(attributed), forKey: markdown as NSString)
        return attributed
    } catch {
        let fallback = AttributedString(markdown)
        markdownCache.setObject(NSAttributedString(fallback), forKey: markdown as NSString)
        return fallback
    }
}

// MARK: - Chat Input Bar (for bridge-based agents)

/// A text input bar that lets users type messages directly in the Dynamic Island.
/// Supports two modes:
/// 1. Reply mode (pendingInteraction with pasteReply) — responds to an agent question
/// 2. Proactive mode (no pending interaction) — sends a new user prompt as an interrupt
struct ChatInputBar: View {
    let pendingInteraction: AIAgentInteraction?
    @ObservedObject var session: AIAgentSession
    let style: AIAgentCardStyle

    @State private var text: String = ""
    @State private var isSubmitting = false
    @State private var submissionResult: SubmissionResult?
    @State private var dismissFeedbackTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @ObservedObject private var agentManager = AIAgentManager.shared

    private enum SubmissionResult: Equatable {
        case submitted(String)
        case copied(String)
        case proactiveSent(String)
        case failed(String)
    }

    private var accentColor: Color {
        style.accentColor(for: session.agentType)
    }

    private var isReplyMode: Bool {
        pendingInteraction?.responseMode == .pasteReply
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    private var placeholderText: String {
        isReplyMode ? "输入回复..." : "输入消息..."
    }

    var body: some View {
        VStack(spacing: 6) {
            // Status hint for proactive mode
            if !isReplyMode {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: style.scaled(8)))
                    Text("消息将发送给助手")
                        .font(.system(size: style.scaled(8.5)))
                }
                .foregroundColor(.gray.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submission feedback
            if let result = submissionResult {
                feedbackRow(result: result)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // Input row
            HStack(spacing: 6) {
                TextField(placeholderText, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: style.scaled(11)))
                    .foregroundColor(.white.opacity(0.9))
                    .focused($isFocused)
                    .disabled(isSubmitting)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .textFieldStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .onSubmit(submit)

                Button(action: submit) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: style.scaled(20)))
                                .foregroundColor(canSend ? accentColor : .gray.opacity(0.4))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canSend)
                .help("发送 (Enter)")
                .scaleEffect(canSend ? 1.0 : 0.9)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !trimmed.isEmpty else { return }

        dismissFeedbackTask?.cancel()
        isSubmitting = true
        submissionResult = nil
        let previousText = text

        if isReplyMode, let interaction = pendingInteraction {
            // Reply to a pending interaction (existing flow)
            Task {
                let result = await agentManager.submitInteractionResponse(
                    session: session,
                    interaction: interaction,
                    option: trimmed
                )

                await MainActor.run {
                    isSubmitting = false
                    switch result {
                    case .submitted:
                        submissionResult = .submitted(trimmed)
                        text = ""
                        isFocused = true
                        scheduleFeedbackDismiss()
                    case .copiedForManualSend:
                        submissionResult = .copied(trimmed)
                        scheduleFeedbackDismiss()
                    case .requiresAccessibility:
                        submissionResult = .copied(trimmed)
                        scheduleFeedbackDismiss()
                    case .failed(let message):
                        submissionResult = .failed(message)
                        text = previousText
                    }
                }
            }
        } else {
            // Send as proactive prompt
            Task {
                let success = await agentManager.sendProactivePrompt(
                    session: session,
                    prompt: trimmed
                )

                await MainActor.run {
                    isSubmitting = false
                    if success {
                        // Add the prompt to conversation history
                        let turn = AIAgentConversationTurn(userPrompt: trimmed)
                        session.conversationTurns.append(turn)
                        session.lastUserPrompt = trimmed
                        submissionResult = .proactiveSent(trimmed)
                        text = ""
                        isFocused = true
                        scheduleFeedbackDismiss()
                    } else {
                        submissionResult = .failed("发送失败，请在终端直接输入")
                        text = previousText
                    }
                }
            }
        }
    }

    private func scheduleFeedbackDismiss() {
        dismissFeedbackTask?.cancel()
        dismissFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    submissionResult = nil
                }
            }
        }
    }

    @ViewBuilder
    private func feedbackRow(result: SubmissionResult) -> some View {
        HStack(spacing: 5) {
            switch result {
            case .submitted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.green.opacity(0.8))
                Text("回复已发送")
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.green.opacity(0.75))

            case .proactiveSent:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.green.opacity(0.8))
                Text("消息已发送")
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.green.opacity(0.75))

            case .copied:
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.orange.opacity(0.8))
                Text("已复制到剪贴板，需手动粘贴到助手窗口")
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.orange.opacity(0.75))

            case .failed(let message):
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(.red.opacity(0.8))
                Text(message)
                    .font(.system(size: style.scaled(9)))
                    .foregroundColor(.red.opacity(0.75))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    submissionResult = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: style.scaled(7)))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(resultBackgroundColor.opacity(0.08))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var resultBackgroundColor: Color {
        switch submissionResult {
        case .submitted: return .green
        case .proactiveSent: return .green
        case .copied: return .orange
        case .failed, .none: return .red
        }
    }
}

// MARK: - Press Scale Button Style

/// A button style that subtly scales down on press for tactile feedback.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    NotchAIAgentView()
        .frame(width: 500, height: 300)
        .background(Color.black)
}

#Preview("AI Wing Indicator") {
    AIAgentMusicWingIndicator()
        .frame(width: 30, height: 30)
        .background(Color.black)
}
