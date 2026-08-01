//
//  MusicManager.swift
//  CharBar
//
//  Adapted from boringNotch - Main coordinator for media controllers
//

import AppKit
import Combine
import SwiftUI

// MARK: - Media Controller Type
enum MediaControllerType: String, CaseIterable, Codable {
    case nowPlaying = "System-Wide (NowPlaying)"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
}

// MARK: - MusicManager
class MusicManager: ObservableObject {
    // MARK: - Singleton
    static let shared = MusicManager()
    
    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    
    // Active controller
    private var activeController: (any MediaControllerProtocol)?
    
    // MARK: - Published Properties for UI
    @Published var songTitle: String = "Not Playing"
    @Published var artistName: String = ""
    @Published var albumName: String = ""
    @Published var albumArt: NSImage? = nil
    @Published var isPlaying: Bool = false
    @Published var isPlayerIdle: Bool = true
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = Date()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false
    
    private var artworkData: Data? = nil
    
    // MARK: - Initialization
    private init() {
        // Initialize the default controller
        setActiveControllerBasedOnPreference()
    }
    
    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            newController = NowPlayingController()
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    func setActiveControllerBasedOnPreference() {
        // Default to NowPlaying for system-wide detection
        let preferredType: MediaControllerType = .nowPlaying
        
        if let controller = createController(for: preferredType) {
            setActiveController(controller)
        } else if let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if NowPlaying couldn't be created
            setActiveController(fallbackController)
        }
    }
    
    func switchController(to type: MediaControllerType) {
        if let controller = createController(for: type) {
            setActiveController(controller)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        activeController = controller
        canFavoriteTrack = controller.supportsFavorite
        volumeControlSupported = controller.supportsVolumeControl
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Update playing state
        if state.isPlaying != self.isPlaying {
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.isPlayerIdle = !state.isPlaying
            }
        }

        // Update track metadata
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.albumName {
            self.albumName = state.album
        }

        // Update artwork
        if state.artwork != self.artworkData {
            self.artworkData = state.artwork
            if let data = state.artwork, let image = NSImage(data: data) {
                self.albumArt = image
            } else {
                self.albumArt = nil
            }
        }

        // Update time info
        if state.currentTime != self.elapsedTime {
            self.elapsedTime = state.currentTime
        }

        if state.duration != self.songDuration {
            self.songDuration = state.duration
        }

        if state.playbackRate != self.playbackRate {
            self.playbackRate = state.playbackRate
        }
        
        if state.isShuffled != self.isShuffled {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if state.repeatMode != self.repeatMode {
            self.repeatMode = state.repeatMode
        }
        
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if state.volume != self.volume {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
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
        Task {
            await activeController?.togglePlay()
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
        // Immediately update local state for responsive UI
        self.elapsedTime = position
        self.timestampDate = Date()
        
        Task {
            await activeController?.seek(to: position)
        }
    }
    
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    
    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        setFavorite(!isFavoriteTrack)
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    func forceUpdate() {
        Task {
            if activeController?.isActive() == true {
                await activeController?.updatePlaybackInfo()
            }
        }
    }
    
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else { return }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
            }
        }
    }
}

