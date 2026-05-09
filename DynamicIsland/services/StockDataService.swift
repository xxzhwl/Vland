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

// MARK: - GBK String Decoding

private enum GBKStringDecoding {
    static func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let enc = gb18030Encoding,
           let s = String(data: data, encoding: enc) { return s }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static let gb18030Encoding: String.Encoding? = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }()
}

// MARK: - StockDataService

final class StockDataService {

    // MARK: - 新浪财经（A股 + 美股）

    static func fetchSinaQuotes(codes: [String]) async throws -> [String: Quote] {
        guard !codes.isEmpty else { return [:] }
        let escaped = codes
            .map { $0.lowercased().replacingOccurrences(of: ".", with: "$") }
            .joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(escaped)") else { return [:] }
        var req = URLRequest(url: url)
        req.setValue("http://finance.sina.com.cn/", forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parseSinaResponse(GBKStringDecoding.decode(data))
    }

    static func parseSinaResponse(_ body: String) -> [String: Quote] {
        var result: [String: Quote] = [:]
        for line in body.components(separatedBy: ";\n") where line.contains("hq_str_") {
            guard let codeRange  = line.range(of: "hq_str_"),
                  let equalsRange = line.range(of: "=\"") else { continue }
            let code = String(line[codeRange.upperBound..<equalsRange.lowerBound])
                .replacingOccurrences(of: "$", with: ".")

            guard let valStart = line.range(of: "=\""),
                  let valEnd   = line.lastIndex(of: "\""),
                  valEnd > valStart.upperBound else { continue }
            let params = String(line[valStart.upperBound..<valEnd])
                .components(separatedBy: ",")

            guard params.count > 1, !params[0].isEmpty else { continue }

            let quote: Quote?
            if code.hasPrefix("sh") || code.hasPrefix("sz") || code.hasPrefix("bj") {
                quote = parseAStock(code: code, params: params)
            } else if code.hasPrefix("usr_") {
                quote = parseUSStock(code: code, params: params)
            } else {
                continue
            }
            if let q = quote { result[code] = q }
        }
        return result
    }

    // A股: 0=名称, 1=今开, 2=昨收, 3=现价, ..., 30=日期, 31=时间
    private static func parseAStock(code: String, params: [String]) -> Quote? {
        guard params.count >= 32 else { return nil }
        let yestClose = Double(params[2]) ?? 0
        let price     = Double(params[3]) ?? 0
        guard price > 0, yestClose > 0 else { return nil }
        let change        = price - yestClose
        let changePercent = change / yestClose * 100
        let updateTime    = "\(params[30]) \(params[31])".trimmingCharacters(in: .whitespaces)
        return Quote(code: code, name: params[0], price: price, change: change,
                     changePercent: changePercent, updateTime: updateTime)
    }

    // 美股: 0=名称, 1=现价, 2=涨跌%, 3=更新时间, 4=涨跌额, ..., 21=盘外价, 26=昨收
    private static func parseUSStock(code: String, params: [String]) -> Quote? {
        guard params.count >= 27 else { return nil }
        let yestClose = Double(params[26]) ?? 0
        let rawPrice  = Double(params[1])  ?? 0
        let extPrice  = params.count > 21 ? (Double(params[21]) ?? 0) : 0
        let price = rawPrice > 0 ? rawPrice : extPrice
        guard price > 0, yestClose > 0 else { return nil }
        let change        = price - yestClose
        let changePercent = change / yestClose * 100
        return Quote(code: code, name: params[0], price: price, change: change,
                     changePercent: changePercent, updateTime: params[3],
                     extendedPrice: extPrice > 0 ? extPrice : nil)
    }

    // MARK: - 腾讯证券（港股）

    static func fetchTencentHKQuotes(codes: [String]) async throws -> [String: Quote] {
        guard !codes.isEmpty else { return [:] }
        let codeStr = codes.map { "r_\($0)" }.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(codeStr)") else { return [:] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return parseTencentResponse(GBKStringDecoding.decode(data))
    }

    static func parseTencentResponse(_ body: String) -> [String: Quote] {
        var result: [String: Quote] = [:]
        for line in body.components(separatedBy: ";\n") where line.contains("v_r_hk") {
            guard let codeRange  = line.range(of: "v_r_hk"),
                  let equalsRange = line.range(of: "=\"") else { continue }
            let rawCode = String(line[codeRange.lowerBound..<equalsRange.lowerBound])
                .replacingOccurrences(of: "v_r_", with: "")
                .lowercased()

            guard let valStart = line.range(of: "=\""),
                  let valEnd   = line.lastIndex(of: "\""),
                  valEnd > valStart.upperBound else { continue }
            let fields = String(line[valStart.upperBound..<valEnd])
                .components(separatedBy: "~")

            guard fields.count > 30,
                  let price     = Double(fields[3]),
                  let yestClose = Double(fields[4]),
                  price > 0, yestClose > 0 else { continue }
            let change        = price - yestClose
            let changePercent = change / yestClose * 100
            result[rawCode] = Quote(code: rawCode, name: fields[1], price: price, change: change,
                                    changePercent: changePercent, updateTime: fields[30])
        }
        return result
    }

    // MARK: - 汇率

    static func fetchExchangeRates() async -> ExchangeRates {
        let urlStr = "https://hq.sinajs.cn/list=fx_susdcny,fx_susdhkd"
        guard let url = URL(string: urlStr) else { return ExchangeRates() }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return ExchangeRates() }
        let body = GBKStringDecoding.decode(data)

        var rates = ExchangeRates()
        for line in body.components(separatedBy: "\n") {
            if let r = parseRate(from: line, code: "fx_susdcny") { rates.usdToCny = r }
            if let r = parseRate(from: line, code: "fx_susdhkd") { rates.usdToHkd = r }
        }
        return rates
    }

    private static func parseRate(from line: String, code: String) -> Double? {
        guard line.contains(code),
              let s = line.firstIndex(of: "\""),
              let e = line.lastIndex(of: "\""),
              e > s else { return nil }
        let content = String(line[line.index(after: s)..<e])
        return content
            .components(separatedBy: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .first { $0 > 0 }
    }
}
