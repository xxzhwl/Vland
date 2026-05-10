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

// MARK: - NotchStockView

struct NotchStockView: View {
    @StateObject private var stockManager = StockManager.shared
    @Default(.stockWatchlist) var stockWatchlist
    @Default(.stockColorTheme) var stockColorTheme
    @Default(.stockDisplayCurrency) var stockDisplayCurrency

    @State private var isSortByChange = false
    @State private var chartStock: Stock?
    @State private var selectedMarket: Market? = nil

    /// 分组数据
    private var groupedStocks: [(Market, [Stock])] {
        var result: [(Market, [Stock])] = []
        for market in [Market.aStock, .hkStock, .usStock] {
            let stocks = stockWatchlist.filter { $0.market == market }
            let sorted = isSortByChange ? sorted(stocks) : stocks
            if !sorted.isEmpty {
                result.append((market, sorted))
            }
        }
        return result
    }

    private func sorted(_ stocks: [Stock]) -> [Stock] {
        let rule = Defaults[.stockSortRule]
        return stocks.sorted { a, b in
            let va = sortValue(stock: a)
            let vb = sortValue(stock: b)
            return rule == "changeDesc" ? va > vb : va < vb
        }
    }

    private func sortValue(stock: Stock) -> Double {
        guard let q = stockManager.quotes[stock.id] else { return -Double.infinity }
        return q.changePercent
    }

    /// 最高盈利股票
    private var topGainerId: String? {
        let stocks = stockWatchlist.filter { $0.holdingShares != nil && stockManager.quotes[$0.id] != nil }
        let pnls = stocks.compactMap { s -> (String, Double)? in
            guard let q = stockManager.quotes[s.id],
                  let pnl = s.pnl(quote: q) else { return nil }
            return (s.id, pnl)
        }
        guard !pnls.isEmpty else { return nil }
        let best = pnls.max(by: { $0.1 < $1.1 })!
        guard best.1 > 0 else { return nil }
        return best.0
    }

    /// 最高亏损股票
    private var topLoserId: String? {
        let stocks = stockWatchlist.filter { $0.holdingShares != nil && stockManager.quotes[$0.id] != nil }
        let pnls = stocks.compactMap { s -> (String, Double)? in
            guard let q = stockManager.quotes[s.id],
                  let pnl = s.pnl(quote: q) else { return nil }
            return (s.id, pnl)
        }
        guard !pnls.isEmpty else { return nil }
        let worst = pnls.min(by: { $0.1 < $1.1 })!
        guard worst.1 < 0 else { return nil }
        return worst.0
    }

    /// 按选定市场过滤后的分组
    private var filteredStocks: [(Market, [Stock])] {
        guard let market = selectedMarket else { return groupedStocks }
        return groupedStocks.filter { $0.0 == market }
    }

    var body: some View {
        Group {
        if let stock = chartStock {
            StockKLineChartView(stock: stock, onBack: { chartStock = nil })
        } else {
            VStack(alignment: .leading, spacing: 6) {
            // 盈亏汇总
            StockProfitSummaryView()

            if !stockWatchlist.isEmpty {
                // 市场标签页
                Picker("市场", selection: $selectedMarket) {
                    Text("全部").tag(nil as Market?)
                    Text("A股").tag(Market.aStock)
                    Text("港股").tag(Market.hkStock)
                    Text("美股").tag(Market.usStock)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
            }

            if stockWatchlist.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("暂无股票")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("请在设置中添加自选股票")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(filteredStocks.enumerated()), id: \.offset) { _, group in
                            StockGroupHeaderView(market: group.0, count: group.1.count, isOpen: StockManager.isMarketOpen(group.0))
                            ForEach(group.1) { stock in
                                StockListItemView(
                                    stock: stock,
                                    quote: stockManager.quotes[stock.id],
                                    trend: stockManager.trends[stock.id],
                                    isTopGainer: stock.id == topGainerId,
                                    isTopLoser: stock.id == topLoserId
                                )
                                .onTapGesture {
                                    chartStock = stock
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollIndicators(.never)
            }

            Divider()

            // 底部工具栏
            HStack {
                Button {
                    stockManager.forceRefresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(stockManager.isLoading)

                Spacer()

                Button {
                    isSortByChange.toggle()
                } label: {
                    Label("排序", systemImage: isSortByChange ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            }
            .padding(.vertical, 8)
        }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - StockGroupHeaderView

struct StockGroupHeaderView: View {
    let market: Market
    let count: Int
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOpen ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(market.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text("(\(count))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(isOpen ? "交易中" : "已闭市")
                .font(.system(size: 8))
                .foregroundColor(isOpen ? .green : .secondary)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
