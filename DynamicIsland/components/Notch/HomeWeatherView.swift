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

// MARK: - Home Weather View (Placeholder)

/// Placeholder view for the weather card.
/// Designed to occupy the same slot as `SystemStatsHomeView` in the right panel
/// with a comparable intrinsic height (~83pt).
struct HomeWeatherView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Weather")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.yellow)
                    .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("--°")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            HStack(spacing: 16) {
                Label("H: --°", systemImage: "thermometer.sun")
                Label("L: --°", systemImage: "thermometer.snowflake")
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    HomeWeatherView()
        .frame(width: 200)
        .padding()
}
