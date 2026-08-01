//
//  SoundManager.swift
//  CharBar
//
//  Audio manager for focus soundscapes during Pomodoro sessions
//

import Foundation
import AVFoundation
import Combine
import AppKit

/// Available soundscape types for focus sessions
enum Soundscape: String, CaseIterable, Identifiable {
    case silent = "Silent"
    case rain = "Rain"
    case whiteNoise = "White Noise"
    case nature = "Nature"
    case water = "Water"
    case guitar = "Guitar"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .silent: return "speaker.slash.fill"
        case .rain: return "cloud.rain.fill"
        case .whiteNoise: return "waveform"
        case .nature: return "leaf.fill"
        case .water: return "drop.fill"
        case .guitar: return "guitars.fill"
        }
    }
    
    var fileName: String? {
        switch self {
        case .silent: return nil
        case .rain: return "gentle_rain"
        case .whiteNoise: return "white_noise"
        case .nature: return "nature"
        case .water: return "water"
        case .guitar: return "guitar"
        }
    }
    
    var color: NSColor {
        switch self {
        case .silent: return .gray
        case .rain: return .systemBlue
        case .whiteNoise: return .systemPurple
        case .nature: return .systemGreen
        case .water: return .systemTeal
        case .guitar: return .systemOrange
        }
    }
}

/// Manages audio playback for focus soundscapes
class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    @Published var currentSoundscape: Soundscape = .silent {
        didSet {
            UserDefaults.standard.set(currentSoundscape.rawValue, forKey: "selectedSoundscape")
            if isPlaying {
                // Restart with new soundscape
                stopSound()
                playSound()
            }
        }
    }
    
    @Published var volume: Float = 0.5 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "soundscapeVolume")
            audioPlayer?.volume = volume
        }
    }
    
    @Published var isPlaying: Bool = false
    
    private var audioPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?
    
    private init() {
        loadSettings()
        setupAudioSession()
    }
    
    private func loadSettings() {
        if let savedSoundscape = UserDefaults.standard.string(forKey: "selectedSoundscape"),
           let soundscape = Soundscape(rawValue: savedSoundscape) {
            currentSoundscape = soundscape
        }
        
        let savedVolume = UserDefaults.standard.float(forKey: "soundscapeVolume")
        volume = savedVolume > 0 ? savedVolume : 0.5
    }
    
    private func setupAudioSession() {
        // macOS doesn't require audio session setup like iOS
    }
    
    /// Start playing the current soundscape
    func playSound() {
        guard currentSoundscape != .silent else {
            isPlaying = false
            return
        }
        
        guard let fileName = currentSoundscape.fileName else {
            isPlaying = false
            return
        }
        
        // Try to find the audio file
        if let url = findAudioFile(named: fileName) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.numberOfLoops = -1 // Loop indefinitely
                audioPlayer?.volume = 0 // Start at 0 for fade-in
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                
                // Fade in
                fadeIn()
                isPlaying = true
            } catch {
                isPlaying = false
            }
        } else {
            // Generate procedural audio as fallback
            playProceduralSound()
        }
    }
    
    /// Find audio file in bundle or resources
    private func findAudioFile(named name: String) -> URL? {
        let extensions = ["mp3", "wav", "m4a", "aac", "aiff"]
        
        // Try bundle resources
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds") {
                return url
            }
        }
        
        // Try Sounds folder in project
        if let resourcePath = Bundle.main.resourcePath {
            for ext in extensions {
                let path = (resourcePath as NSString).appendingPathComponent("Sounds/\(name).\(ext)")
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        
        return nil
    }
    
    /// Generate procedural audio when sound files aren't available
    private func playProceduralSound() {
        // For now, just mark as playing (user would see the UI state)
        // In a full implementation, you could use AVAudioEngine to generate noise
        isPlaying = true
        
        // You can download free ambient sounds from:
        // - freesound.org
        // - zapsplat.com
        // - mixkit.co
        // Place them in a "Sounds" folder in your project
    }
    
    /// Stop playing with fade-out
    func stopSound() {
        fadeOut {
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.isPlaying = false
        }
    }
    
    /// Pause the current soundscape
    func pauseSound() {
        fadeOut {
            self.audioPlayer?.pause()
            self.isPlaying = false
        }
    }
    
    /// Resume the current soundscape
    func resumeSound() {
        guard audioPlayer != nil else {
            playSound()
            return
        }
        
        audioPlayer?.play()
        fadeIn()
        isPlaying = true
    }
    
    /// Fade in audio over 1 second
    private func fadeIn() {
        fadeTimer?.invalidate()
        
        let targetVolume = volume
        let steps = 20
        let interval = 1.0 / Double(steps)
        var currentStep = 0
        
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            self.audioPlayer?.volume = targetVolume * progress
            
            if currentStep >= steps {
                timer.invalidate()
                self.audioPlayer?.volume = targetVolume
            }
        }
    }
    
    /// Fade out audio over 0.5 seconds
    private func fadeOut(completion: @escaping () -> Void) {
        fadeTimer?.invalidate()
        
        guard let player = audioPlayer, player.isPlaying else {
            completion()
            return
        }
        
        let startVolume = player.volume
        let steps = 10
        let interval = 0.5 / Double(steps)
        var currentStep = 0
        
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            self?.audioPlayer?.volume = startVolume * (1 - progress)
            
            if currentStep >= steps {
                timer.invalidate()
                completion()
            }
        }
    }
    
    /// Toggle play/pause
    func toggle() {
        if isPlaying {
            pauseSound()
        } else {
            if audioPlayer != nil {
                resumeSound()
            } else {
                playSound()
            }
        }
    }
}

