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
import Carbon

// MARK: - AI Agent App Activator

/// Manages macOS application activation for AI agent sessions.
/// Handles both GUI agents (CodeBuddy, Claude Code) and CLI agents (running in terminals).
@MainActor
final class AIAgentAppActivator {
    /// Terminal app candidates for CLI-based agents
    private struct TerminalAppCandidate {
        let bundleIdentifier: String
        let processName: String
    }

    private let terminalAppCandidates: [TerminalAppCandidate] = [
        TerminalAppCandidate(bundleIdentifier: "com.apple.Terminal", processName: "Terminal"),
        TerminalAppCandidate(bundleIdentifier: "com.googlecode.iterm2", processName: "iTerm2"),
        TerminalAppCandidate(bundleIdentifier: "dev.morishitter.alacritty", processName: "Alacritty"),
        TerminalAppCandidate(bundleIdentifier: "io.alacritty", processName: "Alacritty"),
        TerminalAppCandidate(bundleIdentifier: "com.github.wez.wezterm", processName: "WezTerm"),
        TerminalAppCandidate(bundleIdentifier: "com.mitchellh.ghostty", processName: "Ghostty"),
    ]

    /// Callback for reporting errors
    var onError: ((String?) -> Void)?

    // MARK: - Activate Agent App

    func activateAgentApp(session: AIAgentSession) {
        if !session.agentType.bundleIdentifiers.isEmpty {
            activateGUIAgent(
                bundleIdentifiers: session.agentType.bundleIdentifiers,
                applicationNames: session.agentType.applicationNames
            )
            return
        }

        activateTerminalAgent()
    }

    func activateAgentApp(agentType: AIAgentType) {
        if !agentType.bundleIdentifiers.isEmpty {
            activateGUIAgent(
                bundleIdentifiers: agentType.bundleIdentifiers,
                applicationNames: agentType.applicationNames
            )
            return
        }

        // CLI-based agents: try to activate the running terminal
        activateTerminalApp()
    }

    func activateGUIAgent(bundleIdentifiers: [String], applicationNames: [String]) {
        if let appURL = resolvedGUIApplicationURL(
            bundleIdentifiers: bundleIdentifiers,
            applicationNames: applicationNames
        ) {
            openApplication(at: appURL, fallbackBundleIdentifiers: bundleIdentifiers)
            return
        }

        if let bundleIdentifier = bundleIdentifiers.first {
            onError?("Failed to locate app for \(bundleIdentifier)")
        } else if let applicationName = applicationNames.first {
            onError?("Failed to locate app for \(applicationName)")
        }
    }

    func activateTerminalAgent() {
        for candidate in terminalAppCandidates {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).first else {
                continue
            }

            activateRunningApplication(app)
            return
        }

