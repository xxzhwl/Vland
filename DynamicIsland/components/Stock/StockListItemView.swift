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

            // 中间：日内趋势 sparkline — 始终占位，占满剩余区域
            Group {
                if let trend = trend, trend.count >= 2 {
                    MiniTrendView(prices: trend.map(\.price), color: trendColor(isUp: quote?.isUp ?? true))
                } else {
                    Color.clear
                }
            }
            .frame(height: 16)

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

/// Small sparkline showing intraday price trend
struct MiniTrendView: View {
    let prices: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minP = prices.min() ?? 0
            let maxP = prices.max() ?? 1
            let range = max(maxP - minP, 0.01)
            let count = prices.count

            Path { path in
                for (i, p) in prices.enumerated() {
                    let x = count > 1 ? CGFloat(i) / CGFloat(count - 1) * w : w / 2
                    let y = h - CGFloat((p - minP) / range) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, lineWidth: 1)
        }
    }
}
