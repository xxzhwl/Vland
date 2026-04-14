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

    /// Published detection results for the Settings UI
    @Published var detectedAgents: [DetectedAgent] = []
    @Published var bridgeInstalled: Bool = false
    @Published var configurationLog: [String] = []

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

    private static let agentTemplates: [(id: String, name: String, defaultConfigDir: String, settingsFileName: String, hookTypes: [HookTypeSpec], requiresCodexHookFlag: Bool)] = [
        ("codebuddy", "CodeBuddy", ".codebuddy", "settings.json", codebuddyHookTypes, false),
        ("codex", "Codex CLI", ".codex", "hooks.json", codexHookTypes, true),
        ("claude-code", "Claude Code", ".claude", "settings.json", claudeHookTypes, false),
        ("workbuddy", "WorkBuddy", ".workbuddy", "settings.json", codebuddyHookTypes, false),
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
                requiresCodexHookFlag: t.requiresCodexHookFlag
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

    // MARK: - Detection

    func detectInstalledAgents() {
        let fm = FileManager.default
        bridgeInstalled = fm.fileExists(atPath: Self.bridgePath)

        var agents: [DetectedAgent] = []

        for agent in Self.resolvedAgents() {
            let configExists = fm.fileExists(atPath: agent.configDir)
            let settingsExists = fm.fileExists(atPath: agent.settingsFile)

            var hookStatus: DetectedAgent.HookStatus = .notConfigured

            if settingsExists {
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
    }

    // MARK: - Bridge Installation

    func installBridgeScript() -> Bool {
        let fm = FileManager.default
        let bridgeDir = (Self.bridgePath as NSString).deletingLastPathComponent

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
            configurationLog.append("✅ Bridge script installed at \(Self.bridgePath)")
            return true
        } catch {
            configurationLog.append("❌ Failed to install bridge: \(error.localizedDescription)")
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

        if !bridgeInstalled {
            configurationLog.append("📦 Installing bridge script...")
            guard installBridgeScript() else {
                configurationLog.append("❌ Auto-configuration failed: could not install bridge")
                objectWillChange.send()
                return
            }
        } else {
            configurationLog.append("✅ Bridge script already installed")
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
}