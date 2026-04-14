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

import AppKit
import Foundation
import Darwin

@MainActor
final class MemoryUsageMonitor {
    static let shared = MemoryUsageMonitor()

    private let thresholdBytes: UInt64 = 1_024 * 1_024 * 1_024
    private let pollInterval: TimeInterval = 15
    private let restartCooldown: TimeInterval = 300
    private let logSampleInterval: TimeInterval = 300
    private let launchGracePeriod: TimeInterval = 90
    private let requiredConsecutiveBreaches = 3
    private let memoryRecoveryCooldown: TimeInterval = 120
    private var monitorTask: Task<Void, Never>?
    private var lastRestartAttempt: Date = .distantPast
    private var lastLogSample: Date = .distantPast
    private var monitoringStartDate: Date?
    private var consecutiveThresholdBreaches = 0
    private var lastRecoveryAttempt: Date = .distantPast

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitoringStartDate = Date()
        consecutiveThresholdBreaches = 0
        lastLogSample = .distantPast
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.evaluateMemoryFootprint()
                do {
                    try await Task.sleep(for: .seconds(self.pollInterval))
                } catch {
                    break
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        monitoringStartDate = nil
        consecutiveThresholdBreaches = 0
    }

    private func evaluateMemoryFootprint() async {
        guard let usage = currentMemoryFootprint() else { return }

        let now = Date()
        if let monitoringStartDate,
           now.timeIntervalSince(monitoringStartDate) < launchGracePeriod {
            if now.timeIntervalSince(lastLogSample) >= logSampleInterval {
                lastLogSample = now
                Logger.log(
                    "[MemoryMonitor] Warm-up footprint: \(formatMegabytes(usage)) MB",
                    category: .memory
                )
            }
            return
        }

        if usage >= thresholdBytes {
            consecutiveThresholdBreaches += 1

            var measuredUsage = usage
            if consecutiveThresholdBreaches == 1,
               let recoveredUsage = await reclaimMemoryIfPossible(currentUsage: usage) {
                measuredUsage = recoveredUsage
                if recoveredUsage < thresholdBytes {
                    consecutiveThresholdBreaches = 0
                    Logger.log(
                        "[MemoryMonitor] Footprint dropped below threshold after cache trim: \(formatMegabytes(recoveredUsage)) MB",
                        category: .memory
                    )
                    return
                }
            }

            if consecutiveThresholdBreaches >= requiredConsecutiveBreaches {
                restartIfNeeded(currentUsage: measuredUsage)
            } else {
                Logger.log(
                    "[MemoryMonitor] Footprint \(formatMegabytes(measuredUsage)) MB exceeds threshold (\(consecutiveThresholdBreaches)/\(requiredConsecutiveBreaches))",
                    category: .warning
                )
            }
        } else {
            if consecutiveThresholdBreaches > 0 {
                Logger.log(
                    "[MemoryMonitor] Footprint returned below threshold: \(formatMegabytes(usage)) MB",
                    category: .memory
                )
            }
            consecutiveThresholdBreaches = 0

            if now.timeIntervalSince(lastLogSample) >= logSampleInterval {
                lastLogSample = now
                Logger.log("[MemoryMonitor] Footprint: \(formatMegabytes(usage)) MB", category: .memory)
            }
        }
    }

    private func restartIfNeeded(currentUsage: UInt64) {
        let now = Date()
        guard now.timeIntervalSince(lastRestartAttempt) >= restartCooldown else {
            Logger.log("[MemoryMonitor] Usage \(formatMegabytes(currentUsage)) MB exceeds threshold but cooldown active", category: .warning)
            return
        }
        lastRestartAttempt = now
        Logger.log("[MemoryMonitor] Usage \(formatMegabytes(currentUsage)) MB >= \(formatMegabytes(thresholdBytes)) MB. Prompting for restart.", category: .warning)
        presentRestartAlert(currentUsage: currentUsage)
    }

    private func presentRestartAlert(currentUsage: UInt64) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Vland memory usage is high"
        alert.informativeText = "The app is currently using \(formatMegabytes(currentUsage)) MB after automatic cleanup, which exceeds the safe limit of \(formatMegabytes(thresholdBytes)) MB. Restart now to free memory?"
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            relaunchApplication()
        } else {
            Logger.log("[MemoryMonitor] Restart postponed by user", category: .warning)
        }
    }

    private func relaunchApplication() {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        let appURL = workspace.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") ?? Bundle.main.bundleURL

        workspace.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                Logger.log("[MemoryMonitor] Failed to launch replacement app: \(error.localizedDescription)", category: .error)
            }
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func reclaimMemoryIfPossible(currentUsage: UInt64) async -> UInt64? {
        let now = Date()
        guard now.timeIntervalSince(lastRecoveryAttempt) >= memoryRecoveryCooldown else {
            return currentUsage
        }

        lastRecoveryAttempt = now
        Logger.log(
            "[MemoryMonitor] Attempting cache trim at \(formatMegabytes(currentUsage)) MB",
            category: .warning
        )

        URLCache.shared.removeAllCachedResponses()
        ImageService.shared.trimCaches()
        await ThumbnailService.shared.clearCache()

        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return currentUsage
        }

        guard let refreshedUsage = currentMemoryFootprint() else { return nil }
        Logger.log(
            "[MemoryMonitor] Cache trim result: \(formatMegabytes(refreshedUsage)) MB",
            category: .memory
        )
        return refreshedUsage
    }

    private func currentMemoryFootprint() -> UInt64? {
        if let footprint = currentPhysicalFootprint() {
            return footprint
        }
        return currentResidentSize()
    }

    private func currentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            Logger.log(
                "[MemoryMonitor] TASK_VM_INFO failed with code \(result); falling back to resident size",
                category: .warning
            )
            return nil
        }

        return UInt64(info.phys_footprint)
    }

    private func currentResidentSize() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            Logger.log("[MemoryMonitor] task_info failed with code \(result)", category: .error)
            return nil
        }
        return UInt64(info.resident_size)
    }

    private func formatMegabytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f", mb)
    }
}
