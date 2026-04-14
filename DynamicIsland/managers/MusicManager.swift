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

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Lyric Data Structures
struct LyricLine: Identifiable, Codable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    enum SkipDirection: Equatable {
        case backward
        case forward
    }

    struct SkipGesturePulse: Equatable {
        let token: Int
        let direction: SkipDirection
        let behavior: MusicSkipBehavior
    }

    struct MediaSourceDescriptor: Identifiable, Equatable {
        let controllerType: MediaControllerType
        let bundleIdentifier: String
        let isPlaying: Bool
        let isAvailable: Bool
        let lastActiveAt: Date

        var id: String { controllerType.rawValue }

        var displayName: String {
            if let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                .flatMap({ Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }) {
                return appName
            }

            return controllerType.localizedName
        }
    }

    private struct TrackedMediaSource {
        let controllerType: MediaControllerType
        var state: PlaybackState
        var bundleIdentifier: String
        var lastSeen: Date
        var lastActiveAt: Date
        var isAvailable: Bool
    }

    static let skipGestureSeekInterval: TimeInterval = 10

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables: [MediaControllerType: AnyCancellable] = [:]
    private var controllers: [MediaControllerType: any MediaControllerProtocol] = [:]
    private var trackedSources: [MediaControllerType: TrackedMediaSource] = [:]
    private var sourceCleanupTimer: Timer?
    private var debounceIdleTask: Task<Void, Never>?
    @MainActor private var pendingOptimisticPlayState: Bool?
    private var activeControllerType: MediaControllerType?
    private let sourceRetentionInterval: TimeInterval = 45

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Pear Desktop auto-detection
    private static let pearDesktopBundleID = YouTubeMusicConfiguration.default.bundleIdentifier
    private var isPearDesktopAutoSwitched: Bool = false

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

    var hasActiveSession: Bool {
        Self.stateHasDisplayableSession(
            PlaybackState(
                bundleIdentifier: bundleIdentifier ?? "",
                isPlaying: isPlaying,
                title: songTitle,
                artist: artistName,
                album: album,
                currentTime: elapsedTime,
                duration: songDuration,
                playbackRate: playbackRate,
                isShuffled: isShuffled,
                repeatMode: repeatMode,
                lastUpdated: timestampDate
            )
        )
    }

    var shouldShowMediaSourceSwitcher: Bool {
        mediaSources.count > 1
    }

    private static func stateHasDisplayableSession(_ state: PlaybackState) -> Bool {
        if state.isPlaying { return true }

        let trimmedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedArtist = state.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasRealTitle = !trimmedTitle.isEmpty && !placeholderTitles.contains(trimmedTitle)
        let hasRealArtist = !trimmedArtist.isEmpty && !placeholderArtists.contains(trimmedArtist)
        return hasRealTitle || hasRealArtist
    }

    @Published var animations: DynamicIslandAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isLiveStream: Bool = false
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published private(set) var skipGesturePulse: SkipGesturePulse?

    // MARK: - Lyrics Properties
    @Published var currentLyrics: String = ""
    @Published var syncedLyrics: [LyricLine] = []
    @Published var showLyrics: Bool = false
    @Published var currentLyricIndex: Int = -1

    // Task used to periodically sync displayed lyric with playback position
    private var lyricSyncTask: Task<Void, Never>?

    private var artworkData: Data? = nil

    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var flipAngle: Double = 0
    @Published var lastFlipDirection: SkipDirection = .forward
    private let flipAnimationDuration: TimeInterval = 0.45
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var skipGestureToken: Int = 0
    @Published private(set) var mediaSources: [MediaSourceDescriptor] = []
    @Published private(set) var selectedMediaSourceID: String?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isPearDesktopAutoSwitched = false
                    self?.setActiveControllerBasedOnPreference()
                }
            }
            .store(in: &cancellables)

        // Observe Pear Desktop launch/terminate for auto-detection
        setupPearDesktopAutoDetection()
        startSourceCleanupTimer()

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Check if Pear Desktop is already running at startup
            let pearDesktopRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == Self.pearDesktopBundleID
            }

            if pearDesktopRunning && Defaults[.mediaController] != .nowPlaying {
                print("[MusicManager] Pear Desktop detected at startup, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
            }

            // Initialize controllers after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    // MARK: - Pear Desktop Auto-Detection
    private func setupPearDesktopAutoDetection() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                Task { @MainActor in
                    guard Defaults[.mediaController] != .nowPlaying else {
                        self.setActiveControllerBasedOnPreference()
                        return
                    }

                    print("[MusicManager] Pear Desktop launched, auto-switching to YouTubeMusicController")
                    self.isPearDesktopAutoSwitched = true
                    self.setActiveControllerBasedOnPreference()
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                Task { @MainActor in
                    guard Defaults[.mediaController] != .nowPlaying else {
                        self.setActiveControllerBasedOnPreference()
                        return
                    }

                    print("[MusicManager] Pear Desktop terminated, reverting to preferred controller")
                    if self.isPearDesktopAutoSwitched {
                        self.isPearDesktopAutoSwitched = false
                        self.setActiveControllerBasedOnPreference()
                    }
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        sourceCleanupTimer?.invalidate()
        cancellables.removeAll()
        transitionWorkItem?.cancel()
        teardownControllers()
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        return newController
    }

    @MainActor
    private func setActiveControllerBasedOnPreference() {
        print("Preferred Media Controller: \(Defaults[.mediaController])")
        reconfigureControllers()
    }

    private func setActiveController(_ controller: any MediaControllerProtocol, type: MediaControllerType) {
        activeController = controller
        activeControllerType = type
    }

    @MainActor
    private func handleIncomingPlaybackState(_ state: PlaybackState, from controllerType: MediaControllerType) async {
        let now = Date()
        let hasDisplayableSession = Self.stateHasDisplayableSession(state)
        let controllerIsAvailable = controllerType == .nowPlaying || (controllers[controllerType]?.isActive() ?? false)

        if hasDisplayableSession {
            trackedSources[controllerType] = TrackedMediaSource(
                controllerType: controllerType,
                state: state,
                bundleIdentifier: state.bundleIdentifier,
                lastSeen: now,
                lastActiveAt: now,
                isAvailable: controllerIsAvailable
            )
        } else if var existing = trackedSources[controllerType] {
            existing.lastSeen = now
            existing.isAvailable = false
            trackedSources[controllerType] = existing
        }

        refreshTrackedSourcesAndSelection()
    }

    @MainActor
    private func reconfigureControllers() {
        let preferredType = resolvedPreferredControllerType()
        teardownControllers()

        if preferredType == .nowPlaying {
            addController(.nowPlaying)
            addController(.appleMusic)
            addController(.spotify)

            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == Self.pearDesktopBundleID }) {
                addController(.youtubeMusic)
            }
        } else {
            addController(preferredType)

            if controllers[preferredType] == nil && preferredType != .appleMusic {
                addController(.appleMusic)
            }
        }

        refreshTrackedSourcesAndSelection()
        forceUpdate()
    }

    private func teardownControllers() {
        controllerCancellables.removeAll()
        controllers.removeAll()
        activeController = nil
        activeControllerType = nil
        trackedSources.removeAll()
        mediaSources = []
        selectedMediaSourceID = nil
    }

    @MainActor
    private func addController(_ type: MediaControllerType) {
        guard let controller = createController(for: type) else { return }

        controllers[type] = controller
        controllerCancellables[type] = controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    await self?.handleIncomingPlaybackState(state, from: type)
                }
            }
    }

    private func resolvedPreferredControllerType() -> MediaControllerType {
        let preferredType = Defaults[.mediaController]

        if preferredType == .nowPlaying && isNowPlayingDeprecated {
            return .appleMusic
        }

        if isPearDesktopAutoSwitched && preferredType != .nowPlaying {
            return .youtubeMusic
        }

        return preferredType
    }

    private func startSourceCleanupTimer() {
        sourceCleanupTimer?.invalidate()
        sourceCleanupTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTrackedSourcesAndSelection()
            }
        }
    }

    @MainActor
    private func refreshTrackedSourcesAndSelection() {
        let now = Date()

        for type in Array(trackedSources.keys) {
            guard var tracked = trackedSources[type] else { continue }

            if type != .nowPlaying, !(controllers[type]?.isActive() ?? false) {
                tracked.isAvailable = false
                trackedSources[type] = tracked
            }

            if !shouldRetainTrackedSource(tracked, now: now) {
                trackedSources.removeValue(forKey: type)
            }
        }

        let visibleSources = trackedSources.values
            .filter { shouldExposeTrackedSource($0, now: now) }
            .sorted(by: compareTrackedSources)

        mediaSources = visibleSources.map {
            MediaSourceDescriptor(
                controllerType: $0.controllerType,
                bundleIdentifier: $0.bundleIdentifier,
                isPlaying: $0.state.isPlaying,
                isAvailable: $0.isAvailable,
                lastActiveAt: $0.lastActiveAt
            )
        }

        let nextSelection = resolvedSelectedSourceType(from: visibleSources)
        selectedMediaSourceID = nextSelection?.rawValue

        guard let nextSelection,
              let controller = controllers[nextSelection],
              let tracked = trackedSources[nextSelection] else {
            activeController = nil
            activeControllerType = nil
            resetDisplayedPlaybackState()
            return
        }

        setActiveController(controller, type: nextSelection)
        updateFromPlaybackState(tracked.state)
    }

    private func shouldRetainTrackedSource(_ source: TrackedMediaSource, now: Date) -> Bool {
        source.isAvailable || now.timeIntervalSince(source.lastActiveAt) <= sourceRetentionInterval
    }

    private func shouldExposeTrackedSource(_ source: TrackedMediaSource, now: Date) -> Bool {
        guard shouldRetainTrackedSource(source, now: now) else { return false }

        if source.controllerType == .nowPlaying,
           let dedicatedType = dedicatedControllerType(for: source.bundleIdentifier),
           let dedicatedSource = trackedSources[dedicatedType],
           shouldRetainTrackedSource(dedicatedSource, now: now) {
            return false
        }

        return true
    }

    private func resolvedSelectedSourceType(from visibleSources: [TrackedMediaSource]) -> MediaControllerType? {
        if let currentType = activeControllerType,
           visibleSources.contains(where: { $0.controllerType == currentType }) {
            return currentType
        }

        let preferredType = resolvedPreferredControllerType()
        if visibleSources.contains(where: { $0.controllerType == preferredType }) {
            return preferredType
        }

        return visibleSources.first?.controllerType
    }

    private func compareTrackedSources(_ lhs: TrackedMediaSource, _ rhs: TrackedMediaSource) -> Bool {
        if lhs.isAvailable != rhs.isAvailable {
            return lhs.isAvailable && !rhs.isAvailable
        }

        if lhs.state.isPlaying != rhs.state.isPlaying {
            return lhs.state.isPlaying && !rhs.state.isPlaying
        }

        if lhs.lastActiveAt != rhs.lastActiveAt {
            return lhs.lastActiveAt > rhs.lastActiveAt
        }

        return lhs.controllerType.rawValue < rhs.controllerType.rawValue
    }

    private func dedicatedControllerType(for bundleIdentifier: String) -> MediaControllerType? {
        switch bundleIdentifier {
        case "com.apple.Music":
            return .appleMusic
        case "com.spotify.client":
            return .spotify
        case Self.pearDesktopBundleID:
            return .youtubeMusic
        default:
            return nil
        }
    }

    @MainActor
    func selectMediaSource(_ controllerType: MediaControllerType) {
        guard mediaSources.contains(where: { $0.controllerType == controllerType }),
              let controller = controllers[controllerType],
              let tracked = trackedSources[controllerType] else { return }

        setActiveController(controller, type: controllerType)
        selectedMediaSourceID = controllerType.rawValue
        updateFromPlaybackState(tracked.state)
        forceUpdate(controllerType: controllerType)
    }

    @MainActor
    private func resetDisplayedPlaybackState() {
        applyPlayState(false, animation: nil)
        songTitle = "I'm Handsome"
        artistName = "Me"
        album = "Self Love"
        bundleIdentifier = nil
        songDuration = 0
        elapsedTime = 0
        timestampDate = .distantPast
        playbackRate = 1
        isShuffled = false
        repeatMode = .off
        isLiveStream = false
        usingAppIconForArtwork = false
        currentLyrics = ""
        syncedLyrics = []
        currentLyricIndex = -1
        albumArt = defaultImage
        artworkData = nil
        lastArtworkTitle = "I'm Handsome"
        lastArtworkArtist = "Me"
        lastArtworkAlbum = "Self Love"
        lastArtworkBundleIdentifier = nil
    }

    @MainActor
    private func applyPlayState(_ state: Bool, animation: Animation?) {
        if let animation {
            var transaction = Transaction()
            transaction.animation = animation
            withTransaction(transaction) {
                self.isPlaying = state
            }
        } else {
            self.isPlaying = state
        }

        self.updateIdleState(state: state)
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = pendingOptimisticPlayState
        pendingOptimisticPlayState = nil

        if eventIsPlaying != self.isPlaying {
            let animation: Animation? = (expectedState == eventIsPlaying) ? .smooth(duration: 0.18) : .smooth
            applyPlayState(eventIsPlaying, animation: animation)

            if eventIsPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        } else {
            self.updateIdleState(state: eventIsPlaying)
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        let shouldAutoPeekOnTrackChange = Defaults[.showSneakPeekOnTrackChange]

        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier

            // Fetch lyrics for new track whenever content changes
            self.fetchLyrics()

            // Only update sneak peek if there's actual content and something changed
            if shouldAutoPeekOnTrackChange && !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
            // Update current lyric based on elapsed time
            self.updateCurrentLyric(for: state.currentTime)
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        
        updateLiveStreamState(with: state)
        self.timestampDate = state.lastUpdated

        // Manage lyric sync task based on playback/lyrics availability
        if Defaults[.enableLyrics] && !self.syncedLyrics.isEmpty {
            // Ensure syncing runs while lyrics are enabled
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }

    private func triggerFlipAnimation() {
        // Debounce: rapid metadata updates (title, artwork, bundle arriving
        // separately for one track change) should only produce a single flip.
        guard !flipCooldownActive else { return }
        flipCooldownActive = true

        // Direction: positive rotation = next (page turn forward),
        //            negative rotation = previous (page turn backward).
        let delta: Double = lastFlipDirection == .forward ? 180 : -180
        withAnimation(.easeInOut(duration: flipAnimationDuration)) {
            flipAngle += delta
        }

        // Reset cooldown after the animation completes so the next
        // genuine track change can flip again.
        DispatchQueue.main.asyncAfter(deadline: .now() + flipAnimationDuration + 0.15) { [weak self] in
            self?.flipCooldownActive = false
        }
    }

    private func updateLiveStreamState(with state: PlaybackState) {
        let duration = state.duration
        let current = max(state.currentTime, elapsedTime)
        let hasKnownDuration = duration.isFinite && duration > 0
        let isPlaying = state.isPlaying

        if hasKnownDuration {
            liveStreamUnknownDurationCount = 0

            let remaining = duration - current
            let clampedDuration = max(duration, 0)
            let clampedCurrent = clampedDuration > 0
                ? max(0, min(current, clampedDuration))
                : max(0, current)
            let progress = clampedDuration > 0 ? clampedCurrent / clampedDuration : 0
            let sliderAppearsComplete = isPlaying && clampedDuration > 0 && progress >= 0.999
            let nearDurationEdge = isPlaying && remaining.isFinite && remaining <= 1.0 && clampedCurrent >= 10

            if sliderAppearsComplete {
                liveStreamCompletionObservationCount = min(liveStreamCompletionObservationCount + 1, 8)
                liveStreamCompletionReleaseCount = 0
            } else {
                liveStreamCompletionReleaseCount = min(liveStreamCompletionReleaseCount + 1, 8)
                if liveStreamCompletionObservationCount > 0 {
                    liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
                }
            }

            if nearDurationEdge || sliderAppearsComplete {
                liveStreamEdgeObservationCount = min(liveStreamEdgeObservationCount + 1, 12)
            } else if liveStreamEdgeObservationCount > 0 {
                liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            }

            if !isLiveStream {
                if liveStreamCompletionObservationCount >= 3 || liveStreamEdgeObservationCount >= 5 {
                    isLiveStream = true
                }
            } else {
                let shouldClearForKnownDuration =
                    (duration > 10 && remaining > 5)
                    || (liveStreamCompletionObservationCount == 0
                        && liveStreamEdgeObservationCount == 0
                        && liveStreamCompletionReleaseCount >= 4)

                if shouldClearForKnownDuration {
                    isLiveStream = false
                }
            }
        } else if isPlaying {
            liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
            liveStreamCompletionReleaseCount = 0

            liveStreamUnknownDurationCount = min(liveStreamUnknownDurationCount + 1, 8)
            if liveStreamUnknownDurationCount >= 3 && !isLiveStream {
                isLiveStream = true
            }
        } else {
            liveStreamUnknownDurationCount = 0
            liveStreamEdgeObservationCount = 0
            liveStreamCompletionObservationCount = 0
            liveStreamCompletionReleaseCount = 0
        }
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) {
                self?.albumArt = newAlbumArt
                if Defaults[.coloredSpectrogram] {
                    self?.calculateAverageColor()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem!)
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        let standardControlsEnabled = Defaults[.showStandardMediaControls]
        let minimalisticEnabled = Defaults[.enableMinimalisticUI]

        guard standardControlsEnabled || minimalisticEnabled else { return }

        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                pendingOptimisticPlayState = targetState
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }

    func seek(by offset: TimeInterval) {
        guard !isLiveStream else { return }
        let duration = songDuration
        guard duration > 0 else { return }

        let current = estimatedPlaybackPosition()
        let magnitude = abs(offset)

        if offset < 0, current <= magnitude {
            previousTrack()
            return
        }

        if offset > 0, (duration - current) <= magnitude {
            nextTrack()
            return
        }

        let target = min(max(0, current + offset), duration)
        seek(to: target)
    }

    @MainActor
    func handleSkipGesture(direction: SkipDirection) {
        guard Defaults[.enableHorizontalMusicGestures] else { return }
        guard !isPlayerIdle || bundleIdentifier != nil else { return }

        let behavior = Defaults[.musicGestureBehavior]

        switch behavior {
        case .track:
            if direction == .forward {
                lastFlipDirection = .forward
                nextTrack()
            } else {
                lastFlipDirection = .backward
                previousTrack()
            }
        case .tenSecond:
            let interval = Self.skipGestureSeekInterval
            let offset = direction == .forward ? interval : -interval
            seek(by: offset)
        }

        skipGestureToken = skipGestureToken &+ 1
        skipGesturePulse = SkipGesturePulse(
            token: skipGestureToken,
            direction: direction,
            behavior: behavior
        )
    }

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        Task { [weak self] in
            guard let self else { return }

            if resolvedPreferredControllerType() == .nowPlaying {
                for controllerType in controllers.keys {
                    await refreshController(controllerType: controllerType)
                }
            } else if let activeControllerType {
                await refreshController(controllerType: activeControllerType)
            }
        }
    }

    private func forceUpdate(controllerType: MediaControllerType) {
        Task { [weak self] in
            await self?.refreshController(controllerType: controllerType)
        }
    }

    private func refreshController(controllerType: MediaControllerType) async {
        guard let controller = controllers[controllerType], controller.isActive() else { return }

        if let youtubeController = controller as? YouTubeMusicController {
            await youtubeController.pollPlaybackState()
        } else {
            await controller.updatePlaybackInfo()
        }
    }

    // MARK: - Lyrics Methods
    func fetchLyrics() {
        guard Defaults[.enableLyrics] else { return }
        // If the lyrics panel is visible already, provide immediate feedback
        if showLyrics {
            Task { @MainActor in
                self.currentLyrics = "Loading lyrics..."
                self.syncedLyrics = []
                self.currentLyricIndex = -1
            }
        }

        Task {
            do {
                let lyrics = try await fetchLyricsFromAPI(artist: artistName, title: songTitle)
                await MainActor.run {
                    self.syncedLyrics = lyrics
                    self.currentLyricIndex = -1
                    if !lyrics.isEmpty {
                        self.currentLyrics = lyrics[0].text
                    } else {
                        self.currentLyrics = ""
                    }

                    // If lyrics are enabled, start syncing them to playback position
                    if Defaults[.enableLyrics] && !self.syncedLyrics.isEmpty {
                        self.startLyricSync()
                    } else if self.syncedLyrics.isEmpty {
                        self.stopLyricSync()
                    }
                }
            } catch {
                print("Failed to fetch lyrics: \(error)")
                await MainActor.run {
                    self.syncedLyrics = []
                    self.currentLyrics = ""
                    self.currentLyricIndex = -1
                    self.stopLyricSync()
                }
            }
        }
    }

    private func fetchLyricsFromAPI(artist: String, title: String) async throws -> [LyricLine] {
        guard !artist.isEmpty, !title.isEmpty else { return [] }

        // Normalize input and percent-encode
        let cleanArtist = artist.folding(options: .diacriticInsensitive, locale: .current)
        let cleanTitle = title.folding(options: .diacriticInsensitive, locale: .current)
        guard let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        // Use LRCLIB search endpoint which returns an array JSON with `plainLyrics` and/or `syncedLyrics`.
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            // Try parse as array JSON (preferred)
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first {
                let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !synced.isEmpty {
                    return parseLRC(synced)
                } else if !plain.isEmpty {
                    return [LyricLine(timestamp: 0, text: plain)]
                } else {
                    return []
                }
            } else {
                // Fallback: try to decode as UTF8 and handle as LRC or plain text
                if let lrcString = String(data: data, encoding: .utf8) {
                    let trimmed = lrcString.trimmingCharacters(in: .whitespacesAndNewlines)

                    if trimmed.isEmpty  {
                        return []
                    }

                    // If it contains a syncedLyrics key in an object, try that
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                        if let dict = json as? [String: Any],
                            let synced = dict["syncedLyrics"] as? String
                        {
                            return parseLRC(synced)
                        }
                        if let array = json as? [Any], array.isEmpty {
                            return []
                        }
                    }

                    // Otherwise treat as plain lyrics blob
                    return [LyricLine(timestamp: 0, text: trimmed)]
                }
                return []
            }
        } else {
            return []
        }
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        let lines = lrc.components(separatedBy: .newlines)
        var lyrics: [LyricLine] = []

        // Accept patterns like [m:ss], [mm:ss], [mm:ss.xx] where centiseconds are optional
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,2}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if let match = regex.firstMatch(in: line, options: [], range: fullRange) {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let centiRange = match.range(at: 3)

                let minStr = minRange.location != NSNotFound ? nsLine.substring(with: minRange) : "0"
                let secStr = secRange.location != NSNotFound ? nsLine.substring(with: secRange) : "0"
                let centiStr = (centiRange.location != NSNotFound) ? nsLine.substring(with: centiRange) : "0"

                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let centis = Double(centiStr) ?? 0
                let timestamp = minutes * 60 + seconds + centis / 100.0

                let textStart = match.range.location + match.range.length
                if textStart <= nsLine.length {
                    let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        lyrics.append(LyricLine(timestamp: timestamp, text: text))
                    }
                }
            }
        }

        return lyrics.sorted(by: { $0.timestamp < $1.timestamp })
    }

    func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard !syncedLyrics.isEmpty else { return }

        // Find the current lyric based on elapsed time
        var newIndex = -1
        for (index, lyric) in syncedLyrics.enumerated() {
            if elapsedTime >= lyric.timestamp {
                newIndex = index
            } else {
                break
            }
        }

        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
            if newIndex >= 0 && newIndex < syncedLyrics.count {
                currentLyrics = syncedLyrics[newIndex].text
            }
        }
    }

    // Start a background task that periodically updates the displayed lyric
    private func startLyricSync() {
        // If already running, keep it
        if lyricSyncTask != nil { return }

        lyricSyncTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Compute estimated playback position and update lyric
                let position = self.estimatedPlaybackPosition()
                await MainActor.run {
                    self.updateCurrentLyric(for: position)
                }

                // Sleep ~300ms between updates
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func stopLyricSync() {
        lyricSyncTask?.cancel()
        lyricSyncTask = nil
    }

    func toggleLyrics() {
        // Toggle the UI state first so the views can react immediately.
        showLyrics.toggle()

        // If lyrics are requested to be shown but we don't have any yet,
        // show a loading placeholder and start fetching asynchronously.
        if showLyrics && syncedLyrics.isEmpty {
            // Provide immediate feedback so the UI can show a loading state.
            currentLyrics = "Loading lyrics..."

            Task {
                await fetchLyrics()

                // If fetch completed but no lyrics were found, show a friendly message.
                await MainActor.run {
                    if self.syncedLyrics.isEmpty && self.currentLyrics.isEmpty {
                        self.currentLyrics = "No lyrics found"
                    }
                }
            }
        }
    }
}

