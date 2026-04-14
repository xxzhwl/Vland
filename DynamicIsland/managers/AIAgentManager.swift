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
import AppKit
import Carbon
import SwiftUI

// MARK: - AI Agent Manager

/// Manages AI agent monitoring via a Unix Domain Socket server.
/// Bridge scripts (installed into CodeBuddy/Codex/Claude Code hooks) send JSON events
/// over the socket. This manager parses them and updates observable state for the UI.
@MainActor
class AIAgentManager: ObservableObject {
    static let shared = AIAgentManager()

    enum InteractionResponseResult: Equatable {
        case submitted(String)
        case copiedForManualSend(String)
        case requiresAccessibility(String)
        case failed(String)
    }

    /// All active agent sessions, keyed by source identifier
    @Published var sessions: [String: AIAgentSession] = [:]

    /// Whether the socket server is running
    @Published var isListening: Bool = false

    /// Last error message
    @Published var lastError: String?
    @Published private(set) var displayHeartbeat: Date = .now
    @Published private(set) var latestInteractionPresentationID: UUID?
    @Published private(set) var pendingBridgeInteractionIDs = Set<UUID>()
    @Published var selectedDetailSessionID: UUID?
    @Published var isShowingArchivedSessions = false

    /// Socket path — stored in a well-known location
    static let socketPath: String = {
        let tmpDir = NSTemporaryDirectory()
        return (tmpDir as NSString).appendingPathComponent("vland-ai-agent.sock")
    }()

