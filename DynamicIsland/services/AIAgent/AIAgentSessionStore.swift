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

@MainActor
final class AIAgentSessionStore {
    private(set) var sessions: [String: AIAgentSession] = [:]
    private var sessionKeysByID: [UUID: String] = [:]

    func session(forKey key: String) -> AIAgentSession? {
        sessions[key]
    }

    func session(forID id: UUID) -> AIAgentSession? {
        guard let key = sessionKeysByID[id] else { return nil }
        return sessions[key]
    }

    func key(forSessionID id: UUID) -> String? {
        sessionKeysByID[id]
    }

    func insert(_ session: AIAgentSession, forKey key: String) {
        sessions[key] = session
        sessionKeysByID[session.id] = key
    }

    @discardableResult
    func removeSession(forKey key: String) -> AIAgentSession? {
        guard let removed = sessions.removeValue(forKey: key) else { return nil }
        sessionKeysByID.removeValue(forKey: removed.id)
        return removed
    }

    @discardableResult
    func archiveSession(id: UUID) -> AIAgentSession? {
        guard let session = session(forID: id) else { return nil }
        session.isArchived = true
        return session
    }

    @discardableResult
    func restoreSession(id: UUID) -> AIAgentSession? {
        guard let session = session(forID: id) else { return nil }
        session.isArchived = false
        return session
    }

    func pruneSessions(
        olderThan threshold: TimeInterval,
        now: Date = .now
    ) -> [String] {
        let staleKeys = sessions.compactMap { entry -> String? in
            let (key, session) = entry
            guard !session.isArchived else { return nil }
            return now.timeIntervalSince(session.lastActivity) > threshold ? key : nil
        }

        staleKeys.forEach { _ = removeSession(forKey: $0) }
        return staleKeys
    }
}
