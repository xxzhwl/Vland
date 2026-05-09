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

extension Defaults.Keys {
    /// 是否启用股票功能
    static let enableStockFeature = Key<Bool>("enableStockFeature", default: false)

    /// 自选股票列表
    static let stockWatchlist = Key<[Stock]>("stockWatchlist", default: [])

    /// 刷新间隔（秒）
    static let stockRefreshInterval = Key<Int>("stockRefreshInterval", default: 5)

    /// 涨跌颜色主题
    static let stockColorTheme = Key<StockColorTheme>("stockColorTheme", default: .chinese)

    /// 持仓汇总货币
    static let stockDisplayCurrency = Key<DisplayCurrency>("stockDisplayCurrency", default: .cny)

    /// 排序规则
    static let stockSortRule = Key<String>("stockSortRule", default: "changeDesc")

    /// 是否在空闲时显示股票轮播
    static let enableStockIdleDisplay = Key<Bool>("enableStockIdleDisplay", default: false)

    /// 股票轮播间隔（秒）
    static let stockIdleDisplayInterval = Key<Int>("stockIdleDisplayInterval", default: 3)

    /// 空闲行为（统一配置：动画/股票信息/无）
    static let idleBehavior = Key<IdleBehavior>("idleBehavior", default: .animation)

    /// 股票面板最大高度
    static let stockPanelMaxHeight = Key<Double>("stockPanelMaxHeight", default: 280)
}