        activateTerminalApp()
    }

    func activateRunningApplication(_ app: NSRunningApplication) {
        if NSApp.isActive {
            NSApp.deactivate()
        }

        _ = app.unhide()
        _ = app.activate(options: [.activateAllWindows])
    }

    func resolvedGUIApplicationURL(
        bundleIdentifiers: [String],
        applicationNames: [String]
    ) -> URL? {
        let workspace = NSWorkspace.shared

        if let runningApp = runningGUIApplication(bundleIdentifiers: bundleIdentifiers),
           let bundleURL = runningApp.bundleURL {
            return bundleURL
        }

        for bundleIdentifier in bundleIdentifiers {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return appURL
            }
        }

        for applicationName in applicationNames {
            if let appPath = workspace.fullPath(forApplication: applicationName) {
                return URL(fileURLWithPath: appPath)
            }
        }

        return nil
    }

    func openApplication(at appURL: URL, fallbackBundleIdentifiers: [String]) {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false

        workspace.openApplication(at: appURL, configuration: configuration) { [weak self] app, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let app {
                    self.onError?(nil)
                    self.activateRunningApplication(app)
                    return
                }

                if let runningApp = self.runningGUIApplication(bundleIdentifiers: fallbackBundleIdentifiers) {
                    self.onError?(nil)
                    self.activateRunningApplication(runningApp)
                    return
                }

                if let error {
                    self.onError?("Failed to open \(appURL.lastPathComponent): \(error.localizedDescription)")
                } else {
                    self.onError?("Failed to open \(appURL.lastPathComponent)")
                }
            }
        }
    }

    func runningTerminalApplication() -> NSRunningApplication? {
        for candidate in terminalAppCandidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).first {
                return app
            }
        }

        return nil
    }

    func runningGUIApplication(bundleIdentifiers: [String]) -> NSRunningApplication? {
        for bundleIdentifier in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return app
            }
        }

        return nil
    }

    // MARK: - Interaction Response Preparation

    func prepareApplicationForInteractionResponse(session: AIAgentSession) async -> NSRunningApplication? {
        if !session.agentType.bundleIdentifiers.isEmpty {
            if let runningApp = runningGUIApplication(bundleIdentifiers: session.agentType.bundleIdentifiers) {
                activateRunningApplication(runningApp)
                try? await Task.sleep(nanoseconds: 220_000_000)
                return runningApp
            }

            guard resolvedGUIApplicationURL(
                bundleIdentifiers: session.agentType.bundleIdentifiers,
                applicationNames: session.agentType.applicationNames
            ) != nil else {
                return nil
            }

            activateGUIAgent(
                bundleIdentifiers: session.agentType.bundleIdentifiers,
                applicationNames: session.agentType.applicationNames
            )
            guard let launchedApp = await waitForRunningGUIApplication(bundleIdentifiers: session.agentType.bundleIdentifiers) else {
                return nil
            }

            activateRunningApplication(launchedApp)
            try? await Task.sleep(nanoseconds: 350_000_000)
            return launchedApp
        }

        guard let terminalApp = runningTerminalApplication() else {
            return nil
        }

        activateRunningApplication(terminalApp)
        try? await Task.sleep(nanoseconds: 220_000_000)
        return terminalApp
    }

    func waitForRunningGUIApplication(
        bundleIdentifiers: [String],
        timeout: TimeInterval = 2.5
    ) async -> NSRunningApplication? {
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < timeout {
            if let app = runningGUIApplication(bundleIdentifiers: bundleIdentifiers) {
                return app
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    // MARK: - Keyboard Simulation

    func sendPasteAndSubmit(to application: NSRunningApplication) async -> Bool {
        let didPaste = postKeyStroke(CGKeyCode(kVK_ANSI_V), flags: .maskCommand, to: application.processIdentifier)
        guard didPaste else { return false }

        try? await Task.sleep(nanoseconds: 120_000_000)
        return postKeyStroke(CGKeyCode(kVK_Return), to: application.processIdentifier)
    }

    func selectApprovalOption(at index: Int, to application: NSRunningApplication) async -> Bool {
        let pid = application.processIdentifier

        for _ in 0..<8 {
            guard postKeyStroke(CGKeyCode(kVK_UpArrow), to: pid) else { return false }
            try? await Task.sleep(nanoseconds: 35_000_000)
        }

        if index > 0 {
            for _ in 0..<index {
                guard postKeyStroke(CGKeyCode(kVK_DownArrow), to: pid) else { return false }
                try? await Task.sleep(nanoseconds: 35_000_000)
            }
        }

        try? await Task.sleep(nanoseconds: 60_000_000)
        return postKeyStroke(CGKeyCode(kVK_Return), to: pid)
    }

    func postKeyStroke(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        to pid: pid_t
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    // MARK: - Terminal App Activation

    /// Attempt to activate the terminal application that is likely running a CLI agent.
    func activateTerminalApp() {
        let workspace = NSWorkspace.shared

        // First, check if any of these terminals are already running
        for candidate in terminalAppCandidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).first {
                activateRunningApplication(app)
                return
            }
        }

        // No terminal running — try to launch the default Terminal.app
        if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            workspace.openApplication(at: appURL, configuration: configuration)
        }
    }

    // MARK: - Session Visibility Check

    func isUserLikelyViewingSession(_ session: AIAgentSession) -> Bool {
        if NSApp.isActive {
            return true
        }

        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }

        if session.isCLIBacked {
            return terminalAppCandidates.contains { $0.bundleIdentifier == bundleIdentifier }
        }

        return session.agentType.bundleIdentifiers.contains(bundleIdentifier)
    }
}