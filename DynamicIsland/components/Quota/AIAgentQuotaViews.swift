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

import SwiftUI

struct QuotaRingBadge: View {
    let window: QuotaWindow
    let style: AIAgentCardStyle
    let fallbackTint: Color

    private var tint: Color {
        window.severity == .healthy ? fallbackTint : window.severity.tint
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.4)

            if window.isStale {
                Circle()
                    .trim(from: 0.05, to: 0.95)
                    .stroke(Color.gray.opacity(0.45), style: .init(lineWidth: 1.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Rectangle()
                    .fill(Color.gray.opacity(0.65))
                    .frame(width: 1.3, height: style.scaled(8))
                    .rotationEffect(.degrees(45))
            } else {
                Circle()
                    .trim(from: 0, to: max(0.02, window.remainingFraction))
                    .stroke(tint, style: .init(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            if window.severity == .critical && !window.isStale {
                Image(systemName: "exclamationmark")
                    .font(.system(size: style.scaled(5.5), weight: .bold))
                    .foregroundStyle(.red)
            } else {
                Circle()
                    .fill((window.isStale ? Color.gray : tint).opacity(0.9))
                    .frame(width: style.scaled(3), height: style.scaled(3))
            }
        }
        .frame(width: style.scaled(12), height: style.scaled(12))
        .help(tooltipText)
    }

    private var tooltipText: String {
        var parts = [window.displayLabel, window.remainingDisplayText]
        if let reset = window.resetRelativeText {
            parts.append("重置 \(reset)")
        }
        if let detail = window.sourceDetail {
            parts.append(detail)
        }
        if window.isStale {
            parts.append("数据已超过 15 分钟未刷新")
        }
        return parts.joined(separator: " · ")
    }
}

struct QuotaInlineBar: View {
    let snapshot: QuotaSnapshot
    let style: AIAgentCardStyle
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.windows.isEmpty {
                Text(message)
                    .font(.system(size: style.scaled(9.5)))
                    .foregroundStyle(.gray.opacity(0.7))
            } else {
                ForEach(snapshot.windows.prefix(2)) { window in
                    row(for: window)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private func row(for window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(window.displayLabel)
                    .font(.system(size: style.scaled(9), weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: style.scaled(26), alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))

                        Capsule()
                            .fill(progressTint(for: window))
                            .frame(width: geometry.size.width * CGFloat(window.remainingFraction))
                    }
                }
                .frame(height: 5)

                Text(window.remainingDisplayText)
                    .font(.system(size: style.scaled(8.5), weight: .medium, design: .monospaced))
                    .foregroundStyle(progressTint(for: window).opacity(0.92))
                    .frame(width: style.scaled(52), alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text(window.usedDisplayText)
                    .font(.system(size: style.scaled(8.5)))
                    .foregroundStyle(.gray.opacity(0.7))

                if let reset = window.resetRelativeText {
                    Text("· 重置 \(reset)")
                        .font(.system(size: style.scaled(8.5)))
                        .foregroundStyle(.gray.opacity(0.7))
                }

                if window.isStale {
                    Text("· 等待刷新")
                        .font(.system(size: style.scaled(8.5)))
                        .foregroundStyle(.gray.opacity(0.7))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func progressTint(for window: QuotaWindow) -> Color {
        window.severity == .healthy ? accentColor : window.severity.tint
    }

    private var message: String {
        switch snapshot.probeState {
        case .notConfigured:
            return "尚未发现可读取的额度数据源"
        case .stale:
            return "最近额度数据超过 15 分钟未刷新"
        case .unavailable:
            return "暂时没有可展示的额度数据"
        case .available:
            return "额度数据可用"
        }
    }
}
