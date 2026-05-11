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

// MARK: - StockTrendChartView

struct StockTrendChartView: View {
    let stock: Stock
    let quote: Quote?
    let onBack: () -> Void
    let onSwitchToKLine: () -> Void

    @ObservedObject private var stockManager = StockManager.shared
    @State private var selectedTime: String?
    @Default(.stockColorTheme) var stockColorTheme

    private var trendData: [TrendPoint] {
        stockManager.trends[stock.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Text("分时")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.15))
                    .cornerRadius(3)

                Button("日K") {
                    onSwitchToKLine()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(stock.effectiveName)
                    .font(.system(size: 12, weight: .medium))
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if trendData.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text("暂无分时数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            GeometryReader { geo in
                trendCanvas(in: geo)
            }
            if let time = selectedTime, let point = trendData.first(where: { $0.time == time }) {
                trendTooltip(time: time, price: point.price)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Tooltip

    private func trendTooltip(time: String, price: Double) -> some View {
        HStack {
            Text(time)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.3f", price))
                .font(.system(size: 10, weight: .medium))
        }
    }

    // MARK: - Canvas

    private func trendCanvas(in geo: GeometryProxy) -> some View {
        let rect = geo.frame(in: .local)
        let leftMargin: CGFloat = 8
        let rightMargin: CGFloat = 48
        let bottomMargin: CGFloat = 24
        let topMargin: CGFloat = 8

        let chartWidth = max(1, rect.width - leftMargin - rightMargin)
        let chartHeight = max(1, rect.height - topMargin - bottomMargin)

        let prices = trendData.map(\.price)
        guard let maxPrice = prices.max(), let minPrice = prices.min() else {
            return AnyView(Text("—").foregroundColor(.secondary))
        }

        let preClose = quote.map { $0.price - $0.change }

        let rangeMin = preClose.map { min(minPrice, $0) } ?? minPrice
        let rangeMax = preClose.map { max(maxPrice, $0) } ?? maxPrice
        let pricePadding = max((rangeMax - rangeMin) * 0.06, 0.01)
        let displayMin = rangeMin - pricePadding
        let displayMax = rangeMax + pricePadding
        let displayRange = max(displayMax - displayMin, 0.001)

        let step = niceStep(displayRange / max(4, 1))
        let gridStart = floor(displayMin / max(step, 0.001)) * step

        let config = stock.market.tradingConfig
        let totalMin = CGFloat(config.totalMinutes)
        let axisY = topMargin + chartHeight

        var segments: [[CGPoint]] = [[]]
        var prevCumulative: Int?

        for point in trendData {
            guard let cumMin = config.cumulativeMinutes(point.time) else { continue }

            if let prev = prevCumulative, cumMin - prev > 5 {
                segments.append([])
            }

            let x = leftMargin + CGFloat(cumMin) / totalMin * chartWidth
            let y = topMargin + chartHeight - CGFloat((point.price - displayMin) / displayRange) * chartHeight
            segments[segments.count - 1].append(CGPoint(x: x, y: y))
            prevCumulative = cumMin
        }
        segments = segments.filter { !$0.isEmpty }

        let lineColor = trendLineColor

        return AnyView(
            Canvas { context, _ in
                // Horizontal grid lines + y-axis price labels
                var gridPrice = gridStart
                while gridPrice <= displayMax + step * 0.5 {
                    let y = axisY - CGFloat((gridPrice - displayMin) / displayRange) * chartHeight

                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: leftMargin, y: y))
                    gridPath.addLine(to: CGPoint(x: leftMargin + chartWidth, y: y))
                    context.stroke(gridPath, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)

                    context.draw(
                        Text(String(format: "%.2f", gridPrice))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary),
                        at: CGPoint(x: leftMargin + chartWidth + 4, y: y)
                    )

                    gridPrice += step
                }

                // PreClose dashed reference line
                if let pc = preClose {
                    let pcY = axisY - CGFloat((pc - displayMin) / displayRange) * chartHeight
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: leftMargin, y: pcY))
                    dashPath.addLine(to: CGPoint(x: leftMargin + chartWidth, y: pcY))
                    context.stroke(dashPath, with: .color(.secondary.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

                    context.draw(
                        Text("昨收")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary.opacity(0.6)),
                        at: CGPoint(x: leftMargin + chartWidth + 4, y: pcY)
                    )
                }

                // Time axis baseline
                var axisPath = Path()
                axisPath.move(to: CGPoint(x: leftMargin, y: axisY))
                axisPath.addLine(to: CGPoint(x: leftMargin + chartWidth, y: axisY))
                context.stroke(axisPath, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

                // Time labels
                for label in config.timeLabels {
                    guard let cumMin = config.cumulativeMinutes(label) else { continue }
                    let x = leftMargin + CGFloat(cumMin) / totalMin * chartWidth
                    context.draw(
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary),
                        at: CGPoint(x: x, y: axisY + 12)
                    )
                }

                // Trend line segments + fill
                for segment in segments where segment.count >= 2 {
                    var fillPath = Path()
                    fillPath.move(to: CGPoint(x: segment[0].x, y: axisY))
                    fillPath.addLine(to: segment[0])
                    for i in 1..<segment.count {
                        fillPath.addLine(to: segment[i])
                    }
                    fillPath.addLine(to: CGPoint(x: segment.last!.x, y: axisY))
                    fillPath.closeSubpath()
                    context.fill(fillPath, with: .color(lineColor.opacity(0.08)))

                    var linePath = Path()
                    linePath.move(to: segment[0])
                    for i in 1..<segment.count {
                        linePath.addLine(to: segment[i])
                    }
                    context.stroke(linePath, with: .color(lineColor), lineWidth: 1.2)
                }

                // Selected point indicator
                if let time = selectedTime,
                   let cumMin = config.cumulativeMinutes(time) {
                    let sx = leftMargin + CGFloat(cumMin) / totalMin * chartWidth
                    var selPath = Path()
                    selPath.move(to: CGPoint(x: sx, y: topMargin))
                    selPath.addLine(to: CGPoint(x: sx, y: axisY))
                    context.stroke(selPath, with: .color(.primary.opacity(0.25)),
                                   style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let tapX = value.location.x
                        var closestTime: String?
                        var closestDist: CGFloat = 22

                        for point in trendData {
                            guard let cumMin = config.cumulativeMinutes(point.time) else { continue }
                            let x = leftMargin + CGFloat(cumMin) / totalMin * chartWidth
                            let dist = abs(x - tapX)
                            if dist < closestDist {
                                closestDist = dist
                                closestTime = point.time
                            }
                        }

                        if let time = closestTime, selectedTime == time {
                            selectedTime = nil
                        } else {
                            selectedTime = closestTime
                        }
                    }
            )
        )
    }

    // MARK: - Colors

    private var trendLineColor: Color {
        guard let first = trendData.first, let last = trendData.last else { return .secondary }
        let isUp = last.price >= first.price
        switch stockColorTheme {
        case .chinese: return isUp ? .red : .green
        case .western: return isUp ? .green : .red
        }
    }

    // MARK: - Helpers

    private func niceStep(_ range: Double) -> Double {
        guard range > 0 else { return 1 }
        let exponent = floor(log10(range))
        let fraction = range / pow(10, exponent)
        let nice: Double
        if fraction <= 1.5 { nice = 1 }
        else if fraction <= 3.5 { nice = 2 }
        else if fraction <= 7.5 { nice = 5 }
        else { nice = 10 }
        return nice * pow(10, exponent)
    }
}
