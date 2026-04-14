/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Clipboard Plugin - search and paste from clipboard history
 * inside the launcher panel. Reuses ClipboardManager's data.
 */

import SwiftUI

final class ClipboardPlugin: VlandPlugin {
    let id = "clipboard"
    let title = "Clipboard History"
    let subtitle: String? = "Search and paste from history"
    let icon = "clipboard"
    let keywords = ["clipboard", "paste", "复制", "粘贴", "剪贴板", "history"]

    func matchScore(for query: String) -> Double {
        return keywordScore(keywords: keywords, for: query)
    }

    @ViewBuilder
    func makeView(context: PluginContext) -> AnyView {
        AnyView(ClipboardPluginView(context: context))
    }

    func onActivate(context: PluginContext) {
        if !ClipboardManager.shared.isMonitoring {
            ClipboardManager.shared.startMonitoring()
        }
    }
}

// MARK: - Clipboard UI

private struct ClipboardPluginView: View {
    @ObservedObject var context: PluginContext
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    private var filteredItems: [ClipboardItem] {
        let allItems = clipboardManager.clipboardHistory + clipboardManager.pinnedItems
        let q = context.query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return allItems
        }
        return allItems.filter { item in
            item.preview.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredItems.isEmpty {
                emptyState
            } else {
                List(filteredItems) { item in
                    ClipboardItemRow(item: item, onCopy: {
                        context.copyToClipboard(item.preview)
                        context.dismiss()
                    }, style: .launcher)
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .scrollContentBackground(.hidden)
            }

            // Footer
            HStack {
                Text("\(filteredItems.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                Spacer()
                Text("Click to copy & close")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 24))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text("No clipboard history")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Copy something to get started")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
