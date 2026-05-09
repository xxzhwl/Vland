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

import Foundation
import Combine
import AppKit
import Defaults

@MainActor
final class StockManager: ObservableObject {

    static let shared = StockManager()

    // MARK: - Published State

    /// 行情缓存 [stockCode: Quote]
    @Published var quotes: [String: Quote] = [:]

    /// 日内趋势数据 [stockCode: [TrendPoint]]
    @Published var trends: [String: [TrendPoint]] = [:]

    /// 汇率
    @Published var exchangeRates: ExchangeRates = ExchangeRates()

    /// 是否正在加载
    @Published var isLoading: Bool = false

    /// 最后更新时间
    @Published var lastUpdateTime: Date?

    /// 是否发生错误
    @Published var hasError: Bool = false

    // MARK: - Private

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // 自选列表变化时重新调度
        Defaults.publisher(.stockWatchlist, options: [])
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restartTimer()
                }
            }
            .store(in: &cancellables)

        // 刷新间隔变化时重新调度
        Defaults.publisher(.stockRefreshInterval, options: [])
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restartTimer()
                }
            }
            .store(in: &cancellables)

        // 启用/禁用股票功能时重新调度
        Defaults.publisher(.enableStockFeature, options: [])
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    if change.newValue {
                        self?.startAutoRefresh()
                    } else {
                        self?.stopAutoRefresh()
                        self?.quotes = [:]
                        self?.hasError = false
                        self?.isLoading = false
                    }
                }
            }
            .store(in: &cancellables)

        // 唤醒后重新刷新
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    // MARK: - Timer

    func startAutoRefresh() {
        stopAutoRefresh()
        let interval = TimeInterval(Defaults[.stockRefreshInterval])
        // 立即刷新一次（强制模式：开盘闭市都拉取数据以填充缓存）
        Task { @MainActor [weak self] in
            await self?.refresh(force: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard Self.anyMarketOpen() else { return }
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func restartTimer() {
        guard Defaults[.enableStockFeature] else {
            stopAutoRefresh()
            return
        }
        stopAutoRefresh()
        startAutoRefresh()
    }

    /// 强制刷新（跳过交易时段判断）
    func forceRefresh() {
        Task { @MainActor [weak self] in
            await self?.refresh(force: true)
        }
    }

    // MARK: - Refresh

    func refresh(force: Bool = false) async {
        let stocks = Defaults[.stockWatchlist]
        guard !stocks.isEmpty else { return }

        isLoading = true
        hasError = false

        do {
            // 按市场分组，只拉取开市市场（或强制模式）的行情
            let allCodes = stocks.map(\.id)

            var newQuotes: [String: Quote] = [:]
            let aCodes = allCodes.filter { !$0.hasPrefix("hk") && !$0.hasPrefix("usr_") }
            let hkCodes = allCodes.filter { $0.hasPrefix("hk") }
            let usCodes = allCodes.filter { $0.hasPrefix("usr_") }

            async let sinaResult: [String: Quote]? = (force || Self.isMarketOpen(.aStock)) ? try? StockDataService.fetchSinaQuotes(codes: aCodes) : nil
            async let hkResult: [String: Quote]? = (force || Self.isMarketOpen(.hkStock)) ? try? StockDataService.fetchTencentHKQuotes(codes: hkCodes) : nil
            async let usResult: [String: Quote]? = (force || Self.isMarketOpen(.usStock)) ? try? StockDataService.fetchSinaQuotes(codes: usCodes) : nil
            async let ratesResult = StockDataService.fetchExchangeRates()

            // 合并开市市场的新数据
            if let sina = try? await sinaResult { newQuotes.merge(sina) { $1 } }
            if let hk = try? await hkResult { newQuotes.merge(hk) { $1 } }
            if let us = try? await usResult { newQuotes.merge(us) { $1 } }

            // 保留闭市市场的缓存数据
            var merged = quotes
            merged.merge(newQuotes) { $1 }
            quotes = merged
            exchangeRates = await ratesResult
            lastUpdateTime = Date()

            // 从接口返回的名称更新自选列表中的名称
            syncStockNames()

            // 获取日内趋势数据（无论是否开市都尝试获取）
            await refreshTrends(stocks: stocks)
        } catch {
            hasError = true
        }
        isLoading = false
    }

    // MARK: - Intraday Trends

    /// 获取所有自选股票的日内趋势数据（用于 sparkline）
    private func refreshTrends(stocks: [Stock]) async {
        var newTrends: [String: [TrendPoint]] = [:]
        await withTaskGroup(of: (String, [TrendPoint]?).self) { group in
            for stock in stocks {
                group.addTask {
                    let trend = try? await StockKLineService.fetchIntradayTrend(code: stock.id)
                    return (stock.id, trend)
                }
            }
            for await (code, trend) in group {
                if let t = trend { newTrends[code] = t }
            }
        }
        trends = newTrends
    }

    // MARK: - Name Sync

    private func syncStockNames() {
        var stocks = Defaults[.stockWatchlist]
        var changed = false
        for i in stocks.indices {
            if let q = quotes[stocks[i].id], !q.name.isEmpty, q.name != stocks[i].name {
                stocks[i].name = q.name
                changed = true
            }
        }
        if changed {
            Defaults[.stockWatchlist] = stocks
        }
    }

    // MARK: - Computed

    /// 总浮动盈亏
    var totalPnL: Double {
        let stocks = Defaults[.stockWatchlist]
        return stocks.compactMap { s -> Double? in
            guard let q = quotes[s.id],
                  let cost = s.costPrice,
                  let shares = s.holdingShares else { return nil }
            return exchangeRates.convert((q.price - cost) * shares, from: s.market, to: Defaults[.stockDisplayCurrency])
        }.reduce(0, +)
    }

    /// 总当日盈亏
    var totalDailyPnL: Double {
        let stocks = Defaults[.stockWatchlist]
        return stocks.compactMap { s -> Double? in
            guard let q = quotes[s.id],
                  let shares = s.holdingShares,
                  q.isToday else { return nil }
            return exchangeRates.convert(q.change * shares, from: s.market, to: Defaults[.stockDisplayCurrency])
        }.reduce(0, +)
    }

    /// 总成本
    var totalCost: Double {
        let stocks = Defaults[.stockWatchlist]
        return stocks.compactMap { s -> Double? in
            guard let cost = s.costPrice, let shares = s.holdingShares else { return nil }
            return exchangeRates.convert(cost * shares, from: s.market, to: Defaults[.stockDisplayCurrency])
        }.reduce(0, +)
    }

    var totalPnLPercent: Double {
        guard totalCost > 0 else { return 0 }
        return totalPnL / totalCost * 100
    }

    var totalDailyPnLPercent: Double {
        guard totalCost > 0 else { return 0 }
        return totalDailyPnL / totalCost * 100
    }

    /// 是否有持仓数据
    var hasPnLData: Bool {
        Defaults[.stockWatchlist].contains { $0.costPrice != nil && $0.holdingShares != nil }
    }

    // MARK: - 月/年盈亏

    @Published var monthlyPnL: Double = 0
    @Published var yearlyPnL: Double = 0
    @Published var monthlyPnLPercent: Double = 0
    @Published var yearlyPnLPercent: Double = 0
    @Published var periodPnLIsLoading: Bool = false

    /// 根据 K 线数据计算月盈亏和年盈亏
    func refreshPeriodPnL() async {
        let stocks = Defaults[.stockWatchlist].filter { $0.holdingShares != nil }
        guard !stocks.isEmpty else {
            monthlyPnL = 0; yearlyPnL = 0
            monthlyPnLPercent = 0; yearlyPnLPercent = 0
            return
        }

        periodPnLIsLoading = true
        defer { periodPnLIsLoading = false }

        let now = Date()
        let cal = Calendar.current
        let currentMonthPrefix = String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
        let currentYearPrefix = String(format: "%04d", cal.component(.year, from: now))

        var mPnl = 0.0, yPnl = 0.0
        var mCost = 0.0, yCost = 0.0

        for stock in stocks {
            guard let quote = quotes[stock.id], let shares = stock.holdingShares else { continue }
            guard let points = try? await StockKLineService.fetchDaily(code: stock.id, days: 120) else { continue }

            let monthStart = points.first { $0.date.hasPrefix(currentMonthPrefix) }?.close
            let yearStart = points.first { $0.date.hasPrefix(currentYearPrefix) }?.close

            if let ms = monthStart {
                let raw = (quote.price - ms) * shares
                mPnl += exchangeRates.convert(raw, from: stock.market, to: Defaults[.stockDisplayCurrency])
                mCost += exchangeRates.convert(ms * shares, from: stock.market, to: Defaults[.stockDisplayCurrency])
            }
            if let ys = yearStart {
                let raw = (quote.price - ys) * shares
                yPnl += exchangeRates.convert(raw, from: stock.market, to: Defaults[.stockDisplayCurrency])
                yCost += exchangeRates.convert(ys * shares, from: stock.market, to: Defaults[.stockDisplayCurrency])
            }
        }

        monthlyPnL = mPnl
        yearlyPnL = yPnl
        monthlyPnLPercent = mCost > 0 ? mPnl / mCost * 100 : 0
        yearlyPnLPercent = yCost > 0 ? yPnl / yCost * 100 : 0
    }

    // MARK: - Trading Hour Detection

    private static let shanghaiCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private static let easternCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// 判断指定市场当前是否在交易时段
    nonisolated static func isMarketOpen(_ market: Market, at date: Date = Date()) -> Bool {
        switch market {
        case .aStock:
            return isAStockTradingHour(at: date)
        case .hkStock:
            return isHKStockTradingHour(at: date)
        case .usStock:
            return isUSStockTradingHour(at: date)
        }
    }

    /// 判断是否有任意一个自选股所在市场开市
    nonisolated static func anyMarketOpen(at date: Date = Date()) -> Bool {
        let markets = Set(Defaults[.stockWatchlist].map(\.market))
        return markets.contains { isMarketOpen($0, at: date) }
    }

    /// A股交易时段：周一至周五 9:30-11:30, 13:00-15:00（北京时间）
    private nonisolated static func isAStockTradingHour(at date: Date) -> Bool {
        let cal = shanghaiCalendar
        let weekday = cal.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false }
        let t = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return (9*60+30 ... 11*60+30).contains(t) || (13*60 ... 15*60).contains(t)
    }

    /// 港股交易时段：周一至周五 9:30-12:00, 13:00-16:00（北京时间）
    private nonisolated static func isHKStockTradingHour(at date: Date) -> Bool {
        let cal = shanghaiCalendar
        let weekday = cal.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false }
        let t = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return (9*60+30 ... 12*60).contains(t) || (13*60 ... 16*60).contains(t)
    }

    /// 美股交易时段：周一至周五 9:30-16:00（美东时间）
    private nonisolated static func isUSStockTradingHour(at date: Date) -> Bool {
        let cal = easternCalendar
        let weekday = cal.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false }
        let t = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return (9*60+30 ... 16*60).contains(t)
    }
}