// MARK: - Media Branding

extension MusicManager {
    var brandAccentColor: Color {
        Self.brandAccentColor(for: activeControllerType ?? Defaults[.mediaController], bundleIdentifier: bundleIdentifier)
    }

    private static func brandAccentColor(for controller: MediaControllerType, bundleIdentifier: String?) -> Color {
        switch controller {
        case .appleMusic:
            return appleMusicPink
        case .spotify:
            return spotifyGreen
        case .nowPlaying:
            if let bundleIdentifier,
               let bundleColor = brandAccentColor(forBundleIdentifier: bundleIdentifier) {
                return bundleColor
            }
            fallthrough
        case .youtubeMusic:
            return .accentColor
        }
    }

    private static func brandAccentColor(forBundleIdentifier bundleIdentifier: String) -> Color? {
        switch bundleIdentifier {
        case "com.apple.Music":
            return appleMusicPink
        case "com.spotify.client":
            return spotifyGreen
        default:
            return nil
        }
    }

    private static let appleMusicPink = Color(red: 0.999, green: 0.171, blue: 0.331)
    private static let spotifyGreen = Color(red: 0.0, green: 0.857, blue: 0.302)
}

// MARK: - Album Art Flip Helper

private struct AlbumArtFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            // Counter-rotate the content so the image never appears mirrored.
            // At odd multiples of 180° the 3D rotation mirrors along X;
            // applying an opposite scaleEffect cancels that out.
            .scaleEffect(x: cosineSign(for: angle), y: 1)
    }

    /// Returns +1 when the front face is showing, −1 when the back face is showing.
    private func cosineSign(for degrees: Double) -> CGFloat {
        let cos = Darwin.cos(degrees * .pi / 180)
        // Use a small tolerance to avoid flickering exactly at 90°/270°.
        if cos > 0.001 { return 1 }
        if cos < -0.001 { return -1 }
        // At the exact edge, prefer the side we're animating toward.
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
