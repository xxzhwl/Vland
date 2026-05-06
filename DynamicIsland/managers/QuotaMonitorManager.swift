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

@MainActor
final class QuotaMonitorManager: ObservableObject {
    static let shared = QuotaMonitorManager()

    @Published private(set) var snapshots: [AIAgentType: QuotaSnapshot] = [:]
    @Published private(set) var tightestWindow: QuotaWindow?
    @Published private(set) var isRunning = false

    private let aggregator = QuotaAggregator()
    private var providers: [AIAgentType: [QuotaProviding]] = [:]
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        register(provider: ClaudeCodeQuotaProvider())
        register(provider: CodexQuotaProvider())
        register(provider: ClaudeVSCodeQuotaProvider())

        Defaults.publisher(.enableAIAgentFeature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.syncLifecycle(aiAgentEnabled: change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.aiAgentQuotaMonitorEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.syncLifecycle(quotaEnabled: change.newValue)
            }
            .store(in: &cancellables)

        syncLifecycle()
    }

    func refresh() {
        guard isRunning else { return }
        providers.values.flatMap { $0 }.forEach { $0.refresh() }
    }

    func snapshot(for agent: AIAgentType) -> QuotaSnapshot? {
        snapshots[agent]
    }

    private func syncLifecycle(
        aiAgentEnabled: Bool? = nil,
        quotaEnabled: Bool? = nil
    ) {
        let shouldRun = (aiAgentEnabled ?? Defaults[.enableAIAgentFeature])
            && (quotaEnabled ?? Defaults[.aiAgentQuotaMonitorEnabled])

        if shouldRun {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        providers.values.flatMap { $0 }.forEach { $0.stop() }
        snapshots.removeAll()
        tightestWindow = nil
    }

    private func register(provider: QuotaProviding) {
        providers[provider.agent, default: []].append(provider)
        provider.onChange { [weak self] _ in
            Task { @MainActor in
                self?.recompute(agent: provider.agent)
            }
        }
    }

    private func recompute(agent: AIAgentType) {
        let sourceSnapshots = providers[agent]?.compactMap { $0.currentSnapshot() } ?? []
        let merged = aggregator.merge(sourceSnapshots, for: agent)
        snapshots[agent] = merged
        tightestWindow = snapshots.values
            .flatMap(\.windows)
            .filter { !$0.isStale }
            .min(by: { $0.remainingPercent < $1.remainingPercent })
    }
}

@MainActor
extension AIAgentSession {
    var quotaSnapshot: QuotaSnapshot? {
        QuotaMonitorManager.shared.snapshot(for: agentType)
    }

    var primaryQuotaWindow: QuotaWindow? {
        quotaSnapshot?.primaryWindow
    }
}
