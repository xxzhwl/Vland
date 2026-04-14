/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Plugin Launcher - NSPanel management following the project's existing
 * panel manager pattern (see ColorPickerPanelManager, ClipboardPanelManager).
 */

import SwiftUI
import AppKit
import Defaults

// MARK: - Panel Manager

@MainActor
final class PluginLauncherManager: ObservableObject {
    static let shared = PluginLauncherManager()

    private var panel: PluginLauncherPanel?
    private var globalMouseMonitor: Any?
    private var pinnedWindows: [PinnedPluginWindow] = []

    private init() {}

    func showPanel() {
        hidePanel()
        PluginManager.shared.loadInstalledPluginsIfNeeded(in: PluginRegistry.shared)
        PluginLauncherViewModel.shared.prepareForPresentation()

        let newPanel = PluginLauncherPanel()
        self.panel = newPanel
        newPanel.positionCenter()
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            newPanel.makeKey()
        }

        // Listen for global mouse clicks to dismiss search panel
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hidePanel()
            }
        }
    }

    /// Pin the current active plugin into a standalone floating window.
    func pinActivePlugin() {
        let vm = PluginLauncherViewModel.shared
        guard let plugin = vm.activePlugin, let context = vm.pluginContext else { return }

        if let session: WebPluginSession = context.existingCachedObject(forKey: "web-plugin-session:\(plugin.id)") {
            session.captureLatestState { [weak self] in
                self?.presentPinnedWindow(plugin: plugin, context: context, viewModel: vm)
            }
            return
        }

        presentPinnedWindow(plugin: plugin, context: context, viewModel: vm)
    }

    private func presentPinnedWindow(
        plugin: any VlandPlugin,
        context: PluginContext,
        viewModel vm: PluginLauncherViewModel
    ) {
        let pinned = PinnedPluginWindow(context: context, plugin: plugin)
        pinned.positionNearPanel(panel)
        pinned.orderFrontRegardless()
        pinned.makeKeyAndOrderFront(nil)
        pinnedWindows.append(pinned)

        // Reset VM without calling onDeactivate (plugin is still alive in pinned window)
        vm.resetForSearch()

        // Close search panel
        hidePanel()
    }

    func removePinnedWindow(_ window: PinnedPluginWindow) {
        pinnedWindows.removeAll { $0 === window }
    }

    func hidePanel() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        panel?.close()
        panel = nil
    }

    func togglePanel() {
        if let panel = panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }
}

// MARK: - Search Panel

final class PluginLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        setupPanel()
    }

    private func setupPanel() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        styleMask.insert(.fullSizeContentView)

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]

        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        acceptsMouseMovedEvents = true

        let hostingView = NSHostingView(rootView: PluginLauncherView())
        applyPanelCornerMask(hostingView, radius: 16)
        contentView = hostingView

        let preferredSize = CGSize(width: 620, height: 380)
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }

    func positionCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        let x = (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX
        let y = (screenFrame.height - panelFrame.height) / 2 + screenFrame.minY
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Global ESC key handling
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            DispatchQueue.main.async {
                PluginLauncherManager.shared.hidePanel()
            }
        case 125: // Down arrow
            PluginLauncherViewModel.shared.moveSelectionDown()
        case 126: // Up arrow
            PluginLauncherViewModel.shared.moveSelectionUp()
        case 36: // Return
            PluginLauncherViewModel.shared.handleEnter()
        default:
            super.keyDown(with: event)
        }
    }

    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}

// MARK: - Corner Mask Helper

func applyPanelCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}
