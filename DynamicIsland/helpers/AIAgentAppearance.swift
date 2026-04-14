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
import Defaults
import Foundation
import SwiftUI

struct AIAgentCardStyle {
    let fontScale: CGFloat
    let expandedContentMaxHeight: CGFloat
    let theme: ResolvedCardTheme

    func scaled(_ size: CGFloat) -> CGFloat {
        size * fontScale
    }

    /// Returns the accent color for an agent type, respecting theme mode
    func accentColor(for agentType: AIAgentType) -> Color {
        switch Defaults[.aiAgentThemeMode] {
        case .perAgent:
            return agentType.accentColor
        case .uniform:
            return Defaults[.aiAgentUniformAccentColor]
        }
    }

    static var current: AIAgentCardStyle {
        let saved = Defaults[.aiAgentCardTheme]
        return AIAgentCardStyle(
            fontScale: CGFloat(Defaults[.aiAgentCardFontScale]),
            expandedContentMaxHeight: CGFloat(Defaults[.aiAgentCardExpandedMaxHeight]),
            theme: ResolvedCardTheme(from: saved)
        )
    }
}

enum AIAgentIconResolver {
    static func selectedCustomIcon(for agentType: AIAgentType) -> CustomAppIcon? {
        let selections = Defaults[.aiAgentIconSelections]
        guard let selectedID = selections[agentType.rawValue] else { return nil }
        return Defaults[.customAppIcons].first(where: { $0.id.uuidString == selectedID })
    }

    static func image(for agentType: AIAgentType) -> NSImage? {
        if let customIcon = selectedCustomIcon(for: agentType),
           let image = NSImage(contentsOf: customIcon.fileURL) {
            return image
        }

        for bundleIdentifier in agentType.bundleIdentifiers {
            if let image = AppIconAsNSImage(for: bundleIdentifier) {
                return image
            }
        }

        return nil
    }
}
