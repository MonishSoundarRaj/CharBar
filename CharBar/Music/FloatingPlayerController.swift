//
//  FloatingPlayerController.swift
//  CharBar
//
//  Floating Mini Player - Detachable, resizable, always-on-top music player
//

import SwiftUI
import AppKit
import Combine
import Lottie

// MARK: - Floating Player Controller (Singleton)
/// Manages the floating mini player window lifecycle
class FloatingPlayerController: NSObject, ObservableObject {
    static let shared = FloatingPlayerController()
    
    private var floatingPanel: FloatingPlayerPanel?
    private var hostingView: NSHostingView<AnyView>?
    
    // Reference to the app's MediaObserver (set by AppDelegate)
    weak var mediaObserver: MediaObserver?
    
    @Published var isVisible: Bool = false
    
    private override init() {
        super.init()
    }
    
    /// Configure with the app's MediaObserver (call from AppDelegate)
    func configure(with mediaObserver: MediaObserver) {
        self.mediaObserver = mediaObserver
    }
    
    // MARK: - Public API
    
    /// Toggle the floating player visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// Show the floating player
    func show() {
        if floatingPanel == nil {
            createPanel()
        }
        
        guard let panel = floatingPanel else { return }
        
        // Position near mouse or center of screen
        positionPanel(panel)
        
        // Show with fade animation
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        
        isVisible = true
    }
    
    /// Hide the floating player
    func hide() {
        guard let panel = floatingPanel else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.isVisible = false
        }
    }
    
    /// Close and destroy the floating player
    func close() {
        hide()
        floatingPanel = nil
        hostingView = nil
    }
    
    // MARK: - Private Methods
    
    private func createPanel() {
        guard let mediaObserver = mediaObserver else {
            return
        }
        
        let panel = FloatingPlayerPanel()
        
        // Create the SwiftUI content
        let playerView = FloatingMiniPlayerView(
            mediaObserver: mediaObserver,
            onClose: { [weak self] in
                self?.hide()
            }
        )
        
        let hostingView = NSHostingView(rootView: AnyView(playerView))
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 340)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: 340, height: 340))
        
        self.floatingPanel = panel
        self.hostingView = hostingView
    }
    
    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        
        // Get mouse location
        let mouseLocation = NSEvent.mouseLocation
        
        // Position panel near mouse, but ensure it's on screen
        var panelOrigin = NSPoint(
            x: mouseLocation.x - panel.frame.width / 2,
            y: mouseLocation.y - panel.frame.height - 20
        )
        
        // Clamp to screen bounds
        let screenFrame = screen.visibleFrame
        panelOrigin.x = max(screenFrame.minX + 10, min(panelOrigin.x, screenFrame.maxX - panel.frame.width - 10))
        panelOrigin.y = max(screenFrame.minY + 10, min(panelOrigin.y, screenFrame.maxY - panel.frame.height - 10))
        
        panel.setFrameOrigin(panelOrigin)
    }
}

