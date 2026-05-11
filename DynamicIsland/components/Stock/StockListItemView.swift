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
import Defaults

// MARK: - StockListItemView

struct StockListItemView: View {
    let stock: Stock
    let quote: Quote?
    let trend: [TrendPoint]?
    let isTopGainer: Bool
    let isTopLoser: Bool

    @Default(.stockColorTheme) var stockColorTheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧：市场 + 名称 + 代码
            VStack(alignment: .leading, spacing: 1) {
                Text(stock.market.rawValue)
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                HStack(spacing: 2) {
                    Text(stock.effectiveName.isEmpty ? stock.id : stock.effectiveName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if isTopGainer {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                    if isTopLoser {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                    }
                }
                Text(stock.id)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            // 中间：日内趋势 — 固定时间轴，随时间向右绘制
            Group {
                if let trend = trend, trend.count >= 2 {
                    MiniTrendView(trendPoints: trend, market: stock.market, color: trendColor(isUp: quote?.isUp ?? true))
                } else {
                    Color.clear
                }
            }
            .frame(height: 26)

            // 右侧：价格 + 涨跌幅 + 盈亏金额和盈亏率
            HStack {
                if let q = quote {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(q.formattedPrice)
                                .font(.system(size: 11, weight: .medium))
                            Text(q.formattedPercent)
                                .font(.system(size: 10))
                                .foregroundColor(quoteColor(for: q))
                        }

                        if stock.holdingShares != nil {
                            if q.isToday, let daily = stock.dailyPnl(quote: q) {
                                let dailyPct = stock.dailyPnlPercent(quote: q) ?? 0
                                Text("日\(daily >= 0 ? "+" : "")\(String(format: "%.2f", daily)) (\(String(format: "%.2f%%", dailyPct)))")
                                    .font(.system(size: 9))
                                    .foregroundColor(pnlColor(daily))
                            }
                            if let pnl = stock.pnl(quote: q) {
                                let pct = stock.pnlPercent(quote: q) ?? 0
                                Text("浮\(pnl >= 0 ? "+" : "")\(String(format: "%.2f", pnl)) (\(String(format: "%.2f%%", pct)))")
                                    .font(.system(size: 9))
                                    .foregroundColor(pnlColor(pnl))
                            }
                        } else {
                            Text("未持仓")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("--")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(4)
    }

    private func quoteColor(for quote: Quote) -> Color {
        switch stockColorTheme {
        case .chinese: return quote.isUp ? .red : (quote.isDown ? .green : .secondary)
        case .western: return quote.isUp ? .green : (quote.isDown ? .red : .secondary)
        }
    }

    private func pnlColor(_ pnl: Double) -> Color {
        switch stockColorTheme {
        case .chinese: return pnl > 0 ? .red : (pnl < 0 ? .green : .secondary)
        case .western: return pnl > 0 ? .green : (pnl < 0 ? .red : .secondary)
        }
    }

    private func trendColor(isUp: Bool) -> Color {
        switch stockColorTheme {
        case .chinese: return isUp ? .red : .green
        case .western: return isUp ? .green : .red
        }
    }
}

// MARK: - MiniTrendView

/// Sparkline with fixed time axis that draws progressively throughout the day.
/// The x-axis spans the full trading session (e.g. 09:30–15:00 for A-shares).
/// Data points appear at their actual time positions, leaving future time slots empty.
struct MiniTrendView: View {
    let trendPoints: [TrendPoint]
    let market: Market
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let config = market.tradingConfig
            let totalMin = CGFloat(config.totalMinutes)
            let labelH: CGFloat = 9
            let prices = trendPoints.map(\.price)
            let minP = prices.min() ?? 0
            let maxP = prices.max() ?? 1
            let range = max(maxP - minP, 0.01)

            ZStack(alignment: .topLeading) {
                // Line chart
                Canvas { context, size in
                    let lineH = size.height - labelH
                    var prevCumulative: Int?
                    var linePath = Path()
                    var needMove = true

                    for point in trendPoints {
                        guard let cumMin = config.cumulativeMinutes(point.time) else { continue }
                        let x = CGFloat(cumMin) / totalMin * size.width
                        let y = lineH - CGFloat((point.price - minP) / range) * lineH

                        if let prev = prevCumulative, cumMin - prev > 5 {
                            needMove = true
                        }
                        if needMove {
                            linePath.move(to: CGPoint(x: x, y: y))
                            needMove = false
                        } else {
                            linePath.addLine(to: CGPoint(x: x, y: y))
                        }
                        prevCumulative = cumMin
                    }
                    context.stroke(linePath, with: .color(color), lineWidth: 1)
                }

                // Time labels at bottom
                HStack(spacing: 0) {
                    Text(config.timeLabels.first ?? "")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(config.timeLabels.last ?? "")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .offset(y: geo.size.height - labelH + 1)
            }
        }
    }
}
