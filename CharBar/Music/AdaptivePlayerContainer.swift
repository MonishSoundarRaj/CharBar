//
//  AdaptivePlayerContainer.swift
//  CharBar
//
//  Intelligent container that handles adaptive background styling for music player
//

import SwiftUI

// MARK: - Theme Color Extension
extension Color {
    /// The app's current theme background color
    /// This should match your global theme system
    static var themeBackground: Color {
        // Default theme color - can be customized via settings
        let themeName = UserDefaults.standard.string(forKey: "appTheme") ?? "default"
        
        switch themeName {
        case "neonBlue": return Color(red: 0.0, green: 0.47, blue: 0.95)
        case "cyberYellow": return Color(red: 0.95, green: 0.76, blue: 0.05)
        case "synthPurple": return Color(red: 0.58, green: 0.25, blue: 0.95)
        case "mintGreen": return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "warmOrange": return Color(red: 0.95, green: 0.45, blue: 0.15)
        case "roseGold": return Color(red: 0.72, green: 0.43, blue: 0.47)
        default: return Color(red: 0.2, green: 0.6, blue: 0.86) // Default blue
        }
    }
    
    /// Neutral gray for fallback states
    static var neutralGray: Color {
        Color(red: 0.25, green: 0.25, blue: 0.28)
    }
}

// MARK: - Player Style Enum
enum PlayerStyle: Int, CaseIterable, Identifiable {
    case standard = 0
    case compact = 1
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .compact: return "Compact"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "Full player with all controls visible"
        case .compact: return "Minimal square view, reveals controls on hover"
        }
    }
}

// MARK: - Adaptive Player Container
/// A container that applies intelligent background styling based on album artwork and settings
struct AdaptivePlayerContainer<Content: View>: View {
    let content: Content
    let artwork: NSImage?
    
    @AppStorage("music_useAdaptiveColor") private var useAdaptiveColor: Bool = true
    @State private var extractedColor: Color = .black
    @State private var isExtracting: Bool = false
    
    init(artwork: NSImage?, @ViewBuilder content: () -> Content) {
        self.artwork = artwork
        self.content = content()
    }
    
    var body: some View {
        content
            .background(backgroundView)
            .onChange(of: artwork) { _, newArt in
                extractColorFromArtwork(newArt)
            }
            .onAppear {
                extractColorFromArtwork(artwork)
            }
    }
    
    // MARK: - Background View (Three-State Logic)
    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            // Base layer - always dark
            Color.black
            
