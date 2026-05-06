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
import SwiftUI

enum QuotaWindowKind: String, Codable, CaseIterable {
    case fiveHour
    case weekly
    case rateLimit
    case apiBalance

    var sortOrder: Int {
        switch self {
        case .fiveHour:
            return 0
        case .weekly:
            return 1
        case .rateLimit:
            return 2
        case .apiBalance:
            return 3
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "7d"
        case .rateLimit:
            return "速率"
        case .apiBalance:
            return "余额"
        }
    }
}

enum QuotaProbeState: String, Codable {
    case available
    case stale
    case unavailable
    case notConfigured
}

enum QuotaSeverity {
    case healthy
    case caution
    case warning
    case critical
    case stale

    var tint: Color {
        switch self {
        case .healthy:
            return .green
        case .caution:
            return .yellow
        case .warning:
            return .orange
        case .critical:
            return .red
        case .stale:
            return .gray.opacity(0.55)
        }
    }
}

struct QuotaWindow: Codable, Identifiable, Equatable {
    let id: String
    let agent: AIAgentType
    let kind: QuotaWindowKind
    let usedPercent: Double
    let resetsAt: Date?
    let windowDescription: String?
    let updatedAt: Date
    let source: String
    let sourceDetail: String?

    var clampedUsedPercent: Double {
        min(max(usedPercent, 0), 100)
    }

    var remainingPercent: Double {
        max(0, 100 - clampedUsedPercent)
    }

    var remainingFraction: Double {
        remainingPercent / 100
    }

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 15 * 60
    }

    var severity: QuotaSeverity {
        guard !isStale else { return .stale }
        switch remainingPercent {
        case ..<5:
            return .critical
        case ..<15:
            return .warning
        case ..<35:
            return .caution
        default:
            return .healthy
        }
    }

    var displayLabel: String {
        windowDescription ?? kind.shortLabel
    }

    var remainingDisplayText: String {
        "余量 \(Int(remainingPercent.rounded()))%"
    }

    var usedDisplayText: String {
        "已用 \(Int(clampedUsedPercent.rounded()))%"
    }

    var resetRelativeText: String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return "即将重置" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: remaining)
    }
}

struct QuotaSnapshot: Equatable {
    let agent: AIAgentType
    let windows: [QuotaWindow]
    let probeState: QuotaProbeState
    let updatedAt: Date?
    let sourceDescription: String?

    var primaryWindow: QuotaWindow? {
        windows.sorted {
            if $0.kind.sortOrder != $1.kind.sortOrder {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.updatedAt > $1.updatedAt
        }.first
    }

    var freshestWindow: QuotaWindow? {
        windows.max(by: { $0.updatedAt < $1.updatedAt })
    }

    var hasFreshData: Bool {
        windows.contains(where: { !$0.isStale })
    }
}

