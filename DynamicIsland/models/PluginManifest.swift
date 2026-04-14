/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Manifest - JSON manifest model for web-based plugins.
 * Each plugin ships a plugin.json that describes metadata, entry point,
 * keywords, and capabilities.
 */

import Foundation

// MARK: - Plugin Manifest

/// JSON manifest that ships with every web plugin.
/// Placed at the root of the plugin directory alongside the built web assets.
///
/// Example plugin.json:
/// ```json
/// {
///   "id": "com.example.myplugin",
///   "name": "My Plugin",
///   "version": "1.0.0",
///   "description": "Does something useful",
///   "icon": "icon.png",
///   "keywords": ["keyword1", "keyword2"],
///   "main": "dist/index.html",
///   "features": {
///     "clipboard": true,
///     "network": false
///   }
/// }
/// ```
struct PluginManifest: Codable, Identifiable, Hashable {
    /// Unique identifier (reverse domain name style, e.g. "com.example.myplugin")
    let id: String

    /// Human-readable plugin name
    let name: String

    /// Semantic version string
    let version: String

    /// Short description shown in the plugin list
    let description: String?

    /// Icon filename (relative to plugin directory, e.g. "icon.png")
    /// Falls back to SF Symbol if nil or file not found.
    let icon: String?

    /// SF Symbol name (used as fallback if no icon file, or as the list icon)
    let iconSymbol: String?

    /// Keywords that trigger this plugin in search
    let keywords: [String]

    /// Entry point HTML file (relative to plugin directory, e.g. "dist/index.html")
    let main: String

    /// Optional preload script injected before the main page
    let preload: String?

    /// Feature flags
    let features: PluginFeatures?

    /// Minimum Vland version required (optional)
    let minVersion: String?

    /// Author information
    let author: String?

    /// Plugin homepage URL
    let homepage: String?

    // MARK: - Computed

    /// SF Symbol to use in the search list
    var displayIconSymbol: String {
        iconSymbol ?? "puzzlepiece.extension"
    }

    /// Path to the main HTML file
    var mainHTMLPath: String {
        // If main starts with /, treat as absolute within plugin dir
        // Otherwise, resolve relative to plugin root
        main.hasPrefix("/") ? String(main.dropFirst()) : main
    }

    /// Whether this plugin requests network access
    var requestsNetworkAccess: Bool {
        features?.network ?? false
    }

    /// Whether this plugin wants to access clipboard
    var requestsClipboardAccess: Bool {
        features?.clipboard ?? false
    }

    // MARK: - Validation

    var isValid: Bool {
        !id.isEmpty && !name.isEmpty && !main.isEmpty
    }

    // MARK: - Coding

    enum CodingKeys: String, CodingKey {
        case id, name, version, description, icon
        case iconSymbol = "icon_symbol"
        case keywords, main, preload, features
        case minVersion = "min_version"
        case author, homepage
    }

    init(
        id: String,
        name: String,
        version: String = "1.0.0",
        description: String? = nil,
        icon: String? = nil,
        iconSymbol: String? = nil,
        keywords: [String] = [],
        main: String = "index.html",
        preload: String? = nil,
        features: PluginFeatures? = nil,
        minVersion: String? = nil,
        author: String? = nil,
        homepage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.icon = icon
        self.iconSymbol = iconSymbol
        self.keywords = keywords
        self.main = main
        self.preload = preload
        self.features = features
        self.minVersion = minVersion
        self.author = author
        self.homepage = homepage
    }
}

// MARK: - Plugin Features

struct PluginFeatures: Codable, Hashable {
    /// Whether the plugin needs to read/write the clipboard
    let clipboard: Bool?

    /// Whether the plugin needs network access (fetch, XHR)
    let network: Bool?

    /// Whether the plugin needs filesystem access
    let filesystem: Bool?

    init(clipboard: Bool? = nil, network: Bool? = nil, filesystem: Bool? = nil) {
        self.clipboard = clipboard
        self.network = network
        self.filesystem = filesystem
    }

    enum CodingKeys: String, CodingKey {
        case clipboard, network, filesystem
    }
}

// MARK: - Installed Plugin Record

/// Persistent record of an installed plugin, stored in UserDefaults.
struct InstalledPlugin: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let installedAt: Date
    let isEnabled: Bool
    let isBuiltin: Bool
    let directoryURL: URL?  // nil for builtin plugins

    enum CodingKeys: String, CodingKey {
        case id, name, version
        case installedAt = "installed_at"
        case isEnabled = "is_enabled"
        case isBuiltin = "is_builtin"
        case directoryURL = "directory_url"
    }
}
