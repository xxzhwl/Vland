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

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Defaults
import Foundation
import SwiftUI

// MARK: - Screenshot Capture
class ScreenshotSnippingTool: NSObject, ObservableObject {
    static let shared = ScreenshotSnippingTool()

    @Published var isSnipping = false
    private var completion: ((ScreenshotCaptureResult) -> Void)?
    private let captureQueue = DispatchQueue(label: "app.vland.screenshot.capture", qos: .userInitiated)
    private var interactiveSession: InteractiveSnippingSession?

    struct ScreenshotCaptureResult {
        let url: URL
        let image: NSImage
        let selectionRect: CGRect?
    }

    enum ScreenshotType {
        case full
        case window
        case area

        var processArguments: [String] {
            switch self {
            case .full:
                return ["-c"]
            case .window:
                return ["-cw"]
            case .area:
                return ["-cs"]
            }
        }

        var displayName: String {
            switch self {
            case .full: return "Full Screen"
            case .window: return "Window"
            case .area: return "Area"
            }
        }

        var iconName: String {
            switch self {
            case .full: return "rectangle.dashed"
            case .window: return "macwindow"
            case .area: return "viewfinder.rectangular"
            }
        }
    }

    func startSnipping(type: ScreenshotType = .area, completion: @escaping (ScreenshotCaptureResult) -> Void) {
        guard !isSnipping else { return }
        self.completion = completion
        isSnipping = true
        takeScreenshot(type: type)
    }

    func startAreaScreenshot(completion: @escaping (ScreenshotCaptureResult) -> Void) {
        startSnipping(type: .area, completion: completion)
    }

    func startFullScreenshot(completion: @escaping (ScreenshotCaptureResult) -> Void) {
        startSnipping(type: .full, completion: completion)
    }

    func startWindowScreenshot(completion: @escaping (ScreenshotCaptureResult) -> Void) {
        startSnipping(type: .window, completion: completion)
    }

    private func takeScreenshot(type: ScreenshotType) {
        switch type {
        case .full:
            takeSystemScreenshot(type: type)
        case .window, .area:
            startInteractiveSnipping(type: type)
        }
    }

    private func takeSystemScreenshot(type: ScreenshotType) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = type.processArguments

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                getImageFromPasteboard()
            } else {
                finishSnipping()
            }
        } catch {
            print("❌ ScreenshotTool: Failed to run screencapture: \(error)")
            finishSnipping()
        }
    }

    private func startInteractiveSnipping(type: ScreenshotType) {
        DispatchQueue.main.async {
            guard self.isSnipping else { return }

            self.interactiveSession?.cancel()
            let session = InteractiveSnippingSession(
                type: type,
                onCapture: { [weak self] selectionRect in
                    self?.captureSelection(in: selectionRect)
                },
                onCancel: { [weak self] in
                    self?.finishSnipping()
                }
            )
            self.interactiveSession = session
            session.start()
        }
    }

    private func captureSelection(in selectionRect: CGRect) {
        let rect = selectionRect.standardized.integral
        guard rect.width >= 2, rect.height >= 2 else {
            finishSnipping()
            return
        }

        DispatchQueue.main.async {
            self.interactiveSession = nil
        }

        captureQueue.async { [weak self] in
            guard let self else { return }

            if let image = self.captureSelectionWithSystemTool(in: rect) {
                DispatchQueue.main.async {
                    self.saveImageAndComplete(image: image, selectionRect: rect)
                }
                return
            }

            guard CGPreflightScreenCaptureAccess() else {
                print("❌ ScreenshotTool: Screen capture permission unavailable for custom selection")
                self.finishSnipping()
                return
            }

            let quartzRect = ScreenshotGeometry.quartzRect(from: rect)
            guard let cgImage = CGWindowListCreateImage(
                quartzRect,
                [.optionOnScreenOnly],
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                print("❌ ScreenshotTool: Failed to capture custom selection")
                self.finishSnipping()
                return
            }

            let image = NSImage(cgImage: cgImage, size: rect.size)
            DispatchQueue.main.async {
                self.saveImageAndComplete(image: image, selectionRect: rect)
            }
        }
    }

    private func captureSelectionWithSystemTool(in selectionRect: CGRect) -> NSImage? {
        let quartzRect = ScreenshotGeometry.quartzRect(from: selectionRect)
        let rectArgument = [
            Int(quartzRect.minX.rounded(.down)),
            Int(quartzRect.minY.rounded(.down)),
            max(Int(quartzRect.width.rounded(.up)), 1),
            max(Int(quartzRect.height.rounded(.up)), 1)
        ]
        .map(String.init)
        .joined(separator: ",")

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vland-selection-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-R", rectArgument, temporaryURL.path]

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0,
                  let image = NSImage(contentsOf: temporaryURL) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                return nil
            }

            try? FileManager.default.removeItem(at: temporaryURL)
            return image
        } catch {
            print("❌ ScreenshotTool: System rect capture failed: \(error)")
            try? FileManager.default.removeItem(at: temporaryURL)
            return nil
        }
    }

    private func getImageFromPasteboard() {
        guard NSPasteboard.general.canReadItem(withDataConformingToTypes: NSImage.imageTypes),
              let image = NSImage(pasteboard: NSPasteboard.general) else {
            finishSnipping()
            return
        }

        saveImageAndComplete(image: image, selectionRect: nil)
    }

    private func saveImageAndComplete(image: NSImage, selectionRect: CGRect?) {
        let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let autoSave = Defaults[.autoSaveScreenAssistantScreenshots]
        let screenshotDir = autoSave ? ScreenAssistantManager.screenshotDataDirectory : ScreenAssistantManager.temporaryScreenshotDirectory
        let screenshotURL = screenshotDir.appendingPathComponent(filename)

        guard let imageData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: imageData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            finishSnipping()
            return
        }

        do {
            copyImageToPasteboard(image)
            try pngData.write(to: screenshotURL)

            let callback = self.completion
            self.completion = nil
            finishSnipping()

            DispatchQueue.main.async {
                callback?(ScreenshotCaptureResult(url: screenshotURL, image: image, selectionRect: selectionRect))
            }
        } catch {
            print("❌ ScreenshotTool: Failed to save image: \(error)")
            finishSnipping()
        }
    }

    private func copyImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func finishSnipping() {
        DispatchQueue.main.async {
            self.interactiveSession = nil
            self.isSnipping = false
            self.completion = nil
        }
    }

    func cancelSnipping() {
        DispatchQueue.main.async {
            if let session = self.interactiveSession {
                session.cancel()
            } else {
                self.finishSnipping()
            }
        }
    }
}

// MARK: - Interactive Snipping
private enum ScreenshotGeometry {
    static func quartzRect(from appKitRect: CGRect) -> CGRect {
        let rect = appKitRect.standardized
        return CGRect(
            x: rect.minX,
            y: referenceMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitRect(fromQuartzRect quartzRect: CGRect) -> CGRect {
        CGRect(
            x: quartzRect.minX,
            y: referenceMaxY - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    private static var referenceMaxY: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? NSScreen.screens.map(\.frame.maxY).max()
            ?? 0
    }
}

private struct ScreenshotWindowCandidate {
    let frame: CGRect

    var area: CGFloat {
        frame.area
    }

    func contains(_ point: CGPoint) -> Bool {
        frame.insetBy(dx: -1, dy: -1).contains(point)
    }

    static func bestMatch(at point: CGPoint, excluding processID: pid_t) -> ScreenshotWindowCandidate? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var matchingCandidates: [ScreenshotWindowCandidate] = []

        for windowInfo in windowList {
            let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? 0
            guard ownerPID != processID else { continue }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }

            let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.05 else { continue }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else { continue }
            var quartzRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &quartzRect) else { continue }

            let appKitRect = ScreenshotGeometry.appKitRect(fromQuartzRect: quartzRect).standardized
            guard appKitRect.width >= 80, appKitRect.height >= 50 else { continue }

            let candidate = ScreenshotWindowCandidate(frame: appKitRect)
            if candidate.contains(point) {
                matchingCandidates.append(candidate)
            }
        }

        return matchingCandidates.enumerated().min { lhs, rhs in
            if abs(lhs.element.area - rhs.element.area) > 1 {
                return lhs.element.area < rhs.element.area
            }

            return lhs.offset < rhs.offset
        }?.element
    }
}

private final class InteractiveSnippingSession {
    private let type: ScreenshotSnippingTool.ScreenshotType
    private let onCapture: (CGRect) -> Void
    private let onCancel: () -> Void

    private var windows: [ScreenshotOverlayWindow] = []
    private var cursorPushed = false
    private var isFinishing = false

    private(set) var mouseLocation = NSEvent.mouseLocation
    private(set) var hoveredWindow: ScreenshotWindowCandidate?
    private(set) var dragStart: CGPoint?
    private(set) var dragCurrent: CGPoint?
    private(set) var isDragging = false

