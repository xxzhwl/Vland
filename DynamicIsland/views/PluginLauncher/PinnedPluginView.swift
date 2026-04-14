/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * Pinned Plugin Window - Standalone floating window for a pinned plugin.
 * Reuses the existing PluginContext so the plugin's content (e.g. WebView)
 * is preserved when pinning.
 */

import SwiftUI
import AppKit

// MARK: - View

@MainActor
struct PinnedPluginView: View {
    let plugin: any VlandPlugin
    let context: PluginContext
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with solid background
            HStack(spacing: 8) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(plugin.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor).opacity(0.85))

            Divider().opacity(0.3)

            // Plugin content - reuses the existing context
            plugin.makeView(context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor).opacity(0.96))
    }
}

// MARK: - NSPanel

@MainActor
final class PinnedPluginWindow: NSPanel {
    let pluginContext: PluginContext

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Create a pinned window that reuses an existing PluginContext.
    init(context: PluginContext, plugin: any VlandPlugin) {
        self.pluginContext = context
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        // Redirect dismiss to close this pinned window instead of the search panel
        pluginContext.updateDismiss { [weak self] in self?.close() }
        setup(plugin: plugin)
    }

    private func setup(plugin: any VlandPlugin) {
        title = plugin.title
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        minSize = NSSize(width: 420, height: 280)
        animationBehavior = .utilityWindow

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        acceptsMouseMovedEvents = true

        let view = PinnedPluginView(
            plugin: plugin,
            context: pluginContext,
            onClose: { [weak self] in self?.close() }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(NSSize(width: 580, height: 420))
        applyPanelCornerMask(hostingView, radius: 16)
        contentView = hostingView
        setContentSize(NSSize(width: 580, height: 420))
    }

    /// Position to the right of the search panel, or center if no reference.
    func positionNearPanel(_ searchPanel: NSPanel?) {
        if let searchPanel, searchPanel.isVisible {
            let searchFrame = searchPanel.frame
            let pinnedFrame = frame
            let offset: CGFloat = 24
            var origin = NSPoint(x: searchFrame.maxX + offset, y: searchFrame.origin.y)
            // Keep on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                if origin.x + pinnedFrame.width > screenFrame.maxX {
                    origin.x = screenFrame.minX
                }
                if origin.y + pinnedFrame.height > screenFrame.maxY {
                    origin.y = screenFrame.maxY - pinnedFrame.height
                }
                if origin.y < screenFrame.minY {
                    origin.y = screenFrame.minY
                }
            }
            setFrameOrigin(origin)
        } else {
            positionCenter()
        }
    }

    private func positionCenter() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let f = frame
        setFrameOrigin(NSPoint(
            x: (sf.width - f.width) / 2 + sf.minX,
            y: (sf.height - f.height) / 2 + sf.minY
        ))
    }

    // ESC closes this pinned window
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func close() {
        PluginLauncherManager.shared.removePinnedWindow(self)
        super.close()
    }

    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}
