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

// MARK: - StockSettingsView

struct StockSettingsView: View {
    @Default(.enableStockFeature) var enableStockFeature
    @Default(.stockWatchlist) var stockWatchlist
    @Default(.stockRefreshInterval) var stockRefreshInterval
    @Default(.stockColorTheme) var stockColorTheme
    @Default(.stockDisplayCurrency) var stockDisplayCurrency
    @Default(.stockSortRule) var stockSortRule
    @Default(.stockPanelMaxHeight) var stockPanelMaxHeight
    @Default(.idleBehavior) var idleBehavior
    @Default(.enableStockIdleDisplay) var enableStockIdleDisplay
    @Default(.stockIdleDisplayInterval) var stockIdleDisplayInterval
    @Default(.showNotHumanFace) var showNotHumanFace

    @State private var searchText = ""
    @State private var searchResults = [StockSearchResult]()
    @State private var isSearching = false

    @State private var editingStock: Stock?
    @State private var editDisplayName = ""
    @State private var editCost = ""
    @State private var editShares = ""

    @State private var showSortPicker = false

    var body: some View {
        Form {
            // MARK: - 启用开关
            Section {
                Toggle("启用股票功能", isOn: $enableStockFeature)
            } footer: {
                Text("启用后在灵动岛中显示股票 Tab，可查看自选股行情和持仓盈亏")
            }

            // MARK: - 添加股票
            Section {
                HStack {
                    TextField("搜索股票代码或名称", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search() }
                    if isSearching {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Button("搜索") { search() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !searchResults.isEmpty {
                    searchResultsList
                }
            } header: {
                Text("添加股票")
            }

            // MARK: - 自选列表
            if !stockWatchlist.isEmpty {
                Section {
                    ForEach(stockWatchlist) { stock in
                        stockRow(stock)
                    }
                } header: {
                    HStack {
                        Text("自选股票")
                        Text("(\(stockWatchlist.count))")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - 通用设置
            Section {
                Picker("刷新间隔", selection: $stockRefreshInterval) {
                    Text("3 秒").tag(3)
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("30 秒").tag(30)
                }
                .onChange(of: stockRefreshInterval) { _, _ in
                    StockManager.shared.restartTimer()
                }

                Picker("涨跌颜色", selection: $stockColorTheme) {
                    ForEach(StockColorTheme.allCases, id: \.rawValue) { theme in
                        HStack {
                            Text(theme == .chinese ? "红涨" : "绿涨")
                            Text("|")
                                .foregroundColor(.secondary)
                            Text(theme == .chinese ? "绿跌" : "红跌")
                        }
                        .tag(theme)
                    }
                }

                Picker("持仓货币", selection: $stockDisplayCurrency) {
                    ForEach(DisplayCurrency.allCases, id: \.rawValue) { c in
                        Text(c.displayName).tag(c)
                    }
                }

                Picker("排序规则", selection: $stockSortRule) {
                    Text("涨跌幅降序").tag("changeDesc")
                    Text("涨跌幅升序").tag("changeAsc")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $stockPanelMaxHeight, in: 150...600, step: 10) {
                        Text("面板高度")
                    }
                    Text("当前：\(Int(stockPanelMaxHeight)) px")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("通用设置")
            }

            // MARK: - 空闲行为
            Section {
                Picker("空闲时显示", selection: $idleBehavior) {
                    Text("动画").tag(IdleBehavior.animation)
                    Text("股票信息").tag(IdleBehavior.stockCarousel)
                    Text("无").tag(IdleBehavior.none)
                }

                if idleBehavior == .stockCarousel {
                    Picker("轮播间隔", selection: $stockIdleDisplayInterval) {
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                        Text("10 秒").tag(10)
                    }
                }

                if idleBehavior == .animation {
                    Toggle("显示空闲动画", isOn: $showNotHumanFace)
                }
            } header: {
                Text("空闲行为")
            } footer: {
                if idleBehavior == .stockCarousel {
                    Text("闲时灵动岛将轮播显示自选股票行情")
                } else if idleBehavior == .animation {
                    Text("闲时灵动岛显示 Lottie 动画")
                } else {
                    Text("闲时灵动岛仅显示 Vland 图标")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingStock) { stock in
            EditStockSheet(
                stock: stock,
                displayName: $editDisplayName,
                cost: $editCost,
                shares: $editShares,
                onSave: { saveEdit(for: stock) },
                onCancel: { editingStock = nil }
            )
        }
    }

    // MARK: - 搜索结果列表

    @ViewBuilder
    private var searchResultsList: some View {
        List(searchResults) { result in
            Button {
                addStock(result)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.name)
                            .font(.system(size: 13))
                        Text(result.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(result.market.rawValue)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .frame(height: min(CGFloat(searchResults.count) * 38, 200))
    }

    // MARK: - 股票行

    @ViewBuilder
    private func stockRow(_ stock: Stock) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.effectiveName)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 6) {
                    Text(stock.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(stock.market.rawValue)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                if let c = stock.costPrice, let sh = stock.holdingShares {
                    Text("成本 \(String(format: "%.3f", c)) × \(String(format: "%.0f", sh)) 股")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("未设置持仓")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                editingStock = stock
                editDisplayName = stock.displayName ?? ""
                editCost = stock.costPrice.map { String($0) } ?? ""
                editShares = stock.holdingShares.map { String(Int($0)) } ?? ""
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("编辑持仓")
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                var list = stockWatchlist
                list.removeAll { $0.id == stock.id }
                stockWatchlist = list
                if editingStock?.id == stock.id {
                    editingStock = nil
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func search() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        searchResults = []
        Task {
            let results = await StockSearchService.search(keyword: searchText)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    private func addStock(_ result: StockSearchResult) {
        guard !stockWatchlist.contains(where: { $0.id == result.id }) else {
            searchText = ""
            searchResults = []
            return
        }
        var list = stockWatchlist
        list.append(Stock(id: result.id, name: result.name, displayName: nil, market: result.market,
                          costPrice: nil, holdingShares: nil))
        stockWatchlist = list
        searchText = ""
        searchResults = []
    }

    private func saveEdit(for stock: Stock) {
        var list = stockWatchlist
        guard let idx = list.firstIndex(where: { $0.id == stock.id }) else { return }
        list[idx].displayName = editDisplayName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editDisplayName
        list[idx].costPrice = Double(editCost)
        list[idx].holdingShares = Double(editShares)
        stockWatchlist = list
        editingStock = nil
    }
}

// MARK: - EditStockSheet

private struct EditStockSheet: View {
    let stock: Stock
    @Binding var displayName: String
    @Binding var cost: String
    @Binding var shares: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.escape)
                Spacer()
                Text("编辑持仓")
                    .font(.headline)
                Spacer()
                Button("保存", action: onSave)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            Form {
                Section {
                    HStack {
                        Text("股票代码")
                        Spacer()
                        Text(stock.id)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("市场")
                        Spacer()
                        Text(stock.market.rawValue)
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    HStack {
                        Text("显示名称")
                        TextField("（留空则用接口名称）", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("成本价")
                        TextField("如 10.50", text: $cost)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("持仓股数")
                        TextField("如 1000", text: $shares)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 380, height: 320)
    }
}
