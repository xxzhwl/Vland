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

import Combine
import Defaults
import Foundation

// MARK: - AI Agent Hook Configurator

/// Manages detection, installation, and configuration of AI agent bridge hooks.
/// This service is independent from the core event handling pipeline — it's only
/// invoked by the Settings UI.
@MainActor
final class AIAgentHookConfigurator: ObservableObject {
    struct BridgeVersionStatus: Equatable {
        let installedVersion: String?
        let bundledVersion: String?

        var isInstalled: Bool { installedVersion != nil }
        var isOutdated: Bool {
            guard let installedVersion, let bundledVersion else { return false }
            let a = installedVersion.filter(\.isWholeNumber)
            let b = bundledVersion.filter(\.isWholeNumber)
            if let aNum = Int(a), let bNum = Int(b) {
                return aNum < bNum
            }
            return installedVersion != bundledVersion
        }
    }

    /// Represents a detected AI agent tool installation
    struct DetectedAgent: Identifiable {
        let id: String
        let displayName: String
        let settingsPath: String
        let configDirExists: Bool
        let settingsFileExists: Bool
        var hookStatus: HookStatus

        enum HookStatus: Equatable {
            case notConfigured
            case configuredVland
            case configuredOther(String)
        }
    }

    /// Config file format used by the agent.
    /// Agents like CodeBuddy/Claude Code use JSON; Hermes uses YAML.
    enum SettingsFormat {
        case json
        case yaml
    }

    /// Published detection results for the Settings UI
    @Published var detectedAgents: [DetectedAgent] = []
    @Published var bridgeInstalled: Bool = false
    @Published var bridgeVersionStatus = BridgeVersionStatus(installedVersion: nil, bundledVersion: nil)
    @Published var configurationLog: [String] = []
    @Published var claudeQuotaHookStatus = ClaudeQuotaHookStatus()

