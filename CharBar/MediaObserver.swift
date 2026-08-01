import Foundation
import AppKit
import SwiftUI
import Combine
import CoreAudio

// MARK: - MediaRemote Framework (for commands)
private let mediaRemoteBundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))

// For play/pause/next/previous
private let MRMediaRemoteSendCommandFunction: (@convention(c) (Int, AnyObject?) -> Void)? = {
    guard let bundle = mediaRemoteBundle,
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
        return nil
    }
    return unsafeBitCast(pointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
}()

// For seeking - THIS IS THE KEY FUNCTION FOR PROGRESS BAR
private let MRMediaRemoteSetElapsedTimeFunction: (@convention(c) (Double) -> Void)? = {
    guard let bundle = mediaRemoteBundle,
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) else {
        return nil
    }
    return unsafeBitCast(pointer, to: (@convention(c) (Double) -> Void).self)
}()

// MARK: - MediaObserver (Boring Notch Style - Perl Adapter + AppleScript Fallback)
class MediaObserver: ObservableObject {
    // Shared instance for floating bar access
    static let shared = MediaObserver()
    
    @Published var title: String = "Not Playing"
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var isPlaying: Bool = false
    @Published var artworkImage: NSImage? = nil
    @Published var bundleIdentifier: String? = nil
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isFavorite: Bool = false
    @Published var timestampDate: Date = Date()
    @Published var playbackRate: Double = 1.0
    @Published var volume: Float = 0.5 // System volume (0.0 to 1.0)
    
    // Universal source app icon - fetched dynamically from the system
    @Published var sourceAppIcon: NSImage? = nil
    @Published var sourceAppName: String = ""
    
    // Shuffle & Repeat states - tracked per app
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    
    // Setting: Auto-pause previous music when new source starts
    @AppStorage("musicAutoPausePrevious") var autoPausePrevious: Bool = false
    
    /// Check if current source is a music app (vs browser/video)
    var isMusicApp: Bool {
        guard let bundleID = bundleIdentifier else { return true }
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }
    
