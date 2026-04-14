/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
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

import Combine
import Defaults
import SwiftUI

enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case timer
    case reminder
    case recording
    case doNotDisturb
    case bluetoothAudio
    case privacy
    case lockScreen
    case capsLock
    case aiAgent
    case extensionLiveActivity(bundleID: String, activityID: String)
}

extension SneakContentType {
    static func == (lhs: SneakContentType, rhs: SneakContentType) -> Bool {
        switch (lhs, rhs) {
        case (.brightness, .brightness),
             (.volume, .volume),
             (.backlight, .backlight),
             (.music, .music),
             (.mic, .mic),
             (.battery, .battery),
             (.download, .download),
             (.timer, .timer),
             (.reminder, .reminder),
             (.recording, .recording),
             (.doNotDisturb, .doNotDisturb),
             (.bluetoothAudio, .bluetoothAudio),
             (.privacy, .privacy),
             (.lockScreen, .lockScreen),
             (.capsLock, .capsLock),
             (.aiAgent, .aiAgent):
            return true
        case let (.extensionLiveActivity(lb, la), .extensionLiveActivity(rb, ra)):
            return lb == rb && la == ra
        default:
            return false
        }
    }
}

extension SneakContentType {
    var isExtensionPayload: Bool {
        if case .extensionLiveActivity = self {
            return true
        }
        return false
    }
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var duration: TimeInterval = 1.5
    var value: CGFloat = 0
    var icon: String = ""
    var title: String = ""
    var subtitle: String = ""
    var accentColor: Color?
    var styleOverride: SneakPeekStyle? = nil
    var targetScreenName: String? = nil
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

class DynamicIslandViewCoordinator: ObservableObject {
    static let shared = DynamicIslandViewCoordinator()
    static let tabSwitchAnimation = Animation.easeInOut(duration: 0.22)
    static let tabSwitchTravel: CGFloat = 18
    private var cancellables = Set<AnyCancellable>()
    
    private static let tabOrder: [NotchViews] = [.home, .shelf, .timer, .stats, .colorPicker, .notes, .clipboard, .terminal, .aiAgent, .extensionExperience]
    
    /// Direction of the most recent tab switch (true = forward/right, false = backward/left)
    @Published var tabSwitchForward: Bool = true
    
    @Published var currentView: NotchViews = .home {
        didSet {
            if Defaults[.enableMinimalisticUI] && currentView != .home {
                currentView = .home
                return
            }
            // Track direction before SwiftUI re-renders
            let oldIdx = Self.tabOrder.firstIndex(of: oldValue) ?? 0
            let newIdx = Self.tabOrder.firstIndex(of: currentView) ?? 0
            tabSwitchForward = newIdx >= oldIdx
            handleStatsTabTransition(from: oldValue, to: currentView)
        }
    }
    
