/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

enum VlandDistributedNotifications {
    static let didBecomeActive = Notification.Name("com.ebullioscopic.Vland.lifecycle.didBecomeActive")
    static let didBecomeIdle = Notification.Name("com.ebullioscopic.Vland.lifecycle.didBecomeIdle")

    enum UserInfoKey {
        static let sourcePID = "sourcePID"
    }
}
