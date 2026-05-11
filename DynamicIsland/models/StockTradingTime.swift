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

// MARK: - TradingTimeConfig

struct TradingTimeConfig {
    struct Session {
        let startMinutes: Int
        let endMinutes: Int
    }
    let sessions: [Session]
    let totalMinutes: Int
    let timeLabels: [String]

    func cumulativeMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let minutes = h * 60 + m
        var cumulative = 0
        for session in sessions {
            if minutes >= session.startMinutes && minutes <= session.endMinutes {
                return cumulative + (minutes - session.startMinutes)
            }
            cumulative += session.endMinutes - session.startMinutes
        }
        return nil
    }
}

extension Market {
    var tradingConfig: TradingTimeConfig {
        switch self {
        case .aStock:
            TradingTimeConfig(
                sessions: [
                    TradingTimeConfig.Session(startMinutes: 570, endMinutes: 690),
                    TradingTimeConfig.Session(startMinutes: 780, endMinutes: 900),
                ],
                totalMinutes: 240,
                timeLabels: ["09:30", "10:00", "10:30", "11:00", "11:30", "13:00", "13:30", "14:00", "14:30", "15:00"]
            )
        case .hkStock:
            TradingTimeConfig(
                sessions: [
                    TradingTimeConfig.Session(startMinutes: 570, endMinutes: 720),
                    TradingTimeConfig.Session(startMinutes: 780, endMinutes: 960),
                ],
                totalMinutes: 330,
                timeLabels: ["09:30", "10:00", "10:30", "11:00", "11:30", "12:00", "13:00", "13:30", "14:00", "14:30", "15:00", "15:30", "16:00"]
            )
        case .usStock:
            TradingTimeConfig(
                sessions: [
                    TradingTimeConfig.Session(startMinutes: 570, endMinutes: 960),
                ],
                totalMinutes: 390,
                timeLabels: ["09:30", "10:00", "10:30", "11:00", "11:30", "12:00", "12:30", "13:00", "13:30", "14:00", "14:30", "15:00", "15:30", "16:00"]
            )
        }
    }
}
