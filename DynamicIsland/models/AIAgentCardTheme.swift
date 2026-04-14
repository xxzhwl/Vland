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
import Foundation
import SwiftUI

// MARK: - Card Font Design

enum CardFontDesign: String, Codable, CaseIterable, Defaults.Serializable {
    case `default`
    case monospaced
    case rounded
    case serif

    var fontDesign: Font.Design {
        switch self {
        case .default: return .default
        case .monospaced: return .monospaced
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }
}

// MARK: - Theme Mode

enum AIAgentThemeMode: String, Codable, CaseIterable, Defaults.Serializable {
    case perAgent
    case uniform
}

// MARK: - AIAgentCardTheme (all fields optional/nil = use default)

struct AIAgentCardTheme: Codable, Defaults.Serializable {
    var cardBackgroundOpacity: Double?
    var cardBorderOpacity: Double?
    var textPrimaryOpacity: Double?
    var textSecondaryOpacity: Double?
    var textTertiaryOpacity: Double?
    var fontDesign: CardFontDesign?
    var cardCornerRadius: CGFloat?
    var cardPaddingH: CGFloat?
    var cardPaddingV: CGFloat?
    var innerSpacing: CGFloat?
    var sectionSpacing: CGFloat?
    var interactionBackgroundOpacity: Double?
    var interactionBorderOpacity: Double?
    var optionCornerRadius: CGFloat?
    var progressBarHeight: CGFloat?
    var progressBarCornerRadius: CGFloat?
    var progressBarBackgroundOpacity: Double?

    // MARK: - 6 Presets

    static let defaultTheme = AIAgentCardTheme()

    static let minimal = AIAgentCardTheme(
        cardBackgroundOpacity: 0.03,
        cardBorderOpacity: 0.12,
        textPrimaryOpacity: 0.85,
        textSecondaryOpacity: 0.55,
        textTertiaryOpacity: 0.3,
        fontDesign: .default,
        cardCornerRadius: 8,
        cardPaddingH: 8,
        cardPaddingV: 6,
        innerSpacing: 3,
        sectionSpacing: 4,
        interactionBackgroundOpacity: 0.03,
        interactionBorderOpacity: 0.08,
        optionCornerRadius: 4,
        progressBarHeight: 3,
        progressBarCornerRadius: 1.5,
        progressBarBackgroundOpacity: 0.08
    )

    static let vivid = AIAgentCardTheme(
        cardBackgroundOpacity: 0.12,
        cardBorderOpacity: 0.5,
        textPrimaryOpacity: 1.0,
        textSecondaryOpacity: 0.9,
        textTertiaryOpacity: 0.6,
        fontDesign: .default,
        cardCornerRadius: 14,
        cardPaddingH: 14,
        cardPaddingV: 10,
        innerSpacing: 6,
        sectionSpacing: 8,
        interactionBackgroundOpacity: 0.12,
        interactionBorderOpacity: 0.3,
        optionCornerRadius: 8,
        progressBarHeight: 6,
        progressBarCornerRadius: 3,
        progressBarBackgroundOpacity: 0.2
    )

    static let monochrome = AIAgentCardTheme(
        cardBackgroundOpacity: 0.05,
        cardBorderOpacity: 0.2,
        textPrimaryOpacity: 0.85,
        textSecondaryOpacity: 0.6,
        textTertiaryOpacity: 0.35,
        fontDesign: .monospaced,
        cardCornerRadius: 6,
        cardPaddingH: 10,
        cardPaddingV: 8,
        innerSpacing: 4,
        sectionSpacing: 6,
        interactionBackgroundOpacity: 0.05,
        interactionBorderOpacity: 0.12,
        optionCornerRadius: 4,
        progressBarHeight: 4,
        progressBarCornerRadius: 2,
        progressBarBackgroundOpacity: 0.1
    )

    static let neon = AIAgentCardTheme(
        cardBackgroundOpacity: 0.08,
        cardBorderOpacity: 0.7,
        textPrimaryOpacity: 0.95,
        textSecondaryOpacity: 0.8,
        textTertiaryOpacity: 0.5,
        fontDesign: .default,
        cardCornerRadius: 12,
        cardPaddingH: 12,
        cardPaddingV: 9,
        innerSpacing: 5,
        sectionSpacing: 7,
        interactionBackgroundOpacity: 0.08,
        interactionBorderOpacity: 0.25,
        optionCornerRadius: 7,
        progressBarHeight: 5,
        progressBarCornerRadius: 2.5,
        progressBarBackgroundOpacity: 0.15
    )

    static let terminal = AIAgentCardTheme(
        cardBackgroundOpacity: 0.02,
        cardBorderOpacity: 0.15,
        textPrimaryOpacity: 0.9,
        textSecondaryOpacity: 0.7,
        textTertiaryOpacity: 0.4,
        fontDesign: .monospaced,
        cardCornerRadius: 4,
        cardPaddingH: 8,
        cardPaddingV: 6,
        innerSpacing: 3,
        sectionSpacing: 5,
        interactionBackgroundOpacity: 0.02,
        interactionBorderOpacity: 0.1,
        optionCornerRadius: 3,
        progressBarHeight: 3,
        progressBarCornerRadius: 1,
        progressBarBackgroundOpacity: 0.06
    )
}

// MARK: - ResolvedCardTheme (all non-nil)

struct ResolvedCardTheme {
    let cardBackgroundOpacity: Double
    let cardBorderOpacity: Double
    let textPrimaryOpacity: Double
    let textSecondaryOpacity: Double
    let textTertiaryOpacity: Double
    let fontDesign: CardFontDesign
    let cardCornerRadius: CGFloat
    let cardPaddingH: CGFloat
    let cardPaddingV: CGFloat
    let innerSpacing: CGFloat
    let sectionSpacing: CGFloat
    let interactionBackgroundOpacity: Double
    let interactionBorderOpacity: Double
    let optionCornerRadius: CGFloat
    let progressBarHeight: CGFloat
    let progressBarCornerRadius: CGFloat
    let progressBarBackgroundOpacity: Double

    init(from theme: AIAgentCardTheme) {
        cardBackgroundOpacity = theme.cardBackgroundOpacity ?? 0.06
        cardBorderOpacity = theme.cardBorderOpacity ?? 0.25
        textPrimaryOpacity = theme.textPrimaryOpacity ?? 0.9
        textSecondaryOpacity = theme.textSecondaryOpacity ?? 0.7
        textTertiaryOpacity = theme.textTertiaryOpacity ?? 0.4
        fontDesign = theme.fontDesign ?? .default
        cardCornerRadius = theme.cardCornerRadius ?? 10
        cardPaddingH = theme.cardPaddingH ?? 10
        cardPaddingV = theme.cardPaddingV ?? 8
        innerSpacing = theme.innerSpacing ?? 4
        sectionSpacing = theme.sectionSpacing ?? 6
        interactionBackgroundOpacity = theme.interactionBackgroundOpacity ?? 0.06
        interactionBorderOpacity = theme.interactionBorderOpacity ?? 0.15
        optionCornerRadius = theme.optionCornerRadius ?? 6
        progressBarHeight = theme.progressBarHeight ?? 4
        progressBarCornerRadius = theme.progressBarCornerRadius ?? 2
        progressBarBackgroundOpacity = theme.progressBarBackgroundOpacity ?? 0.12
    }

    static let `default` = ResolvedCardTheme(from: .defaultTheme)
}
