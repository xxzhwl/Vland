/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Manager - handles importing, uninstalling, enabling/disabling
 * web-based plugins. Plugins are stored in ~/.vland/plugins/.
 */

import Foundation
import Defaults
import SwiftUI

@MainActor
final class PluginManager: ObservableObject {
    static let shared = PluginManager()

    /// Directory where all web plugins are stored
    var pluginsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".vland/plugins")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// All installed plugin records (persisted)
    @Published private(set) var installedPlugins: [InstalledPlugin] = []

    /// Manifests for currently loaded web plugins (keyed by plugin ID)
    private var manifests: [String: PluginManifest] = [:]
    private var hasLoadedInstalledPlugins = false

    private init() {
        loadInstalledRecords()
    }

    // MARK: - Import

    /// Import a plugin from a directory (user selects via NSOpenPanel).
    /// The directory must contain a plugin.json file.
    func importPlugin() {
        let panel = NSOpenPanel()
        panel.title = "Select Plugin Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose the plugin folder containing plugin.json"

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            try importPluginFromDirectory(sourceURL)
        } catch {
            Logger.log("Failed to import plugin: \(error.localizedDescription)", category: .extensions)
        }
    }

    /// Import a plugin from a zip file.
    func importPluginFromZip(url: URL) {
        // TODO: Support zip import in future iteration
    }

    /// Core import logic: copies plugin to ~/.vland/plugins/<id>/ and registers it.
    func importPluginFromDirectory(_ sourceURL: URL) throws {
        // Read manifest
        let manifestURL = sourceURL.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginError.manifestNotFound
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

        guard manifest.isValid else {
            throw PluginError.invalidManifest
        }

        // Check for duplicate
        if installedPlugins.contains(where: { $0.id == manifest.id }) {
            throw PluginError.duplicatePlugin(manifest.id)
        }

        // Copy to plugins directory
        let destDir = pluginsDirectory.appendingPathComponent(manifest.id)
        if FileManager.default.fileExists(atPath: destDir.path) {
            try FileManager.default.removeItem(at: destDir)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destDir)

        // Remove .git and node_modules if present (save space)
        let gitDir = destDir.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            try? FileManager.default.removeItem(at: gitDir)
        }
        let nodeModules = destDir.appendingPathComponent("node_modules")
        if FileManager.default.fileExists(atPath: nodeModules.path) {
            try? FileManager.default.removeItem(at: nodeModules)
        }

        // Create record
        let record = InstalledPlugin(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            installedAt: Date(),
            isEnabled: true,
            isBuiltin: false,
            directoryURL: destDir
        )

        installedPlugins.append(record)
        manifests[manifest.id] = manifest
        saveInstalledRecords()

        // Register with PluginRegistry
        let plugin = WebPlugin(manifest: manifest, pluginDirectory: destDir)
        PluginRegistry.shared.register(plugin)

        Logger.log("Imported plugin: \(manifest.name) v\(manifest.version)", category: .extensions)
    }

    // MARK: - Uninstall

    func uninstallPlugin(_ pluginID: String) {
        guard let index = installedPlugins.firstIndex(where: { $0.id == pluginID }),
              let record = installedPlugins[index].directoryURL else { return }

        // Remove from filesystem
        try? FileManager.default.removeItem(at: record)

        // Remove from records
        installedPlugins.remove(at: index)
        manifests.removeValue(forKey: pluginID)
        saveInstalledRecords()

        // Unregister from PluginRegistry
        PluginRegistry.shared.unregister(pluginID)

        Logger.log("Uninstalled plugin: \(pluginID)", category: .extensions)
    }

    // MARK: - Enable / Disable

    func setPluginEnabled(_ pluginID: String, enabled: Bool) {
        guard let index = installedPlugins.firstIndex(where: { $0.id == pluginID }) else { return }

        let old = installedPlugins[index]
        installedPlugins[index] = InstalledPlugin(
            id: old.id,
            name: old.name,
            version: old.version,
            installedAt: old.installedAt,
            isEnabled: enabled,
            isBuiltin: old.isBuiltin,
            directoryURL: old.directoryURL
        )
        saveInstalledRecords()

        // Update the plugin's enabled state
        PluginRegistry.shared.setEnabled(pluginID, enabled: enabled)
    }

    // MARK: - Load on Startup

    /// Load all previously installed web plugins from ~/.vland/plugins/
    func loadInstalledPluginsIfNeeded(in registry: PluginRegistry) {
        guard !hasLoadedInstalledPlugins else { return }
        hasLoadedInstalledPlugins = true
        loadInstalledPlugins(in: registry)
    }

    private func loadInstalledPlugins(in registry: PluginRegistry) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: pluginsDirectory,
                includingPropertiesForKeys: nil
            )

            for dir in contents {
                let manifestURL = dir.appendingPathComponent("plugin.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

                do {
                    let data = try Data(contentsOf: manifestURL)
                    let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
                    guard manifest.isValid else { continue }

                    manifests[manifest.id] = manifest

                    // Check if already in records
                    if !installedPlugins.contains(where: { $0.id == manifest.id }) {
                        let record = InstalledPlugin(
                            id: manifest.id,
                            name: manifest.name,
                            version: manifest.version,
                            installedAt: Date(),
                            isEnabled: true,
                            isBuiltin: false,
                            directoryURL: dir
                        )
                        installedPlugins.append(record)
                    }

                    // Only register if enabled
                    if isEnabled(pluginID: manifest.id) {
                        let plugin = WebPlugin(manifest: manifest, pluginDirectory: dir)
                        registry.register(plugin)
                    }
                } catch {
                    Logger.log("Failed to load plugin manifest from \(dir.lastPathComponent): \(error.localizedDescription)", category: .extensions)
                }
            }

            saveInstalledRecords()
        } catch {
            Logger.log("Failed to read plugins directory: \(error.localizedDescription)", category: .extensions)
        }
    }

    // MARK: - Queries

    func isEnabled(pluginID: String) -> Bool {
        installedPlugins.first(where: { $0.id == pluginID })?.isEnabled ?? true
    }

    func manifest(for pluginID: String) -> PluginManifest? {
        manifests[pluginID]
    }

    func pluginIcon(for pluginID: String) -> NSImage? {
        guard let record = installedPlugins.first(where: { $0.id == pluginID }),
              let dir = record.directoryURL,
              let manifest = manifests[pluginID],
              let iconFile = manifest.icon else { return nil }

        let iconURL = dir.appendingPathComponent(iconFile)
        return NSImage(contentsOf: iconURL)
    }

    // MARK: - Persistence

    private func loadInstalledRecords() {
        if let data = UserDefaults.standard.data(forKey: "vlandInstalledPlugins"),
           let records = try? JSONDecoder().decode([InstalledPlugin].self, from: data) {
            installedPlugins = records
        }
    }

    private func saveInstalledRecords() {
        if let data = try? JSONEncoder().encode(installedPlugins) {
            UserDefaults.standard.set(data, forKey: "vlandInstalledPlugins")
        }
    }
}

// MARK: - Errors

enum PluginError: LocalizedError {
    case manifestNotFound
    case invalidManifest
    case duplicatePlugin(String)

    var errorDescription: String? {
        switch self {
        case .manifestNotFound:
            return "plugin.json not found in the selected directory"
        case .invalidManifest:
            return "Invalid plugin.json: missing required fields (id, name, main)"
        case .duplicatePlugin(let id):
            return "Plugin \"\(id)\" is already installed"
        }
    }
}
