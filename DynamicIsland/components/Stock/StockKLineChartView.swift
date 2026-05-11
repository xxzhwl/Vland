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

// MARK: - StockKLineChartView

struct StockKLineChartView: View {
    let stock: Stock
    let onBack: () -> Void
    let onSwitchToTrend: (() -> Void)?

    @State private var data: [KLinePoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedIndex: Int?
    @Default(.stockColorTheme) var stockColorTheme

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .onAppear { loadData() }
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
                if let onSwitch = onSwitchToTrend {
                    Button("分时") {
                        onSwitch()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }

                Text("日K")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.15))
                    .cornerRadius(3)
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
        if isLoading {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        } else if let error = errorMessage {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("重试") { loadData() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        } else if data.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text("暂无K线数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            GeometryReader { geo in
                chartCanvas(in: geo)
            }
            if selectedPoint != nil {
                tooltipBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Selected Point

    private var selectedPoint: KLinePoint? {
        guard let idx = selectedIndex, idx >= 0, idx < data.count else { return nil }
        return data[idx]
    }

    // MARK: - Tooltip

    private var tooltipBar: some View {
        HStack(spacing: 0) {
            if let point = selectedPoint {
                tooltipLabel("日", value: formatDate(point.date))
                    .frame(minWidth: 0)
                Spacer()
                tooltipLabel("开", value: String(format: "%.3f", point.open), color: upDownColor(point.open, point.close))
                Spacer()
                tooltipLabel("高", value: String(format: "%.3f", point.high))
                Spacer()
                tooltipLabel("低", value: String(format: "%.3f", point.low))
                Spacer()
                tooltipLabel("收", value: String(format: "%.3f", point.close), color: upDownColor(point.close, point.open))
                Spacer()
                tooltipLabel("量", value: formatVolume(point.volume))
            }
        }
    }

    private func tooltipLabel(_ title: String, value: String, color: Color? = nil) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(color ?? .primary)
        }
    }

    private func upDownColor(_ a: Double, _ b: Double) -> Color {
        a >= b ? chartUpColor : chartDownColor
    }

    // MARK: - Chart Drawing

    private func chartCanvas(in geo: GeometryProxy) -> some View {
        let rect = geo.frame(in: .local)
        let leftMargin: CGFloat = 8
        let rightMargin: CGFloat = 44
        let bottomMargin: CGFloat = 26
        let topMargin: CGFloat = 8
        let volumeRatio: CGFloat = 0.22

        let chartWidth = max(1, rect.width - leftMargin - rightMargin)
        let chartHeight = max(1, rect.height - topMargin - bottomMargin)
        let candleHeight = chartHeight * (1 - volumeRatio)
        let volHeight = chartHeight * volumeRatio

        let candleTop = topMargin
        let candleBottom = topMargin + candleHeight
        let volumeTop = candleBottom

        let count = data.count
        // 固定最大显示蜡烛数，保证所有股票从相同起点绘制到相同终点
        let maxVisible = 40
        let visibleCount = min(count, maxVisible)
        let startIndex = count - visibleCount
        let slotWidth = chartWidth / CGFloat(visibleCount)
        let candleWidth = max(2, min(slotWidth * 0.75, 8))

        guard count > 0, let maxPrice = data.map(\.high).max(),
              let minPrice = data.map(\.low).min() else {
            return AnyView(Text("—").foregroundColor(.secondary))
        }

        let pricePadding = max((maxPrice - minPrice) * 0.05, 0.01)
        let displayRange = (maxPrice - minPrice) + pricePadding * 2
        let displayMin = minPrice - pricePadding
        let safeRange = max(displayRange, 0.001)

        let maxVolume = data.map(\.volume).max() ?? 1
        let safeMaxVolume = max(maxVolume, 1)

        let step = niceStep((maxPrice - minPrice) / max(5, 1))
        let gridStart = floor(minPrice / max(step, 0.001)) * step

        return AnyView(
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    // Grid lines
                    var gridPrice = gridStart
                    while gridPrice <= maxPrice + step {
                        let y = candleBottom - CGFloat((gridPrice - displayMin) / safeRange) * candleHeight
                        var path = Path()
                        path.move(to: CGPoint(x: leftMargin, y: y))
                        path.addLine(to: CGPoint(x: leftMargin + chartWidth, y: y))
                        context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)

                        context.draw(Text(String(format: "%.2f", gridPrice))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary),
                            at: CGPoint(x: leftMargin + chartWidth + 4, y: y))

                        gridPrice += step
                    }

