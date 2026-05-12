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

import Defaults
import SwiftUI

// MARK: - Page Direction

enum PageDirection {
    case forward, backward
}

// MARK: - Horizontal Scroll Pager (NSEvent-based)

/// An invisible `NSView` that installs a local NSEvent monitor for `.scrollWheel`
/// events and translates horizontal trackpad swipes into `PageDirection` callbacks.
///
/// Design decisions:
/// - Uses a local monitor (not a gesture recognizer) to catch precise scrolling deltas
///   from trackpad two-finger swipes, which `DragGesture` does not recognize.
/// - Returns `event` unmodified so upstream listeners (e.g. music skip gestures)
///   still receive the event; coordination happens via `isHoveringRightPanel`.
/// - Implements a per-gesture lock via `didFlipInCurrentGesture` so a single flick
///   with momentum phase only triggers one page turn.
/// - Falls back to an idle-time gap detector (180ms) when `.began` phase is sporadically
///   missing (short flicks).
final class HorizontalScrollPager {
    private weak var hostView: NSView?
    private var monitor: Any?
    private var accumulatedDX: CGFloat = 0
    private var didFlipInCurrentGesture = false
    private var gestureActive = false
    private var lastEventAt: CFTimeInterval = 0
    private var lastFlipAt: CFTimeInterval = 0
    private let onPage: (PageDirection) -> Void

    private let flipThreshold: CGFloat = 50
    private let flipCooldown: TimeInterval = 0.6
    private let gestureIdleResetInterval: TimeInterval = 0.18

    init(onPage: @escaping (PageDirection) -> Void) {
        self.onPage = onPage
    }

    func attach(to view: NSView) {
        detach()
        hostView = view
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func detach() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        hostView = nil
        accumulatedDX = 0
        didFlipInCurrentGesture = false
        gestureActive = false
    }

    deinit { detach() }

    // MARK: - Event Handler

    private func handle(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        guard let host = hostView, let window = host.window else { return }
        let frameInWindow = host.convert(host.bounds, to: nil)
        guard frameInWindow.contains(event.locationInWindow) else { return }

        let dx = event.scrollingDeltaX
        let now = CACurrentMediaTime()
        let idleGap = now - lastEventAt

        // Gesture start detection
        let isNewGesture = event.phase.contains(.began)
            || event.momentumPhase.contains(.began)
            || (!gestureActive && idleGap > gestureIdleResetInterval)
        if isNewGesture {
            accumulatedDX = 0
            didFlipInCurrentGesture = false
            gestureActive = true
        }
        lastEventAt = now

        // Ignore vertical scrolling
        guard abs(dx) > abs(event.scrollingDeltaY) else {
            handleGestureEndIfNeeded(event)
            return
        }
        // One page per gesture
        guard !didFlipInCurrentGesture else {
            handleGestureEndIfNeeded(event)
            return
        }

        accumulatedDX += dx

        if abs(accumulatedDX) >= flipThreshold, now - lastFlipAt >= flipCooldown {
            let direction: PageDirection = accumulatedDX < 0 ? .forward : .backward
            DispatchQueue.main.async { [onPage] in onPage(direction) }
            lastFlipAt = now
            accumulatedDX = 0
            didFlipInCurrentGesture = true
        }

        handleGestureEndIfNeeded(event)
    }

    private func handleGestureEndIfNeeded(_ event: NSEvent) {
        if event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled) {
            accumulatedDX = 0
            didFlipInCurrentGesture = false
            gestureActive = false
        }
    }
}

// MARK: - NSViewRepresentable Wrapper

private struct HorizontalScrollPagerView: NSViewRepresentable {
    let onPage: (PageDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        // Transparent — we only need it to host the NSEvent monitor
        view.layer?.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.pager.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPage: onPage)
    }

    final class Coordinator {
        let pager: HorizontalScrollPager
        init(onPage: @escaping (PageDirection) -> Void) {
            pager = HorizontalScrollPager(onPage: onPage)
        }
        deinit { pager.detach() }
    }
}

// MARK: - Home Right Panel Host

/// Hosts the right panel content in the Home tab with swipe-based page navigation.
///
/// Cards cycle between `.systemStats` ↔ `.weather` via two-finger horizontal swipes.
/// The `.hidden` state is excluded from pagination — it must be restored through settings.
struct HomeRightPanelHost: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.homeRightPanelContent) private var content
    @State private var lastDirection: PageDirection = .forward

    var body: some View {
        ZStack {
            currentPage
                .id(content)
                .transition(pageTransition)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: content)
        .onHover { hovering in
            vm.isHoveringRightPanel = hovering
        }
        .background(
            HorizontalScrollPagerView { direction in advance(direction) }
        )
    }

    @ViewBuilder
    private var currentPage: some View {
        switch content {
        case .systemStats: SystemStatsHomeView()
        case .weather:     HomeWeatherView()
        case .hidden:      Color.clear.frame(width: 0, height: 0)
        }
    }

    private var pageTransition: AnyTransition {
        let insertEdge: Edge = lastDirection == .forward ? .trailing : .leading
        let removeEdge: Edge = lastDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertEdge).combined(with: .opacity),
            removal: .move(edge: removeEdge).combined(with: .opacity)
        )
    }

    private func advance(_ direction: PageDirection) {
        let pages = HomeRightPanelContent.pageable
        guard pages.count > 1 else { return }
        let i = pages.firstIndex(of: content) ?? 0
        let next: Int
        switch direction {
        case .forward:  next = (i + 1) % pages.count
        case .backward: next = (i - 1 + pages.count) % pages.count
        }
        lastDirection = direction
        content = pages[next]
    }
}

#Preview {
    HomeRightPanelHost()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 200)
        .padding()
}
