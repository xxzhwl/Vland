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

import SwiftUI

struct AIAgentSneakPeekView: View {
    @ObservedObject private var agentManager = AIAgentManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    let maxWidth: CGFloat

    private var attentionSessions: [AIAgentSession] {
        let approvals = agentManager.collapsedSessionsAwaitingApproval
        if !approvals.isEmpty {
            return approvals
        }

        let waiting = agentManager.collapsedSessionsAwaitingInput
        if !waiting.isEmpty {
            return waiting
        }

        return []
    }

    private var todoSessions: [AIAgentSession] {
        agentManager.todoSneakPeekSessions
    }

    private var visibleSessions: [AIAgentSession] {
        Array(displaySessions.prefix(3))
    }

    private var hiddenSessionCount: Int {
        max(0, displaySessions.count - visibleSessions.count)
    }

    private var displaySessions: [AIAgentSession] {
        if !attentionSessions.isEmpty {
            return attentionSessions
        }
        return todoSessions
    }

    private var fallbackTitle: String? {
        let text = coordinator.sneakPeek.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var fallbackSubtitle: String? {
        let text = coordinator.sneakPeek.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var body: some View {
        Group {
            if attentionSessions.count == 1, let session = attentionSessions.first {
                SingleAgentInteractionSneakPeekContent(session: session)
            } else if !attentionSessions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleSessions) { session in
                        MultiAgentInteractionSneakPeekRow(session: session)
                    }

                    if hiddenSessionCount > 0 {
                        Text("还有 \(hiddenSessionCount) 个")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            } else if todoSessions.count == 1, let session = todoSessions.first {
                SingleAgentSneakPeekContent(session: session)
            } else if !todoSessions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleSessions) { session in
                        MultiAgentSneakPeekRow(session: session)
                    }

                    if hiddenSessionCount > 0 {
                        Text("还有 \(hiddenSessionCount) 个")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            } else if fallbackTitle != nil || fallbackSubtitle != nil {
                FallbackAIAgentSneakPeekContent(
                    title: fallbackTitle,
                    subtitle: fallbackSubtitle,
                    accentColor: coordinator.sneakPeek.accentColor
                )
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

private struct SingleAgentInteractionSneakPeekContent: View {
    @ObservedObject var session: AIAgentSession

    private var interaction: AIAgentInteraction? {
        session.latestPendingInteraction
    }

    private var accentColor: Color {
        interaction?.isApprovalSelection == true ? .orange : session.agentType.accentColor
    }

    private var stateLabel: String {
        interaction?.isApprovalSelection == true ? "待审批" : "待操作"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                AIAgentSneakPeekAgentBadge(agentType: session.agentType, tint: accentColor)

                Text(session.agentType.displayName)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text(stateLabel)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.16))
                    )

                Spacer(minLength: 6)

                Text(session.elapsedTimeString)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Text(interaction?.message ?? session.currentTask)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

private struct MultiAgentInteractionSneakPeekRow: View {
    @ObservedObject var session: AIAgentSession

    private var interaction: AIAgentInteraction? {
        session.latestPendingInteraction
    }

    private var accentColor: Color {
        interaction?.isApprovalSelection == true ? .orange : session.agentType.accentColor
    }

    private var stateLabel: String {
        interaction?.isApprovalSelection == true ? "待审批" : "待操作"
    }

    var body: some View {
        HStack(spacing: 5) {
            AIAgentSneakPeekAgentBadge(agentType: session.agentType, tint: accentColor, size: 10)

            Text(session.agentType.displayName)
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(accentColor)
                .lineLimit(1)

            Text(stateLabel)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let interaction {
                Text(String(interaction.message.prefix(12)))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
    }
}

private struct SingleAgentSneakPeekContent: View {
    @ObservedObject var session: AIAgentSession

    /// Unified progress items: prefer structured subtasks (plan/todo),
    /// fall back to todoItems converted to subtasks.
    private var progressItems: [AIAgentSubtask] {
        session.displaySubtasks
    }

    private var completedCount: Int {
        progressItems.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        progressItems.count
    }

    private var allCompleted: Bool {
        totalCount > 0 && progressItems.allSatisfy { $0.status == .completed }
    }

    private var titleText: String {
        if allCompleted {
            return "所有任务已完成"
        }

        return session.currentTodoDisplayText
        ?? session.currentSubtaskDisplayText
        ?? session.currentTask
    }

    private var countTint: Color {
        allCompleted ? .green : session.agentType.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AIAgentSegmentedProgressBar(
                items: progressItems,
                accentColor: session.agentType.accentColor,
                height: 4,
                spacing: 2,
                cornerRadius: 1.5
            )

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: session.agentType.iconName)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(session.agentType.accentColor)

                Text(titleText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text("\(completedCount)/\(totalCount)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(countTint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

private struct FallbackAIAgentSneakPeekContent: View {
    let title: String?
    let subtitle: String?
    let accentColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle((accentColor ?? .white).opacity(0.92))
                    .lineLimit(1)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

private struct MultiAgentSneakPeekRow: View {
    @ObservedObject var session: AIAgentSession

    private var progressItems: [AIAgentSubtask] {
        session.displaySubtasks
    }

    private var completedCount: Int {
        progressItems.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        progressItems.count
    }

    private var allCompleted: Bool {
        totalCount > 0 && progressItems.allSatisfy { $0.status == .completed }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: session.agentType.iconName)
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(session.agentType.accentColor)
                .frame(width: 8, alignment: .center)

            AIAgentSegmentedProgressBar(
                items: progressItems,
                accentColor: session.agentType.accentColor,
                height: 3,
                spacing: 1.5,
                cornerRadius: 1
            )

            Text("\(completedCount)/\(totalCount)")
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(allCompleted ? Color.green : session.agentType.accentColor)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct AIAgentSneakPeekAgentBadge: View {
    let agentType: AIAgentType
    let tint: Color
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: size, height: size)

            if let image = AIAgentIconResolver.image(for: agentType) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.68, height: size * 0.68)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.24), style: .continuous))
            } else {
                Image(systemName: agentType.iconName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct AIAgentSegmentedProgressBar: View {
    let items: [AIAgentSubtask]
    let accentColor: Color
    let height: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat

    private var allCompleted: Bool {
        !items.isEmpty && items.allSatisfy { $0.status == .completed }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items) { item in
                AIAgentSneakPeekSegment(
                    item: item,
                    accentColor: accentColor,
                    allCompleted: allCompleted,
                    height: height,
                    cornerRadius: cornerRadius
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
    }
}

private struct AIAgentSneakPeekSegment: View {
    let item: AIAgentSubtask
    let accentColor: Color
    let allCompleted: Bool
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(segmentColor)
            .frame(height: height)
            .scaleEffect(x: 1, y: item.status == .inProgress && isPulsing ? 1.3 : 1.0, anchor: .center)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: item.status)
            .task(id: item.status) {
                guard item.status == .inProgress else {
                    isPulsing = false
                    return
                }

                isPulsing = false
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }

    private var segmentColor: Color {
        if allCompleted {
            return .green
        }

        switch item.status {
        case .pending:
            return .white.opacity(0.12)
        case .inProgress:
            return accentColor.opacity(0.7)
        case .completed:
            return accentColor
        case .failed:
            return .red.opacity(0.38)
        case .cancelled:
            return .red.opacity(0.38)
        }
    }
}
