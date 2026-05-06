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

struct QuotaAggregator {
    func merge(_ snapshots: [QuotaSnapshot], for agent: AIAgentType) -> QuotaSnapshot {
        guard !snapshots.isEmpty else {
            return QuotaSnapshot(
                agent: agent,
                windows: [],
                probeState: .unavailable,
                updatedAt: nil,
                sourceDescription: nil
            )
        }

        let grouped = Dictionary(grouping: snapshots.flatMap(\.windows), by: \.kind)
        let mergedWindows = grouped.values.compactMap { windows in
            windows.max(by: { $0.updatedAt < $1.updatedAt })
        }
        .sorted { lhs, rhs in
            if lhs.kind.sortOrder != rhs.kind.sortOrder {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let probeState: QuotaProbeState
        if !mergedWindows.isEmpty {
            probeState = mergedWindows.contains(where: { !$0.isStale }) ? .available : .stale
        } else if snapshots.contains(where: { $0.probeState == .notConfigured }) {
            probeState = .notConfigured
        } else if snapshots.contains(where: { $0.probeState == .stale }) {
            probeState = .stale
        } else {
            probeState = .unavailable
        }

        let latestSnapshot = snapshots.compactMap { snapshot -> (Date, String?)? in
            guard let updatedAt = snapshot.updatedAt else { return nil }
            return (updatedAt, snapshot.sourceDescription)
        }.max(by: { $0.0 < $1.0 })

        return QuotaSnapshot(
            agent: agent,
            windows: mergedWindows,
            probeState: probeState,
            updatedAt: latestSnapshot?.0,
            sourceDescription: latestSnapshot?.1
        )
    }
}

