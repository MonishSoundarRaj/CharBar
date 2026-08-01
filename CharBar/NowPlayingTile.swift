import SwiftUI
import Lottie

struct NowPlayingTile: View {
    @ObservedObject var mediaObserver: MediaObserver
    @ObservedObject var audioManager = AudioOutputManager.shared
    @AppStorage("music_useAdaptiveColor") private var useAdaptiveColor: Bool = true
    
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var lastDragged: Date = .distantPast
    @State private var isShareLoading = false
    @State private var extractedColor: Color = .black
    
    // Music character animation state
    @State private var animationName: String = "music"
    @State private var isStaticIcon: Bool = false
    @State private var sfSymbolName: String? = nil
    
    // Track ID for album art animation
    private var trackID: String {
        "\(mediaObserver.title)-\(mediaObserver.artist)-\(mediaObserver.album)"
    }
    
    // Format time as M:SS
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var body: some View {
        standardPlayerView
            .onChange(of: mediaObserver.artworkImage) { _, newArt in
                extractColorFromArtwork(newArt)
            }
            .onChange(of: trackID) { _, _ in
                // Force reset to 0 on track change — the new track's position
                // hasn't been reported yet, so estimatedPlaybackPosition() would
                // still return the old song's value.
                // Setting lastDragged creates a 1s cooldown so the stale
                // estimatedPlaybackPosition() doesn't immediately overwrite this reset.
                sliderValue = 0
                lastDragged = Date()
            }
            .onChange(of: mediaObserver.duration) { _, newDuration in
                if !isDragging && newDuration > 0 {
                    sliderValue = min(sliderValue, newDuration)
                }
            }
            .onAppear {
                extractColorFromArtwork(mediaObserver.artworkImage)
                sliderValue = mediaObserver.estimatedPlaybackPosition()
                audioManager.refreshDevices()
                loadMusicCharacterSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))) { _ in
                loadMusicCharacterSettings()
            }
    }
    
    // MARK: - Music Animation View
    
    private var adaptiveTint: Color {
        useAdaptiveColor && mediaObserver.artworkImage != nil ? extractedColor : Color.white.opacity(0.85)
    }
    
    /// For Lottie colorMultiply: .white is identity (preserves original colors)
    private var lottieTint: Color {
        useAdaptiveColor && mediaObserver.artworkImage != nil ? extractedColor : .white
    }
    
    @ViewBuilder
    private var musicAnimationView: some View {
        if isStaticIcon {
            if let sfName = sfSymbolName {
                Image(systemName: sfName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(adaptiveTint)
                    .opacity(mediaObserver.isPlaying ? 1.0 : 0.3)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(adaptiveTint)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: mediaObserver.isPlaying)
                    .opacity(mediaObserver.isPlaying ? 1.0 : 0.3)
            }
        } else if let anim = LottieAnimation.named(animationName) {
            if mediaObserver.isPlaying {
                LottieView(animation: anim)
                    .playing(loopMode: .loop)
                    .animationSpeed(0.7)
                    .frame(width: 36, height: 36)
                    .colorMultiply(lottieTint)
            } else {
                LottieView(animation: anim)
                    .currentProgress(0.5)
                    .frame(width: 36, height: 36)
                    .colorMultiply(lottieTint)
                    .opacity(0.3)
            }
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(adaptiveTint)
                .symbolEffect(.variableColor.iterative.reversing, isActive: mediaObserver.isPlaying)
                .opacity(mediaObserver.isPlaying ? 1.0 : 0.3)
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
    
    // MARK: - Color Extraction
    private func extractColorFromArtwork(_ image: NSImage?) {
        guard let image = image else {
            withAnimation(.easeInOut(duration: 0.5)) {
                extractedColor = .black
            }
            return
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            let dominantColor = image.vibrantColor
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.extractedColor = dominantColor
                }
            }
        }
    }
    
    // MARK: - Background (Adaptive Gradient OR Glass)
    @ViewBuilder
    private var playerBackground: some View {
        if useAdaptiveColor {
            // Adaptive mode - use gradient
            ZStack {
                Color.black
                
                if mediaObserver.artworkImage != nil {
                    // State A: Adaptive + Artwork - Premium gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            extractedColor.opacity(0.6),
                            extractedColor.opacity(0.2),
                            Color.black
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    // State B: Adaptive + No Artwork - Neutral gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.25).opacity(0.5),
                            Color.black
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        } else {
            // Glass mode — vibrancy follows the dropdown's backdrop so the card
            // stays in sync with light/dark wallpapers. The previous white overlay
            // is replaced with a gentle dark scrim so text contrast stays readable
            // without the "whitish band" the white overlay used to produce.
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
    }
    
    // Track rotation state for spin animation
    @State private var artworkRotation: Double = 0
    @State private var previousTrackID: String = ""
    
    // MARK: - Standard Player View
    private var standardPlayerView: some View {
        VStack(spacing: 10) {
            // Track Info - Album art LEFT, info CENTER, wave RIGHT
            HStack(spacing: 12) {
                // Album Art (LEFT) - with SPIN animation on track change
                ZStack(alignment: .bottomTrailing) {
                    if let artwork = mediaObserver.artworkImage {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black)
                                .frame(width: 100, height: 100)
                            
                            Image(nsImage: artwork)
                                .renderingMode(.original)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            if mediaObserver.isBrowserSource {
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            
                            if !mediaObserver.isPlaying {
                                Color.black.opacity(0.45)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .animation(.easeInOut(duration: 0.3), value: mediaObserver.isPlaying)
                        // Spin animation when track changes
                        .rotation3DEffect(
                            .degrees(artworkRotation),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                        .scaleEffect(artworkRotation != 0 ? 0.95 : 1.0)
                        .id(trackID)
                    } else {
                        // No artwork placeholder
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [Color(NSColor.controlBackgroundColor), Color.black.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: mediaObserver.isBrowserSource ? "play.tv" : "music.note")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                        }
                        .cornerRadius(12)
                    }
                    
                    // Source App Badge (bottom-right of album art)
                    sourceAppBadge
                        .offset(x: 4, y: 4)
                }
                .onChange(of: trackID) { oldID, newID in
                    // Trigger spin animation when track changes
                    if oldID != newID && !oldID.isEmpty {
                        withAnimation(.easeIn(duration: 0.2)) {
                            artworkRotation = 90
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                artworkRotation = 0
                            }
                        }
                    }
                }
                
                // Track info (CENTER) - Clickable to open source app
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: {
                        mediaObserver.openSourceApp()
                    }) {
                        ScrollingTextView(text: mediaObserver.title, font: .system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Click to open in \(getAppName())")
                    
                    Text(mediaObserver.artist)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                    
                    if !mediaObserver.album.isEmpty {
                        Text(mediaObserver.album)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                    }
                }
                .clipped() // Clip scrolling text to not go over artwork
                
                Spacer()
                
                // Right side: Pop Out + Animation
                HStack(spacing: 10) {
                    // Pop Out Button
                    PopOutButton()
                    
                    // User's selected music animation - plays/pauses with music
                    musicAnimationView
                }
            }
            
            // Seekable Progress Bar with TimelineView (Boring Notch style)
            // TimelineView updates every 0.1 seconds while playing
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
                        tintColor: useAdaptiveColor && mediaObserver.artworkImage != nil ? extractedColor : Color.white.opacity(0.85)
                    )
                    .frame(height: 30)
                    
                    // Time Labels
                    HStack {
                        Text(formatTime(isDragging ? sliderValue : mediaObserver.estimatedPlaybackPosition(at: timeline.date)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(mediaObserver.duration))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .onChange(of: timeline.date) { _, newDate in
                    // Only update slider if not dragging and hasn't been recently dragged
                    if !isDragging && newDate.timeIntervalSince(lastDragged) > 1.0 {
                        sliderValue = mediaObserver.estimatedPlaybackPosition(at: newDate)
                    }
                }
            }
            
            // Controls Row 1: Shuffle, Prev/Backward, Play/Pause, Next/Forward, Repeat
            HStack(spacing: 16) {
                // Shuffle Button (hidden for browser sources)
                if isMusicApp {
                    ShuffleButton(mediaObserver: mediaObserver)
                } else {
                    // Empty space for alignment
                    Color.clear.frame(width: 20, height: 20)
                }
                
                Spacer()
                
                // Previous / Skip Backward 15s
                Button(action: {
                    if isMusicApp {
                        mediaObserver.previousTrack()
                    } else {
                        // Skip backward 15 seconds for browser/video
                        let newTime = max(0, mediaObserver.estimatedPlaybackPosition() - 15)
                        mediaObserver.seek(to: newTime)
                    }
                }) {
                    Image(systemName: isMusicApp ? "backward.fill" : "gobackward.15")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help(isMusicApp ? "Previous Track" : "Skip Back 15s")
                
                // Play/Pause
                Button(action: {
                    mediaObserver.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: mediaObserver.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                
                // Next / Skip Forward 30s
                Button(action: {
                    if isMusicApp {
                        mediaObserver.nextTrack()
                    } else {
                        // Skip forward 30 seconds for browser/video
                        let newTime = min(mediaObserver.duration, mediaObserver.estimatedPlaybackPosition() + 30)
                        mediaObserver.seek(to: newTime)
                    }
                }) {
                    Image(systemName: isMusicApp ? "forward.fill" : "goforward.30")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help(isMusicApp ? "Next Track" : "Skip Forward 30s")
                
                Spacer()
                
                // Repeat Button (hidden for browser sources)
                if isMusicApp {
                    RepeatButton(mediaObserver: mediaObserver)
                } else {
                    // Empty space for alignment
                    Color.clear.frame(width: 20, height: 20)
                }
            }
            
            // Controls Row 2: Heart, Jump, Share, Output
            HStack(spacing: 14) {
                // Feature 1: Favorite Button
                FavoriteButton(mediaObserver: mediaObserver)
                
                // Feature 2: Jump to App Button
                Button(action: {
                    mediaObserver.openSourceApp()
                }) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in \(getAppName())")
                .disabled(mediaObserver.bundleIdentifier == nil)
                .opacity(mediaObserver.bundleIdentifier == nil ? 0.3 : 1.0)
                
                Spacer()
                
                // Feature 3: Share Button
                ShareButton(mediaObserver: mediaObserver)
                
                // Audio Output Picker (next to share)
                AudioOutputMenuView(compact: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(playerBackground)
        .shadow(color: useAdaptiveColor ? extractedColor.opacity(0.2) : Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(width: 320)
    }
    
    // Get friendly app name
    /// Check if current source is a music app (vs browser/video)
    private var isMusicApp: Bool {
        mediaObserver.isMusicApp
    }
    
    private func getAppName() -> String {
        switch mediaObserver.bundleIdentifier {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        case "com.google.Chrome": return "Chrome"
        case "org.mozilla.firefox": return "Firefox"
        case "com.apple.Safari": return "Safari"
        case "com.brave.Browser": return "Brave"
        case "company.thebrowser.Browser": return "Arc"
        default: return "App"
        }
    }
    
    // Source App Badge - Shows the actual app icon from the system
    @ViewBuilder
    private var sourceAppBadge: some View {
        ZStack {
            // Background circle with shadow
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            
            // Actual app icon (fetched dynamically)
            if let appIcon = mediaObserver.sourceAppIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
            } else {
                // Fallback to SF Symbol
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Feature 1: Enhanced Favorite Button

struct FavoriteButton: View {
    @ObservedObject var mediaObserver: MediaObserver
    @State private var isToggling = false
    @State private var showUnsupported = false
    
    var body: some View {
        Button(action: toggleFavorite) {
            ZStack {
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 15, height: 15)
                } else {
                    Image(systemName: mediaObserver.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15))
                        .foregroundColor(heartColor)
                        .scaleEffect(mediaObserver.isFavorite ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3), value: mediaObserver.isFavorite)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isToggling || !canFavorite)
        .opacity(canFavorite ? 1.0 : 0.3)
        .help(favoriteHelpText)
        .popover(isPresented: $showUnsupported) {
            Text("Spotify no longer supports the 'Love' feature via automation.")
                .padding()
                .frame(width: 200)
        }
    }
    
    private var canFavorite: Bool {
        // Apple Music fully supports it
        // Spotify removed AppleScript support for loved status
        return mediaObserver.bundleIdentifier == "com.apple.Music"
    }
    
    private var heartColor: Color {
        if mediaObserver.isFavorite {
            return .red
        }
        return .secondary
    }
    
    private var favoriteHelpText: String {
        switch mediaObserver.bundleIdentifier {
        case "com.apple.Music":
            return mediaObserver.isFavorite ? "Remove from Loved" : "Love this track"
        case "com.spotify.client":
            return "Spotify doesn't support remote favorites"
        default:
            return "Favorite not available"
        }
    }
    
    private func toggleFavorite() {
        guard let bundleID = mediaObserver.bundleIdentifier else { return }
        
        if bundleID == "com.apple.Music" {
            isToggling = true
            mediaObserver.toggleFavorite()
            
            // Reset toggling state after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isToggling = false
            }
        } else if bundleID == "com.spotify.client" {
            // Spotify removed the 'loved' AppleScript command
            // Show unsupported message
            showUnsupported = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showUnsupported = false
            }
        }
    }
}

// MARK: - Shuffle Button

struct ShuffleButton: View {
    @ObservedObject var mediaObserver: MediaObserver
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: toggleShuffle) {
            Image(systemName: "shuffle")
                .font(.system(size: 15, weight: mediaObserver.isShuffleEnabled ? .semibold : .regular))
                .foregroundColor(mediaObserver.isShuffleEnabled ? .accentColor : .secondary)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!mediaObserver.supportsShuffleRepeat)
        .opacity(mediaObserver.supportsShuffleRepeat ? 1.0 : 0.3)
        .help(mediaObserver.isShuffleEnabled ? "Shuffle: On" : "Shuffle: Off")
    }
    
    private func toggleShuffle() {
        // Animate
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            isAnimating = true
        }
        
        mediaObserver.toggleShuffle()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Repeat Button

struct RepeatButton: View {
    @ObservedObject var mediaObserver: MediaObserver
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: toggleRepeat) {
            Image(systemName: repeatIcon)
                .font(.system(size: 15, weight: mediaObserver.repeatMode.isActive ? .semibold : .regular))
                .foregroundColor(repeatColor)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!mediaObserver.supportsShuffleRepeat)
        .opacity(mediaObserver.supportsShuffleRepeat ? 1.0 : 0.3)
        .help(repeatHelpText)
    }
    
    private var repeatIcon: String {
        switch mediaObserver.repeatMode {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
    
    private var repeatColor: Color {
        switch mediaObserver.repeatMode {
        case .off: return .secondary
        case .one: return .orange
        case .all: return .accentColor
        }
    }
    
    private var repeatHelpText: String {
        switch mediaObserver.repeatMode {
        case .off: return "Repeat: Off"
        case .one: return "Repeat: One"
        case .all: return "Repeat: All"
        }
    }
    
    private func toggleRepeat() {
        // Animate
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            isAnimating = true
        }
        
        mediaObserver.toggleRepeat()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isAnimating = false
            }
        }
    }
}

// Music Seek Bar Style
enum MusicSeekBarStyle: String, CaseIterable {
    case bar = "Bar"
    case toggle = "Toggle"
    case wavy = "Wavy"
    
    var id: String { rawValue }
}

// Custom Music Progress Slider (Boring Notch style)
struct MusicProgressSlider: View {
    @Binding var value: Double
    let duration: Double
    @Binding var isDragging: Bool
    @Binding var lastDragged: Date
    var onSeek: (Double) -> Void
    var isPlaying: Bool = false
    var tintColor: Color = .accentColor
    
    @AppStorage("musicSeekBarStyle") private var seekBarStyle: MusicSeekBarStyle = .bar
    @State private var isHoveringSeek: Bool = false
    @State private var hoverX: CGFloat = 0
    
    private func formatHoverTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let safeDuration = max(duration, 1.0)
            let progress = min(max(value / safeDuration, 0), 1)
            let filledWidth = progress * width
            
            ZStack(alignment: .leading) {
                switch seekBarStyle {
                case .bar:
                    barSliderContent(width: width, safeDuration: safeDuration, filledWidth: filledWidth)
                case .toggle:
                    toggleSliderContent(width: width, safeDuration: safeDuration, filledWidth: filledWidth, progress: progress)
                case .wavy:
                    wavySliderContent(width: width, safeDuration: safeDuration, progress: progress)
                }
                
                if isHoveringSeek && !isDragging {
                    hoverPreview(width: width, safeDuration: safeDuration)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverX = max(0, min(location.x, width))
                    isHoveringSeek = true
                case .ended:
                    isHoveringSeek = false
                }
            }
        }
    }
    
    @ViewBuilder
    private func hoverPreview(width: CGFloat, safeDuration: Double) -> some View {
        let clampedX = max(0, min(hoverX, width))
        let hoverTime = (clampedX / width) * safeDuration
        
        Text(formatHoverTime(hoverTime))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.95))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .position(x: max(20, min(clampedX, width - 20)), y: -10)
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.12), value: hoverX)
    }
    
    @ViewBuilder
    private func barSliderContent(width: CGFloat, safeDuration: Double, filledWidth: CGFloat) -> some View {
        let height: CGFloat = isDragging ? 8 : (isHoveringSeek ? 7 : 4)
        
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: height / 2)
                .fill(Color.gray.opacity(0.3))
                .frame(height: height)
            
            if isHoveringSeek && !isDragging {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(tintColor.opacity(0.3))
                    .frame(width: max(hoverX, 0), height: height)
            }
            
            RoundedRectangle(cornerRadius: height / 2)
                .fill(tintColor)
                .frame(width: max(filledWidth, 0), height: height)
        }
        .frame(height: 14)
        .contentShape(Rectangle())
        .gesture(makeDragGesture(width: width, safeDuration: safeDuration))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHoveringSeek)
    }
    
    @ViewBuilder
    private func toggleSliderContent(width: CGFloat, safeDuration: Double, filledWidth: CGFloat, progress: Double) -> some View {
        let height: CGFloat = isDragging ? 8 : (isHoveringSeek ? 8 : 6)
        let thumbSize: CGFloat = isDragging ? 16 : (isHoveringSeek ? 14 : 12)
        
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: height / 2)
                .fill(Color.gray.opacity(0.3))
                .frame(height: height)
            
            if isHoveringSeek && !isDragging {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(tintColor.opacity(0.3))
                    .frame(width: max(hoverX, 0), height: height)
            }
            
            RoundedRectangle(cornerRadius: height / 2)
                .fill(tintColor.opacity(0.4))
                .frame(width: max(filledWidth, 0), height: height)
            
            Circle()
                .fill(tintColor)
                .frame(width: thumbSize, height: thumbSize)
                .shadow(color: .black.opacity(0.3), radius: isDragging ? 4 : 2, y: isDragging ? 2 : 1)
                .offset(x: max(0, min(filledWidth - thumbSize / 2, width - thumbSize)))
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .gesture(makeDragGesture(width: width, safeDuration: safeDuration))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHoveringSeek)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
    }
    
    @ViewBuilder
    private func wavySliderContent(width: CGFloat, safeDuration: Double, progress: Double) -> some View {
        let thumbX = width * CGFloat(progress)
        let maxAmplitude: CGFloat = 3.0
        let frequency: CGFloat = 0.12
        let thumbSize: CGFloat = 14.0
        let height: CGFloat = 24.0
        let wavePlaying = isPlaying && !isDragging
        let currentAmplitude: CGFloat = wavePlaying ? maxAmplitude : 0
        
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = wavePlaying ? (time * 2.5) : 0
            
            ZStack(alignment: .leading) {
                Path { path in
                    path.move(to: CGPoint(x: thumbX, y: height / 2))
                    path.addLine(to: CGPoint(x: width, y: height / 2))
                }
                .stroke(tintColor.opacity(0.3), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    for x in stride(from: 0, through: thumbX, by: 1) {
                        let y = (height / 2) + currentAmplitude * sin(x * frequency - phase)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .shadow(color: tintColor.opacity(0.4), radius: 2, x: 0, y: 0)
                
                Circle()
                    .fill(tintColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: thumbX, y: height / 2)
            }
            .animation(.easeInOut(duration: 0.3), value: wavePlaying)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .gesture(makeDragGesture(width: width, safeDuration: safeDuration))
    }
    
    private func makeDragGesture(width: CGFloat, safeDuration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                withAnimation(.easeOut(duration: 0.1)) {
                    isDragging = true
                }
                isHoveringSeek = false
                let percent = max(0, min(gesture.location.x / width, 1))
                value = percent * safeDuration
            }
            .onEnded { gesture in
                let percent = max(0, min(gesture.location.x / width, 1))
                let newTime = percent * safeDuration
                value = newTime
                onSeek(newTime)
                lastDragged = Date()
                withAnimation(.easeOut(duration: 0.2)) {
                    isDragging = false
                }
            }
    }
}

