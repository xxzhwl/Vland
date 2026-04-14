//
//  SettingsHelpers.swift
//  DynamicIsland
//
//  Split from SettingsView.swift - Shared types and helper views
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

/// Groups for organizing settings tabs in the sidebar.
enum SettingsTabGroup: String, CaseIterable, Identifiable {
    case core
    case mediaAndDisplay
    case system
    case productivity
    case utilities
    case developer
    case integrations
    case info

    var id: String { rawValue }

    /// Display title for the section header.  `nil` means no visible header.
    var title: String? {
        switch self {
        case .core:             return nil
        case .mediaAndDisplay:  return String(localized: "Media & Display")
        case .system:           return String(localized: "System")
        case .productivity:     return String(localized: "Productivity")
        case .utilities:        return String(localized: "Utilities")
        case .developer:        return String(localized: "Developer")
        case .integrations:     return String(localized: "Integrations")
        case .info:             return nil
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case liveActivities
    case appearance
    case lockScreen
    case media
    case devices
    case extensions
    case timer
    case calendar
    case hudAndOSD
    case battery
    case stats
    case clipboard
    case screenAssistant
    case colorPicker
    case downloads
    case shelf
    case shortcuts
    case pluginLauncher
    case notes
    case terminal
    case aiAgent
    case about

    var id: String { rawValue }

    /// Which sidebar group this tab belongs to.
    var group: SettingsTabGroup {
        switch self {
        case .general, .appearance:                                          return .core
        case .media, .liveActivities, .lockScreen, .devices:                 return .mediaAndDisplay
        case .hudAndOSD, .battery:                                           return .system
        case .timer, .calendar, .notes:                                      return .productivity
        case .clipboard, .screenAssistant, .colorPicker, .shelf,
             .downloads, .shortcuts, .pluginLauncher:                             return .utilities
        case .stats, .terminal, .aiAgent:                                     return .developer
        case .extensions:                                                    return .integrations
        case .about:                                                         return .info
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .liveActivities: return String(localized: "Live Activities")
        case .appearance: return String(localized: "Appearance")
        case .lockScreen: return String(localized: "Lock Screen")
        case .media: return String(localized: "Media")
        case .devices: return String(localized: "Devices")
        case .extensions: return String(localized: "Extensions")
        case .timer: return String(localized: "Timer")
        case .calendar: return String(localized: "Calendar")
        case .hudAndOSD: return String(localized: "Controls")
        case .battery: return String(localized: "Battery")
        case .stats: return String(localized: "Stats")
        case .clipboard: return String(localized: "Clipboard")
        case .screenAssistant: return String(localized: "Screen Assistant")
        case .colorPicker: return String(localized: "Color Picker")
        case .downloads: return String(localized: "Downloads")
        case .shelf: return String(localized: "Shelf")
        case .shortcuts: return String(localized: "Shortcuts")
        case .pluginLauncher: return String(localized: "Quick Launch")
        case .notes: return String(localized: "Notes")
        case .terminal: return String(localized: "Terminal")
        case .aiAgent: return String(localized: "AI Agents")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .lockScreen: return "lock.laptopcomputer"
        case .media: return "play.laptopcomputer"
        case .devices: return "headphones"
        case .extensions: return "puzzlepiece.extension"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .stats: return "chart.xyaxis.line"
        case .clipboard: return "clipboard"
        case .screenAssistant: return "brain.head.profile"
        case .colorPicker: return "eyedropper"
        case .downloads: return "square.and.arrow.down"
        case .shelf: return "books.vertical"
        case .shortcuts: return "keyboard"
        case .pluginLauncher: return "puzzlepiece.extension"
        case .notes: return "note.text"
        case .terminal: return "apple.terminal"
        case .aiAgent: return "cpu"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .blue
        case .liveActivities: return .pink
        case .appearance: return .purple
        case .lockScreen: return .orange
        case .media: return .green
        case .devices: return Color(red: 0.1, green: 0.11, blue: 0.12)
        case .extensions: return Color(red: 0.557, green: 0.353, blue: 0.957)
        case .timer: return .red
        case .calendar: return .cyan
        case .hudAndOSD: return .indigo
        case .battery: return Color(red: 0.202, green: 0.783, blue: 0.348, opacity: 1.000)
        case .stats: return .teal
        case .clipboard: return .mint
        case .screenAssistant: return .pink
        case .colorPicker: return .accentColor
        case .downloads: return .gray
        case .shelf: return .brown
        case .shortcuts: return .orange
        case .pluginLauncher: return .indigo
        case .notes: return Color(red: 0.979, green: 0.716, blue: 0.153, opacity: 1.000)
        case .terminal: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .aiAgent: return .cyan
        case .about: return .secondary
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

struct SettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?

    var id: String { "\(tab.rawValue)-\(title)" }
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        let tab: SettingsTab
    }

    @Published var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    func focus(on entry: SettingsSearchEntry) {
        guard let highlightID = entry.highlightID else { return }
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: entry.tab)
        activateHighlight(id: highlightID)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    highlightCoordinator.consumeScrollRequest(request)
                }
        }
    }
}


func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "Accessibility permission required",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "Request Access",
        openSettingsButtonTitle: String = "Open Settings",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(requestButtonTitle) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(openSettingsButtonTitle) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HUD()
}
