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
final class AIAgentManager: ObservableObject {
    static let shared = AIAgentManager()

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
    private let hookConfigurator = AIAgentHookConfigurator()
    private let appActivator = AIAgentAppActivator()
    private lazy var notificationCoordinator = AIAgentNotificationCoordinator(appActivator: appActivator)
    private var cancellables = Set<AnyCancellable>()
    private var pendingSessionRemovalItems: [String: DispatchWorkItem] = [:]
    private let minimumActiveSessionVisibilityTimeout: TimeInterval = 45
    private var presentedInteractionKeys = Set<String>()
    private var pendingBridgeResponsesByInteractionID: [UUID: PendingBridgeResponse] = [:]
    private var pendingBridgeResponseIDsByConnection: [AIAgentSocketServer.ClientConnection: UUID] = [:]
    private var bridgeRequestIdToInteractionID: [String: UUID] = [:]

    /// Socket connections keyed by session key, for sending proactive messages
    /// (user typing in the input bar when the agent isn't waiting for input).
    /// The bridge script must keep the connection open and listen for unsolicited
    /// "UserPromptSubmit" messages for this to work.
    private var sessionSocketConnections: [String: AIAgentSocketServer.ClientConnection] = [:]

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
        let bridgeRequestId: String?
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
        activeSessions.filter { session in
            // Must have tasks to display
            guard !session.todoItems.isEmpty || !session.displaySubtasks.isEmpty else {
                return false
            }
            // Exclude sessions waiting for user input (AI is idle, not working)
            // unless they have a pending interaction (e.g., approval request)
            if session.status == .waitingInput && session.latestPendingInteraction == nil {
                return false
            }
            return true
        }
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

    // MARK: - App Activation (forwarded to AIAgentAppActivator)

    func activateAgentApp(session: AIAgentSession) {
        appActivator.activateAgentApp(session: session)
    }

    func activateAgentApp(agentType: AIAgentType) {
        appActivator.activateAgentApp(agentType: agentType)
    }

    private func activateGUIAgent(bundleIdentifiers: [String], applicationNames: [String]) {
        appActivator.activateGUIAgent(bundleIdentifiers: bundleIdentifiers, applicationNames: applicationNames)
    }

    private func activateTerminalAgent() {
        appActivator.activateTerminalAgent()
    }

    private func activateRunningApplication(_ app: NSRunningApplication) {
        appActivator.activateRunningApplication(app)
    }

    private func resolvedGUIApplicationURL(bundleIdentifiers: [String], applicationNames: [String]) -> URL? {
        // This is internal, exposed via prepareApplicationForInteractionResponse
        nil
    }

    private func openApplication(at appURL: URL, fallbackBundleIdentifiers: [String]) {
        // Used internally by appActivator
    }

    private func runningTerminalApplication() -> NSRunningApplication? {
        // Used internally by appActivator
        nil
    }

    private func runningGUIApplication(bundleIdentifiers: [String]) -> NSRunningApplication? {
        // Used internally by appActivator
        nil
    }

    private func prepareApplicationForInteractionResponse(session: AIAgentSession) async -> NSRunningApplication? {
        await appActivator.prepareApplicationForInteractionResponse(session: session)
    }

    private func waitForRunningGUIApplication(bundleIdentifiers: [String], timeout: TimeInterval) async -> NSRunningApplication? {
        await appActivator.waitForRunningGUIApplication(bundleIdentifiers: bundleIdentifiers, timeout: timeout)
    }

    private func sendPasteAndSubmit(to application: NSRunningApplication) async -> Bool {
        await appActivator.sendPasteAndSubmit(to: application)
    }

    private func selectApprovalOption(at index: Int, to application: NSRunningApplication) async -> Bool {
        await appActivator.selectApprovalOption(at: index, to: application)
    }

    private func postKeyStroke(_ keyCode: CGKeyCode, flags: CGEventFlags, to pid: pid_t) -> Bool {
        appActivator.postKeyStroke(keyCode, flags: flags, to: pid)
    }

    private func activateTerminalApp() {
        appActivator.activateTerminalApp()
    }

    private func isUserLikelyViewingSession(_ session: AIAgentSession) -> Bool {
        appActivator.isUserLikelyViewingSession(session)
    }

