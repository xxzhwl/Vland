/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * WebPlugin - VlandPlugin implementation that renders a web-based plugin
 * via WKWebView. Reads plugin.json manifest and delegates UI to WebPluginView.
 */

import SwiftUI

/// A web-based plugin that loads from a local directory containing
/// a plugin.json manifest and built web assets.
@MainActor
final class WebPlugin: VlandPlugin {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String  // SF Symbol
    let keywords: [String]
    let manifest: PluginManifest
    let pluginDirectory: URL

    /// Whether this plugin is currently enabled
    var isEnabled: Bool = true

    init(manifest: PluginManifest, pluginDirectory: URL) {
        self.manifest = manifest
        self.pluginDirectory = pluginDirectory
        self.id = manifest.id
        self.title = manifest.name
        self.subtitle = manifest.description
        self.icon = manifest.displayIconSymbol
        self.keywords = manifest.keywords
    }

    func matchScore(for query: String) -> Double {
        guard isEnabled else { return 0 }
        return keywordScore(keywords: keywords, for: query)
    }

    @ViewBuilder
    func makeView(context: PluginContext) -> AnyView {
        let session = context.cachedObject(forKey: "web-plugin-session:\(id)") {
            WebPluginSession()
        }

        AnyView(WebPluginView(
            session: session,
            pluginDirectory: pluginDirectory,
            mainHTMLPath: manifest.mainHTMLPath,
            preloadScriptPath: manifest.preload,
            query: context.query,
            onDismiss: { context.dismiss() },
            onResult: { text in context.copyToClipboard(text) },
            allowNetwork: manifest.requestsNetworkAccess
        ))
    }

    func onActivate(context: PluginContext) {
        // Web plugins don't need special activation
    }
}