    /// The bridge script path that Vland uses
    static let bridgePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".vland/bin/vland-bridge")
    }()

    /// Source bridge script bundled in app resources
    static var bundledBridgePath: String? {
        if let path = Bundle.main.path(forResource: "vland-bridge", ofType: nil, inDirectory: "bridge") {
            return path
        }
        return Bundle.main.path(forResource: "vland-bridge", ofType: nil)
    }

    struct ClaudeQuotaHookStatus: Equatable {
        var isInstalled = false
        var usageFilePath: String?
        var wrapperPath: String?
        var lastUpdatedAt: Date?
        var preservedCommand: String?
    }

    private struct HookTypeSpec {
        let name: String
        let matcher: String?
        let timeoutSeconds: Int?
    }

    private struct AgentDefinition {
        let id: String
        let name: String
        let configDir: String
        let settingsFile: String
        let hookTypes: [HookTypeSpec]
        let requiresCodexHookFlag: Bool
        let settingsFormat: SettingsFormat
    }

    private static let defaultHookTypes: [HookTypeSpec] = [
        HookTypeSpec(name: "PreToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PostToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "SessionStart", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SessionEnd", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "UserPromptSubmit", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Stop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SubagentStop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Notification", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PreCompact", matcher: nil, timeoutSeconds: nil),
    ]

    private static let codebuddyHookTypes: [HookTypeSpec] = [
        HookTypeSpec(name: "PreToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PostToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "SessionStart", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SessionEnd", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "UserPromptSubmit", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Stop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SubagentStop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Notification", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PreCompact", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "PermissionRequest", matcher: "*", timeoutSeconds: 86_400),
        HookTypeSpec(name: "SubagentStart", matcher: nil, timeoutSeconds: nil),
    ]

    private static let claudeHookTypes: [HookTypeSpec] = [
        HookTypeSpec(name: "PreToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PermissionRequest", matcher: "*", timeoutSeconds: 86_400),
        HookTypeSpec(name: "PostToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "SessionStart", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SessionEnd", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "UserPromptSubmit", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Stop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SubagentStart", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "SubagentStop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Notification", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PreCompact", matcher: nil, timeoutSeconds: nil),
    ]

    private static let codexHookTypes: [HookTypeSpec] = [
        HookTypeSpec(name: "PreToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PostToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "SessionStart", matcher: "startup|resume", timeoutSeconds: nil),
        HookTypeSpec(name: "UserPromptSubmit", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Stop", matcher: nil, timeoutSeconds: nil),
    ]

    // Hermes uses snake_case event names in its YAML config file.
    // Normalization to CamelCase happens in the bridge script (--source hermes).
    private static let hermesHookTypes: [HookTypeSpec] = [
        HookTypeSpec(name: "on_session_start", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "on_session_end", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "pre_tool_call", matcher: "*", timeoutSeconds: 86_400),
        HookTypeSpec(name: "post_tool_call", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "pre_approval_request", matcher: "*", timeoutSeconds: 86_400),
        HookTypeSpec(name: "post_approval_response", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "subagent_stop", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "on_notification", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "on_user_prompt_submit", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "pre_llm_call", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "post_llm_call", matcher: nil, timeoutSeconds: nil),
    ]

    private static let agentTemplates: [(id: String, name: String, defaultConfigDir: String, settingsFileName: String, hookTypes: [HookTypeSpec], requiresCodexHookFlag: Bool, settingsFormat: SettingsFormat)] = [
        ("codebuddy", "CodeBuddy", ".codebuddy", "settings.json", codebuddyHookTypes, false, .json),
        ("codex", "Codex CLI", ".codex", "hooks.json", codexHookTypes, true, .json),
        ("claude-code", "Claude Code", ".claude", "settings.json", claudeHookTypes, false, .json),
        ("workbuddy", "WorkBuddy", ".workbuddy", "settings.json", codebuddyHookTypes, false, .json),
        ("hermes", "Hermes", ".hermes", "config.yaml", hermesHookTypes, false, .yaml),
    ]

    private static func resolvedAgents() -> [AgentDefinition] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let customDirs = Defaults[.aiAgentCustomConfigDirs]

        return agentTemplates.map { t in
            let configDir: String
            if let custom = customDirs[t.id], !custom.isEmpty {
                configDir = (custom as NSString).expandingTildeInPath
            } else {
                configDir = (home as NSString).appendingPathComponent(t.defaultConfigDir)
            }
            let settingsFile = (configDir as NSString).appendingPathComponent(t.settingsFileName)
            return AgentDefinition(
                id: t.id,
                name: t.name,
                configDir: configDir,
                settingsFile: settingsFile,
                hookTypes: t.hookTypes,
                requiresCodexHookFlag: t.requiresCodexHookFlag,
                settingsFormat: t.settingsFormat
            )
        }
    }

    private static var knownAgents: [AgentDefinition] {
        resolvedAgents()
    }

    private static let codexConfigPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".codex/config.toml")
    }()

    private static let claudeSettingsPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".claude/settings.json")
    }()

    private static let claudeQuotaDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".vland/quota")
    }()

    private static let claudeQuotaWrapperName = "claude-status-wrapper.sh"
    private static let claudeQuotaCollectorName = "claude-status-collector.py"
    private static let claudeQuotaUsageFileName = "claude-usage.json"
    private static let claudeQuotaPreservedCommandName = "claude-status-preserved-cmd.txt"

    private static var claudeQuotaWrapperPath: String {
        (claudeQuotaDir as NSString).appendingPathComponent(claudeQuotaWrapperName)
    }

    private static var claudeQuotaCollectorPath: String {
        (claudeQuotaDir as NSString).appendingPathComponent(claudeQuotaCollectorName)
    }

    private static var claudeQuotaUsagePath: String {
        (claudeQuotaDir as NSString).appendingPathComponent(claudeQuotaUsageFileName)
    }

    private static var claudeQuotaPreservedCommandPath: String {
        (claudeQuotaDir as NSString).appendingPathComponent(claudeQuotaPreservedCommandName)
    }

    private static func bundledClaudeQuotaResource(named name: String) -> String? {
        if let path = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "quota") {
            return path
        }
        return Bundle.main.path(forResource: name, ofType: nil)
    }

    private static let bridgeVersionPattern = #"VLAND_BRIDGE_VERSION\s*=\s*"([^"]+)""#

    // MARK: - Detection

    func detectInstalledAgents() {
        let fm = FileManager.default
        bridgeInstalled = fm.fileExists(atPath: Self.bridgePath)
        bridgeVersionStatus = BridgeVersionStatus(
            installedVersion: Self.bridgeVersion(at: Self.bridgePath),
            bundledVersion: Self.bundledBridgePath.flatMap { Self.bridgeVersion(at: $0) }
        )

        var agents: [DetectedAgent] = []

        for agent in Self.resolvedAgents() {
            let configExists = fm.fileExists(atPath: agent.configDir)
            let settingsExists = fm.fileExists(atPath: agent.settingsFile)

            var hookStatus: DetectedAgent.HookStatus = .notConfigured

            if settingsExists {
                if agent.settingsFormat == .yaml {
                    guard let raw = try? String(contentsOfFile: agent.settingsFile, encoding: .utf8) else {
                        continue
                    }

                    let hasVlandMarkers = raw.contains(Self.hermesMarkerBegin) && raw.contains(Self.hermesMarkerEnd)
                    let hasVlandCommand = raw.contains(Self.bridgePath) || raw.contains("vland-bridge")

                    if hasVlandMarkers && hasVlandCommand {
                        hookStatus = .configuredVland
                    } else if raw.contains("vibe-island-bridge") {
                        hookStatus = .configuredOther("vibe-island-bridge")
                    } else if raw.contains("agent-island-bridge") {
                        hookStatus = .configuredOther("agent-island-bridge")
                    } else if raw.contains("hook") && (raw.contains("command") || raw.contains(" type:")) {
                        hookStatus = .configuredOther("hermes-custom")
                    } else {
                        hookStatus = .notConfigured
                    }
                } else {
                    if let data = fm.contents(atPath: agent.settingsFile),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let hooks = json["hooks"] as? [String: Any]
                    {
                        let jsonStr = String(data: data, encoding: .utf8) ?? ""
                        let expectedHookNames = Set(agent.hookTypes.map(\.name))
                        let configuredVlandHooks = configuredHookNames(in: hooks) { command in
                            command.contains(Self.bridgePath) || command.contains("vland-bridge")
                        }

                        if expectedHookNames.isSubset(of: configuredVlandHooks) {
                            hookStatus = .configuredVland
                        } else if jsonStr.contains("vibe-island-bridge") {
                            hookStatus = .configuredOther("vibe-island-bridge")
                        } else if jsonStr.contains("agent-island-bridge") {
                            hookStatus = .configuredOther("agent-island-bridge")
                        } else if !hooks.isEmpty {
                            hookStatus = .notConfigured
                        }
                    }
                }
            }

            agents.append(DetectedAgent(
                id: agent.id,
                displayName: agent.name,
                settingsPath: agent.settingsFile,
                configDirExists: configExists,
                settingsFileExists: settingsExists,
                hookStatus: hookStatus
            ))
        }

        detectedAgents = agents
        detectClaudeQuotaHookStatus()
    }

    func detectClaudeQuotaHookStatus() {
        let fm = FileManager.default
        let settingsPath = Self.claudeSettingsPath
        let wrapperPath = Self.claudeQuotaWrapperPath
        let usagePath = Self.claudeQuotaUsagePath
        let preservedPath = Self.claudeQuotaPreservedCommandPath

        var currentStatus = ClaudeQuotaHookStatus()
        currentStatus.wrapperPath = wrapperPath
        currentStatus.usageFilePath = usagePath

        if fm.fileExists(atPath: usagePath),
           let attrs = try? fm.attributesOfItem(atPath: usagePath),
           let date = attrs[.modificationDate] as? Date {
            currentStatus.lastUpdatedAt = date
        }

        if fm.fileExists(atPath: preservedPath),
           let preserved = try? String(contentsOfFile: preservedPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !preserved.isEmpty {
            currentStatus.preservedCommand = preserved
        }

        if fm.fileExists(atPath: settingsPath),
           let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let statusLine = json["statusLine"] as? [String: Any],
           let command = statusLine["command"] as? String {
            currentStatus.isInstalled = command.contains(wrapperPath)
        } else {
            currentStatus.isInstalled = fm.fileExists(atPath: wrapperPath)
        }

        claudeQuotaHookStatus = currentStatus
    }

    // MARK: - Bridge Installation

    func installBridgeScript() -> Bool {
        let fm = FileManager.default
        let bridgeDir = (Self.bridgePath as NSString).deletingLastPathComponent
        let previousVersion = Self.bridgeVersion(at: Self.bridgePath)
        let bundledVersion = Self.bundledBridgePath.flatMap { Self.bridgeVersion(at: $0) }

        do {
            try fm.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)

            if let bundled = Self.bundledBridgePath {
                if fm.fileExists(atPath: Self.bridgePath) {
                    try fm.removeItem(atPath: Self.bridgePath)
                }
                try fm.copyItem(atPath: bundled, toPath: Self.bridgePath)
            } else {
                guard fm.fileExists(atPath: Self.bridgePath) else {
                    configurationLog.append("❌ Bridge script not found in app bundle")
                    return false
                }
            }

            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.bridgePath)

            bridgeInstalled = true
            bridgeVersionStatus = BridgeVersionStatus(
                installedVersion: Self.bridgeVersion(at: Self.bridgePath),
                bundledVersion: bundledVersion
            )

            if let previousVersion, let installedVersion = bridgeVersionStatus.installedVersion {
                configurationLog.append("✅ Bridge script updated: \(previousVersion) -> \(installedVersion)")
            } else if let installedVersion = bridgeVersionStatus.installedVersion {
                configurationLog.append("✅ Bridge script installed at \(Self.bridgePath) (v\(installedVersion))")
            } else {
                configurationLog.append("✅ Bridge script installed at \(Self.bridgePath)")
            }
            return true
        } catch {
            configurationLog.append("❌ Failed to install bridge: \(error.localizedDescription)")
            return false
        }
    }

    func installClaudeQuotaHook() -> Bool {
        let fm = FileManager.default
        configurationLog.append("🔧 Configuring Claude Code quota hook...")

        do {
            try fm.createDirectory(atPath: Self.claudeQuotaDir, withIntermediateDirectories: true)

            guard let bundledWrapper = Self.bundledClaudeQuotaResource(named: Self.claudeQuotaWrapperName),
                  let bundledCollector = Self.bundledClaudeQuotaResource(named: Self.claudeQuotaCollectorName) else {
                configurationLog.append("  ❌ Bundled quota scripts not found")
                return false
            }

            try installQuotaResource(from: bundledWrapper, to: Self.claudeQuotaWrapperPath)
            try installQuotaResource(from: bundledCollector, to: Self.claudeQuotaCollectorPath)

            let settingsURL = URL(fileURLWithPath: Self.claudeSettingsPath)
            let settingsDir = settingsURL.deletingLastPathComponent()
            try fm.createDirectory(at: settingsDir, withIntermediateDirectories: true)

            var settings: [String: Any] = [:]
            if fm.fileExists(atPath: settingsURL.path),
               let data = try? Data(contentsOf: settingsURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = json
            }

            let existingStatusLine = settings["statusLine"] as? [String: Any]
            let existingCommand = (existingStatusLine?["command"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingCommand,
               !existingCommand.isEmpty,
               !existingCommand.contains(Self.claudeQuotaWrapperPath) {
                try existingCommand.write(
                    toFile: Self.claudeQuotaPreservedCommandPath,
                    atomically: true,
                    encoding: .utf8
                )
            }

            if fm.fileExists(atPath: settingsURL.path) {
                let backupPath = settingsURL.path + ".vland-quota-backup-\(quotaTimestamp())"
                try? fm.copyItem(atPath: settingsURL.path, toPath: backupPath)
                configurationLog.append("  💾 Backed up Claude settings to \(backupPath)")
            }

            settings["statusLine"] = [
                "type": "command",
                "command": Self.claudeQuotaWrapperPath,
            ]

            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try atomicWrite(data: data, to: settingsURL)

            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.claudeQuotaWrapperPath)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.claudeQuotaCollectorPath)

            configurationLog.append("  ✅ Claude Code quota hook installed")
            detectClaudeQuotaHookStatus()
            return true
        } catch {
            configurationLog.append("  ❌ Failed to install Claude quota hook: \(error.localizedDescription)")
            detectClaudeQuotaHookStatus()
            return false
        }
    }

    private func buildHooksDict(source: String, hookTypes: [HookTypeSpec]) -> [String: Any] {
        var hooks: [String: Any] = [:]

        for hookType in hookTypes {
            var commandEntry: [String: Any] = [
                "command": "\"\(Self.bridgePath)\" --source \(source)",
                "type": "command",
            ]
            if let timeoutSeconds = hookType.timeoutSeconds {
                commandEntry["timeout"] = timeoutSeconds
            }

            var hookEntry: [String: Any] = [
                "hooks": [commandEntry]
            ]
            if let matcher = hookType.matcher, !matcher.isEmpty {
                hookEntry["matcher"] = matcher
            }
            hooks[hookType.name] = [hookEntry]
        }

        return hooks
    }

    private func ensureCodexHooksEnabled() -> Bool {
        let fm = FileManager.default
        let configDir = (Self.codexConfigPath as NSString).deletingLastPathComponent

        do {
            if !fm.fileExists(atPath: configDir) {
                try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            }

            let existing = (try? String(contentsOfFile: Self.codexConfigPath, encoding: .utf8)) ?? ""
            let updated = upsertCodexHooksFlag(in: existing)

            if updated != existing || !fm.fileExists(atPath: Self.codexConfigPath) {
                try updated.write(toFile: Self.codexConfigPath, atomically: true, encoding: .utf8)
                configurationLog.append("  ✅ Enabled codex hooks in \(Self.codexConfigPath)")
            }
            return true
        } catch {
            configurationLog.append("  ❌ Failed to enable codex hooks: \(error.localizedDescription)")
            return false
        }
    }

    private func upsertCodexHooksFlag(in config: String) -> String {
        let lines = config.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var hasFeaturesSection = false
        var inFeaturesSection = false
        var insertedCodexFlag = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isSectionHeader = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")

            if isSectionHeader {
                if inFeaturesSection && !insertedCodexFlag {
                    output.append("codex_hooks = true")
                    insertedCodexFlag = true
                }
                inFeaturesSection = (trimmed == "[features]")
                if inFeaturesSection {
                    hasFeaturesSection = true
                }
                output.append(line)
                continue
            }

            if inFeaturesSection && trimmed.hasPrefix("codex_hooks") {
                output.append("codex_hooks = true")
                insertedCodexFlag = true
            } else {
                output.append(line)
            }
        }

        if inFeaturesSection && !insertedCodexFlag {
            output.append("codex_hooks = true")
            insertedCodexFlag = true
        }

        if !hasFeaturesSection {
            if !output.isEmpty && !(output.last ?? "").isEmpty {
                output.append("")
            }
            output.append("[features]")
            output.append("codex_hooks = true")
        }

        var result = output.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    // MARK: - Hermes YAML Managed Block

    private static let hermesMarkerBegin = "# >>> vland hooks >>>"
    private static let hermesMarkerEnd = "# <<< vland hooks <<<"

    /// Build the YAML managed block for Hermes hooks.
    /// Only the text between markers is managed; everything outside is preserved.
    private func buildHermesManagedBlock(hookTypes: [HookTypeSpec]) -> String {
        var lines: [String] = []
        lines.append(Self.hermesMarkerBegin)
        lines.append("# Managed by Vland — do not edit between markers. Re-run \"Configure Hermes\" to refresh.")
        lines.append("hooks_auto_accept: true")
        lines.append("hooks:")

        let command = "\(Self.bridgePath) --source hermes"
        for hookType in hookTypes {
            lines.append("  \(hookType.name):")
            lines.append("    - command: \(command)")
            lines.append("      type: command")
            if let matcher = hookType.matcher, !matcher.isEmpty {
                lines.append("      matcher: \"\(matcher)\"")
            }
            if let timeout = hookType.timeoutSeconds {
                lines.append("      timeout: \(timeout)")
            }
        }
        lines.append(Self.hermesMarkerEnd)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Insert or replace the Vland managed block in existing YAML content.
    /// If no marker block is found, append at the end of the file.
    private func upsertHermesManagedBlock(in existingContent: String, block: String) -> String {
        if let beginRange = existingContent.range(of: Self.hermesMarkerBegin),
           let endRange = existingContent.range(of: Self.hermesMarkerEnd) {
            let fullRange = beginRange.lowerBound..<existingContent.index(after: endRange.upperBound)
            let lineBefore = existingContent[..<beginRange.lowerBound]
            let afterMarker = existingContent[endRange.upperBound...]
            let afterContent = afterMarker.drop(while: { $0.isNewline })
            return lineBefore + block + afterContent
        } else {
            var result = existingContent
            if !result.hasSuffix("\n") {
                result.append("\n")
            }
            result.append(block)
            return result
        }
    }

    /// Write Hermes YAML config with automatic backup.
    private func writeHermesAgentSettings(
        for agent: DetectedAgent,
        definition agentDefinition: AgentDefinition
    ) -> Bool {
        let fm = FileManager.default
        let existing = (try? String(contentsOfFile: agent.settingsPath, encoding: .utf8)) ?? ""
        let newBlock = buildHermesManagedBlock(hookTypes: agentDefinition.hookTypes)
        let updated = upsertHermesManagedBlock(in: existing, block: newBlock)

        if fm.fileExists(atPath: agent.settingsPath), existing != updated {
            let backupPath = agent.settingsPath + ".vland-backup-\(quotaTimestamp())"
            do {
                try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
                configurationLog.append("  💾 Backed up original to \(backupPath)")
            } catch {
                configurationLog.append("  ⚠️ Could not create backup: \(error.localizedDescription)")
            }
        }

        do {
            try updated.write(toFile: agent.settingsPath, atomically: true, encoding: .utf8)
            configurationLog.append("  ✅ Hermes hooks configured in \(agent.settingsPath)")
            if let idx = detectedAgents.firstIndex(where: { $0.id == agent.id }) {
                detectedAgents[idx].hookStatus = .configuredVland
            }
            return true
        } catch {
            configurationLog.append("  ❌ Failed to write Hermes settings: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Configuration

    func configureAgent(_ agent: DetectedAgent) -> Bool {
        let fm = FileManager.default
        configurationLog.append("🔧 Configuring \(agent.displayName)...")

        guard let agentDefinition = Self.resolvedAgents().first(where: { $0.id == agent.id }) else {
            configurationLog.append("  ❌ Unknown agent: \(agent.id)")
            return false
        }

        if !bridgeInstalled {
            guard installBridgeScript() else { return false }
        }

        if agentDefinition.requiresCodexHookFlag {
            guard ensureCodexHooksEnabled() else { return false }
        }

        let configDir = (agent.settingsPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: configDir) {
            do {
                try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
                configurationLog.append("  📁 Created \(configDir)")
            } catch {
                configurationLog.append("  ❌ Failed to create config dir: \(error.localizedDescription)")
                return false
            }
        }

        // Hermes uses YAML with managed marker blocks, not JSON hooks.
        if agentDefinition.settingsFormat == .yaml {
            return writeHermesAgentSettings(for: agent, definition: agentDefinition)
        }

        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: agent.settingsPath),
           let data = fm.contents(atPath: agent.settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = json
        }

        let newHooks = buildHooksDict(source: agent.id, hookTypes: agentDefinition.hookTypes)

        if var existingHooks = settings["hooks"] as? [String: Any] {
            for (hookName, hookValue) in newHooks {
                if let existingEntries = existingHooks[hookName] as? [[String: Any]] {
                    var updatedEntries: [[String: Any]] = []

                    for entry in existingEntries {
                        if let entryHooks = entry["hooks"] as? [[String: Any]] {
                            let hasOurHook = entryHooks.contains { hook in
                                let cmd = hook["command"] as? String ?? ""
                                return cmd.contains("vland-bridge")
                                    || cmd.contains("vibe-island-bridge")
                                    || cmd.contains("agent-island-bridge")
                            }
                            if hasOurHook {
                            } else {
                                updatedEntries.append(entry)
                            }
                        } else {
                            updatedEntries.append(entry)
                        }
                    }

                    if let newEntries = hookValue as? [[String: Any]] {
                        updatedEntries.append(contentsOf: newEntries)
                    }
                    existingHooks[hookName] = updatedEntries
                } else {
                    existingHooks[hookName] = hookValue
                }
            }
            settings["hooks"] = existingHooks
        } else {
            settings["hooks"] = newHooks
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: agent.settingsPath))
            configurationLog.append("  ✅ \(agent.displayName) hooks configured")

            if let idx = detectedAgents.firstIndex(where: { $0.id == agent.id }) {
                detectedAgents[idx].hookStatus = .configuredVland
            }
            return true
        } catch {
            configurationLog.append("  ❌ Failed to write settings: \(error.localizedDescription)")
            return false
        }
    }

    func autoConfigureAll() {
        configurationLog.removeAll()
        configurationLog.append("🚀 Starting auto-configuration...")

        configurationLog.append(bridgeInstalled
            ? "🔄 Refreshing bridge script..."
            : "📦 Installing bridge script...")
        guard installBridgeScript() else {
            configurationLog.append("❌ Auto-configuration failed: could not install bridge")
            objectWillChange.send()
            return
        }

        detectInstalledAgents()

        var configuredCount = 0
        for agent in detectedAgents where agent.configDirExists {
            if agent.hookStatus == .configuredVland {
                configurationLog.append("✅ \(agent.displayName) already configured")
                configuredCount += 1
            } else {
                if configureAgent(agent) {
                    configuredCount += 1
                }
            }
        }

        if configuredCount > 0 {
            configurationLog.append("🎉 Done! Configured \(configuredCount) agent(s). Restart your AI agent to activate.")
        } else {
            configurationLog.append("⚠️ No AI agent tools detected. Install CodeBuddy, Codex CLI, Claude Code, or WorkBuddy first.")
        }

        objectWillChange.send()
    }

    private func configuredHookNames(
        in hooks: [String: Any],
        commandMatcher: (String) -> Bool
    ) -> Set<String> {
        var configured = Set<String>()

        for (hookName, hookValue) in hooks {
            guard let entries = hookValue as? [[String: Any]] else { continue }

            let hasMatchingCommand = entries.contains { entry in
                guard let commandHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return commandHooks.contains { hook in
                    let command = hook["command"] as? String ?? ""
                    return commandMatcher(command)
                }
            }

            if hasMatchingCommand {
                configured.insert(hookName)
            }
        }

        return configured
    }

    private static func bridgeVersion(at path: String) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: bridgeVersionPattern),
              let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
              let range = Range(match.range(at: 1), in: contents) else {
            return nil
        }

        let version = String(contents[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private func installQuotaResource(from bundledPath: String, to destinationPath: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationPath) {
            try fm.removeItem(atPath: destinationPath)
        }
        try fm.copyItem(atPath: bundledPath, toPath: destinationPath)
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".tmp")
        try data.write(to: tmpURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmpURL, to: url)
    }

    private func quotaTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
