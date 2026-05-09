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

// MARK: - KLinePoint

struct KLinePoint: Identifiable {
    let id = UUID()
    let date: String       // "2024-01-02"
    let open: Double
    let close: Double
    let high: Double
    let low: Double
    let volume: Double

    var isUp: Bool { close >= open }
}

// MARK: - TrendPoint

struct TrendPoint {
    let time: String    // "09:30"
    let price: Double
}
