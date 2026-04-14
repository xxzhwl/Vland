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

import AppKit
import Defaults
import SwiftUI

// MARK: - AI Agent Notification Coordinator

/// Manages UI notifications (Sneak Peek) and sound effects for AI agent events.
/// Coordinates with DynamicIslandViewCoordinator for UI presentation.
@MainActor
final class AIAgentNotificationCoordinator {
    // MARK: - Dependencies

    private let appActivator: AIAgentAppActivator

    // MARK: - Notification Context

    private enum NotificationContext {
        case sessionStart
        case promptSubmitted
        case taskProgress
        case waitingInput
        case interactionTimeout
        case lifecycleSound
    }

    // MARK: - Initialization

    init(appActivator: AIAgentAppActivator) {
        self.appActivator = appActivator
    }

    // MARK: - Session Start Notification

    func notifySessionStart(session: AIAgentSession, event: AIAgentHookEvent) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: .sessionStart) else { return }

        let agentType = session.agentType

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .aiAgent,
            duration: 3.0,
            icon: agentType.iconName,
            title: agentType.displayName,
            subtitle: "会话已启动",
            accentColor: agentType.accentColor
        )
        markNotificationEmitted(for: session)
    }

    // MARK: - Task Progress Notification

    func notifyTaskProgress(session: AIAgentSession) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: .taskProgress),
              !session.todoItems.isEmpty || !session.displaySubtasks.isEmpty else { return }

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .aiAgent,
            duration: 30.0,
            icon: session.agentType.iconName,
            title: session.agentType.displayName,
            subtitle: session.currentTodoDisplayText
                ?? session.currentSubtaskDisplayText
                ?? "正在执行任务...",
            accentColor: session.agentType.accentColor,
            styleOverride: .standard
        )
        markNotificationEmitted(for: session)
    }

    // MARK: - Waiting Input Notification

    func notifyWaitingInput(session: AIAgentSession, interaction: AIAgentInteraction, isBridge: Bool) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: .waitingInput) else { return }

        let isApprovalRequest = interaction.isApprovalSelection

        if isApprovalRequest || session.todoItems.isEmpty {
            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .aiAgent,
                duration: isBridge ? 4.5 : 4.0,
                icon: isBridge ? "exclamationmark.triangle.fill" : session.agentType.iconName,
                title: isApprovalRequest ? "需要审批" : "\(session.agentType.displayName) 需要输入",
                subtitle: String(interaction.message.prefix(50)),
                accentColor: isApprovalRequest ? .orange : session.agentType.accentColor
            )
        } else {
            notifyTaskProgress(session: session)
        }

        // Also show an expanding preview below the closed notch
        DynamicIslandViewCoordinator.shared.toggleExpandingView(
            status: true,
            type: .aiAgent
        )
        markNotificationEmitted(for: session)
    }

    // MARK: - Interaction Result Notification

    func notifyInteractionResult(
        session: AIAgentSession,
        interaction: AIAgentInteraction,
        result: InteractionResponseResult,
        option: String
    ) {
        let title: String
        let subtitle: String
        let accentColor: Color

        switch result {
        case .submitted:
            if interaction.responseMode == .approvalSelection {
                title = option.caseInsensitiveCompare("Allow") == .orderedSame ? "已批准" : "已阻止"
                subtitle = String(interaction.message.prefix(50))
                accentColor = option.caseInsensitiveCompare("Allow") == .orderedSame ? .green : .red
            } else {
                title = "已发送回复"
                subtitle = String(option.prefix(50))
                accentColor = session.agentType.accentColor
            }
            AIAgentSoundEffectManager.shared.play(.replySent)

        case .copiedForManualSend:
            title = interaction.responseMode == .approvalSelection ? "打开审批提示" : "已复制回复"
            subtitle = interaction.responseMode == .approvalSelection
                ? "选择: \(String(option.prefix(40)))"
                : String(option.prefix(50))
            accentColor = .orange
            AIAgentSoundEffectManager.shared.play(.replyCopied)

        case .requiresAccessibility:
            title = "需要辅助功能权限"
            subtitle = interaction.responseMode == .approvalSelection
                ? "启用后可一键审批"
                : "回复已复制，需手动提交"
            accentColor = .orange
            AIAgentSoundEffectManager.shared.play(.replyCopied)

        case .failed(let message):
            title = interaction.responseMode == .approvalSelection ? "审批失败" : "回复失败"
            subtitle = String(message.prefix(50))
            accentColor = .red
            AIAgentSoundEffectManager.shared.play(.error)
        }

        if session.todoItems.isEmpty {
            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .aiAgent,
                duration: 3.0,
                icon: session.agentType.iconName,
                title: title,
                subtitle: subtitle,
                accentColor: accentColor
            )
        } else {
            notifyTaskProgress(session: session)
        }
    }

    // MARK: - Interaction Timeout Notification

    func notifyInteractionTimeout(session: AIAgentSession, message: String) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: .interactionTimeout) else { return }

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .aiAgent,
            duration: 4.0,
            icon: "exclamationmark.triangle.fill",
            title: "交互超时",
            subtitle: String(message.prefix(50)),
            accentColor: .red
        )
        markNotificationEmitted(for: session)
    }

    // MARK: - Dismiss Sneak Peek

    func dismissAgentSneakPeek() {
        DynamicIslandViewCoordinator.shared.toggleSneakPeek(status: false, type: .aiAgent)
    }

    // MARK: - Sound Effects

    func playSoundIfNeeded(for event: AIAgentHookEvent, session: AIAgentSession) {
        guard shouldNotify(for: session, context: .lifecycleSound) else { return }

        switch event.hookType {
        case "SessionStart":
            AIAgentSoundEffectManager.shared.play(.sessionStart)
        case "UserPromptSubmit":
            AIAgentSoundEffectManager.shared.play(.promptSubmitted)
        case "Stop", "SubagentStop":
            AIAgentSoundEffectManager.shared.play(.completed)
        default:
            break
        }
    }

    // MARK: - Prompt Submit Notification

    func notifyPromptSubmit(session: AIAgentSession, event: AIAgentHookEvent) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: .promptSubmitted) else { return }

        let agentType = session.agentType

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .aiAgent,
            duration: 3.0,
            icon: agentType.iconName,
            title: agentType.displayName,
            subtitle: event.message.map { String($0.prefix(50)) } ?? "新任务",
            accentColor: agentType.accentColor
        )
        markNotificationEmitted(for: session)
    }

    // MARK: - Session End Handler

    func notifySessionEnd() {
        dismissAgentSneakPeek()
    }

    // MARK: - Private Helpers

    private func shouldNotify(for session: AIAgentSession, context: NotificationContext) -> Bool {
        !appActivator.isUserLikelyViewingSession(session)
    }

    private func markNotificationEmitted(for session: AIAgentSession, at date: Date = .now) {
        session.lastNotificationAt = date
    }
}