    init(
        type: ScreenshotSnippingTool.ScreenshotType,
        onCapture: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.type = type
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    var effectiveSelectionRect: CGRect? {
        if type == .window {
            return hoveredWindow?.frame
        }

        if isDragging, let dragRect = dragRect {
            return dragRect
        }

        return hoveredWindow?.frame
    }

    var instructionText: String {
        switch type {
        case .full:
            return ""
        case .window:
            return "Move to highlight a window. Click to capture. Esc to cancel."
        case .area:
            return "Drag to select. Click to capture the highlighted window. Esc to cancel."
        }
    }

    private var dragRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        let rect = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
        return rect.width >= 2 && rect.height >= 2 ? rect : nil
    }

    func start() {
        guard !NSScreen.screens.isEmpty else {
            onCancel()
            return
        }

        let initialMouse = NSEvent.mouseLocation
        mouseLocation = initialMouse

        for screen in NSScreen.screens {
            let overlayWindow = ScreenshotOverlayWindow(screen: screen, session: self)
            windows.append(overlayWindow)
            overlayWindow.orderFrontRegardless()
        }

        hoveredWindow = ScreenshotWindowCandidate.bestMatch(at: initialMouse, excluding: getpid())

        if let keyWindow = windows.first(where: { $0.screenFrame.contains(initialMouse) }) ?? windows.first {
            NSApp.activate(ignoringOtherApps: true)
            keyWindow.makeKeyAndOrderFront(nil)
        }

        NSCursor.crosshair.push()
        cursorPushed = true
        refreshOverlays()
    }

    func cancel() {
        finish {
            self.onCancel()
        }
    }

    func handle(event: NSEvent) -> Bool {
        switch event.type {
        case .mouseMoved:
            mouseLocation = globalLocation(for: event)
            refreshHoveredWindow(at: mouseLocation)
            refreshOverlays()
            return true

        case .leftMouseDown:
            let point = globalLocation(for: event)
            mouseLocation = point
            dragStart = point
            dragCurrent = point
            isDragging = false
            refreshHoveredWindow(at: point)
            refreshOverlays()
            return true

        case .leftMouseDragged:
            let point = globalLocation(for: event)
            mouseLocation = point
            dragCurrent = point

            if type == .area, let dragStart, distance(from: dragStart, to: point) >= 4 {
                isDragging = true
            }

            if !isDragging {
                refreshHoveredWindow(at: point)
            }

            refreshOverlays()
            return true

        case .leftMouseUp:
            mouseLocation = globalLocation(for: event)
            dragCurrent = mouseLocation

            if type == .area, isDragging, let rect = dragRect {
                finish(with: rect)
            } else if let windowRect = hoveredWindow?.frame {
                finish(with: windowRect)
            } else {
                dragStart = nil
                dragCurrent = nil
                isDragging = false
                refreshHoveredWindow(at: mouseLocation)
                refreshOverlays()
            }

            return true

        case .rightMouseDown:
            cancel()
            return true

        case .keyDown:
            if event.keyCode == 53 {
                cancel()
                return true
            }

            if (event.keyCode == 36 || event.keyCode == 76), let rect = effectiveSelectionRect {
                finish(with: rect)
                return true
            }

            return true

        default:
            return false
        }
    }

    private func finish(with selectionRect: CGRect) {
        let finalRect = selectionRect.standardized.integral
        guard finalRect.width >= 2, finalRect.height >= 2 else {
            cancel()
            return
        }

        finish {
            self.onCapture(finalRect)
        }
    }

    private func finish(_ action: @escaping () -> Void) {
        guard !isFinishing else { return }
        isFinishing = true

        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }

        let openWindows = windows
        windows.removeAll()

        for window in openWindows {
            window.orderOut(nil)
            window.close()
        }

        DispatchQueue.main.async {
            action()
        }
    }

    fileprivate func refreshOverlays() {
        windows.forEach { $0.overlayView.needsDisplay = true }
    }

    private func refreshHoveredWindow(at point: CGPoint) {
        hoveredWindow = ScreenshotWindowCandidate.bestMatch(at: point, excluding: getpid())
    }

    private func globalLocation(for event: NSEvent) -> CGPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

private final class ScreenshotOverlayWindow: NSWindow {
    let screenFrame: CGRect
    let overlayView: ScreenshotOverlayView
    private weak var snippingSession: InteractiveSnippingSession?

    init(screen: NSScreen, session: InteractiveSnippingSession) {
        screenFrame = screen.frame
        overlayView = ScreenshotOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame, session: session)
        snippingSession = session

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        title = "Vland Screenshot Overlay"
        sharingType = .none
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if snippingSession?.handle(event: event) == true {
            return
        }
        super.sendEvent(event)
    }
}

private final class ScreenshotOverlayView: NSView {
    private let screenFrame: CGRect
    private weak var session: InteractiveSnippingSession?

    init(frame frameRect: CGRect, screenFrame: CGRect, session: InteractiveSnippingSession) {
        self.screenFrame = screenFrame
        self.session = session
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let session else { return }

        drawDimmedBackground(using: session)
        drawSelection(using: session)
        drawCrosshair(using: session)
        drawInstruction(using: session)
    }

    private func drawDimmedBackground(using session: InteractiveSnippingSession) {
        let path = NSBezierPath(rect: bounds)
        if let localSelection = localRect(from: session.effectiveSelectionRect) {
            path.append(NSBezierPath(rect: localSelection))
            path.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.48).setFill()
        path.fill()
    }

    private func drawSelection(using session: InteractiveSnippingSession) {
        guard let globalSelection = session.effectiveSelectionRect,
              let localSelection = localRect(from: globalSelection) else {
            return
        }

        let accentPath = NSBezierPath(roundedRect: localSelection.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        accentPath.lineWidth = 4
        accentPath.stroke()

        let borderPath = NSBezierPath(roundedRect: localSelection.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        borderPath.lineWidth = 2
        borderPath.stroke()

        drawHandles(around: localSelection)
        drawSizeBadge(for: globalSelection, localRect: localSelection)
    }

    private func drawCrosshair(using session: InteractiveSnippingSession) {
        guard !session.isDragging,
              session.effectiveSelectionRect == nil,
              screenFrame.contains(session.mouseLocation) else {
            return
        }

        let point = localPoint(from: session.mouseLocation)
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: point.x - 10, y: point.y))
        crosshair.line(to: CGPoint(x: point.x + 10, y: point.y))
        crosshair.move(to: CGPoint(x: point.x, y: point.y - 10))
        crosshair.line(to: CGPoint(x: point.x, y: point.y + 10))
        NSColor.white.withAlphaComponent(0.92).setStroke()
        crosshair.lineWidth = 1.5
        crosshair.stroke()
    }

