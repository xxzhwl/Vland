/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Launcher - VlandPlugin protocol, PluginContext, and search result model.
 */

import SwiftUI
import Defaults

// MARK: - VlandPlugin Protocol

/// The core protocol every plugin must implement.
/// Inspired by uTools: each plugin defines how it matches user queries,
/// what UI it renders inside the launcher panel, and how it responds
/// to lifecycle events (activate, deactivate, query change).
protocol VlandPlugin: Identifiable, AnyObject {
    var id: String { get }

    /// Display name shown in the search result list.
    var title: String { get }

    /// Optional secondary text (e.g. "Calculates math expressions").
    var subtitle: String? { get }

    /// SF Symbol name for the icon.
    var icon: String { get }

    /// Keywords that trigger this plugin (supports Chinese & English).
    var keywords: [String] { get }

    /// Returns a match score > 0 if this plugin should appear for the given query.
    /// Higher = better match. Return 0 to exclude.
    func matchScore(for query: String) -> Double

    /// Render the plugin's custom UI inside the launcher panel.
    @ViewBuilder func makeView(context: PluginContext) -> AnyView

    /// Called when the user selects this plugin (Enter key or click).
    func onActivate(context: PluginContext)

    /// Called when the user navigates away from this plugin (Esc or backspace to empty).
    func onDeactivate(context: PluginContext)
}

// MARK: - Default Implementations

extension VlandPlugin {
    var subtitle: String? { nil }
    func onActivate(context: PluginContext) {}
    func onDeactivate(context: PluginContext) {}
}

// MARK: - Plugin Context

/// Shared context passed to every plugin so it can interact with the launcher host.
@MainActor
final class PluginContext: ObservableObject {
    let plugin: any VlandPlugin
    @Published var query: String = ""

    private var _dismiss: (() -> Void)?
    private var retainedObjects: [String: AnyObject] = [:]

    init(plugin: any VlandPlugin, dismiss: @escaping () -> Void) {
        self.plugin = plugin
        self._dismiss = dismiss
    }

    /// Close the launcher panel.
    func dismiss() {
        _dismiss?()
    }

    /// Update the dismiss handler at runtime (used when moving plugin to a new window).
    func updateDismiss(_ handler: @escaping () -> Void) {
        _dismiss = handler
    }

    /// Return a stable object scoped to the current plugin session.
    /// Useful for preserving AppKit/WebKit state when moving the plugin
    /// between the launcher panel and a pinned window.
    func cachedObject<T: AnyObject>(forKey key: String, create: () -> T) -> T {
        if let existing = retainedObjects[key] as? T {
            return existing
        }

        let object = create()
        retainedObjects[key] = object
        return object
    }

    /// Read a previously cached object without creating a new one.
    func existingCachedObject<T: AnyObject>(forKey key: String) -> T? {
        retainedObjects[key] as? T
    }

    /// Copy text to the system clipboard and dismiss.
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        dismiss()
    }
}

// MARK: - Search Result

struct PluginSearchResult: Identifiable {
    let plugin: any VlandPlugin
    let score: Double

    var id: String { plugin.id }
}

// MARK: - Keyword Matching Helpers

func keywordScore(keywords: [String], for query: String) -> Double {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return 0 }

    var best: Double = 0
    for kw in keywords {
        let k = kw.lowercased()
        if k == q { best = max(best, 1.0) }                        // exact
        else if k.hasPrefix(q) { best = max(best, 0.85) }          // prefix
        else if k.localizedStandardContains(q) { best = max(best, 0.6) } // contains
    }
    return best
}

// MARK: - Defaults Keys

extension Defaults.Keys {
    static let enablePluginLauncher = Key<Bool>("enablePluginLauncher", default: true)
    static let pluginLauncherRecentPlugins = Key<[String]>("pluginLauncherRecentPlugins", default: [])
}