// MARK: - Floating Player Panel (NSPanel Subclass)
/// Custom NSPanel configured for floating, borderless behavior with fixed size
class FloatingPlayerPanel: NSPanel {
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        configurePanel()
    }
    
    private func configurePanel() {
        // Floating behavior
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Appearance - fully transparent with rounded corners
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        
        // Make content view layer-backed with rounded corners
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 16
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.backgroundColor = CGColor.clear
        
        // Allow moving by background - we intercept in mouseDown to prevent
        // seek bar drags from triggering window movement.
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        
        // Fixed size - larger square for all controls
        minSize = NSSize(width: 280, height: 280)
        maxSize = NSSize(width: 280, height: 280)
        
        // Keep on top always
        hidesOnDeactivate = false
    }
    
    // Allow the window to become key for interactions
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    override func mouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        // The seek bar and controls are in the bottom ~60pt of the panel.
        // Prevent window drag when clicking in that region so the seek bar works.
        if locationInWindow.y < 60 {
            // Don't call super — this prevents the window drag.
            // The SwiftUI DragGesture on the seek bar will handle this event.
            return
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Floating Mini Player View
/// Compact album art view - shows controls overlay on hover
struct FloatingMiniPlayerView: View {
    @ObservedObject var mediaObserver: MediaObserver
    @ObservedObject var audioManager = AudioOutputManager.shared
    @AppStorage("music_useAdaptiveColor") private var useAdaptiveColor: Bool = true
    
    @State private var extractedColor: Color = .black
    @State private var isHovering: Bool = false
    @State private var sliderValue: Double = 0
    @State private var isDragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    // Music character animation state
    @State private var animationName: String = "music"
    @State private var isStaticIcon: Bool = false
    @State private var sfSymbolName: String? = nil
    
    let onClose: () -> Void
    
    // Size of the floating player
    private let playerSize: CGFloat = 320
    
    private var trackID: String {
        "\(mediaObserver.title)-\(mediaObserver.artist)-\(mediaObserver.album)"
    }
    
    init(mediaObserver: MediaObserver, onClose: @escaping () -> Void) {
        self.mediaObserver = mediaObserver
        self.onClose = onClose
    }
    
    // Format time as M:SS
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    /// Check if current source is a music app (vs browser/video)
    private var isMusicApp: Bool {
        guard let bundleID = mediaObserver.bundleIdentifier else { return true }
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }
    
    var body: some View {
        ZStack {
            // Album Art Background (full size)
            artworkView
            
            // Hover overlay with controls
            if isHovering {
                controlsOverlay
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    ))
            }
            
            // Top bar - Source logo (left) - Only visible when NOT hovering
            if !isHovering {
                VStack {
                    HStack(alignment: .top) {
                        if let icon = mediaObserver.sourceAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(color: .black.opacity(0.5), radius: 4)
                        }
                        Spacer()
                    }
                    .padding(10)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Close button (top-right) - ALWAYS VISIBLE
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                Spacer()
            }
            
            // Bottom bar - Title & wave - Only visible when NOT hovering
            if !isHovering {
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mediaObserver.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(mediaObserver.artist)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        musicAnimationView
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 16,
                                bottomTrailingRadius: 16,
                                topTrailingRadius: 0
                            )
                        )
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isHovering)
        .frame(width: playerSize, height: playerSize)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: extractedColor.opacity(0.4), radius: 12, x: 0, y: 6)
        .onHover { hovering in
            withAnimation(hovering ? .easeInOut(duration: 0.3) : .easeOut(duration: 0.45)) {
                isHovering = hovering
            }
        }
        .onChange(of: mediaObserver.artworkImage) { _, newArt in
            extractColor(from: newArt)
        }
        .onChange(of: trackID) { oldID, newID in
            sliderValue = 0
            lastDragged = Date()
        }
        .onChange(of: mediaObserver.duration) { _, newDuration in
            // Duration updated (e.g. new track loaded) - clamp slider
            if !isDragging && newDuration > 0 {
                sliderValue = min(sliderValue, newDuration)
            }
        }
        .onAppear {
            extractColor(from: mediaObserver.artworkImage)
            sliderValue = mediaObserver.estimatedPlaybackPosition()
            audioManager.refreshDevices()
            loadMusicCharacterSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))) { _ in
            loadMusicCharacterSettings()
        }
    }
    
    // MARK: - Music Animation View
    @ViewBuilder
    private var musicAnimationView: some View {
        if isStaticIcon {
            // Static icon mode - show SF Symbol with play/pause state
            if let sfName = sfSymbolName {
                Image(systemName: sfName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .opacity(mediaObserver.isPlaying ? 1.0 : 0.4)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: mediaObserver.isPlaying)
                    .opacity(mediaObserver.isPlaying ? 1.0 : 0.4)
            }
        } else if let anim = LottieAnimation.named(animationName) {
            // Lottie animation - plays when music plays, pauses when music pauses
            if mediaObserver.isPlaying {
                LottieView(animation: anim)
                    .playing(loopMode: .loop)
                    .animationSpeed(0.7)
                    .frame(width: 32, height: 32)
            } else {
                LottieView(animation: anim)
                    .currentProgress(0.5)
                    .frame(width: 32, height: 32)
                    .opacity(0.4)
            }
        } else {
            // Fallback to wave icon
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .symbolEffect(.variableColor.iterative.reversing, isActive: mediaObserver.isPlaying)
                .opacity(mediaObserver.isPlaying ? 1.0 : 0.4)
        }
    }
    
    // MARK: - Load Music Character Settings
    private func loadMusicCharacterSettings() {
        if let config = sharedSettingsManager?.configurations[.music] {
            isStaticIcon = config.character.isStaticIcon
            animationName = config.character.lottieFileName ?? "music"
            sfSymbolName = config.character.sfSymbolName
        }
    }
    
    // MARK: - Album Art View
    @ViewBuilder
    private var artworkView: some View {
        if let artwork = mediaObserver.artworkImage {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .frame(width: playerSize, height: playerSize)
                
                Image(nsImage: artwork)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: playerSize, height: playerSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                if mediaObserver.isBrowserSource {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                if !mediaObserver.isPlaying && !isHovering {
                    Color.black.opacity(0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .transition(.opacity)
                    
                    Image(systemName: "pause.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.7))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: mediaObserver.isPlaying)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                Image(systemName: mediaObserver.isBrowserSource ? "play.tv" : "music.note")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(width: playerSize, height: playerSize)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Controls Overlay (shown on hover)
    private var controlsOverlay: some View {
        ZStack {
            // Blur/Dim background with rounded corners
            Color.black.opacity(0.65)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(spacing: 16) {
                // Track Info
                VStack(spacing: 4) {
                    Text(mediaObserver.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(mediaObserver.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.top, 35)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Main Playback Controls Row
                HStack(spacing: 28) {
                    // Previous / Back 15s
                    Button(action: {
                        if isMusicApp { mediaObserver.previousTrack() }
                        else { mediaObserver.seek(to: max(0, mediaObserver.estimatedPlaybackPosition() - 15)) }
                    }) {
                        Image(systemName: isMusicApp ? "backward.fill" : "gobackward.15")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    // Play/Pause
                    Button(action: { mediaObserver.togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 56, height: 56)
                            Image(systemName: mediaObserver.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Next / Forward 30s
                    Button(action: {
                        if isMusicApp { mediaObserver.nextTrack() }
                        else { mediaObserver.seek(to: min(mediaObserver.duration, mediaObserver.estimatedPlaybackPosition() + 30)) }
                    }) {
                        Image(systemName: isMusicApp ? "forward.fill" : "goforward.30")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                
                // Secondary Controls Row
                HStack(spacing: 20) {
                    // Audio Output (icon only, no arrow)
                    CompactAudioPickerButton()
                    
                    // Shuffle (music apps only)
                    if isMusicApp {
                        Button(action: { mediaObserver.toggleShuffle() }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 16))
                                .foregroundColor(mediaObserver.isShuffleEnabled ? .accentColor : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Repeat (music apps only)
                    if isMusicApp {
                        Button(action: { mediaObserver.toggleRepeat() }) {
                            Image(systemName: mediaObserver.repeatMode == .one ? "repeat.1" : "repeat")
                                .font(.system(size: 16))
                                .foregroundColor(mediaObserver.repeatMode != .off ? .accentColor : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Share
                    ShareButton(mediaObserver: mediaObserver)
                }
                .padding(.top, 4)
                
                Spacer()
                
                // Progress Bar (uses shared MusicProgressSlider respecting user's seek bar style)
                TimelineView(.animation(minimumInterval: mediaObserver.isPlaying ? 0.1 : nil)) { timeline in
                    VStack(spacing: 4) {
                        MusicProgressSlider(
                            value: $sliderValue,
                            duration: mediaObserver.duration,
                            isDragging: $isDragging,
                            lastDragged: $lastDragged,
                            onSeek: { newTime in
                                mediaObserver.seek(to: newTime)
                            },
                            isPlaying: mediaObserver.isPlaying,
                            tintColor: .white
                        )
                        .frame(height: 30)
                        
                        HStack {
                            Text(formatTime(isDragging ? sliderValue : mediaObserver.estimatedPlaybackPosition(at: timeline.date)))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                                .monospacedDigit()
                            Spacer()
                            Text(formatTime(mediaObserver.duration))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                                .monospacedDigit()
                        }
                    }
                    .onChange(of: timeline.date) { _, newDate in
                        if !isDragging && newDate.timeIntervalSince(lastDragged) > 1.0 {
                            sliderValue = mediaObserver.estimatedPlaybackPosition(at: newDate)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
    
    // MARK: - Color Extraction
    private func extractColor(from image: NSImage?) {
        guard let image = image else {
            withAnimation { extractedColor = .black }
            return
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            let color = image.vibrantColor
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.6)) {
                    extractedColor = color
                }
            }
        }
    }
}

// MARK: - Visual Effect Blur (for glass background)
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Pop Out Button (Add to your player header)
struct PopOutButton: View {
    var body: some View {
        Button(action: {
            FloatingPlayerController.shared.show()
        }) {
            Image(systemName: "pip.enter")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Pop Out Mini Player")
    }
}

// MARK: - Compact Audio Picker (Icon only, NO arrow, shows menu on click)
struct CompactAudioPickerButton: View {
    @ObservedObject var audioManager = AudioOutputManager.shared
    @State private var isHovering = false
    
    var body: some View {
        Menu {
            ForEach(audioManager.outputDevices) { device in
                Button(action: {
                    audioManager.setDefaultOutputDevice(device)
                }) {
                    HStack {
                        Image(systemName: device.icon)
                        Text(device.name)
                        if device.isDefault {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            
            Divider()
            
            Button(action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("Sound Settings...", systemImage: "gear")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovering ? 0.2 : 0.1))
                
                Image(systemName: audioManager.currentDevice?.icon ?? "hifispeaker.2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(isHovering ? 1.0 : 0.8))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 32, height: 32)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden) // Remove the dropdown arrow
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            audioManager.refreshDevices()
        }
    }
}

