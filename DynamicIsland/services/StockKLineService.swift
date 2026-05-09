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

// MARK: - StockKLineService

final class StockKLineService {

    private static var cache: [String: (data: [KLinePoint], timestamp: Date)] = [:]
    private static let cacheTTL: TimeInterval = 60

    /// Fetch daily K-line data for a stock.
    /// - Parameters:
    ///   - code: Stock code, e.g. "sh600000", "usr_aapl", "hk00700"
    ///   - days: Number of trading days (max ~120)
    /// - Returns: Array of KLinePoint, newest first.
    static func fetchDaily(code: String, days: Int = 60) async throws -> [KLinePoint] {
        if let cached = cache[code], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.data
        }

        // Try East Money first (most reliable), fall back to Tencent
        let points: [KLinePoint]
        do {
            points = try await fetchEastMoney(code: code, days: days)
        } catch {
            points = try await fetchFromTencent(code: code, days: days)
        }

        cache[code] = (points, Date())
        return points
    }

    static func clearCache() {
        cache.removeAll()
    }

    // MARK: - East Money API (主)

    /// East Money K-line endpoint
    /// URL: https://push2his.eastmoney.com/api/qt/stock/kline/get?secid={market}.{code}&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56,f57&klt=101&fqt=1&end=20500101&lmt={days}
    /// klt=101 = daily K-line, fqt=1 = forward-adjusted (不复权), 0 = unadjusted
    /// Each kline string: "date,open,close,high,low,volume,amount"
    private static func fetchEastMoney(code: String, days: Int) async throws -> [KLinePoint] {
        let (marketId, secCode) = eastMoneyCode(code)
        guard let url = URL(string: "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=\(marketId).\(secCode)&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56,f57&klt=101&fqt=1&end=20500101&lmt=\(days)") else {
            throw KLineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: req)
        return try parseEMResponse(data: data)
    }

    private static func parseEMResponse(data: Data) throws -> [KLinePoint] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let klines = dataObj["klines"] as? [String] else {
            throw KLineError.invalidResponse
        }

        let points: [KLinePoint] = klines.compactMap { line in
            let parts = line.components(separatedBy: ",")
            // f51=date, f52=open, f53=close, f54=high, f55=low, f56=volume
            guard parts.count >= 7,
                  let open = Double(parts[1]),
                  let close = Double(parts[2]),
                  let high = Double(parts[3]),
                  let low = Double(parts[4]),
                  let volume = Double(parts[5]) else {
                return nil
            }
            return KLinePoint(date: parts[0], open: open, close: close, high: high, low: low, volume: volume)
        }

        guard !points.isEmpty else {
            throw KLineError.noData
        }

        return points
    }

    /// Map our stock code to East Money (marketId, securityCode)
    private static func eastMoneyCode(_ code: String) -> (Int, String) {
        if code.hasPrefix("sh") {
            return (1, String(code.dropFirst(2)))
        } else if code.hasPrefix("sz") || code.hasPrefix("bj") {
            return (0, String(code.dropFirst(2)))
        } else if code.hasPrefix("hk") {
            return (116, String(code.dropFirst(2)))
        } else if code.hasPrefix("usr_") {
            return (105, String(code.dropFirst(4)))
        }
        return (1, code)
    }

    // MARK: - East Money Intraday Trend

    /// Fetch intraday price trend (1-min intervals) for a stock.
    /// Uses East Money trends2 API which returns the most recent trading day's minute-level data.
    static func fetchIntradayTrend(code: String) async throws -> [TrendPoint] {
        let (marketId, secCode) = eastMoneyCode(code)
        guard let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/trends2/get?secid=\(marketId).\(secCode)&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56&ndays=1") else {
            throw KLineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: req)
        return try parseTrendResponse(data: data)
    }

    private static func parseTrendResponse(data: Data) throws -> [TrendPoint] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let trends = dataObj["trends"] as? [String] else {
            throw KLineError.invalidResponse
        }

        let points: [TrendPoint] = trends.compactMap { line in
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 2,
                  let price = Double(parts[1]) else {
                return nil
            }
            return TrendPoint(time: parts[0], price: price)
        }

        guard !points.isEmpty else {
            throw KLineError.noData
        }

        return points
    }

    // MARK: - Tencent API (备选)

    private static func fetchFromTencent(code: String, days: Int) async throws -> [KLinePoint] {
        let param = "\(code),day,,,\(days)"
        guard let url = URL(string: "http://ifzqgtimg.com/appstock/app/kline/mkline?param=\(param)") else {
            throw KLineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: req)
        return try parseTencentResponse(data: data)
    }

    private static func parseTencentResponse(data: Data) throws -> [KLinePoint] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw KLineError.invalidResponse
        }

        guard let stockKey = dataObj.keys.first(where: { $0 != "qt" }),
              let stockData = dataObj[stockKey] as? [String: Any],
              let dayArray = stockData["day"] as? [[Any]] else {
            throw KLineError.noData
        }

        let points: [KLinePoint] = dayArray.compactMap { entry in
            guard entry.count >= 6,
                  let dateStr = entry[0] as? String,
                  let open = Double("\(entry[1])"),
                  let close = Double("\(entry[2])"),
                  let high = Double("\(entry[3])"),
                  let low = Double("\(entry[4])"),
                  let volume = Double("\(entry[5])") else {
                return nil
            }
            return KLinePoint(date: dateStr, open: open, close: close, high: high, low: low, volume: volume)
        }

        guard !points.isEmpty else {
            throw KLineError.noData
        }

        return points
    }

    // MARK: - Errors

    enum KLineError: LocalizedError {
        case invalidURL
        case invalidResponse
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidURL:   return "请求地址无效"
            case .invalidResponse: return "数据格式错误"
            case .noData:       return "暂无K线数据"
            }
        }
    }
}
