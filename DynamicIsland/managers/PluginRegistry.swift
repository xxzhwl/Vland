/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Registry - singleton that holds all registered plugins
 * and provides search matching with recent-use ranking.
 */

import SwiftUI
import Defaults

@MainActor
final class PluginRegistry: ObservableObject {
    static let shared = PluginRegistry()

    @Published private(set) var plugins: [any VlandPlugin] = []

    private init() {
        registerBuiltinPlugins()
    }

    // MARK: - Registration

    func register(_ plugin: any VlandPlugin) {
        // Avoid duplicates
        if plugins.contains(where: { $0.id == plugin.id }) { return }
        plugins.append(plugin)
    }

    func unregister(_ pluginID: String) {
        plugins.removeAll { $0.id == pluginID }
    }

    func setEnabled(_ pluginID: String, enabled: Bool) {
        // Find the web plugin and toggle its enabled state
        if let index = plugins.firstIndex(where: { $0.id == pluginID }) {
            if let webPlugin = plugins[index] as? WebPlugin {
                webPlugin.isEnabled = enabled
            } else if !enabled {
                // For native plugins, remove from list (they can't be disabled easily)
                // Actually, just keep them — native plugins are always on
            }
        }
    }

    // MARK: - Search

    func search(query: String) -> [PluginSearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces)

        // Empty query → show recent plugins
        if q.isEmpty {
            return recentPluginResults()
        }

        let scored = plugins.compactMap { plugin -> PluginSearchResult? in
            let score = plugin.matchScore(for: q)
            return score > 0 ? PluginSearchResult(plugin: plugin, score: score) : nil
        }

        // Boost recently used plugins slightly
        let recentIDs = Set(Defaults[.pluginLauncherRecentPlugins])
        let boosted = scored.map { result -> PluginSearchResult in
            if recentIDs.contains(result.plugin.id) {
                return PluginSearchResult(plugin: result.plugin, score: result.score + 0.05)
            }
            return result
        }

        return boosted.sorted { $0.score > $1.score }
    }

    // MARK: - Recent Plugins

    func recordUsage(pluginID: String) {
        var recent = Defaults[.pluginLauncherRecentPlugins]
        recent.removeAll { $0 == pluginID }
        recent.insert(pluginID, at: 0)
        if recent.count > 8 { recent = Array(recent.prefix(8)) }
        Defaults[.pluginLauncherRecentPlugins] = recent
    }

    func clearRecentPlugins() {
        Defaults[.pluginLauncherRecentPlugins] = []
    }

    private func recentPluginResults() -> [PluginSearchResult] {
        let recentIDs = Defaults[.pluginLauncherRecentPlugins]
        var results: [PluginSearchResult] = []
        var seen = Set<String>()

        for id in recentIDs {
            guard let plugin = plugins.first(where: { $0.id == id }),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            results.append(PluginSearchResult(plugin: plugin, score: 0.5))
        }

        // Append remaining plugins that aren't in recent list
        for plugin in plugins {
            if !seen.contains(plugin.id) {
                results.append(PluginSearchResult(plugin: plugin, score: 0.1))
            }
        }

        return results
    }

    // MARK: - Built-in Plugins

    private func registerBuiltinPlugins() {
        register(ClipboardPlugin())
    }
}
