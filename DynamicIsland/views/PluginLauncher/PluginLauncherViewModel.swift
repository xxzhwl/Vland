/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Launcher - View model managing search state, plugin activation,
 * keyboard navigation, and the shared PluginContext.
 */

import SwiftUI
import Defaults
import Combine

@MainActor
final class PluginLauncherViewModel: ObservableObject {
    static let shared = PluginLauncherViewModel()

    @Published var query: String = ""
    @Published var searchResults: [PluginSearchResult] = []
    @Published var selectedIndex: Int = 0
    @Published var activePlugin: (any VlandPlugin)?

    var pluginContext: PluginContext!
    private var cancellable: AnyCancellable?

    private let registry = PluginRegistry.shared
    private let placeholderPlugin = PluginLauncherPlaceholderPlugin()

    init() {
        self.pluginContext = makeContext(for: placeholderPlugin)
        updateResults()

        // Observe plugin registry changes (import/uninstall/enable/disable)
        cancellable = registry.$plugins
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateResults()
            }
    }

    func prepareForPresentation() {
        if let activePlugin {
            activePlugin.onDeactivate(context: pluginContext)
            self.activePlugin = nil
        }
        pluginContext = makeContext(for: placeholderPlugin)
        query = ""
        selectedIndex = 0
        updateResults()
    }

    // MARK: - Query Handling

    func onQueryChanged(_ newQuery: String) {
        if let active = activePlugin {
            // Forward query changes to active plugin
            pluginContext.query = newQuery

            // If user clears the query, go back to list
            if newQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                deactivatePlugin()
            }
            return
        }
        updateResults()
    }

    func clearQuery() {
        query = ""
        selectedIndex = 0
        if activePlugin != nil {
            deactivatePlugin()
        }
        updateResults()
    }

    // MARK: - Results

    private func updateResults() {
        searchResults = registry.search(query: query)
        selectedIndex = min(selectedIndex, max(0, searchResults.count - 1))
    }

    /// Internal access for Manager to reset state without triggering plugin deactivate.
    func updateResultsInternal() {
        searchResults = registry.search(query: query)
        selectedIndex = min(selectedIndex, max(0, searchResults.count - 1))
    }

    /// Internal access for Manager to create a fresh context.
    func makeContextInternal(for plugin: any VlandPlugin) -> PluginContext {
        PluginContext(plugin: plugin) { [weak self] in
            self?.dismiss()
        }
    }

    /// Reset VM to search mode without calling onDeactivate on the current plugin.
    /// Used when pinning: the plugin moves to a new window, so we just clear the VM state.
    func resetForSearch() {
        activePlugin = nil
        pluginContext = makeContextInternal(for: placeholderPlugin)
        query = ""
        updateResultsInternal()
    }

    // MARK: - Selection & Activation

    func selectPlugin(at index: Int) {
        guard index >= 0, index < searchResults.count else { return }
        let result = searchResults[index]
        activatePlugin(result.plugin)
    }

    func hoverPlugin(at index: Int) {
        guard index >= 0, index < searchResults.count else { return }
        selectedIndex = index
    }

    func activatePlugin(_ plugin: any VlandPlugin) {
        if let activePlugin, activePlugin.id != plugin.id {
            activePlugin.onDeactivate(context: pluginContext)
        }
        activePlugin = plugin

        // Recreate context with correct plugin reference
        pluginContext = makeContext(for: plugin)
        pluginContext.query = query

        // Update dismiss closure for the new context
        plugin.onActivate(context: pluginContext)

        // Record usage
        registry.recordUsage(pluginID: plugin.id)
    }

    func deactivatePlugin() {
        guard let plugin = activePlugin else { return }
        plugin.onDeactivate(context: pluginContext)
        activePlugin = nil
        query = ""
        updateResults()
    }

    // MARK: - Pin

    /// Pin the active plugin into a standalone floating window.
    func pinActivePlugin() {
        PluginLauncherManager.shared.pinActivePlugin()
    }

    // MARK: - Keyboard Actions

    func handleEnter() {
        if let active = activePlugin {
            // In plugin mode, let the plugin handle Enter via its view
            return
        }
        guard selectedIndex >= 0, selectedIndex < searchResults.count else { return }
        activatePlugin(searchResults[selectedIndex].plugin)
    }

    func moveSelectionUp() {
        guard !searchResults.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = searchResults.count - 1
        }
    }

    func moveSelectionDown() {
        guard !searchResults.isEmpty else { return }
        if selectedIndex < searchResults.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        if activePlugin != nil {
            deactivatePlugin()
        }
        PluginLauncherManager.shared.hidePanel()
    }

    private func makeContext(for plugin: any VlandPlugin) -> PluginContext {
        PluginContext(plugin: plugin) { [weak self] in
            self?.dismiss()
        }
    }
}

private final class PluginLauncherPlaceholderPlugin: VlandPlugin {
    let id = "__plugin_launcher_placeholder__"
    let title = "Quick Launch"
    let icon = "magnifyingglass"
    let keywords: [String] = []

    func matchScore(for query: String) -> Double { 0 }

    @ViewBuilder
    func makeView(context: PluginContext) -> AnyView {
        AnyView(EmptyView())
    }
}
