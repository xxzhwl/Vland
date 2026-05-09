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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    // Context bar (compact)
                    contextBar

                    summarySection

                    if let latestInteraction = session.latestPendingInteraction,
                       session.status == .waitingInput {
                        pendingInputSection(interaction: latestInteraction)
                    }

                    if !session.structuredSubtasks.isEmpty {
                        tasksSection
                    }

                    if !session.subagentToolCalls.isEmpty {
                        subagentsSection
                    }

                    if !session.conversationTurns.isEmpty {
                        conversationSection
                    }

                    metadataSection

                    if !session.eventLog.isEmpty {
                        eventLogSection
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Context Bar

    @ViewBuilder
    private var contextBar: some View {
        if let ratio = session.contextUsageRatio {
            let barColor: Color = ratio >= 0.95 ? .red : ratio >= 0.8 ? .yellow : accentColor
            let pct = Int(ratio * 100)

            HStack(spacing: 6) {
                Image(systemName: "memorychip.fill")
                    .font(.system(size: style.scaled(8)))
                    .foregroundColor(barColor.opacity(0.8))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barColor.opacity(0.8))
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(height: 4)

                Text("CTX \(pct)%")
                    .font(.system(size: style.scaled(8), weight: .medium, design: .monospaced))
                    .foregroundColor(barColor.opacity(0.85))

                if session.compactCount > 0 {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: style.scaled(7)))
                        .foregroundColor(.yellow.opacity(0.7))
                    Text("×\(session.compactCount)")
                        .font(.system(size: style.scaled(8), design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            // Top row: back + agent identity + actions
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

                AgentTypeIconView(agentType: session.agentType, size: style.scaled(16))
                    .frame(width: 20, height: 20)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.agentType.displayName)
                        .font(.system(size: style.scaled(12), weight: .bold))
                        .foregroundColor(accentColor)

                    Text(session.projectName ?? session.project ?? "Unknown Project")
                        .font(.system(size: style.scaled(8.5)))
                        .foregroundColor(.gray.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                statusChip(text: session.status.displayName, tint: session.status.color)
                phaseChip

                Button(action: { agentManager.activateAgentApp(session: session) }) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: style.scaled(11), weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.95))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(accentColor.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help("打开关联的 AI 助手窗口")

                if session.isArchived {
                    Button(action: { agentManager.restoreSession(session) }) {
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
                    Button(action: { agentManager.archiveSession(session) }) {
                        Image(systemName: "archivebox")
                            .font(.system(size: style.scaled(11), weight: .semibold))
                            .foregroundColor(.orange.opacity(0.9))
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

            // Accent strip
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accentColor.opacity(0.25))
                .frame(height: 2)
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "text.alignleft", title: "Summary")

            VStack(alignment: .leading, spacing: 8) {
                if let prompt = session.lastUserPrompt {
                    summaryRow(label: "Prompt", value: prompt, lines: 3)
                }
                summaryRow(label: "Current", value: session.currentTask, lines: 2)
                if let output = session.lastAgentOutput {
                    Divider().background(Color.white.opacity(0.06))
                    summaryRow(label: "Latest Output", value: output, lines: 3)
                }
            }
        }
        .styledSection()
    }

    // MARK: - Pending Input Section

    private func pendingInputSection(interaction: AIAgentInteraction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "hand.raised.fill", title: "Pending Input", tint: .orange)

            InteractionView(
                interaction: interaction,
                accentColor: accentColor,
                session: session,
                prominent: true,
                style: style
            )
        }
        .styledSection()
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "checklist", title: "Task Plan")

            SessionTasksView(
                tasks: session.structuredSubtasks,
                accentColor: accentColor,
                style: style
            )
        }
    }

    // MARK: - Subagents Section

    private var subagentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "square.stack.3d.up.fill", title: "Subagents", tint: .purple)

            SubagentTasksView(
                toolCalls: session.subagentToolCalls,
                accentColor: accentColor,
                style: style
            )
        }
    }

    // MARK: - Conversation Section

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "bubble.left.and.bubble.right.fill", title: "Conversation")

            LazyVStack(alignment: .leading, spacing: 6) {
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

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "info.circle.fill", title: "Metadata")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 6)],
                alignment: .leading,
                spacing: 4
            ) {
                metadataCell(label: "Elapsed", value: session.elapsedTimeString)
                metadataCell(label: "Session ID", value: session.sessionId)
                metadataCell(label: "TTY", value: session.tty)
                metadataCell(label: "PID", value: session.pid.map(String.init))
                metadataCell(label: "Tool Use ID", value: session.toolUseId)
                metadataCell(label: "Agent ID", value: session.agentInstanceId)
                metadataCell(label: "Parent Tool", value: session.parentToolId)
                metadataCell(label: "Transcript", value: session.transcriptPath, mono: true)
                if let reconciledAt = session.lastTranscriptReconciledAt {
                    metadataCell(
                        label: "Reconciled",
                        value: Self.detailTimestampFormatter.string(from: reconciledAt)
                    )
                }
                if let model = session.modelName {
                    metadataCell(label: "Model", value: model)
                }
                if let contextLabel = session.contextUsageLabel {
                    metadataCell(label: "Context", value: contextLabel)
                }
                if session.compactCount > 0 {
                    metadataCell(label: "Compacted", value: "\(session.compactCount) 次")
                }
            }
        }
        .styledSection()
    }

    // MARK: - Event Log Section

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "list.bullet.rectangle", title: "Recent Events")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.eventLog.suffix(12).reversed().enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .top, spacing: 8) {
                        // Timeline
                        VStack(spacing: 0) {
                            Circle()
                                .fill(colorForHookType(entry.hookType))
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)

                            if index < min(session.eventLog.suffix(12).count, 12) - 1 {
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 1, height: nil)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 8)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.timeString)
                                    .font(.system(size: style.scaled(8), design: .monospaced))
                                    .foregroundColor(.gray.opacity(0.4))

                                Circle()
                                    .fill(colorForHookType(entry.hookType).opacity(0.15))
                                    .frame(width: 4, height: 4)

                                Text(entry.hookType)
                                    .font(.system(size: style.scaled(8), weight: .medium))
                                    .foregroundColor(colorForHookType(entry.hookType).opacity(0.7))
                            }

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
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .styledSection()
    }

    // MARK: - Reusable Components

    private func sectionHeader(icon: String, title: String, tint: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: style.scaled(9), weight: .semibold))
                .foregroundColor((tint ?? .gray).opacity(0.7))

            Text(title)
                .font(.system(size: style.scaled(9), weight: .semibold))
                .foregroundColor(.gray.opacity(0.68))
        }
    }

    private func summaryRow(label: String, value: String, lines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: style.scaled(8), weight: .medium))
                .foregroundColor(.gray.opacity(0.55))

            Text(value)
                .font(.system(size: style.scaled(9.5)))
                .foregroundColor(.white.opacity(0.84))
                .lineLimit(lines)
                .textSelection(.enabled)
        }
    }

    private func metadataCell(label: String, value: String?, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: style.scaled(7.5), weight: .medium))
                .foregroundColor(.gray.opacity(0.5))

            Text(value ?? "-")
                .font(.system(size: style.scaled(8.5), design: mono ? .monospaced : .default))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var phaseChip: some View {
        let tint: Color = session.phase.isAttentionBlocking ? .orange : .gray
        return Text(session.phase.rawValue)
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

    private var accentColor: Color {
        style.accentColor(for: session.agentType)
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

// MARK: - Section Style Modifier

private struct StyledSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}

private extension View {
    func styledSection() -> some View {
        modifier(StyledSectionModifier())
    }
}
