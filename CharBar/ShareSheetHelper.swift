//
//  ShareSheetHelper.swift
//  CharBar
//
//  Native macOS Share Sheet for music tracks
//

import SwiftUI
import AppKit

// MARK: - Share Sheet Helper

class ShareSheetHelper {
    static let shared = ShareSheetHelper()
    
    private init() {}
    
    // MARK: - Get Track Share URL
    
    /// Fetches the shareable URL for the current track
    func getTrackShareURL(bundleIdentifier: String?, completion: @escaping (URL?) -> Void) {
        guard let bundleID = bundleIdentifier else {
            completion(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var shareURL: URL? = nil
            
            if bundleID == "com.apple.Music" {
                shareURL = self.getAppleMusicShareURL()
            } else if bundleID == "com.spotify.client" {
                shareURL = self.getSpotifyShareURL()
            }
            
            DispatchQueue.main.async {
                completion(shareURL)
            }
        }
    }
    
    // MARK: - Apple Music Share URL
    
    private func getAppleMusicShareURL() -> URL? {
        // Get the Apple Music store URL for the current track
        let script = """
        tell application "Music"
            try
                -- Try to get the store URL first (works for Apple Music tracks)
                set trackProps to properties of current track
                
                -- Check if it's a library track with a store ID
                set trackID to persistent ID of current track
                set trackName to name of current track
                set trackArtist to artist of current track
                
                -- Build a search URL as fallback
                set searchQuery to trackName & " " & trackArtist
                set encodedQuery to do shell script "python3 -c \\"import urllib.parse; print(urllib.parse.quote('" & searchQuery & "'))\\""
                
                return "https://music.apple.com/search?term=" & encodedQuery
            on error
                return ""
            end try
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let descriptor = scriptObject.executeAndReturnError(&error)
            
            if error == nil, let urlString = descriptor.stringValue, !urlString.isEmpty {
                return URL(string: urlString)
            }
        }
        
        return nil
    }
    
    // MARK: - Spotify Share URL
    
    private func getSpotifyShareURL() -> URL? {
        let script = """
        tell application "Spotify"
            try
                set spotifyURI to spotify url of current track
                -- Convert spotify:track:xxx to https://open.spotify.com/track/xxx
                set AppleScript's text item delimiters to ":"
                set uriParts to text items of spotifyURI
                set AppleScript's text item delimiters to ""
                
                if (count of uriParts) >= 3 then
                    set trackType to item 2 of uriParts
                    set trackID to item 3 of uriParts
                    return "https://open.spotify.com/" & trackType & "/" & trackID
                else
                    return spotifyURI
                end if
            on error
                return ""
            end try
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let descriptor = scriptObject.executeAndReturnError(&error)
            
            if error == nil, let urlString = descriptor.stringValue, !urlString.isEmpty {
                return URL(string: urlString)
            }
        }
        
        return nil
    }
    
    // MARK: - Show Share Sheet
    
    func showShareSheet(
        url: URL?,
        title: String,
        artist: String,
        artwork: NSImage?,
        relativeTo view: NSView
    ) {
        var items: [Any] = []
        
        // Add the track info text
        let trackInfo = "\(title) by \(artist)"
        items.append(trackInfo)
        
        // Add URL if available
        if let shareURL = url {
            items.append(shareURL)
        }
        
        // Add artwork if available
        if let image = artwork {
            items.append(image)
        }
        
        // Create and show the sharing service picker
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

// MARK: - SwiftUI Share Button View

struct ShareButton: View {
    @ObservedObject var mediaObserver: MediaObserver
    @State private var shareURL: URL? = nil
    @State private var isLoading = false
    
    var body: some View {
        Button(action: shareTrack) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 15, height: 15)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading || mediaObserver.title == "Not Playing")
        .opacity(mediaObserver.title == "Not Playing" ? 0.3 : 1.0)
        .help("Share this track")
    }
    
    private func shareTrack() {
        isLoading = true
        
        ShareSheetHelper.shared.getTrackShareURL(bundleIdentifier: mediaObserver.bundleIdentifier) { url in
            self.shareURL = url
            self.isLoading = false
            
            // Show the share sheet
            if let window = NSApp.keyWindow ?? NSApp.windows.first,
               let contentView = window.contentView {
                ShareSheetHelper.shared.showShareSheet(
                    url: url,
                    title: mediaObserver.title,
                    artist: mediaObserver.artist,
                    artwork: mediaObserver.artworkImage,
                    relativeTo: contentView
                )
            }
        }
    }
}

// MARK: - Audio Output Menu View (Apple-style, icon only)

struct AudioOutputMenuView: View {
    @ObservedObject var audioManager = AudioOutputManager.shared
    var compact: Bool = false
    @State private var isExpanded = false
    @State private var isHovering = false
    
    var body: some View {
        Menu {
            ForEach(audioManager.outputDevices) { device in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        audioManager.setDefaultOutputDevice(device)
                    }
                }) {
                    HStack {
                        Image(systemName: device.icon)
                            .symbolRenderingMode(.hierarchical)
                        Text(device.name)
                        if device.isDefault {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            
            if audioManager.outputDevices.isEmpty {
                Text("No output devices")
                    .foregroundColor(.secondary)
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
            // Icon only - no dropdown arrow
            Image(systemName: currentDeviceIcon)
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.1 : 0.05))
                )
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden) // Hide the dropdown arrow
        .frame(width: compact ? 22 : 28)
        .help("Audio Output: \(audioManager.currentDevice?.name ?? "Unknown")")
        .onAppear {
            audioManager.refreshDevices()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var currentDeviceIcon: String {
        audioManager.currentDevice?.icon ?? "hifispeaker.2"
    }
}

