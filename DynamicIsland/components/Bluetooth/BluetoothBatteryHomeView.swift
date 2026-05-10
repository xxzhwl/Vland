import SwiftUI
import Defaults

enum HomeBatteryDisplayStyle: String, Defaults.Serializable, CaseIterable {
    case ring
    case bar

    var label: String {
        switch self {
        case .ring: return "Ring"
        case .bar: return "Bar"
        }
    }
}

struct BluetoothBatteryHomeView: View {
    @ObservedObject private var bluetoothManager = BluetoothAudioManager.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.homeBatteryDisplayStyle) private var displayStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader

            VStack(alignment: .leading, spacing: 6) {
                macBatteryRow

                if !bluetoothManager.nonAudioAccessories.isEmpty || !bluetoothManager.connectedDevices.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 2)
                }

                if bluetoothManager.nonAudioAccessories.isEmpty && bluetoothManager.connectedDevices.isEmpty {
                    emptyState
                } else {
                    ForEach(bluetoothManager.nonAudioAccessories) { device in
                        accessoryRow(device: device)
                    }

                    ForEach(bluetoothManager.connectedDevices) { device in
                        accessoryRow(device: device)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .onAppear {
            bluetoothManager.refreshDeviceList()
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "battery.100")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Battery")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "bluetooth.slash")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("No devices connected")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    // MARK: - Mac Battery Row

    private var macBatteryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: batteryModel.isPluggedIn ? "bolt.fill" : "macbook")
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(batteryModel.isPluggedIn ? .yellow : .secondary)
                .frame(width: 18)

            Text("Mac")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if batteryModel.isInLowPowerMode {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.green)
            }

            batteryIndicator(level: Int(batteryModel.levelBattery))
        }
    }

    // MARK: - Accessory Row

    private func accessoryRow(device: BluetoothAudioDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: device.deviceType.sfSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)

                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                if let level = device.batteryLevel, !device.deviceType.isAirPodsType {
                    batteryIndicator(level: level)
                }
            }

            if device.deviceType.isAirPodsType {
                airpodsSubComponents(device: device)
            }
        }
    }

    // MARK: - AirPods Sub-components

    @ViewBuilder
    private func airpodsSubComponents(device: BluetoothAudioDevice) -> some View {
        let hasSub = device.batteryLevelLeft != nil
            || device.batteryLevelRight != nil
            || device.batteryLevelCase != nil

        if hasSub {
            HStack(spacing: 12) {
                if let left = device.batteryLevelLeft {
                    subComponentView(level: left, label: "L")
                }
                if let right = device.batteryLevelRight {
                    subComponentView(level: right, label: "R")
                }
                if let caseLevel = device.batteryLevelCase {
                    subComponentView(level: caseLevel, label: "C")
                }
            }
            .padding(.leading, 26)
        } else if let level = device.batteryLevel {
            HStack(spacing: 6) {
                Spacer().frame(width: 18)
                batteryIndicator(level: level)
            }
        }
    }

    private func subComponentView(level: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            batteryIndicator(level: level, compact: true)
        }
    }

    // MARK: - Battery Indicator (switchable style)

    @ViewBuilder
    private func batteryIndicator(level: Int, compact: Bool = false) -> some View {
        switch displayStyle {
        case .ring:
            batteryRing(level: level, size: compact ? 22 : 26)
        case .bar:
            batteryBar(level: level, height: compact ? 5 : 7)
        }
    }

    // MARK: - Ring Style

    private func batteryRing(level: Int, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(clamped(level)) / 100)
                .stroke(batteryColor(for: level), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    // MARK: - Bar Style (battery icon shape matching system style)

    private func batteryBar(level: Int, height: CGFloat) -> some View {
        let level = clamped(level)
        let color = batteryColor(for: level)
        let bodyHeight = height + 3
        let capWidth: CGFloat = 3
        let capHeightRatio: CGFloat = 0.55

        return HStack(spacing: 5) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    // Battery body: fill behind, outline in front
                    ZStack(alignment: .leading) {
                        // Fill — padded inside the outline
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .padding(1.5)
                            .frame(
                                width: max(0, (geometry.size.width - capWidth - 5) * CGFloat(level) / 100),
                                alignment: .leading
                            )
                        // Outline drawn on top
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    }

                    // Terminal cap — neutral gray, same as outline
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.25))
                        .frame(width: capWidth, height: bodyHeight * capHeightRatio)
                }
            }
            .frame(height: bodyHeight)

            Text("\(level)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .frame(minWidth: 30, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func clamped(_ level: Int) -> Int {
        min(max(level, 0), 100)
    }

    private func batteryColor(for level: Int) -> Color {
        switch clamped(level) {
        case ..<20:
            return .red
        case ..<50:
            return .orange
        default:
            return .green
        }
    }
}