                    // Candles & volume (仅显示最近 maxVisible 根)
                    for i in startIndex..<count {
                        let point = data[i]
                        let visibleIdx = i - startIndex
                        let x = leftMargin + slotWidth * CGFloat(visibleIdx) + slotWidth / 2
                        let color = point.isUp ? chartUpColor : chartDownColor

                        // Wick
                        let wickTop = candleBottom - CGFloat((point.high - displayMin) / safeRange) * candleHeight
                        let wickBot = candleBottom - CGFloat((point.low - displayMin) / safeRange) * candleHeight
                        var wick = Path()
                        wick.move(to: CGPoint(x: x, y: wickTop))
                        wick.addLine(to: CGPoint(x: x, y: wickBot))
                        context.stroke(wick, with: .color(color), lineWidth: 1)

                        // Body
                        let bodyTopY = candleBottom - CGFloat((max(point.open, point.close) - displayMin) / safeRange) * candleHeight
                        let bodyBotY = candleBottom - CGFloat((min(point.open, point.close) - displayMin) / safeRange) * candleHeight
                        let bodyH = max(bodyBotY - bodyTopY, 1)
                        let bodyRect = CGRect(x: x - candleWidth / 2, y: bodyTopY, width: candleWidth, height: bodyH)
                        context.fill(Path(roundedRect: bodyRect, cornerRadius: 1), with: .color(color))

                        // Volume
                        let vH = volHeight * CGFloat(point.volume / safeMaxVolume)
                        let volRect = CGRect(x: x - candleWidth / 2, y: volumeTop + volHeight - vH, width: candleWidth, height: vH)
                        context.fill(Path(roundedRect: volRect, cornerRadius: 0.5), with: .color(color.opacity(0.35)))

                        // Highlight selected
                        if selectedIndex == i {
                            var dash = Path()
                            dash.move(to: CGPoint(x: x, y: candleTop))
                            dash.addLine(to: CGPoint(x: x, y: volumeTop + volHeight))
                            context.stroke(dash, with: .color(.primary.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                            let selRect = CGRect(x: x - candleWidth / 2 - 1, y: bodyTopY - 1, width: candleWidth + 2, height: bodyH + 2)
                            context.stroke(Path(roundedRect: selRect, cornerRadius: 1), with: .color(.primary), lineWidth: 1)
                        }
                    }

                    // Separator: candles / volume
                    var sep = Path()
                    sep.move(to: CGPoint(x: leftMargin, y: volumeTop))
                    sep.addLine(to: CGPoint(x: leftMargin + chartWidth, y: volumeTop))
                    context.stroke(sep, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)

                    // Date labels (仅对可见部分标注)
                    let dateStep = max(1, visibleCount / 8)
                    for i in stride(from: 0, to: visibleCount, by: dateStep) {
                        let dataIdx = startIndex + i
                        let x = leftMargin + slotWidth * CGFloat(i) + slotWidth / 2
                        context.draw(Text(shortDate(data[dataIdx].date))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary),
                            at: CGPoint(x: x, y: volumeTop + volHeight + 14))
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let tapX = value.location.x
                            let visibleIdx = Int(round((tapX - leftMargin - slotWidth / 2) / slotWidth))
                            if visibleIdx >= 0, visibleIdx < visibleCount {
                                let idx = startIndex + visibleIdx
                                selectedIndex = (selectedIndex == idx) ? nil : idx
                            } else {
                                selectedIndex = nil
                            }
                        }
                )
            }
        )
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true
        errorMessage = nil
        selectedIndex = nil
        Task {
            do {
                let points = try await StockKLineService.fetchDaily(code: stock.id, days: 60)
                await MainActor.run {
                    data = points
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Colors

    private var chartUpColor: Color {
        stockColorTheme == .chinese ? Color.red : Color.green
    }

    private var chartDownColor: Color {
        stockColorTheme == .chinese ? Color.green : Color.red
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

    private func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count >= 3 else { return date }
        return "\(parts[1])/\(parts[2])"
    }

    private func formatDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count >= 3 else { return date }
        return "\(parts[0])/\(parts[1])/\(parts[2])"
    }

    private func formatVolume(_ vol: Double) -> String {
        if vol >= 100_000_000 {
            return String(format: "%.1f亿", vol / 100_000_000)
        } else if vol >= 10_000 {
            return String(format: "%.0f万", vol / 10_000)
        }
        return String(format: "%.0f", vol)
    }
}
