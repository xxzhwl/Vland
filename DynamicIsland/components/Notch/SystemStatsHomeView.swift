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

import Defaults
import SwiftUI

// MARK: - System Stats Home View

struct SystemStatsHomeView: View {
    @ObservedObject private var statsManager = StatsManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            VStack(spacing: 4) {
                gauge(icon: "cpu", label: "CPU", percent: statsManager.cpuUsage, tint: cpuTint)
                gauge(icon: "memorychip", label: "Memory", percent: statsManager.memoryUsage, tint: memoryTint)
            }
            networkRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { openActivityMonitor() }
        .help("Click to open Activity Monitor")
        .onAppear {
            if !statsManager.isMonitoring { statsManager.startMonitoring() }
        }
        .onChange(of: vm.notchState) { _, newState in
            if newState == .open, !statsManager.isMonitoring {
                statsManager.startMonitoring()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("System")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gauge Row

    private func gauge(icon: String, label: String, percent: Double, tint: Color) -> some View {
        let clamped = max(0, min(percent, 100))
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(tint)
                        .frame(width: geo.size.width * CGFloat(clamped / 100.0))
                        .animation(.easeOut(duration: 0.4), value: clamped)
                }
            }
            .frame(height: 5)

            Text(String(format: "%.0f%%", clamped))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)
        }
    }

    // MARK: - Color thresholds

    private var cpuTint: Color {
        switch statsManager.cpuUsage {
        case ..<40: return .green
        case ..<75: return .orange
        default:    return .red
        }
    }

    private var memoryTint: Color {
        switch statsManager.memoryUsage {
        case ..<60: return .blue
        case ..<85: return .orange
        default:    return .red
        }
    }

    // MARK: - Network Row

    private var networkRow: some View {
        let activeInterface = statsManager.networkInterfaces
            .first(where: { $0.isActive && ($0.type == .wifi || $0.type == .ethernet) })
        let displayName = activeInterface?.displayName
            ?? (statsManager.networkDownload + statsManager.networkUpload > 0 ? "Network" : "Offline")
        let iconName: String = {
            switch activeInterface?.type {
            case .wifi:     return "wifi"
            case .ethernet: return "cable.connector"
            case .cellular: return "antenna.radiowaves.left.and.right"
            default:        return "wifi.slash"
            }
        }()
        let iconColor: Color = activeInterface?.isActive == true ? .blue : .secondary

        return HStack(alignment: .center, spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            throughputLabel(arrow: "arrow.down", value: statsManager.networkDownload, color: .green)
            throughputLabel(arrow: "arrow.up", value: statsManager.networkUpload, color: .orange)
        }
    }

    private func throughputLabel(arrow: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: arrow)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(color)
            Text(StatsFormatting.throughput(value))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    SystemStatsHomeView()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 200)
        .padding()
}
