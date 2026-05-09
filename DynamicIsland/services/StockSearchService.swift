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

// MARK: - StockSearchService

final class StockSearchService {

    /// 搜索股票，返回搜索结果列表
    /// 优先使用腾讯搜索 API，失败时兜底到新浪 Suggest
    static func search(keyword: String) async -> [StockSearchResult] {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let results = await tencentSearch(keyword)
        if !results.isEmpty { return results }
        return await sinaSuggestSearch(keyword)
    }

    // MARK: - 腾讯搜索（主）

    /// 腾讯代理搜索，直接返回中文名
    /// https://proxy.finance.qq.com/ifzqgtimg/appstock/smartbox/search/get?q=xxx
    private static func tencentSearch(_ keyword: String) async -> [StockSearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://proxy.finance.qq.com/ifzqgtimg/appstock/smartbox/search/get?q=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let stocks = dataObj["stock"] as? [[String]] else {
            return []
        }

        let results = stocks.compactMap { item -> StockSearchResult? in
            guard item.count >= 3 else { return nil }
            let mkt  = item[0].lowercased()
            let code = item[1].lowercased()
            let name = item[2]
            switch mkt {
            case "sh", "sz", "bj":
                return StockSearchResult(id: "\(mkt)\(code)", name: name, market: .aStock)
            case "hk":
                return StockSearchResult(id: "hk\(code)", name: name, market: .hkStock)
            case "us":
                let parts = code.components(separatedBy: ".")
                let ticker = (parts.count > 1 ? parts.dropLast().joined(separator: ".") : code).lowercased()
                return StockSearchResult(id: "usr_\(ticker)", name: name, market: .usStock)
            default:
                return nil
            }
        }

        return results.isEmpty ? directResult(for: keyword) : results
    }

    // MARK: - 新浪 Suggest（兜底）

    private static func sinaSuggestSearch(_ keyword: String) async -> [StockSearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggest3.sinajs.cn/suggest/type=11,12,13,14&key=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return directResult(for: keyword)
        }

        let encoding = gb18030Encoding
        let body: String
        if let enc = encoding, let s = String(data: data, encoding: enc) {
            body = s
        } else {
            body = String(data: data, encoding: .utf8) ?? ""
        }

        guard let s = body.range(of: "\""),
              let e = body.lastIndex(of: "\""),
              e > s.upperBound else { return directResult(for: keyword) }

        return String(body[body.index(after: s.lowerBound)..<e])
            .components(separatedBy: ";")
            .filter { !$0.isEmpty }
            .compactMap { item -> StockSearchResult? in
                let p = item.components(separatedBy: ",")
                guard p.count >= 5 else { return nil }
                let market: Market
                let id: String
                switch p[0] {
                case "11", "14":
                    market = .aStock
                    id = p[3].lowercased()
                case "12":
                    market = .hkStock
                    id = "hk" + p[3].lowercased()
                case "13":
                    market = .usStock
                    id = p[3].lowercased()
                default:
                    return nil
                }
                return StockSearchResult(id: id, name: p[4], market: market)
            }
    }

    // MARK: - 直接代码兜底

    /// 将纯数字/字母输入当作直接代码
    private static func directResult(for keyword: String) -> [StockSearchResult] {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }

        if k.hasPrefix("sh") || k.hasPrefix("sz") || k.hasPrefix("bj") {
            return [StockSearchResult(id: k, name: k.uppercased(), market: .aStock)]
        }
        if k.hasPrefix("hk") {
            return [StockSearchResult(id: k, name: k.uppercased(), market: .hkStock)]
        }
        if k.hasPrefix("usr_") {
            return [StockSearchResult(id: k, name: k.uppercased(), market: .usStock)]
        }
        // 港股 4-5 位纯数字
        if k.allSatisfy(\.isNumber), k.count >= 4, k.count <= 5 {
            let padded = String(repeating: "0", count: 5 - k.count) + k
            return [StockSearchResult(id: "hk\(padded)", name: k, market: .hkStock)]
        }
        // A股 6 位纯数字
        if k.allSatisfy(\.isNumber), k.count == 6 {
            let prefix = (k.hasPrefix("0") || k.hasPrefix("3")) ? "sz" : "sh"
            return [StockSearchResult(id: "\(prefix)\(k)", name: k, market: .aStock)]
        }
        return []
    }

    // MARK: - Helpers

    private static let gb18030Encoding: String.Encoding? = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }()
}
