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
import Defaults

// MARK: - Market

enum Market: String, Codable, CaseIterable, Defaults.Serializable {
    case aStock  = "A股"
    case hkStock = "港股"
    case usStock = "美股"

    static func from(code: String) -> Market {
        if code.hasPrefix("hk")   { return .hkStock }
        if code.hasPrefix("usr_") { return .usStock }
        return .aStock
    }
}

// MARK: - Stock

struct Stock: Identifiable, Codable, Equatable, Defaults.Serializable {
    var id: String              // 股票代码，如 "sh600000"、"usr_aapl"、"hk00700"
    var name: String
    var displayName: String?    // 用户自定义显示名称
    var market: Market
    var costPrice: Double?      // 持仓成本价（nil = 未设置）
    var holdingShares: Double?  // 持仓股数（nil = 未设置）

    /// 持仓浮盈亏 = (当前价 - 成本价) × 股数
    func pnl(quote: Quote) -> Double? {
        guard let cost = costPrice, let shares = holdingShares else { return nil }
        return (quote.price - cost) * shares
    }

    /// 当日盈亏 = 涨跌额 × 股数
    func dailyPnl(quote: Quote) -> Double? {
        guard let shares = holdingShares else { return nil }
        return quote.change * shares
    }

    /// 浮盈亏百分比
    func pnlPercent(quote: Quote) -> Double? {
        guard let cost = costPrice, cost > 0 else { return nil }
        return (quote.price - cost) / cost * 100
    }

    /// 当日盈亏百分比
    func dailyPnlPercent(quote: Quote) -> Double? {
        guard let cost = costPrice, cost > 0 else { return nil }
        return quote.change / cost * 100
    }

    /// 显示的股票名称（自定义名 > 接口名）
    var effectiveName: String {
        displayName ?? name
    }
}

// MARK: - Quote

struct Quote: Codable, Equatable {
    var code: String
    var name: String = ""
    var price: Double
    var change: Double
    var changePercent: Double
    var updateTime: String
    var extendedPrice: Double? = nil

    var previousClose: Double { price - change }

    var isUp:   Bool { change > 0 }
    var isDown: Bool { change < 0 }

    /// 数据是否为今天
    var isToday: Bool {
        let digits = updateTime.replacingOccurrences(of: "/", with: "-")
        guard digits.count >= 10 else { return false }
        let dateStr = String(digits.prefix(10))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let today = fmt.string(from: Date())
        return dateStr == today
    }

    var formattedPercent: String {
        let sign = changePercent >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", changePercent)
    }

    var formattedPrice: String {
        if price >= 10 { return String(format: "%.2f", price) }
        return String(format: "%.3f", price)
    }
}

// MARK: - ExchangeRates

struct ExchangeRates {
    var usdToCny: Double = 7.28
    var usdToHkd: Double = 7.78
    var hkdToCny: Double { usdToCny / usdToHkd }

    func convert(_ amount: Double, from market: Market, to currency: DisplayCurrency) -> Double {
        let inCny: Double
        switch market {
        case .aStock:  inCny = amount
        case .hkStock: inCny = amount * hkdToCny
        case .usStock: inCny = amount * usdToCny
        }
        switch currency {
        case .cny: return inCny
        case .hkd: return inCny / hkdToCny
        case .usd: return inCny / usdToCny
        }
    }
}

// MARK: - DisplayCurrency

enum DisplayCurrency: String, Codable, CaseIterable, Defaults.Serializable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .hkd: return "HK$"
        case .usd: return "$"
        }
    }

    var displayName: String {
        switch self {
        case .cny: return "人民币 ¥"
        case .hkd: return "港币 HK$"
        case .usd: return "美元 $"
        }
    }
}

// MARK: - ColorTheme

enum StockColorTheme: String, Codable, CaseIterable, Defaults.Serializable {
    case chinese = "chinese"
    case western = "western"

    var displayName: String {
        switch self {
        case .chinese: return "红涨绿跌"
        case .western: return "绿涨红跌"
        }
    }

}

// MARK: - IdleBehavior

enum IdleBehavior: String, Codable, CaseIterable, Defaults.Serializable {
    case animation = "animation"     // Lottie动画（现有）
    case stockCarousel = "stockCarousel" // 股票轮播（新增）
    case none = "none"               // 不显示

    var displayName: String {
        switch self {
        case .animation: return "动画"
        case .stockCarousel: return "股票信息"
        case .none: return "无"
        }
    }
}

// MARK: - SearchResult

struct StockSearchResult: Identifiable {
    let id: String
    let name: String
    let market: Market
}