    /// Check if current source is a browser (YouTube, etc.)
    var isBrowserSource: Bool {
        guard let bundleID = bundleIdentifier else { return false }
        let browserBundles = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser", // Arc
            "com.operasoftware.Opera"
        ]
        return browserBundles.contains(bundleID)
    }
    
    // Cache for app icons to avoid refetching
    private var iconCache: [String: NSImage] = [:]
    private var lastBundleIdentifier: String? = nil
    
    enum RepeatMode: String {
        case off = "off"
        case one = "one"
        case all = "all"
        
        var icon: String {
            switch self {
            case .off: return "repeat"
            case .one: return "repeat.1"
            case .all: return "repeat"
            }
        }
        
        var isActive: Bool {
            return self != .off
        }
    }
    
    // Timer for volume updates
    private var volumeTimer: Timer?
    
    // Task for clearing stale artwork
    private var artworkClearTask: DispatchWorkItem?
    
    // MARK: - Universal App Icon Fetching
    
    /// Fetch the app icon for any bundle identifier
    func getAppIcon(for bundleID: String) -> NSImage? {
        // Check cache first
        if let cached = iconCache[bundleID] {
            return cached
        }
        
        // Try to get from running app (fastest)
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = app.icon {
            iconCache[bundleID] = icon
            return icon
        }
        
        // Try to find the app on disk (slower but reliable)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            iconCache[bundleID] = icon
            return icon
        }
        
        return nil
    }
    
    /// Get friendly app name from bundle identifier
    func getAppName(for bundleID: String?) -> String {
        guard let bundleID = bundleID else { return "Unknown" }
        
        // Known apps
        switch bundleID {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        case "com.google.Chrome": return "Chrome"
        case "org.mozilla.firefox": return "Firefox"
        case "com.apple.Safari": return "Safari"
        case "com.brave.Browser": return "Brave"
        case "company.thebrowser.Browser": return "Arc"
        case "com.microsoft.edgemac": return "Edge"
        case "com.operasoftware.Opera": return "Opera"
        default:
            // Try to get app name from running application
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               let name = app.localizedName {
                return name
            }
            // Fallback: extract from bundle ID
            return bundleID.components(separatedBy: ".").last?.capitalized ?? "App"
        }
    }
    
    /// Update source app info - call this whenever bundleIdentifier is set
    /// This is now more robust and always updates the icon/name when bundle changes
    func updateSourceAppInfo(forceBundleID: String? = nil) {
        let bundleID = forceBundleID ?? bundleIdentifier
        
        guard let bundleID = bundleID, !bundleID.isEmpty else {
            sourceAppIcon = nil
            sourceAppName = ""
            lastBundleIdentifier = nil
            return
        }
        
        // Only update if bundle ID actually changed
        guard bundleID != lastBundleIdentifier else { return }
        
        // Update tracking
        let previousBundle = lastBundleIdentifier
        lastBundleIdentifier = bundleID
        
        // Fetch icon and name immediately (synchronous)
        if let icon = getAppIcon(for: bundleID) {
            sourceAppIcon = icon
        }
        sourceAppName = getAppName(for: bundleID)
        
        // Only reset shuffle/repeat state when actually switching between apps
        if previousBundle != nil && previousBundle != bundleID {
            isShuffleEnabled = false
            repeatMode = .off
            // Fetch the new app's shuffle/repeat state
            fetchShuffleRepeatState(for: bundleID)
        }
    }
    
    /// Fetch current shuffle/repeat state from the active app
    private func fetchShuffleRepeatState(for bundleID: String) {
        switch bundleID {
        case "com.apple.Music":
            fetchAppleMusicShuffleRepeatState()
        case "com.spotify.client":
            fetchSpotifyShuffleRepeatState()
        default:
            // Other apps don't support shuffle/repeat
            isShuffleEnabled = false
            repeatMode = .off
        }
    }
    
    private func fetchAppleMusicShuffleRepeatState() {
        let script = """
        tell application "Music"
            if it is running then
                try
                    set shuffleState to shuffle enabled
                    set repeatState to song repeat as text
                    return {shuffleState, repeatState}
                on error
                    return {false, "off"}
                end try
            else
                return {false, "off"}
            end if
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil && descriptor.numberOfItems >= 2 {
                    let shuffleEnabled = descriptor.atIndex(1)?.booleanValue ?? false
                    let repeatString = descriptor.atIndex(2)?.stringValue?.lowercased() ?? "off"
                    
                    var repeatMode: RepeatMode = .off
                    if repeatString.contains("all") {
                        repeatMode = .all
                    } else if repeatString.contains("one") {
                        repeatMode = .one
                    }
                    
                    DispatchQueue.main.async {
                        self?.isShuffleEnabled = shuffleEnabled
                        self?.repeatMode = repeatMode
                    }
                }
            }
        }
    }
    
    private func fetchSpotifyShuffleRepeatState() {
        let script = """
        tell application "Spotify"
            if it is running then
                try
                    set shuffleState to shuffling
                    set repeatState to repeating
                    return {shuffleState, repeatState}
                on error
                    return {false, false}
                end try
            else
                return {false, false}
            end if
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil && descriptor.numberOfItems >= 2 {
                    let shuffleEnabled = descriptor.atIndex(1)?.booleanValue ?? false
                    let repeatEnabled = descriptor.atIndex(2)?.booleanValue ?? false
                    
                    DispatchQueue.main.async {
                        self?.isShuffleEnabled = shuffleEnabled
                        self?.repeatMode = repeatEnabled ? .all : .off
                    }
                }
            }
        }
    }
    
    // Calculate real-time playback position (Boring Notch style)
    func estimatedPlaybackPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return min(currentTime, duration) }
        
        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = currentTime + (timeDifference * playbackRate)
        return min(max(0, estimated), max(duration, 1))
    }
    
    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var usingPerlAdapter: Bool = false
    
    init() {
        // Try to use the Perl adapter first (like Boring Notch)
        Task { @MainActor in
            await self.setupPerlAdapterStream()
        }
        
        // Also set up notification-based fallback
        setupNotificationObservers()
        
        // Setup volume monitoring
        setupVolumeMonitoring()
        
        // And polling fallback
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if !(self?.usingPerlAdapter ?? false) {
                self?.fetchNowPlayingViaAppleScript()
            }
        }
        
        // Initial fetch
        fetchNowPlayingViaAppleScript()
    }
    
    deinit {
        streamTask?.cancel()
        pollTimer?.invalidate()
        
        if let process = self.process, process.isRunning {
            process.terminate()
        }
    }
    
    // MARK: - Perl Adapter Stream (Boring Notch's Method)
    private func setupPerlAdapterStream() async {
        // Look for the Perl script in Resources (like Boring Notch)
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") else {
            return
        }
        
        // Framework should be in PrivateFrameworks folder (like Boring Notch)
        guard let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else {
            return
        }
        
        guard FileManager.default.fileExists(atPath: frameworkPath) else {
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        
        self.process = process
        self.pipeHandler = pipeHandler
        
        do {
            try process.run()
            self.usingPerlAdapter = true
            
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            self.usingPerlAdapter = false
        }
    }
    
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }
        
        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }
    
    @MainActor
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) {
        let payload = update.payload
        let diff = update.diff ?? false
        
        // For diff updates, only update fields that are provided
        // For full updates (diff=false), we still only update if provided
        // We DON'T reset to empty - that should only happen via forceResetToIdle()
        
        // Update title - and track if it changed (for artwork refresh)
        var titleChanged = false
        if let newTitle = payload.title {
            titleChanged = (self.title != newTitle)
            self.title = newTitle
            
            if titleChanged {
                self.currentTime = payload.elapsedTime ?? 0
                self.timestampDate = Date()
                if payload.duration == nil {
                    self.duration = 0
                }
                // Force playbackRate to match current playing state so
                // estimatedPlaybackPosition() doesn't use a stale rate
                // (browser sources often omit playbackRate in track-change updates)
                if let playing = payload.playing {
                    self.playbackRate = playing ? 1.0 : 0.0
                } else {
                    self.playbackRate = self.isPlaying ? 1.0 : 0.0
                }
                
                // Cancel any pending clear
                artworkClearTask?.cancel()
                
                // Schedule clear in 0.5 seconds - will be cancelled if new artwork arrives
                let task = DispatchWorkItem { [weak self] in
                    self?.clearArtworkIfStale()
                }
                artworkClearTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
            }
        }
        // Don't reset title if not provided - keep current value
        
        // Update artist
        if let newArtist = payload.artist {
            self.artist = newArtist
        }
        // Don't reset artist if not provided
        
        // Update album
        if let newAlbum = payload.album {
            self.album = newAlbum
        }
        // Don't reset album if not provided
        
        // Update playing state - ONLY when explicitly provided
        if let playing = payload.playing {
            self.isPlaying = playing
        }
        // NOTE: If payload.playing is nil, we DON'T change isPlaying at all
        
        // Update bundle identifier and source app info
        if let bundleID = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier {
            let previousBundle = self.bundleIdentifier
            let bundleChanged = previousBundle != bundleID
            
            // When source app changes AND new source is playing, optionally pause the old one
            if bundleChanged {
                let newIsPlaying = payload.playing ?? false
                
                // Auto-pause previous source if enabled and new source started playing
                if autoPausePrevious && newIsPlaying, let oldBundle = previousBundle {
                    pauseApp(bundleID: oldBundle)
                }
                
                // NOTE: Don't clear artwork here - wait for new artwork
                // This prevents the visual "flash to blank" delay
            }
            
            self.bundleIdentifier = bundleID
            
            if bundleChanged {
                updateSourceAppInfo(forceBundleID: bundleID)
            }
        }
        
        // Update artwork - only when provided
        if let artworkDataString = payload.artworkData {
            // Cancel any scheduled artwork clear since we got artwork data
            artworkClearTask?.cancel()
            artworkClearTask = nil
            
            if !artworkDataString.isEmpty,
               let data = Data(base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)),
               let image = NSImage(data: data) {
                // Ensure high quality rendering
                image.cacheMode = .never
                
                // Create a high-res representation if needed
                if let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff) {
                    let hiResImage = NSImage(size: bitmap.size)
                    hiResImage.addRepresentation(bitmap)
                    hiResImage.cacheMode = .never
                    self.artworkImage = hiResImage
                } else {
                    self.artworkImage = image
                }
            } else {
                // Artwork data was provided but empty - clear it immediately
                self.artworkImage = nil
            }
        }
        // If artwork not provided, scheduled clear will handle it if track changed
        
        // Update duration - only when provided
        if let newDuration = payload.duration {
            self.duration = newDuration
        }
        // Don't reset duration if not provided
        
        // Update elapsed time - only when provided
        if let elapsedTime = payload.elapsedTime {
            self.currentTime = elapsedTime
            self.timestampDate = Date() // Record when we got this position
        }
        // Don't reset currentTime if not provided
        
        // Update playback rate
        if let rate = payload.playbackRate {
            self.playbackRate = rate
        } else if payload.playing != nil {
            // Only update playbackRate if we got a playing state
            self.playbackRate = self.isPlaying ? 1.0 : 0.0
        }
        // Otherwise keep current playbackRate
        