    private func drawInstruction(using session: InteractiveSnippingSession) {
        guard !session.instructionText.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = session.instructionText as NSString
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 14, height: 8)
        let rect = CGRect(
            x: (bounds.width - textSize.width) / 2 - padding.width,
            y: bounds.height - textSize.height - 28 - padding.height,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.black.withAlphaComponent(0.58).setFill()
        capsule.fill()

        text.draw(
            in: CGRect(
                x: rect.minX + padding.width,
                y: rect.minY + padding.height,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }

    private func drawHandles(around rect: CGRect) {
        let handleSize: CGFloat = 8
        let half = handleSize / 2
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]

        for point in points {
            let handleRect = CGRect(x: point.x - half, y: point.y - half, width: handleSize, height: handleSize)
            let handle = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            handle.fill()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }
    }

    private func drawSizeBadge(for globalRect: CGRect, localRect: CGRect) {
        let badgeText = "\(Int(globalRect.width.rounded())) × \(Int(globalRect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = badgeText.size(withAttributes: attributes)
        let padding = CGSize(width: 10, height: 6)
        let preferredY = localRect.maxY + 10
        let y = min(preferredY, bounds.height - textSize.height - padding.height * 2 - 12)
        let rect = CGRect(
            x: max(12, min(localRect.minX, bounds.width - textSize.width - padding.width * 2 - 12)),
            y: y,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        let badge = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        badge.fill()

        badgeText.draw(
            in: CGRect(
                x: rect.minX + padding.width,
                y: rect.minY + padding.height,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }

    private func localRect(from globalRect: CGRect?) -> CGRect? {
        guard let globalRect else { return nil }
        let intersected = globalRect.intersection(screenFrame)
        guard !intersected.isNull, !intersected.isEmpty else { return nil }

        return CGRect(
            x: intersected.minX - screenFrame.minX,
            y: intersected.minY - screenFrame.minY,
            width: intersected.width,
            height: intersected.height
        )
    }

    private func localPoint(from globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: globalPoint.x - screenFrame.minX,
            y: globalPoint.y - screenFrame.minY
        )
    }
}

// MARK: - Screen Recording
final class ScreenRecordingTool: NSObject, ObservableObject {
    static let shared = ScreenRecordingTool()

    @Published private(set) var isRecording = false

    private var process: Process?
    private var outputURL: URL?
    private var completion: ((URL) -> Void)?

    func toggleRecording(completion: @escaping (URL) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(completion: completion)
        }
    }

    func startRecording(completion: @escaping (URL) -> Void) {
        guard !isRecording else { return }

        let fileName = "screen_recording_\(Int(Date().timeIntervalSince1970)).mov"
        let targetURL = ScreenAssistantManager.screenRecordingDataDirectory.appendingPathComponent(fileName)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-v", targetURL.path]
        task.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.handleRecordingCompletion(terminationStatus: process.terminationStatus)
        }

        do {
            try task.run()
            process = task
            outputURL = targetURL
            self.completion = completion

            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("❌ ScreenRecordingTool: Failed to start recording: \(error)")
            clearState()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        process?.interrupt()
    }

    private func handleRecordingCompletion(terminationStatus _: Int32) {
        let finishedURL = outputURL
        let callback = completion
        clearState()

        guard let finishedURL,
              FileManager.default.fileExists(atPath: finishedURL.path) else {
            return
        }

        DispatchQueue.main.async {
            callback?(finishedURL)
        }
    }

    private func clearState() {
        DispatchQueue.main.async {
            self.isRecording = false
            self.process = nil
            self.outputURL = nil
            self.completion = nil
        }
    }
}

// MARK: - Screenshot Action Overlay
@MainActor
final class ScreenshotActionOverlayManager: NSObject, NSWindowDelegate {
    static let shared = ScreenshotActionOverlayManager()

    private var legacyWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var paletteWindow: NSWindow?
    private var backdropWindows: [NSWindow] = []
    private var editor: ScreenshotPostCaptureEditor?
    private var keyMonitor: Any?

    func show(
        capture: ScreenshotSnippingTool.ScreenshotCaptureResult,
        onAddToChat: @escaping (URL) -> Void
    ) {
        close()

        let editor = ScreenshotPostCaptureEditor(
            capture: capture,
            onAddToChat: onAddToChat,
            onClose: { [weak self] in self?.close() }
        )
        self.editor = editor

        if let selectionRect = editor.selectionRect,
           selectionRect.width >= 2,
           selectionRect.height >= 2 {
            showQuickEditor(editor: editor, selectionRect: selectionRect)
        } else {
            showLegacyEditor(editor: editor, imageSize: capture.image.size)
        }

        beginKeyMonitoring()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === legacyWindow else { return }
        clearState()
    }

    func close() {
        let windowsToClose = [legacyWindow, editorWindow, paletteWindow].compactMap { $0 } + backdropWindows
        clearState()
        windowsToClose.forEach {
            $0.orderOut(nil)
            $0.close()
        }
    }

    private func showLegacyEditor(editor: ScreenshotPostCaptureEditor, imageSize: CGSize) {
        let windowSize = preferredWindowSize(for: imageSize)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Screenshot Studio"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ScreenshotActionOverlayView(editor: editor))

        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        legacyWindow = panel
    }

    private func showQuickEditor(editor: ScreenshotPostCaptureEditor, selectionRect: CGRect) {
        let targetScreen = screen(containing: selectionRect) ?? NSScreen.main
        let backdrops = NSScreen.screens.map { screen in
            let window: ScreenshotBackdropWindow

            if screen.frame == targetScreen?.frame {
                window = ScreenshotBackdropWindow(
                    screen: screen,
                    selectionRect: selectionRect,
                    editor: editor
                ) { [weak self] in
                    self?.close()
                }
            } else {
                window = ScreenshotBackdropWindow(screen: screen, selectionRect: selectionRect) { [weak self] in
                    self?.close()
                }
            }

            window.orderFrontRegardless()
            return window
        }

        backdropWindows = backdrops
        backdrops.first(where: { $0.frame == targetScreen?.frame })?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        if let centerMatch = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) {
            return centerMatch
        }

        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }

    private func beginKeyMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.close()
                return nil
            }

            return event
        }
    }

    private func clearState() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        legacyWindow = nil
        editorWindow = nil
        paletteWindow = nil
        backdropWindows.removeAll()
        editor = nil
    }

    private func preferredWindowSize(for imageSize: CGSize) -> CGSize {
        let maxPreviewWidth: CGFloat = 860
        let maxPreviewHeight: CGFloat = 500
        let minWindowWidth: CGFloat = 760
        let minWindowHeight: CGFloat = 620

        let safeWidth = max(imageSize.width, 1)
        let safeHeight = max(imageSize.height, 1)
        let scale = min(maxPreviewWidth / safeWidth, maxPreviewHeight / safeHeight, 1.0)

        let previewWidth = max(560, safeWidth * scale)
        let previewHeight = max(300, safeHeight * scale)

        return CGSize(
            width: max(minWindowWidth, previewWidth + 36),
            height: max(minWindowHeight, previewHeight + 180)
        )
    }

    private func position(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            window.center()
            return
        }

        let visible = targetScreen.visibleFrame
        let width = window.frame.width
        let height = window.frame.height

        var x = mouse.x - width / 2
        var y = mouse.y - height - 18

        x = max(visible.minX + 12, min(x, visible.maxX - width - 12))
        y = max(visible.minY + 12, min(y, visible.maxY - height - 12))

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private enum ScreenshotEditorTool: String, CaseIterable, Identifiable {
    case preview
    case rectangle
    case ellipse
    case arrow
    case mark
    case mosaic
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: return "Select"
        case .rectangle: return "Rect"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .mark: return "Brush"
        case .mosaic: return "Mosaic"
        case .text: return "Text"
        }
    }

    var iconName: String {
        switch self {
        case .preview: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .arrow: return "arrow.up.right"
        case .mark: return "pencil.and.scribble"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }
}

private struct ScreenshotEditorColorOption: Identifiable {
    let id: String
    let color: NSColor
}

private let screenshotEditorColors: [ScreenshotEditorColorOption] = [
    .init(id: "red", color: .systemRed),
    .init(id: "yellow", color: .systemYellow),
    .init(id: "green", color: .systemGreen),
    .init(id: "cyan", color: .systemCyan),
    .init(id: "white", color: .white)
]

private enum ScreenshotEditHistoryItem {
    case stroke(UUID)
    case rectangle(UUID)
    case ellipse(UUID)
    case arrow(UUID)
    case mosaic(UUID)
    case text(UUID)
}

private enum ScreenshotExportMode {
    case workingCopy
    case saveCopy
}

private struct ScreenshotStroke: Identifiable {
    let id: UUID
    var normalizedPoints: [CGPoint]
    let colorID: String
    let widthScale: CGFloat
}

private struct ScreenshotMosaicRegion: Identifiable {
    let id: UUID
    let normalizedRect: CGRect
}

private struct ScreenshotRectangleOverlay: Identifiable {
    let id: UUID
    let normalizedRect: CGRect
    let colorID: String
    let widthScale: CGFloat
}

private struct ScreenshotEllipseOverlay: Identifiable {
    let id: UUID
    let normalizedRect: CGRect
    let colorID: String
    let widthScale: CGFloat
}

private struct ScreenshotArrowOverlay: Identifiable {
    let id: UUID
    let startPoint: CGPoint
    let endPoint: CGPoint
    let colorID: String
    let widthScale: CGFloat
}

private struct ScreenshotTextOverlay: Identifiable {
    let id: UUID
    let text: String
    let normalizedPosition: CGPoint
    let colorID: String
    let sizeScale: CGFloat
}

@MainActor
private final class ScreenshotPostCaptureEditor: ObservableObject {
    private static let ciContext = CIContext(options: nil)

    let baseImage: NSImage
    let previewSize: CGSize
    let renderSize: CGSize
    let selectionRect: CGRect?

    @Published var selectedTool: ScreenshotEditorTool = .preview
    @Published var selectedColorID: String = screenshotEditorColors.first?.id ?? "red"
    @Published var strokeWidthScale: Double = 0.006
    @Published var mosaicBlockSize: Double = 18 {
        didSet { refreshPixelatedImage() }
    }
    @Published var pendingText: String = "Callout"
    @Published var textSizeScale: Double = 0.048
    @Published var saveDirectoryPath: String

    @Published private(set) var pixelatedImage: NSImage
    @Published private(set) var strokes: [ScreenshotStroke] = []
    @Published private(set) var rectangles: [ScreenshotRectangleOverlay] = []
    @Published private(set) var ellipses: [ScreenshotEllipseOverlay] = []
    @Published private(set) var arrows: [ScreenshotArrowOverlay] = []
    @Published private(set) var mosaicRegions: [ScreenshotMosaicRegion] = []
    @Published private(set) var textItems: [ScreenshotTextOverlay] = []
    @Published private(set) var activeStroke: ScreenshotStroke?
    @Published private(set) var draftRectangleRect: CGRect?
    @Published private(set) var draftEllipseRect: CGRect?
    @Published private(set) var activeArrow: ScreenshotArrowOverlay?
    @Published private(set) var draftMosaicRect: CGRect?
    @Published private(set) var statusMessage: String = "Choose a tool to annotate, or save, pin and send right away."
    @Published private(set) var lastSavedURL: URL?

    private let captureResult: ScreenshotSnippingTool.ScreenshotCaptureResult
    private let addToChatHandler: (URL) -> Void
    private let closeHandler: () -> Void

    private var rectangleStartPoint: CGPoint?
    private var ellipseStartPoint: CGPoint?
    private var arrowStartPoint: CGPoint?
    private var mosaicStartPoint: CGPoint?
    private var history: [ScreenshotEditHistoryItem] = []

