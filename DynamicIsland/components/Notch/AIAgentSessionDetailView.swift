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

struct AIAgentSessionDetailView: View {
    @ObservedObject var session: AIAgentSession
    let style: AIAgentCardStyle
    @ObservedObject private var agentManager = AIAgentManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    summarySection
                    metadataSection

                    if let latestInteraction = session.latestPendingInteraction,
                       session.status == .waitingInput {
                        detailSection(title: "Pending Input") {
                            InteractionView(
                                interaction: latestInteraction,
                                accentColor: style.accentColor(for: session.agentType),
                                session: session,
                                prominent: true,
                                style: style
                            )
                        }
                    }

                    if !session.structuredSubtasks.isEmpty {
                        detailSection(title: "Task Plan") {
                            SessionTasksView(
                                tasks: session.structuredSubtasks,
                                accentColor: style.accentColor(for: session.agentType),
                                style: style
                            )
                        }
                    }

                    if !session.subagentToolCalls.isEmpty {
                        detailSection(title: "Subagents") {
                            SubagentTasksView(
                                toolCalls: session.subagentToolCalls,
                                accentColor: style.accentColor(for: session.agentType),
                                style: style
                            )
                        }
                    }

                    if !session.conversationTurns.isEmpty {
                        detailSection(title: "Conversation") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(session.conversationTurns) { turn in
                                    TurnView(
                                        turn: turn,
                                        session: session,
                                        hiddenInteractionID: session.latestPendingInteraction?.id,
                                        style: style
                                    )
                                }
                            }
                        }
                    }

                    if !session.eventLog.isEmpty {
                        detailSection(title: "Recent Events") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(session.eventLog.suffix(12).reversed()) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(entry.timeString)
                                            .font(.system(size: style.scaled(8), design: .monospaced))
                                            .foregroundColor(.gray.opacity(0.45))
                                            .frame(width: 44, alignment: .leading)

                                        Circle()
                                            .fill(colorForHookType(entry.hookType))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 4)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.description)
                                                .font(.system(size: style.scaled(9.5)))
                                                .foregroundColor(.white.opacity(0.82))
                                                .lineLimit(2)

                                            if let detail = entry.detail, !detail.isEmpty {
                                                Text(detail)
                                                    .font(.system(size: style.scaled(8.5)))
                                                    .foregroundColor(.gray.opacity(0.55))
                                                    .lineLimit(2)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { agentManager.dismissSessionDetail() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: style.scaled(10), weight: .semibold))
                    Text("Back")
                        .font(.system(size: style.scaled(10), weight: .medium))
                }
                .foregroundColor(.white.opacity(0.82))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.agentType.displayName)
                    .font(.system(size: style.scaled(12), weight: .bold))
                    .foregroundColor(style.accentColor(for: session.agentType))

                Text(session.projectName ?? session.project ?? "Unknown Project")
                    .font(.system(size: style.scaled(8.5)))
                    .foregroundColor(.gray.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            detailChip(text: session.status.displayName, tint: session.status.color)
            detailChip(text: session.phase.rawValue, tint: session.phase.isAttentionBlocking ? .orange : .gray)

            Button(action: { agentManager.activateAgentApp(session: session) }) {
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

            if session.isArchived {
                Button(action: { agentManager.restoreSession(session) }) {
                    actionBadge(symbol: "arrow.uturn.backward.circle", tint: .green)
                }
                .buttonStyle(.plain)
                .help("恢复会话")
            } else if session.canArchiveManually {
                Button(action: { agentManager.archiveSession(session) }) {
                    actionBadge(symbol: "archivebox", tint: .orange)
                }
                .buttonStyle(.plain)
                .help("归档会话")
            }
        }
    }

    private var summarySection: some View {
        detailSection(title: "Summary") {
            VStack(alignment: .leading, spacing: 6) {
                if let prompt = session.lastUserPrompt {
                    labeledText(label: "Prompt", value: prompt)
                }

                labeledText(label: "Current", value: session.currentTask)

                if let output = session.lastAgentOutput {
                    labeledText(label: "Latest Output", value: output)
                }
            }
        }
    }

    private var metadataSection: some View {
        detailSection(title: "Metadata") {
            VStack(alignment: .leading, spacing: 6) {
                detailMetadataRow(label: "Elapsed", value: session.elapsedTimeString)
                detailMetadataRow(label: "Session ID", value: session.sessionId)
                detailMetadataRow(label: "TTY", value: session.tty)
                detailMetadataRow(label: "PID", value: session.pid.map(String.init))
                detailMetadataRow(label: "Tool Use ID", value: session.toolUseId)
                detailMetadataRow(label: "Agent ID", value: session.agentInstanceId)
                detailMetadataRow(label: "Parent Tool", value: session.parentToolId)
                detailMetadataRow(label: "Transcript", value: session.transcriptPath)
                detailMetadataRow(
                    label: "Reconciled",
                    value: session.lastTranscriptReconciledAt.map(Self.detailTimestampFormatter.string(from:))
                )
                // Context tracking
                if session.modelName != nil || session.contextUsageLabel != nil {
                    Divider().background(Color.white.opacity(0.08))
                }
                detailMetadataRow(label: "Model", value: session.modelName)
                if let contextLabel = session.contextUsageLabel {
                    detailMetadataRow(label: "Context", value: contextLabel)
                }
                if session.compactCount > 0 {
                    detailMetadataRow(label: "Compacted", value: "\(session.compactCount) 次")
                }
            }
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: style.scaled(9), weight: .semibold))
                .foregroundColor(.gray.opacity(0.68))

            content()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func labeledText(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: style.scaled(8), weight: .medium))
                .foregroundColor(.gray.opacity(0.55))

            Text(value)
                .font(.system(size: style.scaled(9.5)))
                .foregroundColor(.white.opacity(0.84))
                .textSelection(.enabled)
        }
    }

    private func detailMetadataRow(label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: style.scaled(8.5), weight: .medium))
                .foregroundColor(.gray.opacity(0.58))
                .frame(width: 70, alignment: .leading)

            Text(value ?? "-")
                .font(.system(size: style.scaled(8.8), design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }

    private func detailChip(text: String, tint: Color) -> some View {
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

    private func actionBadge(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: style.scaled(11), weight: .semibold))
            .foregroundColor(tint.opacity(0.9))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
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

    private static let detailTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