    // MARK: - Session Comparison (forwarded - Phase 6)

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
            notificationCoordinator.notifyInteractionResult(session: session, interaction: interaction, result: result, option: response)
            return result
        }

        guard let targetApp = await prepareApplicationForInteractionResponse(session: session) else {
            activateAgentApp(session: session)

            let result = InteractionResponseResult.copiedForManualSend(response)
            notificationCoordinator.notifyInteractionResult(session: session, interaction: interaction, result: result, option: response)
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

        notificationCoordinator.notifyInteractionResult(session: session, interaction: interaction, result: result, option: response)
        return result
    }

    func hasPendingBridgeResponse(for interactionID: UUID) -> Bool {
        pendingBridgeInteractionIDs.contains(interactionID)
    }

    /// Whether there's an active socket connection for this session.
    /// Used to determine if proactive prompting is available.
    func hasActiveBridgeConnection(for session: AIAgentSession) -> Bool {
        guard let key = sessionStore.key(forSessionID: session.id) else { return false }
        return sessionSocketConnections[key] != nil
    }

    /// Sends a proactive user prompt to the bridge when there's no pending interaction.
    /// Tries socket first (fast path), then tmux, then falls back to clipboard+app activation.
    func sendProactivePrompt(session: AIAgentSession, prompt: String) async -> Bool {
        // Try 1: socket connection (fast path)
        if let key = sessionStore.key(forSessionID: session.id),
           let connection = sessionSocketConnections[key] {
            let payload: [String: Any] = [
                "source": session.agentType.rawValue,
                "hook_type": "UserPromptSubmit",
                "timestamp": Date().timeIntervalSince1970,
                "session_id": session.sessionId ?? "",
                "user_prompt": prompt,
            ]

            if await socketServer.sendResponse(payload, to: connection, closeAfterWrite: false) {
                return true
            }
        }

        // Try 2: tmux (for CLI agents running in tmux)
        if let tty = session.tty {
            let tmuxController = TmuxController.shared
            if let target = await tmuxController.findTarget(forTTY: tty) {
                if await tmuxController.sendMessage(prompt, to: target) {
                    return true
                }
            }
        }

        // Try 3: clipboard + app activation (like vibe-notch's paste-and-submit approach)
        return await sendProactiveViaClipboard(session: session, prompt: prompt)
    }

    /// Fallback: copy prompt to clipboard, activate the agent app, paste and submit.
    /// Works without an active socket connection.
    private func sendProactiveViaClipboard(session: AIAgentSession, prompt: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        let authoredChangeCount = pasteboard.changeCount

        guard AccessibilityPermissionStore.shared.isAuthorized else {
            AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
            activateAgentApp(session: session)
            snapshot.restore(to: pasteboard)
            return false
        }

        guard let targetApp = await prepareApplicationForInteractionResponse(session: session) else {
            activateAgentApp(session: session)
            snapshot.restore(to: pasteboard)
            return false
        }

        let didSubmit = await sendPasteAndSubmit(to: targetApp)

        // Restore pasteboard after a short delay to let the paste happen
        try? await Task.sleep(nanoseconds: 450_000_000)
        restorePasteboard(snapshot, ifChangeCountIs: authoredChangeCount)

        return didSubmit
    }

    private func submitBridgeInteractionResponse(
        session: AIAgentSession,
        interaction: AIAgentInteraction,
        option: String
    ) async -> InteractionResponseResult {
        guard let payload = AIAgentBridgeProtocol.responsePayload(for: interaction, option: option) else {
            let result = InteractionResponseResult.failed("Unsupported interaction response.")
            session.resolveInteraction(
                id: interaction.id,
                state: .failed("Unsupported interaction response."),
                taskOverride: "Failed to submit interaction",
                statusOverride: .error
            )
            notificationCoordinator.notifyInteractionResult(session: session, interaction: interaction, result: result, option: option)
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
            notificationCoordinator.notifyInteractionResult(session: session, interaction: interaction, result: result, option: option)
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
        notificationCoordinator.notifyInteractionResult(session: session, interaction: interaction, result: result, option: option)
        return result
    }

    private func writeBridgeResponse(
        _ payload: [String: Any],
        for interactionID: UUID
    ) async -> Bool {
        guard let pending = pendingBridgeResponsesByInteractionID[interactionID] else {
            return false
        }

        // Clean up stale session socket connection — sendResponse will close
        // the socket (closeAfterWrite: true by default), making it unusable.
        let staleKeys = sessionSocketConnections.filter { $0.value == pending.connection }.keys
        for key in staleKeys {
            sessionSocketConnections.removeValue(forKey: key)
        }

        _ = cleanupPendingBridgeResponse(interactionID)
        return await socketServer.sendResponse(payload, to: pending.connection)
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot, ifChangeCountIs expectedChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount else { return }
        snapshot.restore(to: pasteboard)
    }

    // MARK: - Lifecycle

    private init() {
        configureMonitoringPipeline()

        // Wire up app activator error callback
        appActivator.onError = { [weak self] error in
            self?.lastError = error
        }

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
                self.discoverExistingSessions()
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
        bridgeRequestIdToInteractionID.removeAll()
        sessionSocketConnections.removeAll()
        pendingSessionRemovalItems.values.forEach { $0.cancel() }
        pendingSessionRemovalItems.removeAll()
    }

    // MARK: - Event Handling

    @discardableResult
    private func handleEvent(
        _ event: AIAgentHookEvent,
        connection: AIAgentSocketServer.ClientConnection
    ) -> AIAgentSession {
        // BridgeDropped: bridge timed out without getting a response from Vland.
        // This happens when the user approved/rejected the action directly in the CLI.
        // Resolve the pending interaction gracefully so the UI doesn't show a stale
        // pending approval or an error state.
        if event.hookType == "BridgeDropped" {
            handleBridgeDropped(event)
            return AIAgentSession(agentType: .codebuddy)
        }

        let result = eventReducer.reduce(event, in: sessionStore)
        let session = result.session

        // Store the latest socket connection for this session
        // so we can send proactive user prompts when there's no pending interaction.
        sessionSocketConnections[result.sessionKey] = connection

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
            notificationCoordinator.notifyTaskProgress(session: session)
        }

        notificationCoordinator.playSoundIfNeeded(for: event, session: session)

        // Trigger sneak peek notification for important events
        if event.hookType == "SessionStart" {
            notificationCoordinator.notifySessionStart(session: session, event: event)
        } else if event.hookType == "UserPromptSubmit" {
            notificationCoordinator.notifyPromptSubmit(session: session, event: event)
        }

        if event.hookType == "SessionEnd" || event.hookType == "Stop" {
            notificationCoordinator.notifySessionEnd()
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
            connection: connection,
            bridgeRequestId: event.bridgeRequestId
        )
        pendingBridgeResponsesByInteractionID[interaction.id] = pending
        pendingBridgeResponseIDsByConnection[connection] = interaction.id
        pendingBridgeInteractionIDs.insert(interaction.id)
        if let bridgeId = event.bridgeRequestId {
            bridgeRequestIdToInteractionID[bridgeId] = interaction.id
        }

        if interaction.responseMode == .approvalSelection {
            notificationCoordinator.notifyWaitingInput(session: session, interaction: interaction, isBridge: true)
        }
    }

    @discardableResult
    private func cleanupPendingBridgeResponse(_ interactionID: UUID) -> PendingBridgeResponse? {
        guard let pending = pendingBridgeResponsesByInteractionID.removeValue(forKey: interactionID) else {
            return nil
        }

        pendingBridgeResponseIDsByConnection.removeValue(forKey: pending.connection)
        pendingBridgeInteractionIDs.remove(interactionID)
        if let bridgeId = pending.bridgeRequestId {
            bridgeRequestIdToInteractionID.removeValue(forKey: bridgeId)
        }

        return pending
    }

    /// Handle BridgeDropped event — bridge timed out or was disconnected after
    /// the user handled the approval directly in the CLI.
    /// Resolve the pending interaction gracefully instead of showing an error state.
    private func handleBridgeDropped(_ event: AIAgentHookEvent) {
        // Prefer bridgeRequestId-based matching for precise correlation
        if let bridgeRequestId = event.bridgeRequestId,
           let interactionID = bridgeRequestIdToInteractionID[bridgeRequestId],
           let pending = pendingBridgeResponsesByInteractionID[interactionID] {
            let sessionKey = pending.sessionKey
            cleanupPendingBridgeResponse(interactionID)

            if let session = sessionStore.session(forKey: sessionKey) {
                session.resolveInteraction(
                    id: interactionID,
                    state: .submitted("已在终端处理"),
                    taskOverride: "批准请求已在终端处理",
                    statusOverride: .thinking
                )
                syncSessionsFromStore()
            }
            return
        }

        // Fallback: match by session_id (for older bridge versions without bridgeRequestId)
        guard let sessionId = event.sessionId else { return }
        let affectedIDs = pendingBridgeResponsesByInteractionID.compactMap { interactionID, pending -> UUID? in
            guard let session = sessionStore.session(forKey: pending.sessionKey),
                  session.sessionId == sessionId else { return nil }
            return interactionID
        }

        for interactionID in affectedIDs {
            guard let pending = pendingBridgeResponsesByInteractionID[interactionID] else { continue }
            let sessionKey = pending.sessionKey
            cleanupPendingBridgeResponse(interactionID)
            guard let session = sessionStore.session(forKey: sessionKey) else { continue }
            session.resolveInteraction(
                id: interactionID,
                state: .submitted("已在终端处理"),
                taskOverride: "批准请求已在终端处理",
                statusOverride: .thinking
            )
        }
        syncSessionsFromStore()
    }

    private func handleClientDisconnect(connection: AIAgentSocketServer.ClientConnection) {
        // Clean up per-session connection tracking
        sessionSocketConnections = sessionSocketConnections.filter { $0.value != connection }

        if let interactionID = pendingBridgeResponseIDsByConnection[connection],
           let pending = cleanupPendingBridgeResponse(interactionID),
           let session = sessionStore.session(forKey: pending.sessionKey) {
            if let interaction = interaction(in: session, interactionID: interactionID),
               interaction.bridgeResponseKind == "codex_approval" {
                session.resolveInteraction(
                    id: interactionID,
                    state: .submitted("Handled in Codex"),
                    taskOverride: "Approval handled in Codex",
                    statusOverride: .thinking
                )
                syncSessionsFromStore()
                return
            }

            // Bridge disconnected without receiving a response from Vland.
            // This means the approval was handled externally (e.g. user approved
            // directly in the CLI, or the bridge process was terminated).
            // Resolve gracefully instead of showing an error.
            session.resolveInteraction(
                id: interactionID,
                state: .submitted("已在终端处理"),
                taskOverride: "批准请求已在终端处理",
                statusOverride: .idle
            )
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
            notificationCoordinator.notifyTaskProgress(session: session)
        }
    }

    private func scheduleEndedSessionRemoval(sessionKey: String) {
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  let session = self.sessionStore.session(forKey: sessionKey),
                  !session.isArchived,
                  !session.status.isActive else {
                return
            }

            _ = self.sessionStore.archiveSession(id: session.id)
            self.transcriptWatcher.unwatch(sessionKey: sessionKey)
            if self.selectedDetailSessionID == session.id {
                self.isShowingArchivedSessions = true
            }
            self.syncSessionsFromStore()
            self.pendingSessionRemovalItems.removeValue(forKey: sessionKey)
        }
        pendingSessionRemovalItems[sessionKey] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
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
        session.lastActivity = Date()  // Move to top of active list
        if let key = sessionStore.key(forSessionID: session.id) {
            refreshTranscriptWatch(for: session, sessionKey: key)
        }
        isShowingArchivedSessions = false  // Switch back to active tab
        syncSessionsFromStore()
    }

    private func interactionMessage(in session: AIAgentSession, interactionID: UUID) -> String? {
        interaction(in: session, interactionID: interactionID)?.message
    }

    private func interaction(in session: AIAgentSession, interactionID: UUID) -> AIAgentInteraction? {
        for turn in session.conversationTurns {
            if let interaction = turn.interactions.first(where: { $0.id == interactionID }) {
                return interaction
            }
        }
        return nil
    }

    private func sessionDidReceiveInteractionIfNeeded(_ session: AIAgentSession) {
        guard session.status == .waitingInput, let interaction = session.latestPendingInteraction else { return }
        let interactionKey = "\(session.id.uuidString)-\(interaction.timestamp.timeIntervalSince1970)-\(interaction.message)"
        guard !presentedInteractionKeys.contains(interactionKey) else { return }
        presentedInteractionKeys.insert(interactionKey)

        latestInteractionPresentationID = UUID()
        AIAgentSoundEffectManager.shared.play(.waitingInput)
        notificationCoordinator.notifyWaitingInput(
            session: session,
            interaction: interaction,
            isBridge: hasPendingBridgeResponse(for: interaction.id)
        )
    }

    private func isTodoOrPlanTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        let normalized = toolName.lowercased()
        return normalized == "todo_write" || normalized == "todowrite"
            || normalized == "update_plan" || normalized == "updateplan"
            || normalized == "taskcreate"
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

    // MARK: - Full Transcript Loading

    /// Reload full transcript for a session (forces reload even if already loaded).
    func reloadFullTranscript(for session: AIAgentSession) async {
        await MainActor.run { session.isTranscriptLoaded = false }
        await loadFullTranscript(for: session)
    }

    /// Load full transcript for a session (lazy, on-demand for detailed mode).
    func loadFullTranscript(for session: AIAgentSession) async {
        guard session.agentType.supportsFullHistory else {
            await MainActor.run { session.transcriptLoadError = "Agent type does not support full history" }
            return
        }
        guard !session.isTranscriptLoaded else { return }

        let transcriptPath = session.transcriptPath
        let sessionId = session.sessionId

        #if DEBUG
        NSLog("[Vland] loadFullTranscript: agentType=\(session.agentType.rawValue), transcriptPath=\(transcriptPath ?? "nil"), sessionId=\(sessionId ?? "nil")")
        #endif

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
            #if DEBUG
            NSLog("[Vland] loadFullTranscript: loaded \(messages.count) messages")
            #endif
            await MainActor.run {
                session.fullTranscript = messages
                session.isTranscriptLoaded = true
                session.transcriptLoadError = nil
            }
        } catch {
            #if DEBUG
            NSLog("[Vland] loadFullTranscript: error=\(error.localizedDescription)")
            #endif
            await MainActor.run {
                session.transcriptLoadError = error.localizedDescription
            }
        }
    }

    // MARK: - Stale Session Cleanup

    private func startStaleSessionCleanup() {
        BackgroundTaskCoordinator.shared.register { [weak self] in
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

    /// On startup, discover running agent processes and create sessions for them.
    /// Called once after the socket server starts. This bridges the gap between
    /// Vland restarting (which wipes in-memory sessions) and the next real hook event.
    private func discoverExistingSessions() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let discovered = AIAgentSessionDiscovery.discoverRunningSessions()
            guard !discovered.isEmpty else { return }

            await MainActor.run { [discovered, weak self] in
                guard let self else { return }
                for info in discovered {
                    let event = AIAgentHookEvent(
                        source: info.agentType.rawValue,
                        hookType: "SessionStart",
                        timestamp: Date().timeIntervalSince1970,
                        sessionId: info.sessionId,
                        pid: info.pid.map(Int.init),
                        tty: nil,
                        needsResponse: false,
                        toolName: nil,
                        toolInput: nil,
                        toolInputRaw: nil,
                        filePath: nil,
                        project: info.project,
                        transcriptPath: info.transcriptPath,
                        message: "会话已恢复",
                        userPrompt: nil,
                        agentOutput: nil,
                        toolOutput: nil,
                        todoItems: nil,
                        subtasks: nil,
                        interaction: nil,
                        toolUseId: nil,
                        agentId: nil,
                        parentToolId: nil,
                        rawHookType: nil,
                        bridgeRequestId: nil,
                        contextWindow: nil,
                        contextUsed: nil,
                        model: nil
                    )

                    let result = self.eventReducer.reduce(event, in: self.sessionStore)

                    if result.wasCreated {
                        result.session.status = .thinking
                        result.session.phase = .active
                        result.session.currentTask = "会话已恢复"
                        self.refreshTranscriptWatch(for: result.session, sessionKey: result.sessionKey)
                    }
                }

                if !discovered.isEmpty {
                    self.syncSessionsFromStore()
                }
            }
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
        case .thinking, .coding, .running:
            return age <= activeSessionVisibilityTimeout
        case .waitingInput:
            // Only show in collapsed notch if there's a pending interaction (e.g., approval request)
            // If AI is just waiting for next user input (CLI idle), don't show
            guard session.latestPendingInteraction != nil else { return false }
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

    // MARK: - Hook Configuration (forwarded to AIAgentHookConfigurator)

    typealias DetectedAgent = AIAgentHookConfigurator.DetectedAgent

    /// Direct reference to hook configurator for Settings UI
    var hookConfig: AIAgentHookConfigurator { hookConfigurator }

    static let bridgePath = AIAgentHookConfigurator.bridgePath
    static var bundledBridgePath: String? { AIAgentHookConfigurator.bundledBridgePath }

    func detectInstalledAgents() { hookConfigurator.detectInstalledAgents() }
    func installBridgeScript() -> Bool { hookConfigurator.installBridgeScript() }
    func configureAgent(_ agent: DetectedAgent) -> Bool { hookConfigurator.configureAgent(agent) }
    func autoConfigureAll() { hookConfigurator.autoConfigureAll() }
}