    init(
        capture: ScreenshotSnippingTool.ScreenshotCaptureResult,
        onAddToChat: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        captureResult = capture
        addToChatHandler = onAddToChat
        closeHandler = onClose
        baseImage = capture.image
        selectionRect = capture.selectionRect?.standardized.integral
        previewSize = capture.image.size

        if let cgImage = capture.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            renderSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            renderSize = capture.image.size
        }

        saveDirectoryPath = Defaults[.screenAssistantScreenshotSavePath]
        pixelatedImage = capture.image
        refreshPixelatedImage()
    }

    var canUndo: Bool {
        activeStroke != nil || activeArrow != nil || draftRectangleRect != nil || draftEllipseRect != nil || draftMosaicRect != nil || !history.isEmpty
    }

    var hasEdits: Bool {
        !strokes.isEmpty || !rectangles.isEmpty || !ellipses.isEmpty || !arrows.isEmpty || !mosaicRegions.isEmpty || !textItems.isEmpty
    }

    var displayedSaveDirectory: String {
        let trimmed = saveDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ScreenAssistantManager.screenshotDataDirectory.path : trimmed
    }

    var toolHint: String {
        switch selectedTool {
        case .preview:
            return "Stay in selection mode, or pick a tool to start annotating."
        case .mark:
            return "Drag on the image to paint callouts."
        case .rectangle:
            return "Drag to frame a region with a rectangle."
        case .ellipse:
            return "Drag to highlight a region with an ellipse."
        case .arrow:
            return "Drag to place an arrow callout."
        case .mosaic:
            return "Drag to cover a region with mosaic."
        case .text:
            return pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Type something first, then click on the image to place it."
                : "Click on the image to drop the current text."
        }
    }

    func color(for id: String) -> NSColor {
        screenshotEditorColors.first(where: { $0.id == id })?.color ?? .systemRed
    }

    func previewLineWidth(for scale: CGFloat, in imageRect: CGRect) -> CGFloat {
        screenshotScaledMetric(scale, in: imageRect.size, minimum: 2)
    }

    func previewFontSize(for scale: CGFloat, in imageRect: CGRect) -> CGFloat {
        screenshotScaledMetric(scale, in: imageRect.size, minimum: 14)
    }

    func beginStroke(at point: CGPoint) {
        guard activeStroke == nil else { return }
        activeStroke = ScreenshotStroke(
            id: UUID(),
            normalizedPoints: [point],
            colorID: selectedColorID,
            widthScale: CGFloat(strokeWidthScale)
        )
    }

    func appendStroke(to point: CGPoint) {
        guard var stroke = activeStroke else {
            beginStroke(at: point)
            return
        }

        if let last = stroke.normalizedPoints.last,
           hypot(last.x - point.x, last.y - point.y) < 0.001 {
            return
        }

        stroke.normalizedPoints.append(point)
        activeStroke = stroke
    }

    func finishStroke() {
        guard var stroke = activeStroke else { return }

        if stroke.normalizedPoints.count == 1, let point = stroke.normalizedPoints.first {
            stroke.normalizedPoints.append(point)
        }

        strokes.append(stroke)
        history.append(.stroke(stroke.id))
        activeStroke = nil
        statusMessage = "Marked. You can keep editing or export it."
    }

    func beginRectangle(at point: CGPoint) {
        rectangleStartPoint = point
        draftRectangleRect = CGRect(origin: point, size: .zero)
    }

    func updateRectangle(to point: CGPoint) {
        guard let start = rectangleStartPoint else {
            beginRectangle(at: point)
            return
        }

        draftRectangleRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
    }

    func finishRectangle() {
        defer {
            rectangleStartPoint = nil
            draftRectangleRect = nil
        }

        guard let draft = draftRectangleRect?.standardized,
              draft.width > 0.01,
              draft.height > 0.01 else {
            return
        }

        let rectangle = ScreenshotRectangleOverlay(
            id: UUID(),
            normalizedRect: draft,
            colorID: selectedColorID,
            widthScale: CGFloat(strokeWidthScale)
        )
        rectangles.append(rectangle)
        history.append(.rectangle(rectangle.id))
        statusMessage = "Rectangle added. Keep annotating or export it."
    }

    func beginEllipse(at point: CGPoint) {
        ellipseStartPoint = point
        draftEllipseRect = CGRect(origin: point, size: .zero)
    }

    func updateEllipse(to point: CGPoint) {
        guard let start = ellipseStartPoint else {
            beginEllipse(at: point)
            return
        }

        draftEllipseRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
    }

    func finishEllipse() {
        defer {
            ellipseStartPoint = nil
            draftEllipseRect = nil
        }

        guard let draft = draftEllipseRect?.standardized,
              draft.width > 0.01,
              draft.height > 0.01 else {
            return
        }

        let ellipse = ScreenshotEllipseOverlay(
            id: UUID(),
            normalizedRect: draft,
            colorID: selectedColorID,
            widthScale: CGFloat(strokeWidthScale)
        )
        ellipses.append(ellipse)
        history.append(.ellipse(ellipse.id))
        statusMessage = "Ellipse added. Keep annotating or export it."
    }

    func beginArrow(at point: CGPoint) {
        arrowStartPoint = point
        activeArrow = ScreenshotArrowOverlay(
            id: UUID(),
            startPoint: point,
            endPoint: point,
            colorID: selectedColorID,
            widthScale: CGFloat(strokeWidthScale)
        )
    }

    func updateArrow(to point: CGPoint) {
        guard let start = arrowStartPoint else {
            beginArrow(at: point)
            return
        }

        activeArrow = ScreenshotArrowOverlay(
            id: activeArrow?.id ?? UUID(),
            startPoint: start,
            endPoint: point,
            colorID: selectedColorID,
            widthScale: CGFloat(strokeWidthScale)
        )
    }

    func finishArrow() {
        defer {
            arrowStartPoint = nil
            activeArrow = nil
        }

        guard let arrow = activeArrow,
              hypot(arrow.endPoint.x - arrow.startPoint.x, arrow.endPoint.y - arrow.startPoint.y) > 0.015 else {
            return
        }

        arrows.append(arrow)
        history.append(.arrow(arrow.id))
        statusMessage = "Arrow added. Keep annotating or export it."
    }

    func beginMosaic(at point: CGPoint) {
        mosaicStartPoint = point
        draftMosaicRect = CGRect(origin: point, size: .zero)
    }

    func updateMosaic(to point: CGPoint) {
        guard let start = mosaicStartPoint else {
            beginMosaic(at: point)
            return
        }

        draftMosaicRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
    }

    func finishMosaic() {
        defer {
            mosaicStartPoint = nil
            draftMosaicRect = nil
        }

        guard let draft = draftMosaicRect?.standardized,
              draft.width > 0.01,
              draft.height > 0.01 else {
            return
        }

        let region = ScreenshotMosaicRegion(id: UUID(), normalizedRect: draft)
        mosaicRegions.append(region)
        history.append(.mosaic(region.id))
        statusMessage = "Mosaic applied. Add more or export it."
    }

    func addText(at point: CGPoint) {
        let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "Type some text before placing it on the screenshot."
            return
        }

        let item = ScreenshotTextOverlay(
            id: UUID(),
            text: text,
            normalizedPosition: point,
            colorID: selectedColorID,
            sizeScale: CGFloat(textSizeScale)
        )
        textItems.append(item)
        history.append(.text(item.id))
        statusMessage = "Text placed. Move on to save, pin or send."
    }

    func undo() {
        if activeStroke != nil {
            activeStroke = nil
            statusMessage = "Current brush stroke removed."
            return
        }

        if activeArrow != nil {
            activeArrow = nil
            arrowStartPoint = nil
            statusMessage = "Current arrow removed."
            return
        }

        if draftRectangleRect != nil {
            draftRectangleRect = nil
            rectangleStartPoint = nil
            statusMessage = "Current rectangle removed."
            return
        }

        if draftEllipseRect != nil {
            draftEllipseRect = nil
            ellipseStartPoint = nil
            statusMessage = "Current ellipse removed."
            return
        }

        if draftMosaicRect != nil {
            draftMosaicRect = nil
            mosaicStartPoint = nil
            statusMessage = "Current mosaic selection removed."
            return
        }

        guard let last = history.popLast() else { return }

        switch last {
        case .stroke(let id):
            strokes.removeAll { $0.id == id }
        case .rectangle(let id):
            rectangles.removeAll { $0.id == id }
        case .ellipse(let id):
            ellipses.removeAll { $0.id == id }
        case .arrow(let id):
            arrows.removeAll { $0.id == id }
        case .mosaic(let id):
            mosaicRegions.removeAll { $0.id == id }
        case .text(let id):
            textItems.removeAll { $0.id == id }
        }

        statusMessage = "Last edit undone."
    }

    func clearAllEdits() {
        activeStroke = nil
        activeArrow = nil
        draftRectangleRect = nil
        draftEllipseRect = nil
        draftMosaicRect = nil
        rectangleStartPoint = nil
        ellipseStartPoint = nil
        arrowStartPoint = nil
        mosaicStartPoint = nil
        strokes.removeAll()
        rectangles.removeAll()
        ellipses.removeAll()
        arrows.removeAll()
        mosaicRegions.removeAll()
        textItems.removeAll()
        history.removeAll()
        statusMessage = "Edits cleared."
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select Screenshot Save Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let path = panel.url?.path {
            saveDirectoryPath = path
            statusMessage = "Save folder updated."
        }
    }

    func restoreDefaultDirectory() {
        saveDirectoryPath = ""
        statusMessage = "Save folder reset to the default screenshots directory."
    }

    func saveEditedImage() {
        do {
            let image = outputImage()
            let url = try export(image: image, mode: .saveCopy)
            lastSavedURL = url
            statusMessage = "Saved to \(screenshotAbbreviatedPath(url.path))."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func openSaveDirectory() {
        NSWorkspace.shared.open(URL(fileURLWithPath: displayedSaveDirectory, isDirectory: true))
    }

    func revealLastSavedFile() {
        guard let lastSavedURL else {
            statusMessage = "Save an edited screenshot first, then it can be revealed in Finder."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([lastSavedURL])
    }

    func addToChat() {
        do {
            let image = outputImage()
            let url = try export(image: image, mode: .workingCopy)
            addToChatHandler(url)
            closeHandler()
        } catch {
            statusMessage = "Send failed: \(error.localizedDescription)"
        }
    }

    func pinToScreen() {
        let image = outputImage()
        copyImageToPasteboard(image)
        ScreenshotPinWindowManager.shared.pin(image: image)
        closeHandler()
    }

    func addAndPin() {
        do {
            let image = outputImage()
            let url = try export(image: image, mode: .workingCopy)
            addToChatHandler(url)
            ScreenshotPinWindowManager.shared.pin(image: image)
            closeHandler()
        } catch {
            statusMessage = "Add + Pin failed: \(error.localizedDescription)"
        }
    }

    func closeEditor() {
        closeHandler()
    }

    private func refreshPixelatedImage() {
        pixelatedImage = Self.makePixelatedImage(
            from: baseImage,
            previewSize: previewSize,
            blockSize: CGFloat(mosaicBlockSize)
        ) ?? baseImage
    }

    private static func makePixelatedImage(from image: NSImage, previewSize: CGSize, blockSize: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage
        filter.center = CGPoint(x: ciImage.extent.midX, y: ciImage.extent.midY)
        filter.scale = Float(max(blockSize, 6))

        guard let outputImage = filter.outputImage,
              let result = ciContext.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: result, size: previewSize)
    }

    private func outputImage() -> NSImage {
        normalizedImage(hasEdits ? renderEditedImage() : baseImage)
    }

    private func renderEditedImage() -> NSImage {
        guard hasEdits else { return normalizedImage(baseImage) }
        let outputSize = CGSize(
            width: max(renderSize.width, 1),
            height: max(renderSize.height, 1)
        )
        let bounds = CGRect(origin: .zero, size: outputSize)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: max(Int(outputSize.width.rounded()), 1),
                  height: max(Int(outputSize.height.rounded()), 1),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return normalizedImage(baseImage)
        }

        context.interpolationQuality = .high
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(bounds)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        baseImage.draw(in: bounds)

        for region in mosaicRegions {
            let rect = screenshotDenormalizedRect(region.normalizedRect, in: bounds).standardized
            guard rect.width > 0, rect.height > 0 else { continue }

            context.saveGState()
            context.clip(to: rect)
            pixelatedImage.draw(in: bounds)
            context.restoreGState()
        }

        rectangles.forEach { draw(rectangle: $0, in: bounds) }
        ellipses.forEach { draw(ellipse: $0, in: bounds) }
        strokes.forEach { draw(stroke: $0, in: bounds) }
        arrows.forEach { draw(arrow: $0, in: bounds) }
        textItems.forEach { draw(text: $0, in: bounds) }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            return normalizedImage(baseImage)
        }

        return verticallyCorrectedImage(from: cgImage)
    }

    private func normalizedImage(_ image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        return NSImage(cgImage: cgImage, size: image.size)
    }

    private func verticallyCorrectedImage(from cgImage: CGImage) -> NSImage {
        let outputSize = CGSize(width: cgImage.width, height: cgImage.height)

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: cgImage.width,
                  height: cgImage.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return NSImage(cgImage: cgImage, size: previewSize)
        }

        context.translateBy(x: 0, y: outputSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: outputSize))

        guard let corrected = context.makeImage() else {
            return NSImage(cgImage: cgImage, size: previewSize)
        }

        return NSImage(cgImage: corrected, size: previewSize)
    }

    private func draw(stroke: ScreenshotStroke, in bounds: CGRect) {
        let points = stroke.normalizedPoints.map { screenshotDenormalizedPoint($0, in: bounds) }
        let lineWidth = screenshotScaledMetric(stroke.widthScale, in: bounds.size, minimum: 2)
        let color = color(for: stroke.colorID)

        if let first = points.first,
           points.dropFirst().allSatisfy({ hypot($0.x - first.x, $0.y - first.y) < 0.5 }) {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: first.x - lineWidth / 2,
                y: first.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth
            )).fill()
            return
        }

        let path = NSBezierPath()
        if let first = points.first {
            path.move(to: first)
        }
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private func draw(rectangle: ScreenshotRectangleOverlay, in bounds: CGRect) {
        let rect = screenshotDenormalizedRect(rectangle.normalizedRect, in: bounds).standardized
        guard rect.width > 0, rect.height > 0 else { return }

        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.lineWidth = screenshotScaledMetric(rectangle.widthScale, in: bounds.size, minimum: 2)
        color(for: rectangle.colorID).setStroke()
        path.stroke()
    }

    private func draw(ellipse: ScreenshotEllipseOverlay, in bounds: CGRect) {
        let rect = screenshotDenormalizedRect(ellipse.normalizedRect, in: bounds).standardized
        guard rect.width > 0, rect.height > 0 else { return }

        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = screenshotScaledMetric(ellipse.widthScale, in: bounds.size, minimum: 2)
        color(for: ellipse.colorID).setStroke()
        path.stroke()
    }

    private func draw(arrow: ScreenshotArrowOverlay, in bounds: CGRect) {
        let start = screenshotDenormalizedPoint(arrow.startPoint, in: bounds)
        let end = screenshotDenormalizedPoint(arrow.endPoint, in: bounds)
        let lineWidth = screenshotScaledMetric(arrow.widthScale, in: bounds.size, minimum: 2)
        let color = color(for: arrow.colorID)

        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: end)
        shaft.lineCapStyle = .round
        shaft.lineJoinStyle = .round
        shaft.lineWidth = lineWidth
        color.setStroke()
        shaft.stroke()

        let headPoints = screenshotArrowHeadPoints(from: start, to: end, headLength: max(12, lineWidth * 5))
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: headPoints.left)
        head.move(to: end)
        head.line(to: headPoints.right)
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.lineWidth = lineWidth
        color.setStroke()
        head.stroke()
    }

    private func draw(text: ScreenshotTextOverlay, in bounds: CGRect) {
        let origin = screenshotDenormalizedPoint(text.normalizedPosition, in: bounds)
        let fontSize = screenshotScaledMetric(text.sizeScale, in: bounds.size, minimum: 14)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = max(fontSize * 0.18, 2)
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color(for: text.colorID),
            .strokeColor: NSColor.black.withAlphaComponent(0.16),
            .strokeWidth: -3.0,
            .shadow: shadow
        ]

        (text.text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func export(image: NSImage, mode: ScreenshotExportMode) throws -> URL {
        let destination = try destinationURL(for: mode)

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ScreenshotPostCaptureEditor", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to encode the edited screenshot."
            ])
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: destination, options: .atomic)
        copyImageToPasteboard(image)
        return destination
    }

    private func destinationURL(for mode: ScreenshotExportMode) throws -> URL {
        switch mode {
        case .workingCopy:
            return captureResult.url
        case .saveCopy:
            let preferredDirectory = saveDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseDirectory = preferredDirectory.isEmpty
                ? ScreenAssistantManager.screenshotDataDirectory
                : URL(fileURLWithPath: preferredDirectory, isDirectory: true)

            let basename = captureResult.url.deletingPathExtension().lastPathComponent
            let timestamp = Int(Date().timeIntervalSince1970)
            return baseDirectory.appendingPathComponent("\(basename)_edited_\(timestamp).png")
        }
    }

    private func copyImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

