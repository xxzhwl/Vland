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

// MARK: - StockIdleDisplayView

/// 空闲态时在灵动岛上轮播显示自选股票行情
/// 布局在灵动岛摄像头两侧：左侧显示市场+名称，右侧显示价格+涨跌幅
struct StockIdleDisplayView: View {
    let cameraWidth: CGFloat

    @StateObject private var stockManager = StockManager.shared
    @Default(.stockWatchlist) var stockWatchlist
    @Default(.stockIdleDisplayInterval) var displayInterval
    @Default(.stockColorTheme) var stockColorTheme

    @State private var currentIndex = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
        if stockWatchlist.isEmpty {
            HStack(spacing: 0) {
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            HStack(spacing: 0) {
                // 左侧：市场 + 股票名称
                HStack {
                    if let stock = currentStock {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stock.market.rawValue)
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                            Text(stock.effectiveName)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 110, alignment: .leading)
                .padding(.leading, 8)

                // 中间：摄像头区域
                Rectangle().fill(.black)
                    .frame(width: cameraWidth)

                // 右侧：当前价格 + 涨跌幅
                HStack {
                    Spacer(minLength: 0)
                    if let stock = currentStock, let quote = stockManager.quotes[stock.id] {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(quote.formattedPrice)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(quoteColor(for: quote))
                            Text(quote.formattedPercent)
                                .font(.system(size: 9))
                                .foregroundColor(quoteColor(for: quote))
                        }
                    }
                }
                .frame(maxWidth: 100, alignment: .trailing)
                .padding(.trailing, 8)
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .id("\(currentStock?.id ?? "")-\(currentIndex)")
            .onAppear {
                startTimer()
                if stockManager.quotes.isEmpty {
                    Task { @MainActor in
                        await stockManager.refresh(force: true)
                    }
                }
            }
            .onDisappear {
                stopTimer()
            }
            .onChange(of: stockWatchlist.count) { _, _ in
                currentIndex = 0
                restartTimer()
            }
        }
        }
        .preferredColorScheme(.dark)
    }

    private var currentStock: Stock? {
        guard !stockWatchlist.isEmpty else { return nil }
        let idx = currentIndex % stockWatchlist.count
        guard idx < stockWatchlist.count else { return nil }
        return stockWatchlist[idx]
    }

    private func startTimer() {
        stopTimer()
        let interval = TimeInterval(max(displayInterval, 3))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                currentIndex = (currentIndex + 1) % max(stockWatchlist.count, 1)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        startTimer()
    }

    private func quoteColor(for quote: Quote) -> Color {
        switch stockColorTheme {
        case .chinese: return quote.isUp ? .red : (quote.isDown ? .green : .secondary)
        case .western: return quote.isUp ? .green : (quote.isDown ? .red : .secondary)
        }
    }
}