    private let sessionStore = AIAgentSessionStore()
    private let eventReducer = AIAgentEventReducer()
    private let socketServer = AIAgentSocketServer(socketPath: AIAgentManager.socketPath)
    private let transcriptReconciler = AIAgentTranscriptReconciler()
    private lazy var transcriptWatcher = AIAgentTranscriptWatcher(reconciler: transcriptReconciler)
    private var cancellables = Set<AnyCancellable>()
    private var staleSessionTimer: Timer?
    private let minimumActiveSessionVisibilityTimeout: TimeInterval = 45
    private var presentedInteractionKeys = Set<String>()
    private var pendingBridgeResponsesByInteractionID: [UUID: PendingBridgeResponse] = [:]
    private var pendingBridgeResponseIDsByConnection: [AIAgentSocketServer.ClientConnection: UUID] = [:]

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                })
            }
            return PasteboardSnapshot(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }

            let restoredItems = items.map { storedItem -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in storedItem {
                    item.setData(data, forType: type)
                }
                return item
            }

            pasteboard.writeObjects(restoredItems)
        }
    }

    private struct PendingBridgeResponse {
        let interactionID: UUID
        let sessionKey: String
        let connection: AIAgentSocketServer.ClientConnection
    }

    // MARK: - Computed Properties

    var displayedSessions: [AIAgentSession] {
        let now = Date()
        return sessions.values
            .filter { shouldDisplayInExpandedTab($0, now: now) }
            .sorted(by: compareExpandedSessions)
    }

    var activeSessions: [AIAgentSession] {
        let now = Date()
        return sessions.values
            .filter { shouldDisplayInCollapsedNotch($0, now: now) }
            .sorted(by: compareCollapsedSessions)
    }

    var todoSneakPeekSessions: [AIAgentSession] {
        activeSessions.filter { !$0.todoItems.isEmpty || !$0.displaySubtasks.isEmpty }
    }

    var hasRestorableTodoSneakPeek: Bool {
        if !sessionsAwaitingInput.isEmpty {
            return true
        }

        return todoSneakPeekSessions.contains { session in
            let hasActiveTodo = session.todoItems.contains { item in
                item.status == .pending || item.status == .inProgress
            }
            let hasActiveSubtask = session.displaySubtasks.contains { subtask in
                subtask.status == .pending || subtask.status == .inProgress
            }
            return hasActiveTodo || hasActiveSubtask
        }
    }

    var activeSessionCount: Int {
        activeSessions.count
    }

    var allSessions: [AIAgentSession] {
        sessions.values
            .filter { !$0.isArchived }
            .sorted(by: compareExpandedSessions)
    }

    var archivedSessions: [AIAgentSession] {
        sessions.values
            .filter(\.isArchived)
            .sorted(by: compareExpandedSessions)
    }

    var selectedDetailSession: AIAgentSession? {
        guard let selectedDetailSessionID else { return nil }
        return sessionStore.session(forID: selectedDetailSessionID)
    }

    var sessionsAwaitingInput: [AIAgentSession] {
        displayedSessions.filter { $0.status == .waitingInput && $0.latestPendingInteraction != nil }
    }

    var sessionsAwaitingApproval: [AIAgentSession] {
        sessionsAwaitingInput.filter { $0.latestPendingInteraction?.isApprovalSelection == true }
    }

    var collapsedSessionsAwaitingInput: [AIAgentSession] {
        activeSessions.filter { $0.status == .waitingInput && $0.latestPendingInteraction != nil }
    }

    var collapsedSessionsAwaitingApproval: [AIAgentSession] {
        collapsedSessionsAwaitingInput.filter { $0.latestPendingInteraction?.isApprovalSelection == true }
    }

    var hasPendingApproval: Bool {
        !sessionsAwaitingApproval.isEmpty
    }

    private var activeSessionVisibilityTimeout: TimeInterval {
        let cleanupThreshold = TimeInterval(max(1, Defaults[.aiAgentAutoCleanupMinutes])) * 60
        return max(minimumActiveSessionVisibilityTimeout, cleanupThreshold)
    }

    private struct TerminalAppCandidate {
        let bundleIdentifier: String
        let processName: String
    }

    private enum NotificationContext {
        case sessionStart
        case promptSubmitted
        case taskProgress
        case waitingInput
        case interactionTimeout
        case lifecycleSound
    }

    private let terminalAppCandidates: [TerminalAppCandidate] = [
        TerminalAppCandidate(bundleIdentifier: "com.apple.Terminal", processName: "Terminal"),
        TerminalAppCandidate(bundleIdentifier: "com.googlecode.iterm2", processName: "iTerm2"),
        TerminalAppCandidate(bundleIdentifier: "dev.morishitter.alacritty", processName: "Alacritty"),
        TerminalAppCandidate(bundleIdentifier: "io.alacritty", processName: "Alacritty"),
        TerminalAppCandidate(bundleIdentifier: "com.github.wez.wezterm", processName: "WezTerm"),
        TerminalAppCandidate(bundleIdentifier: "com.mitchellh.ghostty", processName: "Ghostty"),
    ]

    private func compareExpandedSessions(_ lhs: AIAgentSession, _ rhs: AIAgentSession) -> Bool {
        compareSessions(lhs, rhs, using: \.expandedSortAnchor)
    }

    private func compareCollapsedSessions(_ lhs: AIAgentSession, _ rhs: AIAgentSession) -> Bool {
        compareSessions(lhs, rhs, using: \.collapsedSortAnchor)
    }

    private func compareSessions(
        _ lhs: AIAgentSession,
        _ rhs: AIAgentSession,
        using anchor: KeyPath<AIAgentSession, Date>
    ) -> Bool {
        let lhsNeedsInput = lhs.phase.isAttentionBlocking && lhs.latestPendingInteraction != nil
        let rhsNeedsInput = rhs.phase.isAttentionBlocking && rhs.latestPendingInteraction != nil
        if lhsNeedsInput != rhsNeedsInput {
            return lhsNeedsInput && !rhsNeedsInput
        }

        let lhsAnchor = lhs[keyPath: anchor]
        let rhsAnchor = rhs[keyPath: anchor]
        if lhsAnchor != rhsAnchor {
            return lhsAnchor > rhsAnchor
        }

        if lhs.lastActivity != rhs.lastActivity {
            return lhs.lastActivity > rhs.lastActivity
        }

        return lhs.startTime > rhs.startTime
    }

    private func isUserLikelyViewingSession(_ session: AIAgentSession) -> Bool {
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

    private func shouldNotify(for session: AIAgentSession, context _: NotificationContext) -> Bool {
        !isUserLikelyViewingSession(session)
    }

    private func markNotificationEmitted(for session: AIAgentSession, at date: Date = .now) {
        session.lastNotificationAt = date
    }

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

    func submitInteractionResponse(
        session: AIAgentSession,
        interaction: AIAgentInteraction,
        option: String
    ) async -> InteractionResponseResult {
        let response = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else {
            return .failed("Reply is empty.")
        }

        if hasPendingBridgeResponse(for: interaction.id) {
            return await submitBridgeInteractionResponse(
                session: session,
                interaction: interaction,
                option: response
            )
        }

        if interaction.responseMode == .approvalSelection {
            return .failed("Approval request expired.")
        }

        let usesPasteboardSubmission = interaction.responseMode == .pasteReply
        let pasteboard = NSPasteboard.general
        let snapshot = usesPasteboardSubmission ? PasteboardSnapshot.capture(from: pasteboard) : nil
        var authoredChangeCount: Int?
        if usesPasteboardSubmission {
            pasteboard.clearContents()
            pasteboard.setString(response, forType: .string)
            authoredChangeCount = pasteboard.changeCount
        }

        guard AccessibilityPermissionStore.shared.isAuthorized else {
            AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
            activateAgentApp(session: session)

            let result = InteractionResponseResult.requiresAccessibility(response)
            triggerInteractionSelectionSneakPeek(session: session, option: response, interaction: interaction, result: result)
            return result
        }

        guard let targetApp = await prepareApplicationForInteractionResponse(session: session) else {
            activateAgentApp(session: session)

            let result = InteractionResponseResult.copiedForManualSend(response)
            triggerInteractionSelectionSneakPeek(session: session, option: response, interaction: interaction, result: result)
            return result
        }

        let didSubmit: Bool
        switch interaction.responseMode {
        case .pasteReply:
            didSubmit = await sendPasteAndSubmit(to: targetApp)
        case .approvalSelection:
            let selectedIndex = interaction.options?.firstIndex(of: option) ?? 0
            didSubmit = await selectApprovalOption(at: selectedIndex, to: targetApp)
        }
        let result: InteractionResponseResult = didSubmit ? .submitted(response) : .copiedForManualSend(response)

        if didSubmit, usesPasteboardSubmission, let snapshot, let authoredChangeCount {
            try? await Task.sleep(nanoseconds: 450_000_000)
            restorePasteboard(snapshot, ifChangeCountIs: authoredChangeCount)
        }

        triggerInteractionSelectionSneakPeek(session: session, option: response, interaction: interaction, result: result)
        return result
    }

    func hasPendingBridgeResponse(for interactionID: UUID) -> Bool {
        pendingBridgeInteractionIDs.contains(interactionID)
    }

    private func submitBridgeInteractionResponse(
        session: AIAgentSession,
        interaction: AIAgentInteraction,
        option: String
    ) async -> InteractionResponseResult {
        guard let payload = bridgeResponsePayload(for: interaction, option: option) else {
            let result = InteractionResponseResult.failed("Unsupported interaction response.")
            session.resolveInteraction(
                id: interaction.id,
                state: .failed("Unsupported interaction response."),
                taskOverride: "Failed to submit interaction",
                statusOverride: .error
            )
            triggerInteractionSelectionSneakPeek(session: session, option: option, interaction: interaction, result: result)
            return result
        }

        let didSend = await writeBridgeResponse(payload, for: interaction.id)
        guard didSend else {
            let result = InteractionResponseResult.failed("Approval request expired.")
            session.resolveInteraction(
                id: interaction.id,
                state: .failed("Approval request expired."),
                taskOverride: "Approval request expired.",
                statusOverride: .error
            )
            triggerInteractionSelectionSneakPeek(session: session, option: option, interaction: interaction, result: result)
            return result
        }

        session.resolveInteraction(
            id: interaction.id,
            state: .submitted(option),
            taskOverride: interaction.responseMode == .approvalSelection
                ? "Approval sent: \(option)"
                : "Reply sent: \(option)",
            statusOverride: .thinking
        )

        let result = InteractionResponseResult.submitted(option)
        triggerInteractionSelectionSneakPeek(session: session, option: option, interaction: interaction, result: result)
        return result
    }

    private func bridgeResponsePayload(
        for interaction: AIAgentInteraction,
        option: String
    ) -> [String: Any]? {
        if let payload = bridgeSpecificResponsePayload(for: interaction, option: option) {
            return payload
        }

        switch interaction.responseMode {
        case .approvalSelection:
            if option.caseInsensitiveCompare("Allow") == .orderedSame
                || option.caseInsensitiveCompare("Yes") == .orderedSame {
                return ["decision": "allow"]
            }

            return [
                "decision": "block",
                "reason": "User rejected from Vland",
            ]

        case .pasteReply:
            return [
                "decision": "allow",
                "selected": [option],
            ]
        }
    }

    private func bridgeSpecificResponsePayload(
        for interaction: AIAgentInteraction,
        option: String
    ) -> [String: Any]? {
        guard let kind = interaction.bridgeResponseKind else { return nil }

        switch kind {
        case "claude_permission_request":
            if option.caseInsensitiveCompare("Allow") == .orderedSame
                || option.caseInsensitiveCompare("Yes") == .orderedSame {
                return [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": "allow"
                        ]
                    ]
                ]
            }

            return [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "deny",
                        "message": "User rejected from Vland",
                        "interrupt": false
                    ]
                ]
            ]

        case "claude_ask_user_question":
            guard let context = bridgeResponseContext(from: interaction.bridgeResponseContext),
                  var toolInput = context["tool_input"] as? [String: Any],
                  let question = context["question"] as? String else {
                return nil
            }

            var answers = toolInput["answers"] as? [String: String] ?? [:]
            answers[question] = option
            toolInput["answers"] = answers

            return [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "updatedInput": toolInput
                ]
            ]

        case "codebuddy_ask_user_question":
            guard let context = bridgeResponseContext(from: interaction.bridgeResponseContext),
                  var toolInput = context["tool_input"] as? [String: Any],
                  let question = context["question"] as? String else {
                return nil
            }

            var answers = toolInput["answers"] as? [String: String] ?? [:]
            answers[question] = option
            toolInput["answers"] = answers

            return [
                "hookSpecificOutput": [
                    "permissionDecision": "allow",
                    "modifiedInput": toolInput
                ]
            ]

        case "codebuddy_approval":
            // Use CodeBuddy native hookSpecificOutput protocol
            if option.caseInsensitiveCompare("Allow") == .orderedSame
                || option.caseInsensitiveCompare("Yes") == .orderedSame {
                return [
                    "hookSpecificOutput": [
                        "permissionDecision": "allow"
                    ]
                ]
            }
            return [
                "hookSpecificOutput": [
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "User rejected from Vland"
                ]
            ]

        default:
            return nil
        }
    }

    private func bridgeResponseContext(from rawValue: String?) -> [String: Any]? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func writeBridgeResponse(
        _ payload: [String: Any],
        for interactionID: UUID
    ) async -> Bool {
        guard let pending = pendingBridgeResponsesByInteractionID[interactionID] else {
            return false
        }

        _ = cleanupPendingBridgeResponse(interactionID)
        return await socketServer.sendResponse(payload, to: pending.connection)
    }

    /// Activate (bring to front) the macOS application associated with the given agent type.
    /// For CLI-based agents (claude-code, codex, gemini-cli), this attempts to activate the terminal
    /// that is likely running the agent.
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

    private func activateGUIAgent(bundleIdentifiers: [String], applicationNames: [String]) {
        if let appURL = resolvedGUIApplicationURL(
            bundleIdentifiers: bundleIdentifiers,
            applicationNames: applicationNames
        ) {
            openApplication(at: appURL, fallbackBundleIdentifiers: bundleIdentifiers)
            return
        }

        if let bundleIdentifier = bundleIdentifiers.first {
            lastError = "Failed to locate app for \(bundleIdentifier)"
        } else if let applicationName = applicationNames.first {
            lastError = "Failed to locate app for \(applicationName)"
        }
    }

    private func activateTerminalAgent() {
        for candidate in terminalAppCandidates {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).first else {
                continue
            }

            activateRunningApplication(app)
            return
        }

        activateTerminalApp()
    }

    private func activateRunningApplication(_ app: NSRunningApplication) {
        if NSApp.isActive {
            NSApp.deactivate()
        }

        _ = app.unhide()
        _ = app.activate(options: [.activateAllWindows])
    }

    private func resolvedGUIApplicationURL(
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

    private func openApplication(at appURL: URL, fallbackBundleIdentifiers: [String]) {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false

        workspace.openApplication(at: appURL, configuration: configuration) { [weak self] app, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let app {
                    self.lastError = nil
                    self.activateRunningApplication(app)
                    return
                }

                if let runningApp = self.runningGUIApplication(bundleIdentifiers: fallbackBundleIdentifiers) {
                    self.lastError = nil
                    self.activateRunningApplication(runningApp)
                    return
                }

                if let error {
                    self.lastError = "Failed to open \(appURL.lastPathComponent): \(error.localizedDescription)"
                } else {
                    self.lastError = "Failed to open \(appURL.lastPathComponent)"
                }
            }
        }
    }

    private func runningTerminalApplication() -> NSRunningApplication? {
        for candidate in terminalAppCandidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).first {
                return app
            }
        }

        return nil
    }

    private func runningGUIApplication(bundleIdentifiers: [String]) -> NSRunningApplication? {
        for bundleIdentifier in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return app
            }
        }

        return nil
    }

    private func prepareApplicationForInteractionResponse(session: AIAgentSession) async -> NSRunningApplication? {
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

    private func waitForRunningGUIApplication(
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

    private func sendPasteAndSubmit(to application: NSRunningApplication) async -> Bool {
        let didPaste = postKeyStroke(CGKeyCode(kVK_ANSI_V), flags: .maskCommand, to: application.processIdentifier)
        guard didPaste else { return false }

        try? await Task.sleep(nanoseconds: 120_000_000)
        return postKeyStroke(CGKeyCode(kVK_Return), to: application.processIdentifier)
    }

    private func selectApprovalOption(at index: Int, to application: NSRunningApplication) async -> Bool {
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

    private func postKeyStroke(
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

    private func restorePasteboard(_ snapshot: PasteboardSnapshot, ifChangeCountIs expectedChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount else { return }
        snapshot.restore(to: pasteboard)
    }

    /// Attempt to activate the terminal application that is likely running a CLI agent.
    private func activateTerminalApp() {
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

    // MARK: - Lifecycle

    private init() {
        configureMonitoringPipeline()

        // Observe feature toggle
        Defaults.publisher(.enableAIAgentFeature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startServer()
                } else {
                    self?.stopServer()
                }
            }
            .store(in: &cancellables)

        // Start server if feature is already enabled
        if Defaults[.enableAIAgentFeature] {
            startServer()
        }
    }

    private func configureMonitoringPipeline() {
        socketServer.onStateChange = { [weak self] isListening, errorMessage in
            guard let self else { return }
            self.isListening = isListening
            self.lastError = errorMessage

            if isListening {
                self.startStaleSessionCleanup()
            } else {
                self.staleSessionTimer?.invalidate()
                self.staleSessionTimer = nil
            }
        }

        socketServer.onEvent = { [weak self] event, connection in
            self?.handleEvent(event, connection: connection)
        }

        socketServer.onDisconnect = { [weak self] connection in
            self?.handleClientDisconnect(connection: connection)
        }

        transcriptWatcher.onSnapshot = { [weak self] sessionKey, snapshot in
            self?.handleTranscriptSnapshot(snapshot, sessionKey: sessionKey)
        }
    }

    // MARK: - Socket Server

    func startServer() {
        guard !isListening else { return }
        socketServer.start()
    }

    func stopServer() {
        socketServer.stop()
        transcriptWatcher.stopAll()
        pendingBridgeResponsesByInteractionID.removeAll()
        pendingBridgeResponseIDsByConnection.removeAll()
        pendingBridgeInteractionIDs.removeAll()
    }

    // MARK: - Event Handling

    @discardableResult
    private func handleEvent(
        _ event: AIAgentHookEvent,
        connection: AIAgentSocketServer.ClientConnection
    ) -> AIAgentSession {
        let result = eventReducer.reduce(event, in: sessionStore)
        let session = result.session

        syncSessionsFromStore()
        refreshTranscriptWatch(for: session, sessionKey: result.sessionKey)
        registerPendingBridgeResponseIfNeeded(
            for: event,
            session: session,
            sessionKey: result.sessionKey,
            connection: connection
        )

        if result.shouldScheduleEndedRemoval {
            scheduleEndedSessionRemoval(sessionKey: result.sessionKey)
        }

        if shouldTriggerTaskPreview(for: event, session: session, hadVisibleTasks: result.hadVisibleTasks) {
            triggerTodoSneakPeek(for: session)
        }

        playSoundEffectIfNeeded(for: event, session: session)

        // Trigger sneak peek notification for important events
        if event.hookType == "SessionStart" || event.hookType == "UserPromptSubmit" {
            triggerSneakPeek(for: session, event: event)
        }

        if event.hookType == "SessionEnd" || event.hookType == "Stop" {
            DynamicIslandViewCoordinator.shared.toggleSneakPeek(status: false, type: .aiAgent)
        }

        sessionDidReceiveInteractionIfNeeded(session)

        return session
    }

    private func registerPendingBridgeResponseIfNeeded(
        for event: AIAgentHookEvent,
        session: AIAgentSession,
        sessionKey: String,
        connection: AIAgentSocketServer.ClientConnection
    ) {
        guard event.needsResponse == true,
              let interaction = session.latestPendingInteraction,
              pendingBridgeResponsesByInteractionID[interaction.id] == nil else {
            return
        }

        let pending = PendingBridgeResponse(
            interactionID: interaction.id,
            sessionKey: sessionKey,
            connection: connection
        )
        pendingBridgeResponsesByInteractionID[interaction.id] = pending
        pendingBridgeResponseIDsByConnection[connection] = interaction.id
        pendingBridgeInteractionIDs.insert(interaction.id)

        if interaction.responseMode == .approvalSelection {
            triggerWaitingInputSneakPeek(for: session, interaction: interaction)
        }
    }

    @discardableResult
    private func cleanupPendingBridgeResponse(_ interactionID: UUID) -> PendingBridgeResponse? {
        guard let pending = pendingBridgeResponsesByInteractionID.removeValue(forKey: interactionID) else {
            return nil
        }

        pendingBridgeResponseIDsByConnection.removeValue(forKey: pending.connection)
        pendingBridgeInteractionIDs.remove(interactionID)

        return pending
    }

    private func handleClientDisconnect(connection: AIAgentSocketServer.ClientConnection) {
        if let interactionID = pendingBridgeResponseIDsByConnection[connection],
           let pending = cleanupPendingBridgeResponse(interactionID),
           let session = sessionStore.session(forKey: pending.sessionKey) {
            let message = interactionMessage(in: session, interactionID: interactionID)
                ?? "Interaction timed out."
            session.resolveInteraction(
                id: interactionID,
                state: .timedOut,
                taskOverride: "Interaction timed out.",
                statusOverride: .error
            )
            triggerInteractionTimeoutSneakPeek(session: session, message: message)
            syncSessionsFromStore()
        }
    }

    private func syncSessionsFromStore() {
        sessions = sessionStore.sessions
    }

    private func refreshTranscriptWatch(for session: AIAgentSession, sessionKey: String) {
        if session.isArchived {
            transcriptWatcher.unwatch(sessionKey: sessionKey)
            return
        }
        transcriptWatcher.watch(sessionKey: sessionKey, session: session)
    }

    private func handleTranscriptSnapshot(
        _ snapshot: AIAgentTranscriptSnapshot,
        sessionKey: String
    ) {
        guard let session = sessionStore.session(forKey: sessionKey) else {
            transcriptWatcher.unwatch(sessionKey: sessionKey)
            return
        }

        let hadVisibleTasks = sessionHasVisibleTaskState(session)
        session.applyTranscriptSnapshot(snapshot)
        syncSessionsFromStore()

        if !hadVisibleTasks && sessionHasVisibleTaskState(session) {
            triggerTodoSneakPeek(for: session)
        }
    }

    private func scheduleEndedSessionRemoval(sessionKey: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self,
                  let session = self.sessionStore.session(forKey: sessionKey),
                  !session.isArchived,
                  !session.status.isActive else {
                return
            }

            _ = self.sessionStore.removeSession(forKey: sessionKey)
            self.transcriptWatcher.unwatch(sessionKey: sessionKey)
            if self.selectedDetailSessionID == session.id {
                self.selectedDetailSessionID = nil
            }
            self.syncSessionsFromStore()
        }
    }

    func presentSessionDetail(_ session: AIAgentSession) {
        selectedDetailSessionID = session.id
        if session.isArchived {
            isShowingArchivedSessions = true
        }
    }

    func dismissSessionDetail() {
        selectedDetailSessionID = nil
    }

    func archiveSession(_ session: AIAgentSession) {
        guard session.canArchiveManually else { return }
        _ = sessionStore.archiveSession(id: session.id)
        if let key = sessionStore.key(forSessionID: session.id) {
            transcriptWatcher.unwatch(sessionKey: key)
        }
        if selectedDetailSessionID == session.id {
            isShowingArchivedSessions = true
        }
        syncSessionsFromStore()
    }

    func restoreSession(_ session: AIAgentSession) {
        _ = sessionStore.restoreSession(id: session.id)
        if let key = sessionStore.key(forSessionID: session.id) {
            refreshTranscriptWatch(for: session, sessionKey: key)
        }
        syncSessionsFromStore()
    }

    private func interactionMessage(in session: AIAgentSession, interactionID: UUID) -> String? {
        for turn in session.conversationTurns {
            if let interaction = turn.interactions.first(where: { $0.id == interactionID }) {
                return interaction.message
            }
        }
        return nil
    }

    private func sessionDidReceiveInteractionIfNeeded(_ session: AIAgentSession) {
        guard session.status == .waitingInput, let interaction = session.latestPendingInteraction else { return }
        let interactionKey = "\(session.id.uuidString)-\(interaction.timestamp.timeIntervalSince1970)-\(interaction.message)"
        guard !presentedInteractionKeys.contains(interactionKey) else { return }
        presentedInteractionKeys.insert(interactionKey)
        guard shouldNotify(for: session, context: .waitingInput) else { return }

        latestInteractionPresentationID = UUID()
        markNotificationEmitted(for: session)
        AIAgentSoundEffectManager.shared.play(.waitingInput)
        triggerWaitingInputSneakPeek(for: session, interaction: interaction)
    }

    private func playSoundEffectIfNeeded(for event: AIAgentHookEvent, session: AIAgentSession) {
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

    private func triggerSneakPeek(for session: AIAgentSession, event: AIAgentHookEvent) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: event.hookType == "SessionStart" ? .sessionStart : .promptSubmitted) else { return }

        let agentType = session.agentType
        let title = agentType.displayName
        let subtitle: String
        switch event.hookType {
        case "SessionStart":
            subtitle = "会话已启动"
        case "UserPromptSubmit":
            subtitle = event.message.map { String($0.prefix(50)) } ?? "新任务"
        default:
            subtitle = event.hookType
        }

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .aiAgent,
            duration: 3.0,
            icon: agentType.iconName,
            title: title,
            subtitle: subtitle,
            accentColor: agentType.accentColor
        )
        markNotificationEmitted(for: session)
    }

    private func triggerTodoSneakPeek(for session: AIAgentSession) {
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

    private func triggerWaitingInputSneakPeek(for session: AIAgentSession, interaction: AIAgentInteraction) {
        guard Defaults[.aiAgentShowSneakPeek],
              shouldNotify(for: session, context: .waitingInput) else { return }
        let isApprovalRequest = interaction.isApprovalSelection
        let isBridgeApproval = hasPendingBridgeResponse(for: interaction.id) && isApprovalRequest

        if isApprovalRequest || session.todoItems.isEmpty {
            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .aiAgent,
                duration: isBridgeApproval ? 4.5 : 4.0,
                icon: isBridgeApproval ? "exclamationmark.triangle.fill" : session.agentType.iconName,
                title: isApprovalRequest ? "需要审批" : "\(session.agentType.displayName) 需要输入",
                subtitle: String(interaction.message.prefix(50)),
                accentColor: isApprovalRequest ? .orange : session.agentType.accentColor
            )
        } else {
            triggerTodoSneakPeek(for: session)
        }

        // Also show an expanding preview below the closed notch (like music playback preview),
        // so users can see there's a task requiring attention even when the island is collapsed.
        DynamicIslandViewCoordinator.shared.toggleExpandingView(
            status: true,
            type: .aiAgent
        )
        markNotificationEmitted(for: session)
    }

    private func triggerInteractionTimeoutSneakPeek(session: AIAgentSession, message: String) {
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

    private func isTodoOrPlanTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        let normalized = toolName.lowercased()
        return normalized == "todo_write" || normalized == "todowrite"
            || normalized == "update_plan" || normalized == "updateplan"
    }

    private func sessionHasVisibleTaskState(_ session: AIAgentSession) -> Bool {
        !session.todoItems.isEmpty || !session.displaySubtasks.isEmpty
    }

    private func shouldTriggerTaskPreview(
        for event: AIAgentHookEvent,
        session: AIAgentSession,
        hadVisibleTasks: Bool
    ) -> Bool {
        let hasVisibleTasks = sessionHasVisibleTaskState(session)
        guard hasVisibleTasks else { return false }

        if !hadVisibleTasks {
            return true
        }

        if isTodoOrPlanTool(event.toolName) {
            return true
        }

        if let subtasks = event.subtasks, !subtasks.isEmpty {
            return true
        }

        return false
    }

    private func triggerInteractionSelectionSneakPeek(
        session: AIAgentSession,
        option: String,
        interaction: AIAgentInteraction,
        result: InteractionResponseResult
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
            triggerTodoSneakPeek(for: session)
        }
    }

    // MARK: - Full Transcript Loading

    /// Load full transcript for a session (lazy, on-demand for detailed mode).
    func loadFullTranscript(for session: AIAgentSession) async {
        guard session.agentType.supportsFullHistory else {
            await MainActor.run { session.transcriptLoadError = "Agent type does not support full history" }
            return
        }
        guard !session.isTranscriptLoaded else { return }

        let transcriptPath = session.transcriptPath
        let sessionId = session.sessionId

        NSLog("[Vland] loadFullTranscript: agentType=\(session.agentType.rawValue), transcriptPath=\(transcriptPath ?? "nil"), sessionId=\(sessionId ?? "nil")")

        guard let transcriptPath, !transcriptPath.isEmpty else {
            await MainActor.run { session.transcriptLoadError = "No transcript path available" }
            return
        }

        do {
            let messages = try await TranscriptReader.readTranscript(
                agentType: session.agentType,
                transcriptPath: transcriptPath,
                sessionId: sessionId
            )
            NSLog("[Vland] loadFullTranscript: loaded \(messages.count) messages")
            await MainActor.run {
                session.fullTranscript = messages
                session.isTranscriptLoaded = true
                session.transcriptLoadError = nil
            }
        } catch {
            NSLog("[Vland] loadFullTranscript: error=\(error.localizedDescription)")
            await MainActor.run {
                session.transcriptLoadError = error.localizedDescription
            }
        }
    }

    // MARK: - Stale Session Cleanup

    private func startStaleSessionCleanup() {
        staleSessionTimer?.invalidate()
        staleSessionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cleanupStaleSessions()
                self.displayHeartbeat = Date()
            }
        }
    }

    private func cleanupStaleSessions() {
        let now = Date()
        let activeThreshold = activeSessionVisibilityTimeout
        let endedThreshold = TimeInterval(max(5, Defaults[.aiAgentExpandedRetentionSeconds]))

        // Collect keys based on each session's retention policy
        var keysToAutoArchive: [String] = []
        var keysToRemove: [String] = []

        for (key, session) in sessionStore.sessions {
            guard !session.isArchived else { continue }

            let age = now.timeIntervalSince(session.lastActivity)
            let threshold: TimeInterval

            switch session.status {
            case .completed, .error, .sessionEnd:
                threshold = endedThreshold
            case .idle:
                // idle sessions that have been around are zombies - remove them
                threshold = endedThreshold
            case .thinking, .coding, .running, .waitingInput, .sessionStart:
                threshold = activeThreshold
            }

            if age > threshold {
                switch session.status {
                case .completed, .error, .sessionEnd:
                    keysToAutoArchive.append(key)
                default:
                    keysToRemove.append(key)
                }
            }
        }

        // Auto-archive completed/ended sessions instead of deleting
        for key in keysToAutoArchive {
            if let session = sessionStore.sessions[key] {
                _ = sessionStore.archiveSession(id: session.id)
                transcriptWatcher.unwatch(sessionKey: key)
            }
        }

        // Only remove zombie sessions (still active but timed out)
        for key in keysToRemove {
            sessionStore.removeSession(forKey: key)
            transcriptWatcher.unwatch(sessionKey: key)
        }

        if !keysToRemove.isEmpty || !keysToAutoArchive.isEmpty {
            if let selectedDetailSessionID,
               sessionStore.session(forID: selectedDetailSessionID) == nil {
                self.selectedDetailSessionID = nil
            }
            syncSessionsFromStore()
        }
    }

    private func shouldDisplayInCollapsedNotch(_ session: AIAgentSession, now: Date) -> Bool {
        guard !session.isArchived else { return false }
        let age = now.timeIntervalSince(session.lastActivity)

        switch session.status {
        case .sessionStart:
            // A session that only has SessionStart but no user prompt or tool calls
            // is not truly active — show it briefly (15s) then hide from collapsed notch.
            // It will still appear in the expanded tab for a while.
            let hasRealActivity = session.lastUserPrompt != nil || !session.conversationTurns.isEmpty
            let timeout: TimeInterval = hasRealActivity ? activeSessionVisibilityTimeout : 15
            return age <= timeout
        case .thinking, .coding, .running, .waitingInput:
            return age <= activeSessionVisibilityTimeout
        case .completed, .error, .idle, .sessionEnd:
            return false
        }
    }

    private func shouldDisplayInExpandedTab(_ session: AIAgentSession, now: Date) -> Bool {
        guard !session.isArchived else { return false }
        let age = now.timeIntervalSince(session.lastActivity)
        let endedSessionRetention = TimeInterval(max(5, Defaults[.aiAgentExpandedRetentionSeconds]))

        switch session.status {
        case .sessionStart:
            // Ghost session: show in expanded tab for 30s max, then auto-hide
            let hasRealActivity = session.lastUserPrompt != nil || !session.conversationTurns.isEmpty
            let timeout: TimeInterval = hasRealActivity ? activeSessionVisibilityTimeout : 30
            return age <= timeout
        case .thinking, .coding, .running, .waitingInput:
            return age <= activeSessionVisibilityTimeout
        case .completed, .error, .sessionEnd:
            return age <= endedSessionRetention
        case .idle:
            return false
        }
    }

    // MARK: - Auto-Detection & Configuration

    /// Represents a detected AI agent tool installation
    struct DetectedAgent: Identifiable {
        let id: String         // e.g. "codebuddy", "claude-code"
        let displayName: String
        let settingsPath: String
        let configDirExists: Bool
        let settingsFileExists: Bool
        var hookStatus: HookStatus

        enum HookStatus: Equatable {
            case notConfigured
            case configuredVland
            case configuredOther(String) // bridge path that is not vland's
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
        // Some build setups flatten resources without preserving subdirectories.
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

    /// Default hook set (used as base for CodeBuddy/WorkBuddy)
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

    /// CodeBuddy / WorkBuddy hook set with pre-registered PermissionRequest and SubagentStart
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
        // Pre-registered for future support (no side effects until CodeBuddy emits these events)
        HookTypeSpec(name: "PermissionRequest", matcher: "*", timeoutSeconds: 86_400),
        HookTypeSpec(name: "SubagentStart", matcher: nil, timeoutSeconds: nil),
    ]

    /// Claude Code has dedicated approval and subagent lifecycle hooks.
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

    /// Codex currently uses a smaller hook event set.
    private static let codexHookTypes: [HookTypeSpec] = [
        HookTypeSpec(name: "PreToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "PostToolUse", matcher: "*", timeoutSeconds: nil),
        HookTypeSpec(name: "SessionStart", matcher: "startup|resume", timeoutSeconds: nil),
        HookTypeSpec(name: "UserPromptSubmit", matcher: nil, timeoutSeconds: nil),
        HookTypeSpec(name: "Stop", matcher: nil, timeoutSeconds: nil),
    ]

    /// Agent configuration templates (id, name, defaultConfigDir, settingsFileName, hookTypes, requiresCodexHookFlag)
    private static let agentTemplates: [(id: String, name: String, defaultConfigDir: String, settingsFileName: String, hookTypes: [HookTypeSpec], requiresCodexHookFlag: Bool)] = [
        ("codebuddy", "CodeBuddy", ".codebuddy", "settings.json", codebuddyHookTypes, false),
        ("codex", "Codex CLI", ".codex", "hooks.json", codexHookTypes, true),
        ("claude-code", "Claude Code", ".claude", "settings.json", claudeHookTypes, false),
        ("workbuddy", "WorkBuddy", ".workbuddy", "settings.json", codebuddyHookTypes, false),
    ]

    /// Resolved agent definitions with custom directory support
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

    /// All known AI agent tools and their settings file locations (legacy, resolved at call time)
    private static var knownAgents: [AgentDefinition] {
        resolvedAgents()
    }

    /// Codex feature flag path (required for codex hooks to run)
    private static let codexConfigPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".codex/config.toml")
    }()

    /// Detect installed AI agent tools and their hook configuration status
    func detectInstalledAgents() {
        let fm = FileManager.default
        bridgeInstalled = fm.fileExists(atPath: Self.bridgePath)

        var agents: [DetectedAgent] = []

        for agent in Self.resolvedAgents() {
            let configExists = fm.fileExists(atPath: agent.configDir)
            let settingsExists = fm.fileExists(atPath: agent.settingsFile)

            var hookStatus: DetectedAgent.HookStatus = .notConfigured

            if settingsExists {
                // Check if hooks are already configured
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
                        // Has hooks but not for vland
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

    /// Install the bridge script from bundled resources
    func installBridgeScript() -> Bool {
        let fm = FileManager.default
        let bridgeDir = (Self.bridgePath as NSString).deletingLastPathComponent

        do {
            // Create directory
            try fm.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)

            // Copy from bundled resources
            if let bundled = Self.bundledBridgePath {
                if fm.fileExists(atPath: Self.bridgePath) {
                    try fm.removeItem(atPath: Self.bridgePath)
                }
                try fm.copyItem(atPath: bundled, toPath: Self.bridgePath)
            } else {
                // Fallback: bridge is already installed (from previous setup)
                guard fm.fileExists(atPath: Self.bridgePath) else {
                    configurationLog.append("❌ Bridge script not found in app bundle")
                    return false
                }
            }

            // Make executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.bridgePath)

            bridgeInstalled = true
            configurationLog.append("✅ Bridge script installed at \(Self.bridgePath)")
            return true
        } catch {
            configurationLog.append("❌ Failed to install bridge: \(error.localizedDescription)")
            return false
        }
    }

    /// Build the hooks JSON structure for a given agent source
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

    /// Configure hooks for a specific agent
    func configureAgent(_ agent: DetectedAgent) -> Bool {
        let fm = FileManager.default
        configurationLog.append("🔧 Configuring \(agent.displayName)...")

        guard let agentDefinition = Self.resolvedAgents().first(where: { $0.id == agent.id }) else {
            configurationLog.append("  ❌ Unknown agent: \(agent.id)")
            return false
        }

        // Ensure bridge is installed
        if !bridgeInstalled {
            guard installBridgeScript() else { return false }
        }

        // Codex requires the feature flag in ~/.codex/config.toml
        if agentDefinition.requiresCodexHookFlag {
            guard ensureCodexHooksEnabled() else { return false }
        }

        // Ensure config directory exists
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

        // Read existing settings or create new
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: agent.settingsPath),
           let data = fm.contents(atPath: agent.settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = json
        }

        // Build and merge hooks
        let newHooks = buildHooksDict(source: agent.id, hookTypes: agentDefinition.hookTypes)

        if var existingHooks = settings["hooks"] as? [String: Any] {
            // Merge: for each hook type, replace or add vland-bridge entries
            for (hookName, hookValue) in newHooks {
                if let existingEntries = existingHooks[hookName] as? [[String: Any]] {
                    // Check if there are non-vland hooks to preserve
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
                                // Replace with vland version
                            } else {
                                updatedEntries.append(entry)
                            }
                        } else {
                            updatedEntries.append(entry)
                        }
                    }

                    // Add our hook entries
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

        // Write back
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: agent.settingsPath))
            configurationLog.append("  ✅ \(agent.displayName) hooks configured")

            // Update detection state
            if let idx = detectedAgents.firstIndex(where: { $0.id == agent.id }) {
                detectedAgents[idx].hookStatus = .configuredVland
            }
            return true
        } catch {
            configurationLog.append("  ❌ Failed to write settings: \(error.localizedDescription)")
            return false
        }
    }

    /// One-click: install bridge + configure all detected agents
    func autoConfigureAll() {
        configurationLog.removeAll()
        configurationLog.append("🚀 Starting auto-configuration...")

        // Step 1: Install bridge
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

        // Step 2: Detect agents
        detectInstalledAgents()

        // Step 3: Configure each detected agent
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
