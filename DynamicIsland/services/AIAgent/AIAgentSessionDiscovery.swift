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

import Darwin
import Foundation

/// Discovers running AI agent sessions after Vland restarts.
///
/// Vland's session store is in-memory only — when the app restarts,
/// all session state is lost. This discovery mechanism scans running
/// processes and their transcript files to find sessions that were
/// active before the restart, so they reappear in the AI Agent panel.
struct AIAgentSessionDiscovery {

    struct DiscoveredSession {
        let agentType: AIAgentType
        let sessionId: String?
        let project: String?
        let transcriptPath: String?
        let pid: Int32?
    }

    // MARK: - Public API

    /// Discover running agent sessions by scanning processes and transcript files.
    /// Returns sessions that appear to be currently active.
    static func discoverRunningSessions() -> [DiscoveredSession] {
        let allPIDs = allProcessPIDs()

        let claudePIDs = allPIDs.filter { isProcess(pid: $0, names: ["claude", "claude-code"]) }

        var results: [DiscoveredSession] = []

        if !claudePIDs.isEmpty {
            results.append(contentsOf: discoverClaudeSessions(pids: claudePIDs))
        }

        return results
    }

    // MARK: - Process Detection

    private static func allProcessPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count))
        let written = proc_listallpids(&pids, Int32(MemoryLayout<Int32>.size * pids.count))
        guard written > 0 else { return [] }
        return pids.prefix(Int(written)).filter { $0 > 0 }
    }

    private static func isProcess(pid: Int32, names: [String]) -> Bool {
        // Check executable path first (most reliable)
        if let path = executablePath(pid: pid) {
            let name = (path as NSString).lastPathComponent.lowercased()
            if names.contains(name) { return true }
        }
        // Fallback: check BSD process name (max 16 chars, truncated)
        if let name = processName(pid: pid) {
            if names.contains(name.lowercased()) { return true }
        }
        return false
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_SIZE
        let size = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard size > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Get BSD process name (truncated to 16 chars).
    /// This is the `pbi_name` field from `proc_bsdinfo`.
    private static func processName(pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size >= MemoryLayout<proc_bsdinfo>.size else { return nil }

        let name = withUnsafePointer(to: info.pbi_name) { rawPtr in
            rawPtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.pbi_name)) { charPtr in
                String(cString: charPtr)
            }
        }
        return name.isEmpty ? nil : name
    }

    // MARK: - Claude Code Session Discovery

    private static func discoverClaudeSessions(pids: [Int32]) -> [DiscoveredSession] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeProjectsDir = home.appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: claudeProjectsDir.path) else { return [] }

        let recentFiles = findRecentTranscriptFiles(in: claudeProjectsDir)

        return recentFiles.map { file in
            let project = extractProjectFromTranscript(path: file.path)

            return DiscoveredSession(
                agentType: .claudeCode,
                sessionId: file.sessionId,
                project: project,
                transcriptPath: file.path,
                pid: pids.first
            )
        }
    }

    /// Find `.jsonl` files modified within the last hour under the given directory.
    private static func findRecentTranscriptFiles(in directory: URL) -> [(path: String, modDate: Date, sessionId: String)] {
        let fm = FileManager.default
        var results: [(String, Date, String)] = []
        let cutoff = Date().addingTimeInterval(-3600)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate,
                  modDate > cutoff else { continue }

            let sessionId = fileURL.deletingPathExtension().lastPathComponent
            results.append((fileURL.path, modDate, sessionId))
        }

        results.sort { $0.1 > $1.1 }
        return results
    }

    /// Try to read the project path from the JSONL transcript file.
    /// The `project` field is present in hook events written to the transcript.
    private static func extractProjectFromTranscript(path: String) -> String? {
        guard let fileHandle = FileHandle(forReadingAtPath: path),
              let chunk = try? fileHandle.read(upToCount: 20000) else { return nil }
        try? fileHandle.close()

        let content = String(data: chunk, encoding: String.Encoding.utf8) ?? ""
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: String.Encoding.utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let project = json["project"] as? String, project != "/" {
                return project
            }
            if let payload = json["payload"] as? [String: Any],
               let project = payload["project"] as? String, project != "/" {
                return project
            }
        }

        return nil
    }
}
