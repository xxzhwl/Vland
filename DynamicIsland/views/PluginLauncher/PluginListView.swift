/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Launcher - Search result list view with keyboard navigation support.
 */

import SwiftUI

@MainActor
struct PluginListView: View {
    let results: [PluginSearchResult]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onHover: (Int) -> Void

    var body: some View {
        if results.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                List(Array(results.enumerated()), id: \.offset) { index, result in
                    PluginListRow(
                        result: result,
                        isSelected: index == selectedIndex
                    )
                    .onTapGesture {
                        onSelect(index)
                    }
                    .onHover { isHovering in
                        if isHovering { onHover(index) }
                    }
                    .id(index)
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .overlay(alignment: .bottom) {
                    shortcutHintBar
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text("No matching plugins")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            shortcutHintBar
        }
    }

    // MARK: - Shortcut Hints

    private var shortcutHintBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("↑↓").font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("Navigate").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text("↵").font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("Open").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text("esc").font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("Close").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - List Row

private struct PluginListRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let result: PluginSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.plugin.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(primaryForegroundColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackgroundColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(result.plugin.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(primaryForegroundColor)

                    PluginSourceBadge(source: pluginSource, isSelected: isSelected)
                }

                if let subtitle = result.plugin.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryForegroundColor)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
    }

    private var pluginSource: PluginSource {
        result.plugin is WebPlugin ? .imported : .builtin
    }

    private var primaryForegroundColor: Color {
        if isSelected, colorScheme == .dark {
            return .white
        }
        return .primary
    }

    private var secondaryForegroundColor: Color {
        if isSelected, colorScheme == .dark {
            return .white.opacity(0.78)
        }
        return .secondary
    }

    private var iconBackgroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.18)
        }
        return Color.secondary.opacity(colorScheme == .dark ? 0.14 : 0.1)
    }

    private var rowBackgroundColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.14)
    }

    private var rowBorderColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.accentColor.opacity(0.42) : Color.accentColor.opacity(0.24)
    }
}

private enum PluginSource {
    case builtin
    case imported

    var label: String {
        switch self {
        case .builtin:
            return "Built-in"
        case .imported:
            return "Imported"
        }
    }

    var tint: Color {
        switch self {
        case .builtin:
            return .teal
        case .imported:
            return .indigo
        }
    }
}

private struct PluginSourceBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let source: PluginSource
    let isSelected: Bool

    var body: some View {
        Text(source.label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundColor: Color {
        if isSelected, colorScheme == .dark {
            return .white.opacity(0.92)
        }
        return source.tint
    }

    private var backgroundColor: Color {
        if isSelected, colorScheme == .dark {
            return .white.opacity(0.12)
        }
        return source.tint.opacity(colorScheme == .dark ? 0.2 : 0.12)
    }
}