// Visual Effect View for "Glass" background
struct EffectView: NSViewRepresentable {
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

// Scrolling text for dropdown menu
struct ScrollingTextView: View {
    let text: String
    let font: Font
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false) // Allow text to be its natural width
                .offset(x: offset)
                .onAppear {
                    checkAndScroll(containerWidth: geometry.size.width)
                }
        }
        .frame(height: 18)
        .clipped() // IMPORTANT: Clip scrolling text to container bounds
    }
    
    private func checkAndScroll(containerWidth: CGFloat) {
        let textWidth = text.widthOfString(usingFont: NSFont.systemFont(ofSize: 13, weight: .semibold))
        
        if textWidth > containerWidth {
            let scrollDistance = textWidth - containerWidth + 10
            
            // Start scrolling after 1s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                scrollCycle(distance: scrollDistance, count: 0)
            }
        }
    }
    
    private func scrollCycle(distance: CGFloat, count: Int) {
        guard count < 2 else { return } // Scroll only twice
        
        // Scroll
        withAnimation(.linear(duration: Double(distance / 25))) {
            offset = -distance
        }
        
        // Reset after scroll
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(distance / 25) + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                offset = 0
            }
            
            // Next cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                scrollCycle(distance: distance, count: count + 1)
            }
        }
    }
}