    @Published var statsSecondRowExpansion: CGFloat = 1
    @Published var notesLayoutState: NotesLayoutState = .list
    @Published var selectedExtensionExperienceID: String?
    
    
    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("timerLiveActivityEnabled") var timerLiveActivityEnabled: Bool = true

    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.timerDisplayMode) private var timerDisplayMode
    
    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if TrayDrop.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }
    
    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @AppStorage("hudReplacement") var hudReplacement: Bool = true
    
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }
    
    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"

    @Published var optionKeyPressed: Bool = true

    private let extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    
    private init() {
        selectedScreen = preferredScreen
        Defaults.publisher(.timerDisplayMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleTimerDisplayModeChange(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableTimerFeature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleTimerFeatureToggle(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableMinimalisticUI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleMinimalisticModeChange(change.newValue)
            }
            .store(in: &cancellables)

        AIAgentManager.shared.$sessions
            .map { _ in () }
            .merge(with: AIAgentManager.shared.$displayHeartbeat.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAIAgentVisibilityChange()
            }
            .store(in: &cancellables)

        AIAgentManager.shared.$latestInteractionPresentationID
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAIAgentInteractionPresentation()
            }
            .store(in: &cancellables)

        extensionNotchExperienceManager.$activeExperiences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] experiences in
                self?.handleExtensionExperienceSnapshot(experiences)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableThirdPartyExtensions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExtensionFeatureToggle()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableExtensionNotchExperiences)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExtensionFeatureToggle()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableExtensionNotchTabs)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExtensionFeatureToggle()
            }
            .store(in: &cancellables)

        handleExtensionExperienceSnapshot(extensionNotchExperienceManager.activeExperiences)

        // Observe all tab-affecting settings to enforce minimum notch width
        Publishers.MergeMany(
            Defaults.publisher(.showStandardMediaControls).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showCalendar).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showMirror).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.dynamicShelf).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTimerFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.timerDisplayMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableStatsFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableNotes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableClipboardManager).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.clipboardDisplayMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTerminalFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableAIAgentFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableMinimalisticUI).map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { _ in
            enforceMinimumNotchWidth()
        }
        .store(in: &cancellables)

        // Enforce minimum width on launch for existing configurations
        enforceMinimumNotchWidth()
    }

    private func handleStatsTabTransition(from oldValue: NotchViews, to newValue: NotchViews) {
        guard oldValue != newValue else { return }
        if newValue == .stats && Defaults[.enableStatsFeature] {
            statsSecondRowExpansion = 1
        }
    }

    private func handleTimerDisplayModeChange(_ mode: TimerDisplayMode) {
        guard mode == .popover, currentView == .timer else { return }
        switchToView(.home)
    }

    private func handleTimerFeatureToggle(_ isEnabled: Bool) {
        guard !isEnabled, currentView == .timer else { return }
        switchToView(.home)
    }

    private func handleMinimalisticModeChange(_ isEnabled: Bool) {
        guard isEnabled else { return }
        if currentView != .home {
            switchToView(.home)
        }
    }

    private func handleAIAgentVisibilityChange() {
        guard currentView == .aiAgent else { return }
        guard Defaults[.enableAIAgentFeature] else {
            switchToView(.home)
            return
        }
    }

    private func handleAIAgentInteractionPresentation() {
        guard Defaults[.enableAIAgentFeature], !Defaults[.enableMinimalisticUI] else { return }
        if AIAgentManager.shared.hasPendingApproval {
            switchToView(.aiAgent, animated: false)
            toggleExpandingView(status: true, type: .aiAgent)
            return
        }
        if let delegate = AppDelegate.shared, delegate.vm.notchState == .closed {
            delegate.vm.open()
        }
        switchToView(.aiAgent)
    }

    private func handleExtensionExperienceSnapshot(_ experiences: [ExtensionNotchExperiencePayload]) {
        guard extensionTabsAllowed else {
            selectedExtensionExperienceID = nil
            resetExtensionViewIfNeeded()
            return
        }

        let tabCapablePayloads = experiences.filter { $0.descriptor.tab != nil }
        guard !tabCapablePayloads.isEmpty else {
            selectedExtensionExperienceID = nil
            resetExtensionViewIfNeeded()
            return
        }

        if let currentID = selectedExtensionExperienceID,
           tabCapablePayloads.contains(where: { $0.descriptor.id == currentID }) {
            return
        }

        selectedExtensionExperienceID = tabCapablePayloads.first?.descriptor.id
    }

    private func handleExtensionFeatureToggle() {
        handleExtensionExperienceSnapshot(extensionNotchExperienceManager.activeExperiences)
    }

    private func resetExtensionViewIfNeeded() {
        guard currentView == .extensionExperience else { return }
        switchToView(.home)
    }

    private var extensionTabsAllowed: Bool {
        Defaults[.enableThirdPartyExtensions]
        && Defaults[.enableExtensionNotchExperiences]
        && Defaults[.enableExtensionNotchTabs]
    }

    func switchToView(_ view: NotchViews, extensionExperienceID: String? = nil, animated: Bool = true) {
        let resolvedExtensionExperienceID = view == .extensionExperience
            ? (extensionExperienceID ?? selectedExtensionExperienceID)
            : nil

        let isSameSelection: Bool
        if view == .extensionExperience {
            isSameSelection = currentView == view && selectedExtensionExperienceID == resolvedExtensionExperienceID
        } else {
            isSameSelection = currentView == view
        }

        guard !isSameSelection else { return }

        let updateSelection = {
            self.selectedExtensionExperienceID = resolvedExtensionExperienceID
            self.currentView = view
        }

        if animated {
            withAnimation(Self.tabSwitchAnimation) {
                updateSelection()
            }
        } else {
            updateSelection()
        }
    }
    
    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        title: String = "",
        subtitle: String = "",
        accentColor: Color? = nil,
        styleOverride: SneakPeekStyle? = nil,
        onScreen targetScreen: NSScreen? = nil
    ) {
        let resolvedDuration: TimeInterval
        switch type {
        case .timer:
            resolvedDuration = 10
        case .reminder:
            resolvedDuration = Defaults[.reminderSneakPeekDuration]
        case .extensionLiveActivity:
            resolvedDuration = duration
        default:
            resolvedDuration = duration
        }
        let bypassedTypes: [SneakContentType] = [.music, .timer, .reminder, .bluetoothAudio, .aiAgent]
        
        // Check if it's an extension type
        let isExtensionType: Bool
        if case .extensionLiveActivity = type {
            isExtensionType = true
        } else {
            isExtensionType = false
        }
        
        if !isExtensionType && !bypassedTypes.contains(type) && !Defaults[.enableSystemHUD] {
            return
        }
        let nextSneakPeek = Swift.type(of: self.sneakPeek).init(
            show: status,
            type: type,
            duration: resolvedDuration,
            value: value,
            icon: icon,
            title: title,
            subtitle: subtitle,
            accentColor: accentColor,
            styleOverride: styleOverride,
            targetScreenName: targetScreen?.localizedName
        )

        DispatchQueue.main.async {
            self.backgroundRestoreTask?.cancel()

            if status {
                print("🔵 [toggleSneakPeek] show: type=\(type), current=\(self.sneakPeek.type) showing=\(self.sneakPeek.show)")

                if Self.isPersistentRestorableType(type),
                   self.sneakPeek.show,
                   Self.isTransientType(self.sneakPeek.type) {
                    print("🔵 [toggleSneakPeek] stored as background (persistent override)")
                    self.backgroundSneakPeek = nextSneakPeek
                    return
                }

                // If a transient type (e.g. volume) arrives while a protected type
                // (e.g. bluetoothAudio) is showing, store it as background instead
                // of overriding the protected HUD
                if Self.isTransientType(type),
                   self.sneakPeek.show,
                   Self.isProtectedType(self.sneakPeek.type) {
                    print("🔵 [toggleSneakPeek] transient \(type) deferred — protected \(self.sneakPeek.type) is showing")
                    self.backgroundSneakPeek = nextSneakPeek
                    return
                }

                if Self.isTransientType(type) {
                    self.saveCurrentSneakPeekIfPersistent()
                } else if Self.isPersistentRestorableType(type) {
                    self.backgroundSneakPeek = nil
                }

                withAnimation(.smooth(duration: 0.3)) {
                    self.sneakPeek = nextSneakPeek
                }
                return
            }

            self.hideSneakPeekIfNeeded(type: type)
        }
    }

    private var sneakPeekTask: Task<Void, Never>?
    private var backgroundSneakPeek: sneakPeek?
    private var backgroundRestoreTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()
        
        // Don't schedule auto-hide if duration is infinite (for persistent indicators like Caps Lock)
        guard duration.isFinite else { return }

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    // Hide the sneak peek with the correct type that was showing
                    self.toggleSneakPeek(status: false, type: self.sneakPeek.type)
                }
            }
        }
    }
    
    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeek.duration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    /// Types that should not be overridden by transient HUDs (e.g. volume, brightness)
    /// while they are actively showing. The transient HUD is stored in backgroundSneakPeek
    /// and restored after the protected HUD auto-hides.
    private static func isProtectedType(_ type: SneakContentType) -> Bool {
        switch type {
        case .bluetoothAudio:
            return true
        default:
            return false
        }
    }

    private static func isTransientType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .music:
            return true
        default:
            return false
        }
    }

    private static func isPersistentRestorableType(_ type: SneakContentType) -> Bool {
        type == .aiAgent
    }

    private func saveCurrentSneakPeekIfPersistent() {
        guard sneakPeek.show,
              (Self.isPersistentRestorableType(sneakPeek.type) || Self.isProtectedType(sneakPeek.type)) else { return }
        backgroundSneakPeek = sneakPeek
    }

    private func hideSneakPeekIfNeeded(type: SneakContentType) {
        if type == .aiAgent {
            backgroundSneakPeek = nil
        }

        guard sneakPeek.show, sneakPeek.type == type else { return }

        let shouldRestoreBackground = Self.isTransientType(type) || Self.isProtectedType(type)
        var hiddenSneakPeek = sneakPeek
        hiddenSneakPeek.show = false

        withAnimation(.smooth(duration: 0.3)) {
            sneakPeek = hiddenSneakPeek
        }

        guard shouldRestoreBackground else { return }
        scheduleBackgroundSneakPeekRestoreIfNeeded()
    }

    private func scheduleBackgroundSneakPeekRestoreIfNeeded(after delay: TimeInterval = 0.4) {
        backgroundRestoreTask?.cancel()
        guard backgroundSneakPeek != nil else { return }

        backgroundRestoreTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.restoreBackgroundSneakPeekIfNeeded()
            }
        }
    }

    private func restoreBackgroundSneakPeekIfNeeded() {
        guard !sneakPeek.show, let backgroundSneakPeek else { return }
        guard shouldRestore(backgroundSneakPeek) else {
            self.backgroundSneakPeek = nil
            return
        }

        self.backgroundSneakPeek = nil
        withAnimation(.smooth(duration: 0.3)) {
            sneakPeek = backgroundSneakPeek
        }
    }

    private func shouldRestore(_ peek: sneakPeek) -> Bool {
        switch peek.type {
        case .aiAgent:
            return AIAgentManager.shared.hasRestorableTodoSneakPeek
        default:
            return false
        }
    }
    
    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?
    
    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                // Only auto-hide for battery, not for downloads (DownloadManager handles that)
                if expandingView.type != .download {
                    let duration: TimeInterval = 3
                    expandingViewTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(duration))
                        guard let self = self, !Task.isCancelled else { return }
                        self.toggleExpandingView(status: false, type: .battery)
                    }
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    
    func showEmpty() {
        currentView = .home
    }
    
    // MARK: - Clipboard Management
    @Published var shouldToggleClipboardPopover: Bool = false
    
    func toggleClipboardPopover() {
        // Toggle the published property to trigger UI updates
        shouldToggleClipboardPopover.toggle()
    }
}
