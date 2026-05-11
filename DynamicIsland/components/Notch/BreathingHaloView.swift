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

// MARK: - NotchBottomContour

/// A shape that traces only the bottom U-contour of a notch:
/// left short wall → left bottom quad curve → flat bottom → right bottom quad curve → right short wall.
/// Used by BreathingHaloView in non-island (physical notch) mode to draw the bottom edge bar
/// and contour shimmer without covering the top "ears" that are obscured by the screen notch.
struct NotchBottomContour: Shape {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let sideWallExtension: CGFloat

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, sideWallExtension: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.sideWallExtension = sideWallExtension
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at the left side, just above the bottom-left curve
        let leftWallEndY = rect.maxY - bottomCornerRadius
        let leftWallStartY = leftWallEndY - sideWallExtension

        // Left short wall going down
        path.move(to: CGPoint(x: rect.minX + topCornerRadius, y: leftWallStartY))
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: leftWallEndY))

        // Bottom-left quad curve
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Flat bottom
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right quad curve
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right short wall going up
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: leftWallStartY))

        return path
    }
}

// MARK: - Breathing Halo View

/// A status-aware breathing halo rendered around the closed notch / Dynamic Island pill.
///
/// ## Layers (bottom to top)
/// 1. **Outer glow** — filled shape matching the clip contour, blurred to simulate light spill
/// 2. **Inner stroke pulse** — a stroked outline hugging the contour edge, `plusLighter` blend
/// 3. **Bottom contour bar & shimmer** — a thicker bar on the bottom U (notch) or full perimeter (pill)
///    plus a moving highlight segment (shimmer) that cycles along the contour
struct BreathingHaloView: View {
    let shape: AnyShape
    var notchSize: CGSize?
    let isIslandMode: Bool
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let pillCornerRadius: CGFloat

    @Default(.aiAgentBreathingHaloEnabled) private var breathingHaloEnabled
    @Default(.aiAgentBreathingHaloIntensity) private var breathingHaloIntensity

    @ObservedObject private var aiAgentManager = AIAgentManager.shared

    @State private var isAtMax: Bool = false
    @State private var oneShotPlayed: Bool = false
    @State private var lastStatus: AIAgentStatus?
    @State private var sweepPhase: CGFloat = 0

    private let sideWallExtensionRatio: CGFloat = 0.35

    init(
        shape: AnyShape,
        notchSize: CGSize? = nil,
        isIslandMode: Bool,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        pillCornerRadius: CGFloat
    ) {
        self.shape = shape
        self.notchSize = notchSize
        self.isIslandMode = isIslandMode
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.pillCornerRadius = pillCornerRadius
    }