private struct ScreenshotActionOverlayView: View {
    @StateObject private var editor: ScreenshotPostCaptureEditor

    init(editor: ScreenshotPostCaptureEditor) {
        _editor = StateObject(wrappedValue: editor)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

            VStack(alignment: .leading, spacing: 12) {
                toolbar
                ScreenshotEditorCanvasView(editor: editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 320)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Label("Save Folder", systemImage: "folder")
                            .font(.subheadline.weight(.semibold))

                        Text(screenshotAbbreviatedPath(editor.displayedSaveDirectory))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Button("Choose…", action: editor.chooseSaveDirectory)
                            .buttonStyle(.bordered)
                        Button("Open", action: editor.openSaveDirectory)
                            .buttonStyle(.bordered)
                        Button("Default", action: editor.restoreDefaultDirectory)
                            .buttonStyle(.bordered)
                    }

                    HStack(spacing: 8) {
                        Text(editor.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        if editor.lastSavedURL != nil {
                            Button("Reveal", action: editor.revealLastSavedFile)
                                .buttonStyle(.bordered)
                        }
                        Button("Save", action: editor.saveEditedImage)
                            .buttonStyle(.bordered)
                        Button("Pin to Screen", action: editor.pinToScreen)
                            .buttonStyle(.bordered)
                        Button("Add + Pin", action: editor.addAndPin)
                            .buttonStyle(.bordered)
                        Button("Add to Chat", action: editor.addToChat)
                            .buttonStyle(.borderedProminent)
                        Button("Close", action: editor.closeEditor)
                            .buttonStyle(.borderless)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(Color.clear)
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ScreenshotEditorTool.allCases) { tool in
                    toolButton(for: tool)
                }

                Spacer(minLength: 8)

                Button("Undo", action: editor.undo)
                    .buttonStyle(.bordered)
                    .disabled(!editor.canUndo)
                Button("Reset", action: editor.clearAllEdits)
                    .buttonStyle(.bordered)
                    .disabled(!editor.hasEdits && !editor.canUndo)
            }

            HStack(spacing: 10) {
                if editor.selectedTool == .mark || editor.selectedTool == .rectangle || editor.selectedTool == .ellipse || editor.selectedTool == .arrow || editor.selectedTool == .text {
                    HStack(spacing: 6) {
                        ForEach(screenshotEditorColors) { option in
                            Button {
                                editor.selectedColorID = option.id
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: option.color))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                editor.selectedColorID == option.id ? Color.primary : Color.black.opacity(0.15),
                                                lineWidth: editor.selectedColorID == option.id ? 2 : 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                switch editor.selectedTool {
                case .mark:
                    Text("Width")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $editor.strokeWidthScale, in: 0.003...0.018)
                        .frame(width: 160)
                case .rectangle, .ellipse, .arrow:
                    Text("Width")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $editor.strokeWidthScale, in: 0.003...0.018)
                        .frame(width: 160)
                case .mosaic:
                    Text("Block")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $editor.mosaicBlockSize, in: 8...48, step: 2)
                        .frame(width: 180)
                case .text:
                    TextField("Text", text: $editor.pendingText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $editor.textSizeScale, in: 0.028...0.08)
                        .frame(width: 160)
                case .preview:
                    EmptyView()
                }

                Spacer(minLength: 8)

                Text(editor.toolHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func toolButton(for tool: ScreenshotEditorTool) -> some View {
        let button = Button {
            editor.selectedTool = tool
        } label: {
            Label(tool.title, systemImage: tool.iconName)
                .labelStyle(.titleAndIcon)
        }

        if tool == editor.selectedTool {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

private struct ScreenshotQuickToolbarView: View {
    @ObservedObject var editor: ScreenshotPostCaptureEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickToolbarBar {
                HStack(spacing: 8) {
                    ForEach(ScreenshotEditorTool.allCases) { tool in
                        compactToolButton(for: tool)
                    }

                    Divider()
                        .frame(height: 18)

                    compactActionButton("Undo", icon: "arrow.uturn.backward", disabled: !editor.canUndo, action: editor.undo)
                    compactActionButton("Reset", icon: "arrow.counterclockwise", disabled: !editor.hasEdits && !editor.canUndo, action: editor.clearAllEdits)

                    Spacer(minLength: 8)

                    compactActionButton("Pin", icon: "pin", action: editor.pinToScreen)
                    compactActionButton("Save", icon: "square.and.arrow.down", action: editor.saveEditedImage)
                    compactActionButton("Add", icon: "plus.bubble", action: editor.addToChat)
                    compactActionButton("Close", icon: "xmark", action: editor.closeEditor)
                }
            }

            quickToolbarBar {
                HStack(spacing: 8) {
                    quickParameterRow

                    Spacer(minLength: 8)

                    Text(editor.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 240, alignment: .leading)

                    compactTextButton("Folder", action: editor.chooseSaveDirectory)
                    compactTextButton("Open", action: editor.openSaveDirectory)
                    compactTextButton("Default", action: editor.restoreDefaultDirectory)
                    if editor.lastSavedURL != nil {
                        compactTextButton("Reveal", action: editor.revealLastSavedFile)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var quickParameterRow: some View {
        HStack(spacing: 8) {
            if editor.selectedTool == .mark || editor.selectedTool == .rectangle || editor.selectedTool == .ellipse || editor.selectedTool == .arrow || editor.selectedTool == .text {
                HStack(spacing: 6) {
                    ForEach(screenshotEditorColors) { option in
                        Button {
                            editor.selectedColorID = option.id
                        } label: {
                            Circle()
                                .fill(Color(nsColor: option.color))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            editor.selectedColorID == option.id ? Color.white : Color.black.opacity(0.18),
                                            lineWidth: editor.selectedColorID == option.id ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            switch editor.selectedTool {
            case .mark:
                Text("Width")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $editor.strokeWidthScale, in: 0.003...0.018)
                    .frame(width: 110)
            case .rectangle, .ellipse, .arrow:
                Text("Width")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $editor.strokeWidthScale, in: 0.003...0.018)
                    .frame(width: 110)
            case .mosaic:
                Text("Block")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $editor.mosaicBlockSize, in: 8...48, step: 2)
                    .frame(width: 120)
            case .text:
                TextField("Text", text: $editor.pendingText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Text("Size")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $editor.textSizeScale, in: 0.028...0.08)
                    .frame(width: 110)
            case .preview:
                Text(editor.toolHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quickToolbarBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.black.opacity(0.76))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private func compactToolButton(for tool: ScreenshotEditorTool) -> some View {
        Button {
            editor.selectedTool = tool
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tool == editor.selectedTool ? Color.white : Color.white.opacity(0.86))
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tool == editor.selectedTool ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    @ViewBuilder
    private func compactActionButton(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.6) : Color.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
    }

    private func compactTextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(Color.white.opacity(0.9))
            .controlSize(.small)
    }
}

private enum ScreenshotEditorCanvasStyle: Equatable {
    case panel
    case inline
    case export
}

private struct ScreenshotEditorCanvasView: View {
    @ObservedObject var editor: ScreenshotPostCaptureEditor
    var style: ScreenshotEditorCanvasStyle = .panel

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let isPanel = style == .panel
            let isExport = style == .export
            let canvasBounds = isPanel ? bounds.insetBy(dx: 18, dy: 18) : bounds
            let imageRect = isPanel
                ? screenshotAspectFitRect(for: editor.previewSize, in: canvasBounds)
                : canvasBounds

            ZStack(alignment: .topLeading) {
                if isPanel {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                }

                if isExport {
                    Image(nsImage: editor.baseImage)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .offset(x: imageRect.minX, y: imageRect.minY)
                } else {
                    Image(nsImage: editor.baseImage)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .offset(x: imageRect.minX, y: imageRect.minY)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                ForEach(editor.mosaicRegions) { region in
                    mosaicLayer(for: region.normalizedRect, imageRect: imageRect, showsOutline: !isExport)
                }

                if let draftRect = editor.draftMosaicRect {
                    let previewRect = screenshotDenormalizedRect(draftRect.standardized, in: imageRect)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [8, 5]))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .frame(width: previewRect.width, height: previewRect.height)
                        .offset(x: previewRect.minX, y: previewRect.minY)
                }

                ForEach(editor.rectangles) { rectangle in
                    rectangleLayer(rectangle, imageRect: imageRect)
                }

                if let draftRectangle = editor.draftRectangleRect {
                    rectangleDraftLayer(draftRectangle, imageRect: imageRect)
                }

                ForEach(editor.ellipses) { ellipse in
                    ellipseLayer(ellipse, imageRect: imageRect)
                }

                if let draftEllipse = editor.draftEllipseRect {
                    ellipseDraftLayer(draftEllipse, imageRect: imageRect)
                }

                ForEach(editor.strokes) { stroke in
                    strokeLayer(stroke, imageRect: imageRect)
                }

                if let activeStroke = editor.activeStroke {
                    strokeLayer(activeStroke, imageRect: imageRect)
                }

                ForEach(editor.arrows) { arrow in
                    arrowLayer(arrow, imageRect: imageRect)
                }

                if let activeArrow = editor.activeArrow {
                    arrowLayer(activeArrow, imageRect: imageRect)
                }

                ForEach(editor.textItems) { item in
                    let point = screenshotDenormalizedPoint(item.normalizedPosition, in: imageRect)
                    Text(item.text)
                        .font(.system(size: editor.previewFontSize(for: item.sizeScale, in: imageRect), weight: .semibold))
                        .foregroundStyle(Color(nsColor: editor.color(for: item.colorID)))
                        .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 1)
                        .fixedSize()
                        .offset(x: point.x, y: point.y)
                }

                if !isExport {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isPanel ? Color.white.opacity(0.14) : Color.accentColor.opacity(0.88),
                            lineWidth: isPanel ? 1 : 2
                        )
                        .frame(width: imageRect.width, height: imageRect.height)
                        .offset(x: imageRect.minX, y: imageRect.minY)
                }

                if isPanel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Post-Capture Studio")
                            .font(.system(size: 12, weight: .semibold))
                        Text(editor.toolHint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(14)
                } else if style == .inline {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(editor.previewSize.width.rounded())) × \(Int(editor.previewSize.height.rounded()))")
                            .font(.system(size: 11, weight: .semibold))
                        Text(editor.toolHint)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(10)
                }
            }
            .modifier(ScreenshotEditorCanvasModifier(style: style, imageRect: imageRect, gesture: editingGesture(in: imageRect)))
        }
    }

    private func mosaicLayer(for normalizedRect: CGRect, imageRect: CGRect, showsOutline: Bool) -> some View {
        let previewRect = screenshotDenormalizedRect(normalizedRect, in: imageRect).standardized
        let localMaskRect = CGRect(
            x: previewRect.minX - imageRect.minX,
            y: previewRect.minY - imageRect.minY,
            width: previewRect.width,
            height: previewRect.height
        )

        return Image(nsImage: editor.pixelatedImage)
            .resizable()
            .frame(width: imageRect.width, height: imageRect.height)
            .mask(
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: localMaskRect.width, height: localMaskRect.height)
                        .offset(x: localMaskRect.minX, y: localMaskRect.minY)
                }
                .frame(width: imageRect.width, height: imageRect.height, alignment: .topLeading)
            )
            .offset(x: imageRect.minX, y: imageRect.minY)
            .overlay {
                if showsOutline {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .frame(width: previewRect.width, height: previewRect.height)
                        .offset(x: previewRect.minX, y: previewRect.minY)
                }
            }
    }

    private func strokeLayer(_ stroke: ScreenshotStroke, imageRect: CGRect) -> some View {
        Path { path in
            let points = stroke.normalizedPoints.map { screenshotDenormalizedPoint($0, in: imageRect) }
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(
            Color(nsColor: editor.color(for: stroke.colorID)),
            style: StrokeStyle(
                lineWidth: editor.previewLineWidth(for: stroke.widthScale, in: imageRect),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func rectangleLayer(_ rectangle: ScreenshotRectangleOverlay, imageRect: CGRect) -> some View {
        let previewRect = screenshotDenormalizedRect(rectangle.normalizedRect, in: imageRect).standardized

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                Color(nsColor: editor.color(for: rectangle.colorID)),
                style: StrokeStyle(lineWidth: editor.previewLineWidth(for: rectangle.widthScale, in: imageRect))
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.minX, y: previewRect.minY)
    }

    private func rectangleDraftLayer(_ normalizedRect: CGRect, imageRect: CGRect) -> some View {
        let previewRect = screenshotDenormalizedRect(normalizedRect.standardized, in: imageRect)

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [8, 5]))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.minX, y: previewRect.minY)
    }

    private func ellipseLayer(_ ellipse: ScreenshotEllipseOverlay, imageRect: CGRect) -> some View {
        let previewRect = screenshotDenormalizedRect(ellipse.normalizedRect, in: imageRect).standardized

        return Ellipse()
            .stroke(
                Color(nsColor: editor.color(for: ellipse.colorID)),
                style: StrokeStyle(lineWidth: editor.previewLineWidth(for: ellipse.widthScale, in: imageRect))
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.minX, y: previewRect.minY)
    }

    private func ellipseDraftLayer(_ normalizedRect: CGRect, imageRect: CGRect) -> some View {
        let previewRect = screenshotDenormalizedRect(normalizedRect.standardized, in: imageRect)

        return Ellipse()
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [8, 5]))
            .background(
                Ellipse()
                    .fill(Color.white.opacity(0.08))
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.minX, y: previewRect.minY)
    }

    private func arrowLayer(_ arrow: ScreenshotArrowOverlay, imageRect: CGRect) -> some View {
        let start = screenshotDenormalizedPoint(arrow.startPoint, in: imageRect)
        let end = screenshotDenormalizedPoint(arrow.endPoint, in: imageRect)
        let width = editor.previewLineWidth(for: arrow.widthScale, in: imageRect)
        let headPoints = screenshotArrowHeadPoints(from: start, to: end, headLength: max(12, width * 5))

        return Path { path in
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: end)
            path.addLine(to: headPoints.left)
            path.move(to: end)
            path.addLine(to: headPoints.right)
        }
        .stroke(
            Color(nsColor: editor.color(for: arrow.colorID)),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func editingGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                switch editor.selectedTool {
                case .mark:
                    if editor.activeStroke == nil {
                        guard let point = screenshotNormalizedPoint(from: value.location, in: imageRect) else { return }
                        editor.beginStroke(at: point)
                    } else {
                        editor.appendStroke(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                    }
                case .rectangle:
                    if editor.draftRectangleRect == nil {
                        guard let point = screenshotNormalizedPoint(from: value.location, in: imageRect) else { return }
                        editor.beginRectangle(at: point)
                    } else {
                        editor.updateRectangle(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                    }
                case .ellipse:
                    if editor.draftEllipseRect == nil {
                        guard let point = screenshotNormalizedPoint(from: value.location, in: imageRect) else { return }
                        editor.beginEllipse(at: point)
                    } else {
                        editor.updateEllipse(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                    }
                case .arrow:
                    if editor.activeArrow == nil {
                        guard let point = screenshotNormalizedPoint(from: value.location, in: imageRect) else { return }
                        editor.beginArrow(at: point)
                    } else {
                        editor.updateArrow(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                    }
                case .mosaic:
                    if editor.draftMosaicRect == nil {
                        guard let point = screenshotNormalizedPoint(from: value.location, in: imageRect) else { return }
                        editor.beginMosaic(at: point)
                    } else {
                        editor.updateMosaic(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                    }
                case .text, .preview:
                    break
                }
            }
            .onEnded { value in
                switch editor.selectedTool {
                case .mark:
                    if editor.activeStroke != nil {
                        editor.appendStroke(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                        editor.finishStroke()
                    }
                case .rectangle:
                    if editor.draftRectangleRect != nil {
                        editor.updateRectangle(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                        editor.finishRectangle()
                    }
                case .ellipse:
                    if editor.draftEllipseRect != nil {
                        editor.updateEllipse(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                        editor.finishEllipse()
                    }
                case .arrow:
                    if editor.activeArrow != nil {
                        editor.updateArrow(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                        editor.finishArrow()
                    }
                case .mosaic:
                    if editor.draftMosaicRect != nil {
                        editor.updateMosaic(to: screenshotClampedNormalizedPoint(from: value.location, in: imageRect))
                        editor.finishMosaic()
                    }
                case .text:
                    guard value.isTapLike,
                          let point = screenshotNormalizedPoint(from: value.location, in: imageRect) else { return }
                    editor.addText(at: point)
                case .preview:
                    break
                }
            }
    }
}

private struct ScreenshotEditorCanvasModifier<G: Gesture>: ViewModifier {
    let style: ScreenshotEditorCanvasStyle
    let imageRect: CGRect
    let gesture: G

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .panel:
            content
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
                .gesture(gesture)
        case .inline:
            content
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
                .gesture(gesture)
        case .export:
            content
        }
    }
}

private func screenshotAspectFitRect(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
    guard contentSize.width > 0, contentSize.height > 0,
          bounds.width > 0, bounds.height > 0 else {
        return bounds
    }

    let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
    let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    return CGRect(
        x: bounds.midX - size.width / 2,
        y: bounds.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
}

private func screenshotNormalizedPoint(from location: CGPoint, in imageRect: CGRect) -> CGPoint? {
    guard imageRect.contains(location), imageRect.width > 0, imageRect.height > 0 else {
        return nil
    }

    return CGPoint(
        x: (location.x - imageRect.minX) / imageRect.width,
        y: (location.y - imageRect.minY) / imageRect.height
    )
}

private func screenshotClampedNormalizedPoint(from location: CGPoint, in imageRect: CGRect) -> CGPoint {
    guard imageRect.width > 0, imageRect.height > 0 else { return .zero }

    let x = min(max(location.x, imageRect.minX), imageRect.maxX)
    let y = min(max(location.y, imageRect.minY), imageRect.maxY)
    return CGPoint(
        x: (x - imageRect.minX) / imageRect.width,
        y: (y - imageRect.minY) / imageRect.height
    )
}

private func screenshotDenormalizedPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(
        x: rect.minX + point.x * rect.width,
        y: rect.minY + point.y * rect.height
    )
}

private func screenshotDenormalizedRect(_ normalizedRect: CGRect, in rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX + normalizedRect.minX * rect.width,
        y: rect.minY + normalizedRect.minY * rect.height,
        width: normalizedRect.width * rect.width,
        height: normalizedRect.height * rect.height
    )
}

private func screenshotScaledMetric(_ scale: CGFloat, in size: CGSize, minimum: CGFloat) -> CGFloat {
    max(minimum, min(size.width, size.height) * scale)
}

private func screenshotArrowHeadPoints(from start: CGPoint, to end: CGPoint, headLength: CGFloat) -> (left: CGPoint, right: CGPoint) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let spread: CGFloat = .pi / 7

    let left = CGPoint(
        x: end.x - headLength * cos(angle - spread),
        y: end.y - headLength * sin(angle - spread)
    )
    let right = CGPoint(
        x: end.x - headLength * cos(angle + spread),
        y: end.y - headLength * sin(angle + spread)
    )

    return (left, right)
}

private func screenshotAbbreviatedPath(_ path: String) -> String {
    NSString(string: path).abbreviatingWithTildeInPath
}

private extension DragGesture.Value {
    var isTapLike: Bool {
        hypot(translation.width, translation.height) < 6
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

private final class ScreenshotFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class ScreenshotBackdropWindow: NSWindow {
    init(
        screen: NSScreen,
        selectionRect: CGRect,
        editor: ScreenshotPostCaptureEditor,
        onCancel: @escaping () -> Void
    ) {
        let view = ScreenshotEditorBackdropView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            screenFrame: screen.frame,
            selectionRect: selectionRect,
            editor: editor,
            onCancel: onCancel
        )

        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        configure(screen: screen, contentView: view)
    }

    init(screen: NSScreen, selectionRect: CGRect, onCancel: @escaping () -> Void) {
        let view = ScreenshotBackdropView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            screenFrame: screen.frame,
            selectionRect: selectionRect,
            onCancel: onCancel
        )

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configure(screen: screen, contentView: view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func configure(screen: NSScreen, contentView: NSView) {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)
        self.contentView = contentView
    }
}

private final class ScreenshotBackdropView: NSView {
    private let screenFrame: CGRect
    private let selectionRect: CGRect
    private let onCancel: () -> Void

    init(frame frameRect: CGRect, screenFrame: CGRect, selectionRect: CGRect, onCancel: @escaping () -> Void) {
        self.screenFrame = screenFrame
        self.selectionRect = selectionRect
        self.onCancel = onCancel
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(rect: bounds)
        if let localSelection = localRect(from: selectionRect) {
            path.append(NSBezierPath(rect: localSelection))
            path.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.46).setFill()
        path.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onCancel()
    }

    private func localRect(from globalRect: CGRect) -> CGRect? {
        let intersected = globalRect.intersection(screenFrame)
        guard !intersected.isNull, !intersected.isEmpty else { return nil }

        return CGRect(
            x: intersected.minX - screenFrame.minX,
            y: intersected.minY - screenFrame.minY,
            width: intersected.width,
            height: intersected.height
        )
    }
}

private final class ScreenshotEditorBackdropView: NSView {
    private let screenFrame: CGRect
    private let selectionRect: CGRect
    private let onCancel: () -> Void
    private let canvasHostingView: NSHostingView<AnyView>
    private let toolbarHostingView: NSHostingView<AnyView>

    init(
        frame frameRect: CGRect,
        screenFrame: CGRect,
        selectionRect: CGRect,
        editor: ScreenshotPostCaptureEditor,
        onCancel: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.selectionRect = selectionRect
        self.onCancel = onCancel
        self.canvasHostingView = NSHostingView(
            rootView: AnyView(
                ScreenshotEditorCanvasView(editor: editor, style: .inline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        )
        self.toolbarHostingView = NSHostingView(
            rootView: AnyView(
                ScreenshotQuickToolbarView(editor: editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        )

        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(canvasHostingView)
        addSubview(toolbarHostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        guard let localSelection = localRect(from: selectionRect) else {
            canvasHostingView.frame = .zero
            toolbarHostingView.frame = .zero
            return
        }

        canvasHostingView.frame = localSelection.integral
        toolbarHostingView.frame = toolbarRect(near: localSelection).integral
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(rect: bounds)
        if let localSelection = localRect(from: selectionRect) {
            path.append(NSBezierPath(rect: localSelection))
            path.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.46).setFill()
        path.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onCancel()
    }

    private func toolbarRect(near localSelection: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let spacing: CGFloat = 12
        let width = min(900, max(620, bounds.width - 32))
        let height: CGFloat = 136

        var x = localSelection.midX - width / 2
        x = max(margin, min(x, bounds.maxX - width - margin))

        var y = localSelection.minY - height - spacing
        if y < margin {
            y = localSelection.maxY + spacing
        }
        y = max(margin, min(y, bounds.maxY - height - margin))

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func localRect(from globalRect: CGRect) -> CGRect? {
        let intersected = globalRect.intersection(screenFrame)
        guard !intersected.isNull, !intersected.isEmpty else { return nil }

        return CGRect(
            x: intersected.minX - screenFrame.minX,
            y: intersected.minY - screenFrame.minY,
            width: intersected.width,
            height: intersected.height
        )
    }
}

// MARK: - Pinned Screenshot Window
private final class ScreenshotPinWindowManager: NSObject, NSWindowDelegate {
    static let shared = ScreenshotPinWindowManager()

    private var windows: [NSWindow] = []

    func pin(image: NSImage) {
        let size = preferredSize(for: image.size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Pinned Screenshot"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.contentView = NSHostingView(rootView: PinnedScreenshotView(
            image: image,
            onCopy: { [image] in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            },
            onClose: { [weak window] in
                window?.close()
            }
        ))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows.append(window)
        repositionPinnedWindows()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
        repositionPinnedWindows()
    }

    private func repositionPinnedWindows() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let spacing: CGFloat = 16

        for (index, window) in windows.enumerated() {
            let x = visibleFrame.maxX - window.frame.width - spacing
            let y = visibleFrame.maxY - window.frame.height - spacing - (CGFloat(index) * (window.frame.height + spacing))
            window.setFrameOrigin(NSPoint(x: x, y: max(y, visibleFrame.minY + spacing)))
        }
    }

    private func preferredSize(for original: CGSize) -> CGSize {
        guard original.width > 0, original.height > 0 else {
            return CGSize(width: 520, height: 320)
        }

        let maxWidth: CGFloat = 560
        let maxHeight: CGFloat = 360
        let widthScale = maxWidth / original.width
        let heightScale = maxHeight / original.height
        let scale = min(widthScale, heightScale, 1.0)

        return CGSize(width: original.width * scale, height: original.height * scale)
    }
}

private final class ScreenshotPinnedViewportController: ObservableObject {
    weak var scrollView: ScreenshotPinnedScrollView?

    func resetToFit() {
        scrollView?.resetToFit()
    }

    func setActualSize() {
        scrollView?.setActualSize()
    }
}

private struct PinnedScreenshotView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onClose: () -> Void
    @StateObject private var viewportController = ScreenshotPinnedViewportController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            PinnedScreenshotScrollView(image: image, controller: viewportController)
                .background(Color.black.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Pinned Preview", systemImage: "pin")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer(minLength: 8)

                    Button("Fit", action: viewportController.resetToFit)
                        .buttonStyle(.bordered)
                    Button("100%", action: viewportController.setActualSize)
                        .buttonStyle(.bordered)
                    Button("Copy", action: onCopy)
                        .buttonStyle(.bordered)
                    Button("Close", action: onClose)
                        .buttonStyle(.borderedProminent)
                }

                Text("Pinch to zoom, drag to pan, double-click to fit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(12)
        }
    }
}

private struct PinnedScreenshotScrollView: NSViewRepresentable {
    let image: NSImage
    @ObservedObject var controller: ScreenshotPinnedViewportController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> ScreenshotPinnedScrollView {
        let scrollView = ScreenshotPinnedScrollView(imageSize: image.size)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.wantsLayer = true
        imageView.layer?.magnificationFilter = .trilinear
        imageView.layer?.minificationFilter = .trilinear

        let recognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.resetZoom(_:)))
        recognizer.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(recognizer)
        context.coordinator.controller.scrollView = scrollView

        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ nsView: ScreenshotPinnedScrollView, context: Context) {
        if let imageView = nsView.documentView as? NSImageView {
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image.size)
        }
        context.coordinator.controller.scrollView = nsView
        nsView.applyInitialFitIfNeeded()
    }

    final class Coordinator: NSObject {
        let controller: ScreenshotPinnedViewportController

        init(controller: ScreenshotPinnedViewportController) {
            self.controller = controller
        }

        @objc func resetZoom(_ sender: NSClickGestureRecognizer) {
            controller.resetToFit()
        }
    }
}

private final class ScreenshotPinnedScrollView: NSScrollView {
    private let imageSize: CGSize
    private var hasAppliedInitialFit = false

    init(imageSize: CGSize) {
        self.imageSize = imageSize
        super.init(frame: .zero)

        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.4
        maxMagnification = 8.0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyInitialFitIfNeeded()
    }

    func applyInitialFitIfNeeded() {
        guard !hasAppliedInitialFit else { return }
        resetToFit()
        hasAppliedInitialFit = true
    }

    func resetToFit() {
        guard imageSize.width > 0,
              imageSize.height > 0,
              contentSize.width > 0,
              contentSize.height > 0 else { return }

        let fit = min(contentSize.width / imageSize.width, contentSize.height / imageSize.height)
        let clamped = min(max(fit, minMagnification), maxMagnification)
        setMagnification(clamped, centeredAt: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2))
    }

    func setActualSize() {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let clamped = min(max(CGFloat(1), minMagnification), maxMagnification)
        setMagnification(clamped, centeredAt: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2))
    }
}