extension String {
    func widthOfString(usingFont font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        let size = (self as NSString).size(withAttributes: attributes)
        return size.width
    }
}

// Lottie Wave Animation View
struct LottieWaveView: NSViewRepresentable {
    let isPlaying: Bool

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        // CRITICAL: Initialize layer BEFORE adding animation to prevent ghosting
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear
        containerView.layer?.isOpaque = false

        // Create Lottie animation view
        if let animation = LottieAnimation.named("music") {
            let animationView = LottieAnimationView(animation: animation)
            animationView.contentMode = .scaleAspectFit
            animationView.loopMode = .loop
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.animationSpeed = 0.6 // Same slower speed as menubar

            // Ensure animation view also has proper layer setup
            animationView.wantsLayer = true
            animationView.layer?.backgroundColor = .clear
            animationView.layer?.isOpaque = false

            // Add to container
            containerView.addSubview(animationView)
            animationView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                animationView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                animationView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                animationView.topAnchor.constraint(equalTo: containerView.topAnchor),
                animationView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])

            // Store reference
            context.coordinator.animationView = animationView

            // Start playing if needed
            if isPlaying {
                animationView.play()
            }
        }

        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update animation state based on isPlaying
        if let animationView = context.coordinator.animationView {
            if isPlaying {
                if !animationView.isAnimationPlaying {
                    animationView.play()
                }
            } else {
                animationView.stop()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var animationView: LottieAnimationView?
    }
}