    var body: some View {
        let status = aiAgentManager.dominantBreathingStatus
        let isEnabled = breathingHaloEnabled && status?.shouldRenderBreathingHalo == true

        Group {
            if isEnabled, let status {
                if let size = notchSize {
                    halo(for: status, style: status.breathingStyle, size: size)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                } else {
                    GeometryReader { geo in
                        halo(for: status, style: status.breathingStyle, size: geo.size)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
        }
        .onAppear {
            guard let status = aiAgentManager.dominantBreathingStatus, isEnabled else { return }
            restartAnimation(for: status, style: status.breathingStyle)
        }
        .onChange(of: aiAgentManager.dominantBreathingStatus?.rawValue) { _, _ in
            guard let status = aiAgentManager.dominantBreathingStatus, isEnabled else { return }
            restartAnimation(for: status, style: status.breathingStyle)
        }
    }

    // MARK: - Halo Layers

    @ViewBuilder
    private func halo(for status: AIAgentStatus, style: AIAgentBreathingStyle, size: CGSize) -> some View {
        let intensity = breathingHaloIntensity.scaleFactor
        let opacity = currentOpacity(for: style)
        let radius = currentRadius(for: style) * intensity
        let strokeOpacity = style == .completed ? opacity : min(opacity * 1.6, 0.55)

        ZStack {
            // Layer 1: Outer glow
            shape.fill(style.color)
                .frame(width: size.width, height: size.height)
                .opacity(opacity * intensity)
                .blur(radius: radius)
                .scaleEffect(isIslandMode ? 1.0 : 0.98)

            // Layer 2: Inner stroke pulse
            shape.stroke(style.color.opacity(strokeOpacity), lineWidth: style.strokeWidth)
                .frame(width: size.width, height: size.height)
                .blendMode(.plusLighter)

            // Layer 3: Bottom edge bar + sweep highlight
            bottomEdgeBar(style: style, baseStrokeWidth: style.strokeWidth, breathOpacity: opacity, size: size)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Bottom Edge Bar / Contour

    @ViewBuilder
    private func bottomEdgeBar(
        style: AIAgentBreathingStyle,
        baseStrokeWidth: CGFloat,
        breathOpacity: CGFloat,
        size: CGSize
    ) -> some View {
        if isIslandMode {
            let pill = DynamicIslandPillShape(cornerRadius: max(0, min(pillCornerRadius, min(size.width, size.height) / 2)))
            edgeBarBody(shape: pill, style: style, baseStrokeWidth: baseStrokeWidth, breathOpacity: breathOpacity, size: size)
            contourShimmer(shape: pill, style: style, size: size)
        } else {
            let sideWallExt = bottomCornerRadius * sideWallExtensionRatio
            let contour = NotchBottomContour(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius, sideWallExtension: sideWallExt)
            edgeBarBody(shape: contour, style: style, baseStrokeWidth: baseStrokeWidth, breathOpacity: breathOpacity, size: size)
            contourShimmer(shape: contour, style: style, size: size)
        }
    }

    // MARK: - Generic Edge Bar Body

    @ViewBuilder
    private func edgeBarBody<S: Shape>(
        shape: S,
        style: AIAgentBreathingStyle,
        baseStrokeWidth: CGFloat,
        breathOpacity: CGFloat,
        size: CGSize
    ) -> some View {
        let barThickness: CGFloat = isIslandMode ? 2.4 : 2.8
        let strokeStyle = StrokeStyle(lineWidth: barThickness, lineCap: .round, lineJoin: .round)

        let barColor = style.color.opacity(
            style == .completed
                ? breathOpacity * 0.7
                : min(breathOpacity * 1.8, 0.5)
        )
        shape
            .stroke(barColor, style: strokeStyle)
            .frame(width: size.width, height: size.height)
            .blendMode(.plusLighter)
    }

    // MARK: - Generic Contour Shimmer (Sweep Highlight)

    @ViewBuilder
    private func contourShimmer<S: Shape>(
        shape: S,
        style: AIAgentBreathingStyle,
        size: CGSize
    ) -> some View {
        if style.usesSweep {
            let barThickness: CGFloat = isIslandMode ? 2.4 : 2.8
            let shimmerWidth: CGFloat = barThickness + 0.6

            let halfArc = style.sweepArcLength / 2
            let lo = sweepPhase - halfArc
            let hi = sweepPhase + halfArc
            let segments = trimRanges(lo: lo, hi: hi)

            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                shape
                    .trim(from: segment.from, to: segment.to)
                    .stroke(
                        style.color.opacity(0.85),
                        style: StrokeStyle(lineWidth: shimmerWidth, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: size.width, height: size.height)
                    .blendMode(.plusLighter)
                    .blur(radius: 0.6)
            }
        }
    }

    // MARK: - Trim Ranges (Cross-boundary split)

    /// Splits a trim window `[lo, hi)` into 1–2 segments that stay within `[0, 1]`.
    /// Handles the case where the window crosses the path start/end point.
    private func trimRanges(lo: CGFloat, hi: CGFloat) -> [(from: CGFloat, to: CGFloat)] {
        if lo >= 0, hi <= 1 { return [(lo, hi)] }
        if lo < 0, hi <= 1 { return [(max(0, 1 + lo), 1), (0, max(0, hi))] }
        if lo >= 0, hi > 1 { return [(lo, 1), (0, min(1, hi - 1))] }
        return [(0, 1)]
    }

    // MARK: - Animation Helpers

    private var resolvedStatus: AIAgentStatus? {
        aiAgentManager.dominantBreathingStatus
    }

    private func restartAnimation(for status: AIAgentStatus, style: AIAgentBreathingStyle) {
        // Reset state for clean transition
        isAtMax = false
        oneShotPlayed = false
        sweepPhase = 0
        lastStatus = status

        if style.isLooping {
            withAnimation(.easeInOut(duration: style.period / 2).repeatForever(autoreverses: style.autoreverses)) {
                isAtMax = true
            }
        } else {
            // One-shot: animate to peak, hold, then fade out
            withAnimation(.easeInOut(duration: style.period * 0.3)) {
                isAtMax = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + style.period * 0.6) {
                withAnimation(.easeInOut(duration: style.period * 0.4)) {
                    isAtMax = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + style.period * 0.4 + 0.05) {
                    oneShotPlayed = true
                }
            }
        }

        // Sweep animation
        if style.usesSweep {
            withAnimation(.easeInOut(duration: max(0.3, style.period)).repeatForever(autoreverses: true)) {
                sweepPhase = 1.0
            }
        }
    }

    private func currentOpacity(for style: AIAgentBreathingStyle) -> CGFloat {
        if !style.isLooping, oneShotPlayed { return 0 }
        return isAtMax ? style.opacityRange.upperBound : style.opacityRange.lowerBound
    }

    private func currentRadius(for style: AIAgentBreathingStyle) -> CGFloat {
        return isAtMax ? style.radiusRange.upperBound : style.radiusRange.lowerBound
    }
}

// MARK: - Previews

#Preview("Notch Mode - Thinking") {
    BreathingHaloView(
        shape: AnyShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)),
        notchSize: CGSize(width: 200, height: 32),
        isIslandMode: false,
        topCornerRadius: 6,
        bottomCornerRadius: 14,
        pillCornerRadius: 16
    )
    .padding(20)
    .background(Color.gray.opacity(0.2))
}

#Preview("Pill Mode - Thinking") {
    BreathingHaloView(
        shape: AnyShape(DynamicIslandPillShape(cornerRadius: 16)),
        notchSize: CGSize(width: 185, height: 32),
        isIslandMode: true,
        topCornerRadius: 6,
        bottomCornerRadius: 14,
        pillCornerRadius: 16
    )
    .padding(20)
    .background(Color.gray.opacity(0.2))
}
