//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText: String = ""
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                SettingsSidebarSearchBar(
                    text: $searchText,
                    suggestions: searchSuggestions,
                    onSuggestionSelected: handleSearchSuggestionSelection
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Divider()
                    .padding(.horizontal, 12)

                List(selection: selectionBinding) {
                    ForEach(groupedFilteredTabs, id: \.group) { section in
                        Section {
                            ForEach(section.tabs) { tab in
                                NavigationLink(value: tab) {
                                    sidebarRow(for: tab)
                                }
                            }
                        } header: {
                            if let title = section.group.title {
                                Text(title)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
                .environment(\.defaultMinListRowHeight, 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } detail: {
            detailView(for: resolvedSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar { toolbarSpacingShim }
        .environmentObject(highlightCoordinator)
        .formStyle(.grouped)
        .frame(width: 700)
        .onChange(of: searchText) { _, newValue in
            let matches = tabsMatchingSearch(newValue)
            guard let firstMatch = matches.first else { return }
            if !matches.contains(resolvedSelection) {
                selectedTab = firstMatch
            }
        }
        .background {
            Group {
                #if compiler(>=6.3)
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .glassEffect(
                            .clear
                                .tint(Color.white.opacity(0.1))
                                .interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                } else {
                    ZStack {
                        Color(NSColor.windowBackgroundColor)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                #else
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                #endif
            }
            .ignoresSafeArea()
        }
    }

    private var resolvedSelection: SettingsTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .general)
    }

    @ToolbarContentBuilder
    private var toolbarSpacingShim: some ToolbarContent {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            toolbarSpacerView
        }
        #endif
    }

    @ViewBuilder
    private var toolbarSpacerView: some View {
        Color.clear
            .frame(width: 96, height: 32)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var filteredTabs: [SettingsTab] {
        tabsMatchingSearch(searchText)
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection },
            set: { newValue in
                selectedTab = newValue
            }
        )
    }

    @ViewBuilder
    private func sidebarIcon(for tab: SettingsTab) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tab.tint.opacity(1),
                        tab.tint.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 26, height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7)
                    .blendMode(.plusLighter)
            }
            .shadow(color: tab.tint.opacity(0.35), radius: 2, x: 0, y: 1)
            .overlay {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
    }

    @ViewBuilder
    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(for: tab)
            Text(tab.title)
            if tab == .downloads {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            } else if tab == .extensions {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var availableTabs: [SettingsTab] {
        // Ordered to match group layout: core → media & display → system →
        // productivity → utilities → developer → integrations → info.
        let ordered: [SettingsTab] = [
            // Core
            .general,
            .appearance,
            // Media & Display
            .media,
            .liveActivities,
            .lockScreen,
            .devices,
            // System
            .hudAndOSD,
            .battery,
            // Productivity
            .timer,
            .calendar,
            .notes,
            // Utilities
            .clipboard,
            .screenAssistant,
            .colorPicker,
            .shelf,
            .downloads,
            .shortcuts,
            .pluginLauncher,
            // Developer
            .stats,
            .terminal,
            .aiAgent,
            // Integrations
            .extensions,
            // Info
            .about
        ]

        return ordered.filter { isTabVisible($0) }
    }

    /// Groups the filtered tabs into sidebar sections, preserving both
    /// the group order and the per-group tab order from `availableTabs`.
    private var groupedFilteredTabs: [(group: SettingsTabGroup, tabs: [SettingsTab])] {
        let visible = filteredTabs
        var result: [(group: SettingsTabGroup, tabs: [SettingsTab])] = []

        for group in SettingsTabGroup.allCases {
            let tabs = visible.filter { $0.group == group }
            if !tabs.isEmpty {
                result.append((group: group, tabs: tabs))
            }
        }

        return result
    }

    private func tabsMatchingSearch(_ query: String) -> [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableTabs }

        let entryMatches = searchEntries(matching: trimmed)
        let matchingTabs = Set(entryMatches.map(\.tab))

        return availableTabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(trimmed) || matchingTabs.contains(tab)
        }
    }

    private var searchSuggestions: [SettingsSearchEntry] {
        Array(searchEntries(matching: searchText).filter { $0.tab != .downloads }.prefix(8))
    }

    private func handleSearchSuggestionSelection(_ suggestion: SettingsSearchEntry) {
        guard suggestion.tab != .downloads else { return }
        highlightCoordinator.focus(on: suggestion)
        selectedTab = suggestion.tab
    }

    private struct SettingsSidebarSearchBar: View {
        @Binding var text: String
        let suggestions: [SettingsSearchEntry]
        let onSuggestionSelected: (SettingsSearchEntry) -> Void

        @FocusState private var isFocused: Bool
        @State private var hoveredSuggestionID: SettingsSearchEntry.ID?

        var body: some View {
            VStack(spacing: 6) {
                searchField
                if showSuggestions {
                    suggestionList
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSuggestions)
        }

        private var showSuggestions: Bool {
            isFocused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
        }

        private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)

                TextField("Search Settings", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(triggerFirstSuggestion)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }

        private var suggestionList: some View {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(suggestion.tab.tint)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: suggestion.tab.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(suggestion.tab.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: suggestion))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSuggestionID = hovering ? suggestion.id : (hoveredSuggestionID == suggestion.id ? nil : hoveredSuggestionID)
                    }

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        private func rowBackground(for suggestion: SettingsSearchEntry) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredSuggestionID == suggestion.id ? Color.white.opacity(0.08) : Color.clear)
        }

        private func selectSuggestion(_ suggestion: SettingsSearchEntry) {
            onSuggestionSelected(suggestion)
            isFocused = false
        }

        private func triggerFirstSuggestion() {
            guard let first = suggestions.first else { return }
            selectSuggestion(first)
        }
    }

    private func searchEntries(matching query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return settingsSearchIndex
            .filter { availableTabs.contains($0.tab) }
            .filter { entry in
                entry.title.localizedCaseInsensitiveContains(trimmed) ||
                entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
    }

    private var settingsSearchIndex: [SettingsSearchEntry] {
        [
            // General
            SettingsSearchEntry(tab: .general, title: "Enable Minimalistic UI", keywords: ["minimalistic", "ui mode", "general"], highlightID: SettingsTab.general.highlightID(for: "Enable Minimalistic UI")),
            SettingsSearchEntry(tab: .general, title: "Menubar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon")),
            SettingsSearchEntry(tab: .general, title: "Menubar icon style", keywords: ["menu bar", "status bar", "tray", "icon", "robot", "tv"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon style")),
            SettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
            SettingsSearchEntry(tab: .general, title: "Show on all displays", keywords: ["multi-display", "external monitor"], highlightID: SettingsTab.general.highlightID(for: "Show on all displays")),
            SettingsSearchEntry(tab: .general, title: "Show on a specific display", keywords: ["preferred screen", "display picker"], highlightID: SettingsTab.general.highlightID(for: "Show on a specific display")),
            SettingsSearchEntry(tab: .general, title: "Automatically switch displays", keywords: ["auto switch", "displays"], highlightID: SettingsTab.general.highlightID(for: "Automatically switch displays")),
            SettingsSearchEntry(tab: .general, title: "Hide Dynamic Island during screenshots & recordings", keywords: ["privacy", "screenshot", "recording"], highlightID: SettingsTab.general.highlightID(for: "Hide Dynamic Island during screenshots & recordings")),
            SettingsSearchEntry(tab: .general, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.general.highlightID(for: "Enable gestures")),
            SettingsSearchEntry(tab: .general, title: "Close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.general.highlightID(for: "Close gesture")),
            SettingsSearchEntry(tab: .general, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.general.highlightID(for: "Reverse swipe gestures")),
            SettingsSearchEntry(tab: .general, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.general.highlightID(for: "Reverse scroll gestures")),
            SettingsSearchEntry(tab: .general, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.general.highlightID(for: "Extend hover area")),
            SettingsSearchEntry(tab: .general, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.general.highlightID(for: "Enable haptics")),
            SettingsSearchEntry(tab: .general, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.general.highlightID(for: "Open notch on hover")),
            SettingsSearchEntry(tab: .general, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.general.highlightID(for: "External display style")),
            SettingsSearchEntry(tab: .general, title: "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.general.highlightID(for: "Hide until hovered")),
            SettingsSearchEntry(tab: .general, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.general.highlightID(for: "Notch display height")),

            // Live Activities
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Screen Recording Detection", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Screen Recording Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Recording Indicator", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Recording Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Focus Detection", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Focus Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Indicator", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Label", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Label")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Camera Detection", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Camera Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Microphone Detection", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Microphone Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable music live activity", keywords: ["music", "now playing"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable music live activity")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable reminder live activity")),

            // Battery (Charge)
            SettingsSearchEntry(tab: .battery, title: "Show battery indicator", keywords: ["battery hud", "charge"], highlightID: SettingsTab.battery.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .battery, title: "Show battery percentage", keywords: ["battery percent"], highlightID: SettingsTab.battery.highlightID(for: "Show battery percentage")),
            SettingsSearchEntry(tab: .battery, title: "Show power status notifications", keywords: ["notifications", "power"], highlightID: SettingsTab.battery.highlightID(for: "Show power status notifications")),
            SettingsSearchEntry(tab: .battery, title: "Show power status icons", keywords: ["power icons", "charging icon"], highlightID: SettingsTab.battery.highlightID(for: "Show power status icons")),
            SettingsSearchEntry(tab: .battery, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.battery.highlightID(for: "Play low battery alert sound")),

            // HUDs
            SettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
            SettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
            SettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
            SettingsSearchEntry(tab: .devices, title: "Color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Color-coded battery display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Color-coded volume display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Smooth color transitions")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

            // Custom OSD
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Keyboard Backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Keyboard Backlight OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC app integration", keywords: ["ddc", "third party", "external", "display", "betterdisplay", "lunar"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC app integration")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC provider", keywords: ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC provider")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

            // Media
            SettingsSearchEntry(tab: .media, title: "Music Source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music Source")),
            SettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
            SettingsSearchEntry(tab: .media, title: "Sneak Peek Style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak Peek Style")),
            SettingsSearchEntry(tab: .media, title: "Enable lyrics", keywords: ["lyrics", "song text"], highlightID: SettingsTab.media.highlightID(for: "Enable lyrics")),
            SettingsSearchEntry(tab: .media, title: "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Auto-hide inactive notch media player")),
            SettingsSearchEntry(tab: .media, title: "Show Change Media Output control", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Show Change Media Output control")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax", keywords: ["parallax", "lock screen", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax effect", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax effect")),

            // Calendar
            SettingsSearchEntry(tab: .calendar, title: "Show calendar", keywords: ["calendar", "events"], highlightID: SettingsTab.calendar.highlightID(for: "Show calendar")),
            SettingsSearchEntry(tab: .calendar, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.calendar.highlightID(for: "Enable reminder live activity")),
            SettingsSearchEntry(tab: .calendar, title: "Countdown style", keywords: ["reminder countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Countdown style")),
            SettingsSearchEntry(tab: .calendar, title: "Show lock screen reminder", keywords: ["lock screen", "reminder widget"], highlightID: SettingsTab.calendar.highlightID(for: "Show lock screen reminder")),
            SettingsSearchEntry(tab: .calendar, title: "Show next calendar event", keywords: ["calendar widget", "lock screen", "next event"], highlightID: SettingsTab.calendar.highlightID(for: "Show next calendar event")),
            SettingsSearchEntry(tab: .calendar, title: "Show events within the next", keywords: ["calendar widget", "lookahead"], highlightID: SettingsTab.calendar.highlightID(for: "Show events within the next")),
            SettingsSearchEntry(tab: .calendar, title: "Show events from all calendars", keywords: ["calendar widget", "selection"], highlightID: SettingsTab.calendar.highlightID(for: "Show events from all calendars")),
            SettingsSearchEntry(tab: .calendar, title: "Show countdown", keywords: ["calendar widget", "countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Show countdown")),
            SettingsSearchEntry(tab: .calendar, title: "Show event for entire duration", keywords: ["calendar widget", "duration"], highlightID: SettingsTab.calendar.highlightID(for: "Show event for entire duration")),
            SettingsSearchEntry(tab: .calendar, title: "Hide active event and show next upcoming event", keywords: ["calendar widget", "after start"], highlightID: SettingsTab.calendar.highlightID(for: "Hide active event and show next upcoming event")),
            SettingsSearchEntry(tab: .calendar, title: "Show time remaining", keywords: ["calendar widget", "remaining"], highlightID: SettingsTab.calendar.highlightID(for: "Show time remaining")),
            SettingsSearchEntry(tab: .calendar, title: "Show start time after event begins", keywords: ["calendar widget", "start time"], highlightID: SettingsTab.calendar.highlightID(for: "Show start time after event begins")),
            SettingsSearchEntry(tab: .calendar, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.calendar.highlightID(for: "Chip color")),
            SettingsSearchEntry(tab: .calendar, title: "Hide all-day events", keywords: ["calendar", "all-day"], highlightID: SettingsTab.calendar.highlightID(for: "Hide all-day events")),
            SettingsSearchEntry(tab: .calendar, title: "Hide completed reminders", keywords: ["reminder", "completed"], highlightID: SettingsTab.calendar.highlightID(for: "Hide completed reminders")),
            SettingsSearchEntry(tab: .calendar, title: "Show full event titles", keywords: ["calendar", "titles"], highlightID: SettingsTab.calendar.highlightID(for: "Show full event titles")),
            SettingsSearchEntry(tab: .calendar, title: "Auto-scroll to next event", keywords: ["calendar", "scroll"], highlightID: SettingsTab.calendar.highlightID(for: "Auto-scroll to next event")),

            // Shelf
            SettingsSearchEntry(tab: .shelf, title: "Enable shelf", keywords: ["shelf", "dock"], highlightID: SettingsTab.shelf.highlightID(for: "Enable shelf")),
            SettingsSearchEntry(tab: .shelf, title: "Open shelf tab by default if items added", keywords: ["auto open", "shelf tab"], highlightID: SettingsTab.shelf.highlightID(for: "Open shelf tab by default if items added")),
            SettingsSearchEntry(tab: .shelf, title: "Expanded drag detection area", keywords: ["shelf", "drag"], highlightID: SettingsTab.shelf.highlightID(for: "Expanded drag detection area")),
            SettingsSearchEntry(tab: .shelf, title: "Copy items on drag", keywords: ["shelf", "drag", "copy"], highlightID: SettingsTab.shelf.highlightID(for: "Copy items on drag")),
            SettingsSearchEntry(tab: .shelf, title: "Remove from shelf after dragging", keywords: ["shelf", "drag", "remove"], highlightID: SettingsTab.shelf.highlightID(for: "Remove from shelf after dragging")),
            SettingsSearchEntry(tab: .shelf, title: "Quick Share Service", keywords: ["shelf", "share", "airdrop", "localsend"], highlightID: SettingsTab.shelf.highlightID(for: "Quick Share Service")),
            SettingsSearchEntry(tab: .shelf, title: "LocalSend Device Picker Style", keywords: ["localsend", "glass", "picker", "material"], highlightID: SettingsTab.shelf.highlightID(for: "Device Picker Style")),

            // Appearance
            SettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
            SettingsSearchEntry(tab: .appearance, title: "Settings icon in notch", keywords: ["settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Settings icon in notch")),
            SettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
            SettingsSearchEntry(tab: .appearance, title: "Corner radius scaling", keywords: ["corner radius", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Corner radius scaling")),
            SettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
            SettingsSearchEntry(tab: .appearance, title: "Notch Width", keywords: ["expanded notch", "width", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Expanded notch width")),
            SettingsSearchEntry(tab: .appearance, title: "Enable colored spectrograms", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.appearance.highlightID(for: "Enable colored spectrograms")),
            SettingsSearchEntry(tab: .appearance, title: "Enable blur effect behind album art", keywords: ["blur", "album art"], highlightID: SettingsTab.appearance.highlightID(for: "Enable blur effect behind album art")),
            SettingsSearchEntry(tab: .appearance, title: "Slider color", keywords: ["slider", "accent"], highlightID: SettingsTab.appearance.highlightID(for: "Slider color")),
            SettingsSearchEntry(tab: .appearance, title: "Enable Dynamic mirror", keywords: ["mirror", "reflection"], highlightID: SettingsTab.appearance.highlightID(for: "Enable Dynamic mirror")),
            SettingsSearchEntry(tab: .appearance, title: "Mirror shape", keywords: ["mirror shape", "circle", "rectangle"], highlightID: SettingsTab.appearance.highlightID(for: "Mirror shape")),
            SettingsSearchEntry(tab: .appearance, title: "Idle Animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Idle Animation")),
            SettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),

            // Lock Screen
            SettingsSearchEntry(tab: .lockScreen, title: "Preview lock screen widgets", keywords: ["preview", "lock screen", "widgets"], highlightID: SettingsTab.lockScreen.highlightID(for: "Preview lock screen widgets")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable lock screen live activity", keywords: ["lock screen", "live activity"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable lock screen live activity")),
            SettingsSearchEntry(tab: .lockScreen, title: "Play lock/unlock sounds", keywords: ["chime", "sound"], highlightID: SettingsTab.lockScreen.highlightID(for: "Play lock/unlock sounds")),
            SettingsSearchEntry(tab: .lockScreen, title: "Material", keywords: ["glass", "frosted", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen media panel", keywords: ["media panel", "lock screen media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen media panel")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show media app icon", keywords: ["app icon", "media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show media app icon")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show panel border", keywords: ["panel border"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show panel border")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable media panel blur", keywords: ["blur", "media panel"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable media panel blur")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen timer", keywords: ["timer widget", "lock screen timer"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen timer")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen weather", keywords: ["weather widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen weather")),
            SettingsSearchEntry(tab: .lockScreen, title: "Layout", keywords: ["inline", "circular", "weather layout"], highlightID: SettingsTab.lockScreen.highlightID(for: "Layout")),
            SettingsSearchEntry(tab: .lockScreen, title: "Weather data provider", keywords: ["wttr", "open meteo"], highlightID: SettingsTab.lockScreen.highlightID(for: "Weather data provider")),
            SettingsSearchEntry(tab: .lockScreen, title: "Temperature unit", keywords: ["celsius", "fahrenheit"], highlightID: SettingsTab.lockScreen.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show location label", keywords: ["location", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show location label")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging status", keywords: ["charging", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging status")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging percentage", keywords: ["charging percentage"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging percentage")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show battery indicator", keywords: ["battery gauge", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use MacBook icon when on battery", keywords: ["laptop icon", "battery"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use MacBook icon when on battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show Bluetooth battery", keywords: ["bluetooth", "gauge"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show Bluetooth battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show AQI widget", keywords: ["air quality", "aqi"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show AQI widget")),
            SettingsSearchEntry(tab: .lockScreen, title: "Air quality scale", keywords: ["aqi", "scale"], highlightID: SettingsTab.lockScreen.highlightID(for: "Air quality scale")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use colored gauges", keywords: ["gauge tint", "monochrome"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use colored gauges")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen reminder", keywords: ["lock screen", "reminder widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen reminder")),
            SettingsSearchEntry(tab: .lockScreen, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.lockScreen.highlightID(for: "Chip color")),
            SettingsSearchEntry(tab: .lockScreen, title: "Reminder alignment", keywords: ["reminder", "alignment", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder alignment")),
            SettingsSearchEntry(tab: .lockScreen, title: "Reminder vertical offset", keywords: ["reminder", "offset", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder vertical offset")),

            // Extensions
            SettingsSearchEntry(tab: .extensions, title: "Enable third-party extensions", keywords: ["extensions", "authorization", "third party"], highlightID: SettingsTab.extensions.highlightID(for: "Enable third-party extensions")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension live activities", keywords: ["extensions", "live activities", "permissions"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension live activities")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension lock screen widgets", keywords: ["extensions", "lock screen", "widgets"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension lock screen widgets")),
            SettingsSearchEntry(tab: .extensions, title: "Enable extension diagnostics logging", keywords: ["extensions", "diagnostics", "logging"], highlightID: SettingsTab.extensions.highlightID(for: "Enable extension diagnostics logging")),
            SettingsSearchEntry(tab: .extensions, title: "Manage app permissions", keywords: ["extensions", "permissions", "apps"], highlightID: SettingsTab.extensions.highlightID(for: "App permissions list")),

            // Shortcuts
            SettingsSearchEntry(tab: .shortcuts, title: "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Enable global keyboard shortcuts")),

            // Quick Launch
            SettingsSearchEntry(tab: .pluginLauncher, title: "Enable Quick Launch", keywords: ["plugin", "launcher", "spotlight", "search", "utools", "quick", "launch", "快捷启动"], highlightID: SettingsTab.pluginLauncher.highlightID(for: "Enable Quick Launch")),
            SettingsSearchEntry(tab: .pluginLauncher, title: "Quick Launch shortcut", keywords: ["plugin", "shortcut", "keyboard"], highlightID: SettingsTab.pluginLauncher.highlightID(for: "Quick Launch Shortcut")),

            // Timer
            SettingsSearchEntry(tab: .timer, title: "Enable timer feature", keywords: ["timer", "enable"], highlightID: SettingsTab.timer.highlightID(for: "Enable timer feature")),
            SettingsSearchEntry(tab: .timer, title: "Mirror macOS Clock timers", keywords: ["system timer", "clock app"], highlightID: SettingsTab.timer.highlightID(for: "Mirror macOS Clock timers")),
            SettingsSearchEntry(tab: .timer, title: "Show lock screen timer widget", keywords: ["lock screen", "timer widget"], highlightID: SettingsTab.timer.highlightID(for: "Show lock screen timer widget")),
            SettingsSearchEntry(tab: .timer, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.timer.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .timer, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.timer.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .timer, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .timer, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.timer.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .timer, title: "Timer tint", keywords: ["timer colour", "preset"], highlightID: SettingsTab.timer.highlightID(for: "Timer tint")),
            SettingsSearchEntry(tab: .timer, title: "Solid colour", keywords: ["timer colour", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Solid colour")),
            SettingsSearchEntry(tab: .timer, title: "Progress style", keywords: ["progress", "bar", "ring"], highlightID: SettingsTab.timer.highlightID(for: "Progress style")),
            SettingsSearchEntry(tab: .timer, title: "Accent colour", keywords: ["accent", "timer"], highlightID: SettingsTab.timer.highlightID(for: "Accent colour")),

            // Stats
            SettingsSearchEntry(tab: .stats, title: "Enable system stats monitoring", keywords: ["stats", "monitoring"], highlightID: SettingsTab.stats.highlightID(for: "Enable system stats monitoring")),
            SettingsSearchEntry(tab: .stats, title: "Stop monitoring after closing the notch", keywords: ["stats", "auto stop"], highlightID: SettingsTab.stats.highlightID(for: "Stop monitoring after closing the notch")),
            SettingsSearchEntry(tab: .stats, title: "CPU Usage", keywords: ["cpu", "graph"], highlightID: SettingsTab.stats.highlightID(for: "CPU Usage")),
            SettingsSearchEntry(tab: .stats, title: "Temperature unit", keywords: ["cpu", "temperature", "celsius", "fahrenheit"], highlightID: SettingsTab.stats.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .stats, title: "Memory Usage", keywords: ["memory", "ram"], highlightID: SettingsTab.stats.highlightID(for: "Memory Usage")),
            SettingsSearchEntry(tab: .stats, title: "GPU Usage", keywords: ["gpu", "graphics"], highlightID: SettingsTab.stats.highlightID(for: "GPU Usage")),
            SettingsSearchEntry(tab: .stats, title: "Network Activity", keywords: ["network", "graph"], highlightID: SettingsTab.stats.highlightID(for: "Network Activity")),
            SettingsSearchEntry(tab: .stats, title: "Disk I/O", keywords: ["disk", "io"], highlightID: SettingsTab.stats.highlightID(for: "Disk I/O")),

            // Clipboard
            SettingsSearchEntry(tab: .clipboard, title: "Enable Clipboard Manager", keywords: ["clipboard", "manager"], highlightID: SettingsTab.clipboard.highlightID(for: "Enable Clipboard Manager")),
            SettingsSearchEntry(tab: .clipboard, title: "Show Clipboard Icon", keywords: ["icon", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Show Clipboard Icon")),
            SettingsSearchEntry(tab: .clipboard, title: "Display Mode", keywords: ["list", "grid", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Display Mode")),
            SettingsSearchEntry(tab: .clipboard, title: "History Size", keywords: ["history", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "History Size")),

            // Screen Assistant
            SettingsSearchEntry(tab: .screenAssistant, title: "Enable Screen Assistant", keywords: ["screen assistant", "ai"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Enable Screen Assistant")),
            SettingsSearchEntry(tab: .screenAssistant, title: "Display Mode", keywords: ["screen assistant", "mode"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Display Mode")),

            // Color Picker
            SettingsSearchEntry(tab: .colorPicker, title: "Enable Color Picker", keywords: ["color picker", "eyedropper"], highlightID: SettingsTab.colorPicker.highlightID(for: "Enable Color Picker")),
            SettingsSearchEntry(tab: .colorPicker, title: "Show Color Picker Icon", keywords: ["color icon", "toolbar"], highlightID: SettingsTab.colorPicker.highlightID(for: "Show Color Picker Icon")),
            SettingsSearchEntry(tab: .colorPicker, title: "Display Mode", keywords: ["color", "list"], highlightID: SettingsTab.colorPicker.highlightID(for: "Display Mode")),
            SettingsSearchEntry(tab: .colorPicker, title: "History Size", keywords: ["color history"], highlightID: SettingsTab.colorPicker.highlightID(for: "History Size")),
            SettingsSearchEntry(tab: .colorPicker, title: "Show All Color Formats", keywords: ["hex", "hsl", "color formats"], highlightID: SettingsTab.colorPicker.highlightID(for: "Show All Color Formats")),

            // Terminal
            SettingsSearchEntry(tab: .terminal, title: "Enable terminal", keywords: ["terminal", "guake", "shell"], highlightID: SettingsTab.terminal.highlightID(for: "Enable terminal")),
            SettingsSearchEntry(tab: .terminal, title: "Shell path", keywords: ["shell", "zsh", "bash", "terminal"], highlightID: SettingsTab.terminal.highlightID(for: "Shell path")),
            SettingsSearchEntry(tab: .terminal, title: "Font size", keywords: ["terminal", "font", "text size"], highlightID: SettingsTab.terminal.highlightID(for: "Font size")),
            SettingsSearchEntry(tab: .terminal, title: "Terminal opacity", keywords: ["terminal", "opacity", "transparency"], highlightID: SettingsTab.terminal.highlightID(for: "Terminal opacity")),
            SettingsSearchEntry(tab: .terminal, title: "Maximum height", keywords: ["terminal", "height", "size"], highlightID: SettingsTab.terminal.highlightID(for: "Maximum height")),
            SettingsSearchEntry(tab: .terminal, title: "Background color", keywords: ["terminal", "background", "color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Background color")),
            SettingsSearchEntry(tab: .terminal, title: "Foreground color", keywords: ["terminal", "foreground", "text color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Foreground color")),
            SettingsSearchEntry(tab: .terminal, title: "Cursor color", keywords: ["terminal", "cursor", "caret", "color"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor color")),
            SettingsSearchEntry(tab: .terminal, title: "Bold as bright", keywords: ["terminal", "bold", "bright", "colors"], highlightID: SettingsTab.terminal.highlightID(for: "Bold as bright")),
            SettingsSearchEntry(tab: .terminal, title: "Cursor style", keywords: ["terminal", "cursor", "block", "underline", "bar", "blink"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor style")),
            SettingsSearchEntry(tab: .terminal, title: "Scrollback lines", keywords: ["terminal", "scrollback", "buffer", "history"], highlightID: SettingsTab.terminal.highlightID(for: "Scrollback lines")),
            SettingsSearchEntry(tab: .terminal, title: "Option as Meta", keywords: ["terminal", "option", "meta", "alt", "key"], highlightID: SettingsTab.terminal.highlightID(for: "Option as Meta")),
            SettingsSearchEntry(tab: .terminal, title: "Mouse reporting", keywords: ["terminal", "mouse", "reporting", "vim", "tmux"], highlightID: SettingsTab.terminal.highlightID(for: "Mouse reporting")),

            // AI Agents
            SettingsSearchEntry(tab: .aiAgent, title: "Enable AI Agent Monitoring", keywords: ["ai", "agent", "monitoring", "codebuddy", "codex", "claude", "workbuddy"], highlightID: SettingsTab.aiAgent.highlightID(for: "Enable AI Agent Monitoring")),
            SettingsSearchEntry(tab: .aiAgent, title: "Show SneakPeek notifications", keywords: ["ai", "agent", "notification", "sneak peek"], highlightID: SettingsTab.aiAgent.highlightID(for: "Show SneakPeek notifications")),
            SettingsSearchEntry(tab: .aiAgent, title: "Play 8-bit sound effects", keywords: ["ai", "agent", "audio", "sound", "8-bit", "chiptune", "feedback"], highlightID: SettingsTab.aiAgent.highlightID(for: "Play 8-bit sound effects")),
            SettingsSearchEntry(tab: .aiAgent, title: "Card font size", keywords: ["ai", "agent", "card", "font", "size", "preview"], highlightID: SettingsTab.aiAgent.highlightID(for: "Card font size")),
            SettingsSearchEntry(tab: .aiAgent, title: "Card max height", keywords: ["ai", "agent", "card", "height", "max height", "preview"], highlightID: SettingsTab.aiAgent.highlightID(for: "Card max height")),
            SettingsSearchEntry(tab: .aiAgent, title: "Expanded max height", keywords: ["ai", "agent", "expanded", "height", "window", "island", "screen", "灵动岛", "展开", "高度"], highlightID: SettingsTab.aiAgent.highlightID(for: "Expanded max height")),
            SettingsSearchEntry(tab: .aiAgent, title: "Agent icons", keywords: ["ai", "agent", "icon", "app icon", "preview", "custom"], highlightID: SettingsTab.aiAgent.highlightID(for: "Agent icons")),
            SettingsSearchEntry(tab: .aiAgent, title: "Finished session retention", keywords: ["ai", "agent", "finished", "retention", "recent", "expanded", "tab"], highlightID: SettingsTab.aiAgent.highlightID(for: "Finished session retention")),
            SettingsSearchEntry(tab: .aiAgent, title: "Auto cleanup", keywords: ["ai", "agent", "cleanup", "stale", "session"], highlightID: SettingsTab.aiAgent.highlightID(for: "Auto cleanup")),
            SettingsSearchEntry(tab: .aiAgent, title: "聊天显示模式", keywords: ["ai", "agent", "chat", "display", "mode", "compact", "detailed", "精简", "详细", "transcript", "对话"], highlightID: SettingsTab.aiAgent.highlightID(for: "Chat display mode")),
            SettingsSearchEntry(tab: .aiAgent, title: "显示思考过程", keywords: ["ai", "agent", "thinking", "思考"], highlightID: SettingsTab.aiAgent.highlightID(for: "Show thinking blocks")),
            SettingsSearchEntry(tab: .aiAgent, title: "显示工具调用详情", keywords: ["ai", "agent", "tool", "details", "工具"], highlightID: SettingsTab.aiAgent.highlightID(for: "Show tool details")),
            SettingsSearchEntry(tab: .aiAgent, title: "显示工具输出", keywords: ["ai", "agent", "tool", "output", "输出"], highlightID: SettingsTab.aiAgent.highlightID(for: "Show tool output")),
        ]
    }

    private func isTabVisible(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .timer, .stats, .clipboard, .screenAssistant, .colorPicker, .shelf, .notes, .terminal, .aiAgent, .pluginLauncher:
            return !enableMinimalisticUI
        default:
            return true
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsForm(tab: .general) {
                GeneralSettings()
            }
        case .liveActivities:
            SettingsForm(tab: .liveActivities) {
                LiveActivitiesSettings()
            }
        case .appearance:
            SettingsForm(tab: .appearance) {
                Appearance()
            }
        case .lockScreen:
            SettingsForm(tab: .lockScreen) {
                LockScreenSettings()
            }
        case .media:
            SettingsForm(tab: .media) {
                Media()
            }
        case .devices:
            SettingsForm(tab: .devices) {
                DevicesSettingsView()
            }
        case .extensions:
            SettingsForm(tab: .extensions) {
                ExtensionsSettingsView()
            }
        case .timer:
            SettingsForm(tab: .timer) {
                TimerSettings()
            }
        case .calendar:
            SettingsForm(tab: .calendar) {
                CalendarSettings()
            }
        case .hudAndOSD:
            SettingsForm(tab: .hudAndOSD) {
                HUDAndOSDSettingsView()
            }
        case .battery:
            SettingsForm(tab: .battery) {
                Charge()
            }
        case .stats:
            SettingsForm(tab: .stats) {
                StatsSettings()
            }
        case .clipboard:
            SettingsForm(tab: .clipboard) {
                ClipboardSettings()
            }
        case .screenAssistant:
            SettingsForm(tab: .screenAssistant) {
                ScreenAssistantSettings()
            }
        case .colorPicker:
            SettingsForm(tab: .colorPicker) {
                ColorPickerSettings()
            }
        case .downloads:
            SettingsForm(tab: .downloads) {
                Downloads()
            }
        case .shelf:
            SettingsForm(tab: .shelf) {
                Shelf()
            }
        case .shortcuts:
            SettingsForm(tab: .shortcuts) {
                Shortcuts()
            }
        case .pluginLauncher:
            SettingsForm(tab: .pluginLauncher) {
                PluginLauncherSettings()
            }
        case .notes:
            SettingsForm(tab: .notes) {
                NotesSettingsView()
            }
        case .terminal:
            SettingsForm(tab: .terminal) {
                TerminalSettings()
            }
        case .aiAgent:
            SettingsForm(tab: .aiAgent) {
                AIAgentSettings()
            }
        case .about:
            if let controller = updaterController {
                SettingsForm(tab: .about) {
                    About(updaterController: controller)
                }
            } else {
                SettingsForm(tab: .about) {
                    About(updaterController: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
                }
            }
        }
    }
}
