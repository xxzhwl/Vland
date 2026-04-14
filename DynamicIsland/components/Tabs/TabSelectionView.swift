/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Vland (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.enableTabReordering) private var enableTabReordering
    @Default(.customTabOrder) private var customTabOrder
    @Default(.tabSpacing) private var tabSpacing
    @Default(.tabSpacingAutoShrink) private var tabSpacingAutoShrink
    @Namespace var animation
    
    // Drag-to-reorder state
    @State private var draggingTabId: String?
    @State private var dragOffset: CGFloat = 0
    @State private var tabFrames: [String: CGRect] = [:]
    @State private var reorderedTabs: [TabModel]?
    @GestureState private var isLongPressing = false
    
    private var baseTabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if enableTimerFeature && timerDisplayMode == .tab {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        if Defaults[.enableStatsFeature] {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        if Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab) {
            let label = Defaults[.enableNotes] ? "Notes" : "Clipboard"
            let icon = Defaults[.enableNotes] ? "note.text" : "doc.on.clipboard"
            tabsArray.append(TabModel(label: label, icon: icon, view: .notes))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if Defaults[.enableAIAgentFeature] {
            tabsArray.append(TabModel(label: "AI Agents", icon: "cpu", view: .aiAgent))
        }
        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }
    
    private var tabs: [TabModel] {
        let base = baseTabs
        guard !customTabOrder.isEmpty else { return base }
        let orderMap = Dictionary(uniqueKeysWithValues: customTabOrder.enumerated().map { ($1, $0) })
        return base.sorted { a, b in
            let idxA = orderMap[a.id] ?? Int.max
            let idxB = orderMap[b.id] ?? Int.max
            return idxA < idxB
        }
    }

    private var isDraggingTab: Bool {
        draggingTabId != nil
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let tabCount = (reorderedTabs ?? tabs).count
            let minSpacing: CGFloat = 8
            let effectiveSpacing: CGFloat = {
                if tabSpacingAutoShrink && tabCount > 1 {
                    // Estimate each tab needs ~26pt width; shrink spacing to fit
                    let maxAllowedSpacing = (availableWidth - CGFloat(tabCount) * 26) / CGFloat(tabCount - 1)
                    return max(minSpacing, min(tabSpacing, maxAllowedSpacing))
                }
                return tabSpacing
            }()

            HStack(spacing: effectiveSpacing) {
                ForEach(Array((reorderedTabs ?? tabs).enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white
                let isDragging = draggingTabId == tab.id

                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    guard draggingTabId == nil else { return }
                    coordinator.switchToView(tab.view, extensionExperienceID: tab.experienceID)
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
                .scaleEffect(isDragging ? 1.15 : 1.0)
                .offset(x: isDragging ? dragOffset : 0)
                .zIndex(isDragging ? 2 : 0)
                .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: isDragging ? 6 : 0, y: isDragging ? 2 : 0)
                .opacity(isDragging ? 0.85 : 1.0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TabFramePreferenceKey.self, value: [tab.id: geo.frame(in: .named("tabContainer"))])
                    }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reorderedTabs?.map(\.id))
            }
            }
            .padding(.horizontal, isDraggingTab ? 12 : 0)
            .coordinateSpace(name: "tabContainer")
            .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                tabFrames = frames
            }
            .animation(DynamicIslandViewCoordinator.tabSwitchAnimation, value: coordinator.currentView)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // If reorder drag is active, skip swipe detection
                        guard draggingTabId == nil else { return }
                    }
                    .onEnded { value in
                        guard draggingTabId == nil else { return }
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > abs(vertical) else { return }
                        if horizontal < 0 {
                            switchToNextTab()
                        } else {
                            switchToPreviousTab()
                        }
                    }
            )
            .simultaneousGesture(
                enableTabReordering ?
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 3, coordinateSpace: .named("tabContainer")))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if draggingTabId == nil, let drag = drag {
                                // Find which tab the long press started on
                                let startLoc = drag.startLocation
                                if let startTab = tabAt(location: startLoc) {
                                    draggingTabId = startTab.id
                                    reorderedTabs = tabs
                                }
                            }
                            if draggingTabId != nil, let drag = drag {
                                dragOffset = drag.translation.width
                                if let dragId = draggingTabId,
                                   let dragTab = (reorderedTabs ?? tabs).first(where: { $0.id == dragId }) {
                                    updateReorder(for: dragTab, dragLocation: drag.location)
                                }
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        commitReorder()
                    }
                : nil
            )
            .onAppear {
                ensureValidSelection(with: tabs)
            }
        }
    }
    
    private func tabAt(location: CGPoint) -> TabModel? {
        for (id, frame) in tabFrames {
            if frame.contains(location) {
                return (reorderedTabs ?? tabs).first(where: { $0.id == id })
            }
        }
        return nil
    }
    
    // MARK: - Reorder Logic
    
    private func updateReorder(for draggedTab: TabModel, dragLocation: CGPoint) {
        guard var current = reorderedTabs else { return }
        guard let draggedIndex = current.firstIndex(where: { $0.id == draggedTab.id }) else { return }
        
        for (id, frame) in tabFrames {
            if id != draggedTab.id && frame.contains(dragLocation) {
                if let targetIndex = current.firstIndex(where: { $0.id == id }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        current.move(fromOffsets: IndexSet(integer: draggedIndex), toOffset: targetIndex > draggedIndex ? targetIndex + 1 : targetIndex)
                        reorderedTabs = current
                    }
                }
                break
            }
        }
    }
    
    private func commitReorder() {
        if let finalOrder = reorderedTabs {
            Defaults[.customTabOrder] = finalOrder.map(\.id)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draggingTabId = nil
            dragOffset = 0
            reorderedTabs = nil
        }
    }

    private func switchToNextTab() {
        let currentTabs = tabs
        guard let currentIdx = currentTabs.firstIndex(where: { isSelected($0) }),
              currentIdx + 1 < currentTabs.count else { return }
        let next = currentTabs[currentIdx + 1]
        coordinator.switchToView(next.view, extensionExperienceID: next.experienceID)
    }

    private func switchToPreviousTab() {
        let currentTabs = tabs
        guard let currentIdx = currentTabs.firstIndex(where: { isSelected($0) }),
              currentIdx > 0 else { return }
        let prev = currentTabs[currentIdx - 1]
        coordinator.switchToView(prev.view, extensionExperienceID: prev.experienceID)
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.switchToView(first.view, extensionExperienceID: first.experienceID, animated: false)
            return
        }
        coordinator.switchToView(first.view, animated: false)
    }
}

// MARK: - Tab Frame Preference Key

private struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
