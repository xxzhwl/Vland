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

struct AIAgentReductionResult {
    let sessionKey: String
    let session: AIAgentSession
    let wasCreated: Bool
    let hadVisibleTasks: Bool
    let shouldScheduleEndedRemoval: Bool
}

@MainActor
final class AIAgentEventReducer {
    func reduce(
        _ event: AIAgentHookEvent,
        in store: AIAgentSessionStore
    ) -> AIAgentReductionResult {
        let sessionKey = sessionKey(for: event)

        if let existingSession = store.session(forKey: sessionKey) {
            let hadVisibleTasks = sessionHasVisibleTaskState(existingSession)
            if existingSession.isArchived {
                existingSession.isArchived = false
            }
            existingSession.applyEvent(event)
            return AIAgentReductionResult(
                sessionKey: sessionKey,
                session: existingSession,
                wasCreated: false,
                hadVisibleTasks: hadVisibleTasks,
                shouldScheduleEndedRemoval: shouldScheduleEndedRemoval(for: event)
            )
        }

        let projectPath: String? = {
            if let project = event.project, project != "/" {
                return project
            }
            return nil
        }()

        let agentType = AIAgentType(rawValue: event.source) ?? .codebuddy
        let session = AIAgentSession(
            agentType: agentType,
            project: projectPath,
            sessionId: event.sessionId
        )
        session.applyEvent(event)
        store.insert(session, forKey: sessionKey)

        return AIAgentReductionResult(
            sessionKey: sessionKey,
            session: session,
            wasCreated: true,
            hadVisibleTasks: false,
            shouldScheduleEndedRemoval: shouldScheduleEndedRemoval(for: event)
        )
    }

    func sessionKey(for event: AIAgentHookEvent) -> String {
        if let sessionID = normalizedText(event.sessionId) {
            return event.source + "-" + sessionID
        }
        if let transcriptPath = normalizedText(event.transcriptPath) {
            return event.source + "-transcript-" + transcriptPath
        }
        if let tty = normalizedText(event.tty) {
            return event.source + "-tty-" + tty
        }
        if let pid = event.pid {
            return event.source + "-pid-" + String(pid)
        }
        return event.source + "-" + (normalizedText(event.project) ?? "default")
    }

    private func shouldScheduleEndedRemoval(for event: AIAgentHookEvent) -> Bool {
        event.hookType == "SessionEnd" || event.hookType == "Stop"
    }

    private func sessionHasVisibleTaskState(_ session: AIAgentSession) -> Bool {
        !session.todoItems.isEmpty || !session.displaySubtasks.isEmpty
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
