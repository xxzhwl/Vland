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

import Defaults
import SwiftUI

// MARK: - Breathing Halo Intensity

enum AIAgentBreathingIntensity: String, Codable, CaseIterable, Defaults.Serializable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "柔和"
        case .medium: return "中等"
        case .high: return "强烈"
        }
    }

    /// Multiplier applied to blur radius and opacity values.
    var scaleFactor: CGFloat {
        switch self {
        case .low: return 0.55
        case .medium: return 1.0
        case .high: return 1.45
        }
    }
}

// MARK: - Breathing Style

struct AIAgentBreathingStyle: Equatable {
    let color: Color
    let radiusRange: ClosedRange<CGFloat>
    let opacityRange: ClosedRange<Double>
    let period: TimeInterval
    let autoreverses: Bool
    let isLooping: Bool
    let strokeWidth: CGFloat
    let usesSweep: Bool
    let sweepArcLength: CGFloat

    static let thinking = AIAgentBreathingStyle(
        color: Color(red: 0.353, green: 0.784, blue: 0.980), // #5AC8FA
        radiusRange: 1.5...5.0,
        opacityRange: 0.12...0.35,
        period: 1.6,
        autoreverses: true,
        isLooping: true,
        strokeWidth: 1.5,
        usesSweep: true,
        sweepArcLength: 0.45
    )

    static let coding = AIAgentBreathingStyle(
        color: Color(red: 0.204, green: 0.780, blue: 0.349), // #34C759
        radiusRange: 1.5...5.0,
        opacityRange: 0.12...0.35,
        period: 1.0,
        autoreverses: true,
        isLooping: true,
        strokeWidth: 1.5,
        usesSweep: true,
        sweepArcLength: 0.35
    )

    static let waitingInput = AIAgentBreathingStyle(
        color: Color(red: 1.0, green: 0.800, blue: 0.0), // #FFCC00
        radiusRange: 2.0...7.0,
        opacityRange: 0.15...0.50,
        period: 0.6,
        autoreverses: true,
        isLooping: true,
        strokeWidth: 2.0,
        usesSweep: false,
        sweepArcLength: 0
    )

    static let completed = AIAgentBreathingStyle(
        color: Color(red: 0.188, green: 0.820, blue: 0.345), // #30D158
        radiusRange: 1.5...5.0,
        opacityRange: 0.12...0.40,
        period: 1.5,
        autoreverses: false,
        isLooping: false,
        strokeWidth: 1.5,
        usesSweep: false,
        sweepArcLength: 0
    )

    static let error = AIAgentBreathingStyle(
        color: Color(red: 1.0, green: 0.271, blue: 0.227), // #FF453A
        radiusRange: 2.0...7.0,
        opacityRange: 0.15...0.50,
        period: 0.5,
        autoreverses: true,
        isLooping: true,
        strokeWidth: 2.0,
        usesSweep: false,
        sweepArcLength: 0
    )
}

// MARK: - AIAgentStatus Breathing Extensions

extension AIAgentStatus {
    /// Whether this status should render a breathing halo at all.
    var shouldRenderBreathingHalo: Bool {
        switch self {
        case .idle, .sessionStart, .sessionEnd:
            return false
        case .thinking, .coding, .running, .waitingInput, .completed, .error:
            return true
        }
    }

    /// Lower = higher priority. Used for multi-session aggregation.
    var breathingPriority: Int {
        switch self {
        case .error: return 0
        case .waitingInput: return 1
        case .thinking: return 2
        case .coding, .running: return 3
        case .completed: return 4
        case .idle, .sessionStart, .sessionEnd: return 99
        }
    }

    /// The visual breathing style mapped from this status.
    var breathingStyle: AIAgentBreathingStyle {
        switch self {
        case .thinking:
            return .thinking
        case .coding, .running:
            return .coding
        case .waitingInput:
            return .waitingInput
        case .completed:
            return .completed
        case .error:
            return .error
        case .idle, .sessionStart, .sessionEnd:
            // Should not be reached when shouldRenderBreathingHalo is checked.
            // Return a safe default.
            return .thinking
        }
    }
}
