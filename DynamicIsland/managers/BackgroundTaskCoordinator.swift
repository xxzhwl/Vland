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

/// Merges multiple low-frequency cleanup/polling tasks into a single shared timer,
/// reducing RunLoop wakeups from multiple independent timers.
final class BackgroundTaskCoordinator {
    static let shared = BackgroundTaskCoordinator()

    private var timer: Timer?
    private var tasks: [() -> Void] = []
    private let lock = NSLock()

    private init() {}

    private var started = false
    private var interval: TimeInterval = 10.0

    func register(_ task: @escaping () -> Void) {
        lock.withLock {
            tasks.append(task)
        }
        lazyStart()
    }

    func unregisterAll() {
        lock.withLock {
            tasks.removeAll()
        }
    }

    private func lazyStart() {
        lock.withLock {
            guard !started else { return }
            started = true
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fire()
        }
    }

    func stop() {
        lock.withLock {
            started = false
        }
        timer?.invalidate()
        timer = nil
    }

    private func fire() {
        var currentTasks: [() -> Void] = []
        lock.withLock {
            currentTasks = tasks
        }
        for task in currentTasks {
            task()
        }
    }
}
