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
import Darwin

final class AIAgentTranscriptWatcher {
    typealias SnapshotHandler = @MainActor (_ sessionKey: String, _ snapshot: AIAgentTranscriptSnapshot) -> Void

    var onSnapshot: SnapshotHandler?

    private struct WatchState {
        let path: String
        let source: AIAgentType
        let dispatchSource: DispatchSourceFileSystemObject
        var lastFingerprint: String?
    }

    private let queue = DispatchQueue(label: "com.vland.aiagent.transcript", qos: .utility)
    private let reconciler: AIAgentTranscriptReconciler
    private var watches: [String: WatchState] = [:]

    init(reconciler: AIAgentTranscriptReconciler) {
        self.reconciler = reconciler
    }

    func watch(sessionKey: String, session: AIAgentSession) {
        guard let rawPath = session.transcriptPath, !rawPath.isEmpty else {
            unwatch(sessionKey: sessionKey)
            return
        }

        let normalizedPath = URL(fileURLWithPath: rawPath).standardized.path
        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            unwatch(sessionKey: sessionKey)
            return
        }

        if let existing = watches[sessionKey],
           existing.path == normalizedPath,
           existing.source == session.agentType {
            scheduleReconcile(sessionKey: sessionKey)
            return
        }

        unwatch(sessionKey: sessionKey)

        let fileDescriptor = open(normalizedPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReconcile(sessionKey: sessionKey)
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        watches[sessionKey] = WatchState(
            path: normalizedPath,
            source: session.agentType,
            dispatchSource: source,
            lastFingerprint: nil
        )

        source.resume()
        scheduleReconcile(sessionKey: sessionKey)
    }

    func unwatch(sessionKey: String) {
        guard let state = watches.removeValue(forKey: sessionKey) else { return }
        state.dispatchSource.cancel()
    }

    func stopAll() {
        let keys = Array(watches.keys)
        keys.forEach(unwatch(sessionKey:))
    }

    private func scheduleReconcile(sessionKey: String) {
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.reconcile(sessionKey: sessionKey)
        }
    }

    private func reconcile(sessionKey: String) {
        guard var state = watches[sessionKey] else { return }
        guard let snapshot = reconciler.reconcile(source: state.source, transcriptPath: state.path) else {
            return
        }

        guard snapshot.fingerprint != state.lastFingerprint else { return }
        state.lastFingerprint = snapshot.fingerprint
        watches[sessionKey] = state

        Task { @MainActor [weak self] in
            self?.onSnapshot?(sessionKey, snapshot)
        }
    }
}
