/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Launcher Settings - enable/disable, shortcut config,
 * import/uninstall plugins, enable/disable individual plugins.
 */

import SwiftUI
import Defaults
import KeyboardShortcuts

struct PluginLauncherSettings: View {
    @Default(.enablePluginLauncher) var enablePluginLauncher
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.pluginLauncherRecentPlugins) var recentPlugins
    @ObservedObject private var pluginManager = PluginManager.shared
    @ObservedObject private var registry = PluginRegistry.shared

    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var showUninstallConfirm: InstalledPlugin?

    private func highlightID(_ title: String) -> String {
        SettingsTab.pluginLauncher.highlightID(for: title)
    }

    var body: some View {
        Form {
            // MARK: - General
            Section {
                Defaults.Toggle(key: .enablePluginLauncher) {
                    Text("Enable Quick Launch")
                }
                .settingsHighlight(id: highlightID("Enable Quick Launch"))
            } header: {
                Text("General")
            } footer: {
                Text("When enabled, press the shortcut to open Quick Launch. Search for tools, browse clipboard history, and run imported web plugins.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // MARK: - Shortcut
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        KeyboardShortcuts.Recorder("Quick Launch:", name: .openPluginLauncher)
                            .disabled(!enableShortcuts || !enablePluginLauncher)
                        if !enablePluginLauncher {
                            Text("Quick Launch is disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        } else if !enableShortcuts {
                            Text("Global shortcuts are disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Default is Cmd+Shift+Space.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // MARK: - Import Plugin
            Section {
                Button {
                    pluginManager.importPlugin()
                } label: {
                    Label("Import Plugin...", systemImage: "plus.circle")
                }

                Button {
                    importPluginFromFolder()
                } label: {
                    Label("Import from Folder...", systemImage: "folder")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Import web plugins (Vite+React, Vite+Vue, or any static web project). The folder must contain a plugin.json manifest file.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // MARK: - Built-in Plugins
            Section {
                ForEach(builtinPlugins, id: \.id) { plugin in
                    PluginManagementRow(
                        plugin: plugin,
                        isWeb: false,
                        isEnabled: true,
                        onToggle: nil,
                        icon: pluginManager.pluginIcon(for: plugin.id)
                    )
                }
            } header: {
                Text("Built-in Plugins")
            }

            // MARK: - Installed Web Plugins
            Section {
                if webPlugins.isEmpty {
                    Text("No web plugins installed")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(pluginManager.installedPlugins.filter { !$0.isBuiltin }, id: \.id) { record in
                        PluginManagementRow(
                            plugin: registry.plugins.first(where: { $0.id == record.id }),
                            isWeb: true,
                            isEnabled: record.isEnabled,
                            onToggle: { enabled in
                                pluginManager.setPluginEnabled(record.id, enabled: enabled)
                            },
                            icon: pluginManager.pluginIcon(for: record.id),
                            record: record,
                            onUninstall: {
                                showUninstallConfirm = record
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Web Plugins")
                    if !webPlugins.isEmpty {
                        Text("\(webPlugins.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.3), in: Capsule())
                    }
                }
            } footer: {
                Text("Web plugins are stored in ~/.vland/plugins/. Each plugin is a built web project with a plugin.json manifest.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // MARK: - Recent
            if !recentPlugins.isEmpty {
                Section {
                    Button(role: .destructive) {
                        PluginRegistry.shared.clearRecentPlugins()
                    } label: {
                        Text("Clear Recent Plugins")
                    }
                } header: {
                    Text("Recent")
                } footer: {
                    Text("Recently used plugins are shown first when you open the launcher with no search query.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Quick Launch")
        .alert("Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .onAppear {
            pluginManager.loadInstalledPluginsIfNeeded(in: registry)
        }
        .alert("Uninstall Plugin", isPresented: Binding(
            get: { showUninstallConfirm != nil },
            set: { if !$0 { showUninstallConfirm = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                showUninstallConfirm = nil
            }
            Button("Uninstall", role: .destructive) {
                if let record = showUninstallConfirm {
                    pluginManager.uninstallPlugin(record.id)
                    showUninstallConfirm = nil
                }
            }
        } message: {
            if let record = showUninstallConfirm {
                Text("Are you sure you want to uninstall \"\(record.name)\"? This will remove all plugin files.")
            }
        }
    }

    // MARK: - Computed

    private var builtinPlugins: [any VlandPlugin] {
        registry.plugins.filter { !($0 is WebPlugin) }
    }

    private var webPlugins: [InstalledPlugin] {
        pluginManager.installedPlugins.filter { !$0.isBuiltin }
    }

    // MARK: - Actions

    private func importPluginFromFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Plugin Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose the folder containing plugin.json and built web assets"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try pluginManager.importPluginFromDirectory(url)
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }
}

// MARK: - Plugin Management Row

private struct PluginManagementRow: View {
    let plugin: (any VlandPlugin)?
    let isWeb: Bool
    let isEnabled: Bool
    let onToggle: ((Bool) -> Void)?
    var icon: NSImage?
    var record: InstalledPlugin?
    var onUninstall: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: plugin?.icon ?? "puzzlepiece.extension")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.secondary.opacity(0.1))
                    )
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(plugin?.title ?? record?.name ?? "Unknown")
                        .font(.system(size: 13, weight: .medium))
                    if isWeb {
                        Text("Web")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.7), in: Capsule())
                    }
                }

                if let subtitle = plugin?.subtitle ?? record.flatMap({ getWebPluginSubtitle($0) }) {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let version = record?.version {
                    Text("v\(version)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                // Toggle for web plugins
                if isWeb, let onToggle {
                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { onToggle($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // Uninstall button for web plugins
                if isWeb, isHovering, let onUninstall {
                    Button(action: onUninstall) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func getWebPluginSubtitle(_ record: InstalledPlugin) -> String {
        let manifest = PluginManager.shared.manifest(for: record.id)
        return manifest?.description ?? manifest?.keywords.joined(separator: ", ") ?? ""
    }
}
