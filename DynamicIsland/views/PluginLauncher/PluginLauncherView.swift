/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Launcher - Main view that contains the search bar, result list,
 * and active plugin view. Switches between list mode and plugin mode.
 */

import SwiftUI

@MainActor
struct PluginLauncherView: View {
    @ObservedObject private var viewModel = PluginLauncherViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.activePlugin == nil {
                searchBar
                Divider().opacity(0.3)
            }
            contentArea
        }
        .frame(width: 580, height: viewModel.activePlugin != nil ? nil : 340)
        .frame(minHeight: viewModel.activePlugin != nil ? 340 : nil)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search plugins or type a query...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .onSubmit { viewModel.handleEnter() }
                .onChange(of: viewModel.query) { _, newValue in
                    viewModel.onQueryChanged(newValue)
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.clear)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let activePlugin = viewModel.activePlugin {
            pluginView(for: activePlugin)
        } else {
            PluginListView(
                results: viewModel.searchResults,
                selectedIndex: viewModel.selectedIndex,
                onSelect: { index in viewModel.selectPlugin(at: index) },
                onHover: { index in viewModel.hoverPlugin(at: index) }
            )
        }
    }

    @ViewBuilder
    private func pluginView(for plugin: any VlandPlugin) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    viewModel.deactivatePlugin()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)

                Text(plugin.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    viewModel.pinActivePlugin()
                } label: {
                    Image(systemName: "pin")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Pin to new window")

                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.2)

            plugin.makeView(context: viewModel.pluginContext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