            // Gradient overlay based on state
            gradientForCurrentState
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var gradientForCurrentState: some View {
        if useAdaptiveColor {
            if artwork != nil {
                // State A: Adaptive ON + Artwork Exists
                // Premium gradient from extracted color to black
                LinearGradient(
                    gradient: Gradient(colors: [
                        extractedColor.opacity(0.7),
                        extractedColor.opacity(0.3),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .animation(.easeInOut(duration: 0.8), value: extractedColor)
            } else {
                // State B: Adaptive ON + No Artwork
                // Neutral gradient (dark gray to black) for premium look
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.neutralGray.opacity(0.6),
                        Color.black.opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            // State C: Adaptive OFF
            // Use the user's selected theme color
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.themeBackground.opacity(0.5),
                    Color.themeBackground.opacity(0.2),
                    Color.black.opacity(0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
        
        // Prevent multiple simultaneous extractions
        guard !isExtracting else { return }
        isExtracting = true
        
        // Extract color on background thread
        DispatchQueue.global(qos: .userInteractive).async {
            let dominantColor = image.vibrantColor
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.extractedColor = dominantColor
                }
                self.isExtracting = false
            }
        }
    }
}

// MARK: - Compact Player View
/// A minimal square player that reveals controls on hover
struct CompactPlayerView: View {
    @ObservedObject var mediaObserver: MediaObserver
    @State private var isHovering: Bool = false
    @AppStorage("music_useAdaptiveColor") private var useAdaptiveColor: Bool = true
    @State private var extractedColor: Color = .black
    
    let size: CGFloat
    
    init(mediaObserver: MediaObserver, size: CGFloat = 120) {
        self.mediaObserver = mediaObserver
        self.size = size
    }
    
    var body: some View {
        AdaptivePlayerContainer(artwork: mediaObserver.artworkImage) {
            ZStack {
                // Album Art or Placeholder
                artworkView
                
                // Hover Overlay
                if isHovering {
                    hoverOverlay
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: extractedColor.opacity(0.3), radius: isHovering ? 12 : 6, x: 0, y: 4)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onChange(of: mediaObserver.artworkImage) { _, newArt in
            if let art = newArt {
                DispatchQueue.global(qos: .userInteractive).async {
                    let color = art.vibrantColor
                    DispatchQueue.main.async {
                        withAnimation { extractedColor = color }
                    }
                }
            }
        }
    }
    
    // MARK: - Artwork View
    @ViewBuilder
    private var artworkView: some View {
        if let artwork = mediaObserver.artworkImage {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
        } else {
            // Stylish placeholder when no artwork
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            // Background matches current state
            if useAdaptiveColor {
                LinearGradient(
                    colors: [Color.neutralGray, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color.themeBackground.opacity(0.5), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Music note icon
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
                
                if isHovering {
                    Text("No Track")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }
    
    // MARK: - Hover Overlay
    private var hoverOverlay: some View {
        ZStack {
            // Glass effect overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            // Dark dim for better contrast
            Color.black.opacity(0.4)
            
            VStack(spacing: 8) {
                Spacer()
                
                // Playback Controls
                HStack(spacing: 20) {
                    Button(action: { mediaObserver.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { mediaObserver.togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: mediaObserver.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { mediaObserver.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Song Title (truncated)
                if !mediaObserver.title.isEmpty && mediaObserver.title != "Not Playing" {
                    VStack(spacing: 2) {
                        Text(mediaObserver.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(mediaObserver.artist)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Music Config View (Settings)
struct MusicConfigView: View {
    @AppStorage("music_useAdaptiveColor") private var useAdaptiveColor: Bool = true
    @AppStorage("musicSeekBarStyle") private var seekBarStyle: MusicSeekBarStyle = .bar
    @AppStorage("musicAutoPausePrevious") private var autoPausePrevious: Bool = false
    @AppStorage("music_showChangeNotification") private var showChangeNotification: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Background Style Selection
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "paintbrush.fill",
                        title: "Background Style",
                        subtitle: "Choose the player background appearance",
                        iconColor: .modernPurple
                    )
                    
                    VStack(spacing: 4) {
                        ModernRadioOption(
                            title: "Adaptive Artwork",
                            subtitle: "Extract colors from album art for a dynamic gradient",
                            isSelected: useAdaptiveColor
                        ) {
                            useAdaptiveColor = true
                        }
                        
                        ModernRadioOption(
                            title: "Glass",
                            subtitle: "Classic frosted glass effect that matches the system",
                            isSelected: !useAdaptiveColor
                        ) {
                            useAdaptiveColor = false
                        }
                    }
                }
            }
            
            // Seek Bar Style Selection
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "slider.horizontal.3",
                        title: "Seek Bar Style",
                        subtitle: "Choose the progress bar appearance",
                        iconColor: .modernCyan
                    )
                    
                    VStack(spacing: 4) {
                        ModernRadioOption(
                            title: "Bar",
                            subtitle: "Minimalist thin progress bar",
                            isSelected: seekBarStyle == .bar
                        ) {
                            seekBarStyle = .bar
                        }
                        
                        ModernRadioOption(
                            title: "Toggle",
                            subtitle: "iOS-style slider with draggable thumb",
                            isSelected: seekBarStyle == .toggle
                        ) {
                            seekBarStyle = .toggle
                        }
                        
                        ModernRadioOption(
                            title: "Wavy",
                            subtitle: "Animated wave that flows with the music",
                            isSelected: seekBarStyle == .wavy
                        ) {
                            seekBarStyle = .wavy
                        }
                    }
                }
            }
            
            // Auto-Pause Previous Source
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "speaker.wave.2.fill",
                        title: "Multiple Sources",
                        subtitle: "Control behavior when switching music apps",
                        iconColor: .modernOrange
                    )
                    
                    ModernToggleRow(
                        icon: "pause.circle.fill",
                        title: "Auto-Pause Previous",
                        subtitle: "When new music starts, pause the previous app (e.g. pause Spotify when Apple Music starts)",
                        iconColor: .modernOrange,
                        isOn: $autoPausePrevious
                    )
                }
            }
            
            // Song Change Notification
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "bell.badge.fill",
                        title: "Notifications",
                        subtitle: "Control music change alerts",
                        iconColor: .modernGreen
                    )
                    
                    ModernToggleRow(
                        icon: "music.note.list",
                        title: "Song Change Notification",
                        subtitle: "Show a popup when the current track changes with artwork and song details",
                        iconColor: .modernGreen,
                        isOn: $showChangeNotification
                    )
                }
            }
        }
    }
}

// MARK: - Settings Toggle Row
struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Config View Preview
        MusicConfigView()
            .frame(width: 400)
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
    }
    .padding()
}