//        print("🎵 Now Playing: \(self.title) - \(self.artist) [\(self.isPlaying ? "Playing" : "Paused")] @ \(self.currentTime)/\(self.duration)")
    }
    
    // MARK: - Notification Observers (Fallback)
    private func setupNotificationObservers() {
        // Apple Music notifications
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMusicNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
        
        // Spotify notifications
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }
    
    @objc private func handleMusicNotification(_ notification: Notification) {
        guard !usingPerlAdapter else { return }
        
        if let userInfo = notification.userInfo {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.bundleIdentifier = "com.apple.Music"
                self.updateSourceAppInfo() // Update app icon and shuffle/repeat state
                self.title = userInfo["Name"] as? String ?? self.title
                self.artist = userInfo["Artist"] as? String ?? self.artist
                self.album = userInfo["Album"] as? String ?? self.album
                
                if let state = userInfo["Player State"] as? String {
                    self.isPlaying = (state == "Playing")
                }
                
                self.fetchMusicArtwork()
            }
        }
    }
    
    @objc private func handleSpotifyNotification(_ notification: Notification) {
        guard !usingPerlAdapter else { return }
        
        if let userInfo = notification.userInfo {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.bundleIdentifier = "com.spotify.client"
                self.updateSourceAppInfo() // Update app icon and shuffle/repeat state
                self.title = userInfo["Name"] as? String ?? self.title
                self.artist = userInfo["Artist"] as? String ?? self.artist
                self.album = userInfo["Album"] as? String ?? self.album
                
                if let state = userInfo["Player State"] as? String {
                    self.isPlaying = (state == "Playing")
                }
            }
        }
    }
    
    // MARK: - AppleScript Fallback
    private func fetchNowPlayingViaAppleScript() {
        if isAppRunning("com.apple.Music") {
            fetchFromAppleMusic()
        } else if isAppRunning("com.spotify.client") {
            fetchFromSpotify()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.resetToIdle()
            }
        }
    }
    
    private func isAppRunning(_ bundleID: String) -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
    
    private func resetToIdle() {
        // Simply reset - no more auto-switching to other sources
        if title != "Not Playing" {
            title = "Not Playing"
            artist = ""
            album = ""
            isPlaying = false
            artworkImage = nil
            bundleIdentifier = nil
            currentTime = 0
            duration = 0
        }
    }
    
    private func clearArtworkIfStale() {
        // This is called 0.5 seconds after a track change
        // If no new artwork has arrived by now, clear the old artwork
        // This prevents old artwork from sticking around for content without artwork (e.g., YouTube videos)
        
        // Clear artwork if we're still playing but no artwork came through
        if self.isPlaying || self.title != "Not Playing" {
            self.artworkImage = nil
        }
        
        artworkClearTask = nil
    }
    
    private func fetchFromAppleMusic() {
        let script = """
        tell application "Music"
            if player state is playing then
                set theState to "playing"
            else
                set theState to "paused"
            end if
            try
                set trackDuration to duration of current track
                set trackPosition to player position
                set shuffleState to shuffle enabled
                set repeatState to song repeat as text
                return {name of current track, artist of current track, album of current track, theState, trackDuration, trackPosition, shuffleState, repeatState}
            on error
                return {"Not Playing", "", "", "stopped", 0, 0, false, "off"}
            end try
        end tell
        """
        executeAppleMusicScript(script)
    }
    
    private func fetchFromSpotify() {
        let script = """
        tell application "Spotify"
            if player state is playing then
                set theState to "playing"
            else
                set theState to "paused"
            end if
            try
                set trackDuration to (duration of current track) / 1000
                set trackPosition to player position
                set shuffleState to shuffling
                set repeatState to repeating
                return {name of current track, artist of current track, album of current track, theState, trackDuration, trackPosition, shuffleState, repeatState}
            on error
                return {"Not Playing", "", "", "stopped", 0, 0, false, false}
            end try
        end tell
        """
        executeSpotifyScript(script)
    }
    
    // MARK: - Apple Music Script Execution (with shuffle/repeat)
    
    private func executeAppleMusicScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: source) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil && descriptor.numberOfItems >= 6 {
                    let newTitle = descriptor.atIndex(1)?.stringValue ?? "Not Playing"
                    let newArtist = descriptor.atIndex(2)?.stringValue ?? ""
                    let newAlbum = descriptor.atIndex(3)?.stringValue ?? ""
                    let stateString = descriptor.atIndex(4)?.stringValue ?? "stopped"
                    let newIsPlaying = (stateString == "playing")
                    
                    var newDuration: Double = 0
                    var newPosition: Double = 0
                    if let durationDesc = descriptor.atIndex(5) {
                        newDuration = Double(durationDesc.int32Value)
                    }
                    if let positionDesc = descriptor.atIndex(6) {
                        newPosition = Double(positionDesc.int32Value)
                    }
                    
                    // Get shuffle state (item 7)
                    var shuffleEnabled = false
                    if descriptor.numberOfItems >= 7, let shuffleDesc = descriptor.atIndex(7) {
                        shuffleEnabled = shuffleDesc.booleanValue
                    }
                    
                    // Get repeat state (item 8) - Apple Music returns "off", "one", or "all"
                    var repeatMode: RepeatMode = .off
                    if descriptor.numberOfItems >= 8, let repeatDesc = descriptor.atIndex(8) {
                        let repeatString = repeatDesc.stringValue?.lowercased() ?? "off"
                        if repeatString.contains("all") {
                            repeatMode = .all
                        } else if repeatString.contains("one") {
                            repeatMode = .one
                        } else {
                            repeatMode = .off
                        }
                    }
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        let titleChanged = self.title != newTitle
                        let bundleChanged = self.bundleIdentifier != "com.apple.Music"
                        
                        self.bundleIdentifier = "com.apple.Music"
                        self.title = newTitle
                        self.artist = newArtist
                        self.album = newAlbum
                        self.isPlaying = newIsPlaying
                        self.duration = newDuration
                        self.currentTime = newPosition
                        self.timestampDate = Date()
                        self.playbackRate = newIsPlaying ? 1.0 : 0.0
                        self.isShuffleEnabled = shuffleEnabled
                        self.repeatMode = repeatMode
                        
                        // Update source app icon if bundle changed
                        if bundleChanged {
                            self.sourceAppIcon = self.getAppIcon(for: "com.apple.Music")
                            self.sourceAppName = "Apple Music"
                            self.lastBundleIdentifier = "com.apple.Music"
                        }
                        
                        // Fetch artwork if title changed OR source changed
                        if (titleChanged || bundleChanged) && newTitle != "Not Playing" {
                            self.fetchMusicArtwork()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Spotify Script Execution (with shuffle/repeat)
    
    private func executeSpotifyScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: source) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil && descriptor.numberOfItems >= 6 {
                    let newTitle = descriptor.atIndex(1)?.stringValue ?? "Not Playing"
                    let newArtist = descriptor.atIndex(2)?.stringValue ?? ""
                    let newAlbum = descriptor.atIndex(3)?.stringValue ?? ""
                    let stateString = descriptor.atIndex(4)?.stringValue ?? "stopped"
                    let newIsPlaying = (stateString == "playing")
                    
                    var newDuration: Double = 0
                    var newPosition: Double = 0
                    if let durationDesc = descriptor.atIndex(5) {
                        newDuration = Double(durationDesc.int32Value)
                    }
                    if let positionDesc = descriptor.atIndex(6) {
                        newPosition = Double(positionDesc.int32Value)
                    }
                    
                    // Get shuffle state (item 7)
                    var shuffleEnabled = false
                    if descriptor.numberOfItems >= 7, let shuffleDesc = descriptor.atIndex(7) {
                        shuffleEnabled = shuffleDesc.booleanValue
                    }
                    
                    // Get repeat state (item 8) - Spotify returns boolean
                    var repeatMode: RepeatMode = .off
                    if descriptor.numberOfItems >= 8, let repeatDesc = descriptor.atIndex(8) {
                        repeatMode = repeatDesc.booleanValue ? .all : .off
                    }
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        let bundleChanged = self.bundleIdentifier != "com.spotify.client"
                        
                        self.bundleIdentifier = "com.spotify.client"
                        self.title = newTitle
                        self.artist = newArtist
                        self.album = newAlbum
                        self.isPlaying = newIsPlaying
                        self.duration = newDuration
                        self.currentTime = newPosition
                        self.timestampDate = Date()
                        self.playbackRate = newIsPlaying ? 1.0 : 0.0
                        self.isShuffleEnabled = shuffleEnabled
                        self.repeatMode = repeatMode
                        
                        // Update source app icon if bundle changed
                        if bundleChanged {
                            self.sourceAppIcon = self.getAppIcon(for: "com.spotify.client")
                            self.sourceAppName = "Spotify"
                            self.lastBundleIdentifier = "com.spotify.client"
                            // Fetch Spotify artwork when switching to Spotify
                            self.fetchSpotifyArtwork()
                        }
                    }
                }
            }
        }
    }
    
    private func fetchSpotifyArtwork() {
        let script = """
        tell application "Spotify"
            try
                return artwork url of current track
            on error
                return ""
            end try
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil, let urlString = descriptor.stringValue, !urlString.isEmpty {
                    // Upgrade Spotify artwork URL to high-res version
                    // Spotify URLs: ab67616d00001e02 (64px) -> ab67616d0000b273 (300px) -> remove size for largest
                    var highResUrl = urlString
                    
                    // Replace small size codes with large size code
                    if highResUrl.contains("ab67616d00001e02") {
                        highResUrl = highResUrl.replacingOccurrences(of: "ab67616d00001e02", with: "ab67616d0000b273")
                    }
                    if highResUrl.contains("ab67616d00004851") {
                        highResUrl = highResUrl.replacingOccurrences(of: "ab67616d00004851", with: "ab67616d0000b273")
                    }
                    
                    // Try 640x640 size first (highest quality)
                    let largestUrl = highResUrl.replacingOccurrences(of: "ab67616d0000b273", with: "ab67616d00000000")
                    
                    // Try largest first, fall back to 300px
                    let urlsToTry = [largestUrl, highResUrl, urlString]
                    
                    for urlStr in urlsToTry {
                        if let url = URL(string: urlStr),
                           let data = try? Data(contentsOf: url),
                           let image = NSImage(data: data),
                           image.size.width > 50 { // Ensure we got a real image
                            
                            // Set high quality rendering hints
                            image.cacheMode = .never
                            
                            DispatchQueue.main.async {
                                self?.artworkClearTask?.cancel()
                                self?.artworkClearTask = nil
                                self?.artworkImage = image
                            }
                            return
                        }
                    }
                }
            }
            
            // If we reach here, artwork fetch failed - clear stale artwork
            DispatchQueue.main.async {
                self?.artworkClearTask?.cancel()
                self?.artworkClearTask = nil
                self?.artworkImage = nil
            }
        }
    }
    
    private func fetchMusicArtwork() {
        let script = """
        tell application "Music"
            try
                return data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil {
                    let data = descriptor.data
                    if !data.isEmpty, let image = NSImage(data: data) {
                        // Ensure high quality rendering
                        image.cacheMode = .never
                        
                        // Create optimized image representation
                        var finalImage = image
                        if let tiff = image.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data: tiff) {
                            let hiResImage = NSImage(size: bitmap.size)
                            hiResImage.addRepresentation(bitmap)
                            hiResImage.cacheMode = .never
                            finalImage = hiResImage
                        }
                        
                        DispatchQueue.main.async {
                            self?.artworkClearTask?.cancel()
                            self?.artworkClearTask = nil
                            self?.artworkImage = finalImage
                        }
                        return
                    }
                }
            }
            
            // If we reach here, artwork fetch failed - clear stale artwork
            DispatchQueue.main.async {
                self?.artworkClearTask?.cancel()
                self?.artworkClearTask = nil
                self?.artworkImage = nil
            }
        }
    }
    
    // MARK: - Playback Controls (AppleScript for known apps, MediaRemote fallback)
    func togglePlayPause() {
        // Use AppleScript for known apps to ensure we control the RIGHT app
        if let bundleID = bundleIdentifier {
            switch bundleID {
            case "com.apple.Music":
                executeAppleScriptVoid("tell application \"Music\" to playpause")
            case "com.spotify.client":
                executeAppleScriptVoid("tell application \"Spotify\" to playpause")
            default:
                // Fallback to MediaRemote for other apps (browsers, etc.)
                MRMediaRemoteSendCommandFunction?(2, nil) // 2 = Toggle
            }
        } else {
            MRMediaRemoteSendCommandFunction?(2, nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if !(self?.usingPerlAdapter ?? false) {
                self?.fetchNowPlayingViaAppleScript()
            }
        }
    }
    
    func nextTrack() {
        if let bundleID = bundleIdentifier {
            switch bundleID {
            case "com.apple.Music":
                executeAppleScriptVoid("tell application \"Music\" to next track")
            case "com.spotify.client":
                executeAppleScriptVoid("tell application \"Spotify\" to next track")
            default:
                MRMediaRemoteSendCommandFunction?(4, nil) // 4 = Next
            }
        } else {
            MRMediaRemoteSendCommandFunction?(4, nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if !(self?.usingPerlAdapter ?? false) {
                self?.fetchNowPlayingViaAppleScript()
            }
        }
    }
    
    func previousTrack() {
        if let bundleID = bundleIdentifier {
            switch bundleID {
            case "com.apple.Music":
                executeAppleScriptVoid("tell application \"Music\" to previous track")
            case "com.spotify.client":
                executeAppleScriptVoid("tell application \"Spotify\" to previous track")
            default:
                MRMediaRemoteSendCommandFunction?(5, nil) // 5 = Previous
            }
        } else {
            MRMediaRemoteSendCommandFunction?(5, nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if !(self?.usingPerlAdapter ?? false) {
                self?.fetchNowPlayingViaAppleScript()
            }
        }
    }
    
    // MARK: - Seek (uses MRMediaRemoteSetElapsedTime like Boring Notch)
    func seek(to position: Double) {
        // Immediately update local state for responsive UI
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = position
            self?.timestampDate = Date()
        }
        
        // Use MediaRemote API directly (works for ALL media apps including YouTube, Chrome, etc.)
        if let seekFunction = MRMediaRemoteSetElapsedTimeFunction {
            seekFunction(position)
        } else {
            // Fallback to AppleScript for specific apps
            if let bundleID = bundleIdentifier {
                if bundleID == "com.apple.Music" {
                    let script = """
                    tell application "Music"
                        set player position to \(position)
                    end tell
                    """
                    executeAppleScriptVoid(script)
                } else if bundleID == "com.spotify.client" {
                    let script = """
                    tell application "Spotify"
                        set player position to \(position)
                    end tell
                    """
                    executeAppleScriptVoid(script)
                }
            }
        }
    }
    
    private func executeAppleScriptVoid(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: source) {
                scriptObject.executeAndReturnError(&error)
            }
        }
    }
    
    /// Pause a specific app by bundle ID
    private func pauseApp(bundleID: String) {
        switch bundleID {
        case "com.apple.Music":
            executeAppleScriptVoid("tell application \"Music\" to pause")
        case "com.spotify.client":
            executeAppleScriptVoid("tell application \"Spotify\" to pause")
        case "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
             "com.operasoftware.Opera", "company.thebrowser.Browser":
            let appName = getAppName(for: bundleID)
            let script = """
            tell application "\(appName)"
                set activeTab to active tab of front window
                execute activeTab javascript "document.querySelectorAll('video,audio').forEach(e => e.pause())"
            end tell
            """
            executeAppleScriptVoid(script)
        case "com.apple.Safari":
            let script = """
            tell application "Safari"
                do JavaScript "document.querySelectorAll('video,audio').forEach(e => e.pause())" in front document
            end tell
            """
            executeAppleScriptVoid(script)
        case "org.mozilla.firefox":
            simulateMediaPauseKey()
        default:
            break
        }
    }
    
    /// Simulate a media pause key press (fallback for apps without AppleScript support)
    private func simulateMediaPauseKey() {
        let keyCode: UInt32 = 0x100000 // NX_KEYTYPE_PLAY (16) << 16
        func postMediaKey(down: Bool) {
            let flags: UInt32 = down ? 0x000A00 : 0x000B00
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int(keyCode | UInt32(flags)),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        postMediaKey(down: true)
        postMediaKey(down: false)
    }
    
    // MARK: - Favorite
    func toggleFavorite() {
        guard let bundleID = bundleIdentifier, bundleID == "com.apple.Music" else {
            return // Only Apple Music supports favorite
        }
        
        let script = """
        tell application "Music"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil {
                    let loved = descriptor.booleanValue
                    DispatchQueue.main.async {
                        self?.isFavorite = loved
                    }
                }
            }
        }
    }
    
    var supportsFavorite: Bool {
        return bundleIdentifier == "com.apple.Music"
    }
    
    // MARK: - Shuffle Toggle
    
    func toggleShuffle() {
        guard let bundleID = bundleIdentifier else { return }
        
        var script: String
        
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                set shuffle enabled to not shuffle enabled
                return shuffle enabled
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                set shuffling to not shuffling
                return shuffling
            end tell
            """
        } else {
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil {
                    let newState = descriptor.booleanValue
                    DispatchQueue.main.async {
                        self?.isShuffleEnabled = newState
                    }
                }
            }
        }
    }
    
    // MARK: - Repeat Toggle
    
    func toggleRepeat() {
        guard let bundleID = bundleIdentifier else { return }
        
        if bundleID == "com.apple.Music" {
            toggleAppleMusicRepeat()
        } else if bundleID == "com.spotify.client" {
            toggleSpotifyRepeat()
        }
    }
    
    private func toggleAppleMusicRepeat() {
        // Cycle: off -> all -> one -> off
        let nextMode: RepeatMode
        switch repeatMode {
        case .off: nextMode = .all
        case .all: nextMode = .one
        case .one: nextMode = .off
        }
        
        let modeString: String
        switch nextMode {
        case .off: modeString = "off"
        case .all: modeString = "all"
        case .one: modeString = "one"
        }
        
        let script = """
        tell application "Music"
            set song repeat to \(modeString)
            return song repeat as text
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil {
                    let resultString = descriptor.stringValue?.lowercased() ?? "off"
                    var newMode: RepeatMode = .off
                    if resultString.contains("all") {
                        newMode = .all
                    } else if resultString.contains("one") {
                        newMode = .one
                    }
                    
                    DispatchQueue.main.async {
                        self?.repeatMode = newMode
                    }
                }
            }
        }
    }
    
    private func toggleSpotifyRepeat() {
        // Spotify only supports on/off for repeat via AppleScript
        let script = """
        tell application "Spotify"
            set repeating to not repeating
            return repeating
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let descriptor = scriptObject.executeAndReturnError(&error)
                
                if error == nil {
                    let newState = descriptor.booleanValue
                    DispatchQueue.main.async {
                        self?.repeatMode = newState ? .all : .off
                    }
                }
            }
        }
    }
    
    var supportsShuffleRepeat: Bool {
        return bundleIdentifier == "com.apple.Music" || bundleIdentifier == "com.spotify.client"
    }
    
    // Open the source app (Music, Spotify, YouTube, etc.)
    func openSourceApp() {
        guard let bundleID = bundleIdentifier else { return }
        
        // Get the app URL from bundle identifier
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        }
    }
    
    // MARK: - Volume Control
    
    private func setupVolumeMonitoring() {
        // Get initial volume
        updateVolume()
        
        // Update volume every 3 seconds (not needed frequently)
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateVolume()
        }
    }
    
    private func updateVolume() {
        volume = getSystemVolume()
    }
    
    func setVolume(_ newVolume: Float) {
        setSystemVolume(newVolume)
        DispatchQueue.main.async {
            self.volume = newVolume
        }
    }
    
    private func getSystemVolume() -> Float {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        
        var getDefaultOutputDevicePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &getDefaultOutputDevicePropertyAddress,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID)
        
        var volume = Float32(0.0)
        var volumeSize = UInt32(MemoryLayout.size(ofValue: volume))
        
        var volumePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        
        AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &volumePropertyAddress,
            0,
            nil,
            &volumeSize,
            &volume)
        
        return volume
    }
    
    private func setSystemVolume(_ volume: Float) {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        
        var getDefaultOutputDevicePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &getDefaultOutputDevicePropertyAddress,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID)
        
        var newVolume = volume
        let volumeSize = UInt32(MemoryLayout.size(ofValue: newVolume))
        
        var volumePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        
        AudioObjectSetPropertyData(
            defaultOutputDeviceID,
            &volumePropertyAddress,
            0,
            nil,
            volumeSize,
            &newVolume)
    }
}

// NOTE: NowPlayingUpdate, NowPlayingPayload, and JSONLinesPipeHandler are defined in 
// MediaControllers/NowPlayingController.swift - no need to duplicate them here.
