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

// MARK: - StockProfitSummaryView

struct StockProfitSummaryView: View {
    @StateObject private var stockManager = StockManager.shared
    @Default(.stockDisplayCurrency) var stockDisplayCurrency

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        if stockManager.hasPnLData {
            VStack(alignment: .leading, spacing: 4) {
                // 头部：标题 + 更新时间
                HStack {
                    Text("持仓盈亏")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        if let t = stockManager.lastUpdateTime {
                            Text("\(Self.timeFmt.string(from: t))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        if stockManager.hasError {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                        if stockManager.periodPnLIsLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        }
                    }
                }

                // 盈亏行：日盈亏 / 月盈亏 / 年盈亏
                HStack(spacing: 0) {
                    pnlCell(label: "日", value: stockManager.totalDailyPnL, pct: stockManager.totalDailyPnLPercent)
                    Spacer()
                    pnlCell(label: "月", value: stockManager.monthlyPnL, pct: stockManager.monthlyPnLPercent)
                    Spacer()
                    pnlCell(label: "年", value: stockManager.yearlyPnL, pct: stockManager.yearlyPnLPercent)
                }

                // 浮盈亏
                HStack(spacing: 0) {
                    let sym = stockDisplayCurrency.symbol
                    let pnl = stockManager.totalPnL
                    let pct = stockManager.totalPnLPercent
                    Text("浮盈 \(pnl >= 0 ? "+" : "")\(sym)\(String(format: "%.2f", pnl))  (\(String(format: "%.2f%%", pct)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(color(for: pnl))
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .onAppear {
                Task { @MainActor in
                    await stockManager.refreshPeriodPnL()
                }
            }
        }
    }

    @ViewBuilder
    private func pnlCell(label: String, value: Double, pct: Double) -> some View {
        let sign = value >= 0 ? "+" : "-"
        let sym = stockDisplayCurrency.symbol
        VStack(spacing: 0) {
            Text("\(label)盈亏")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text("\(sign)\(sym)\(String(format: "%.2f", abs(value)))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color(for: value))
            Text("\(String(format: "%.2f%%", pct))")
                .font(.system(size: 9))
                .foregroundColor(color(for: value).opacity(0.7))
        }
    }

    private func color(for value: Double) -> Color {
        let theme = Defaults[.stockColorTheme]
        switch theme {
        case .chinese: return value > 0 ? .red : (value < 0 ? .green : .secondary)
        case .western: return value > 0 ? .green : (value < 0 ? .red : .secondary)
        }
    }
}
