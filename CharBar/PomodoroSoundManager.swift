//
//  PomodoroSoundManager.swift
//  CharBar
//
//  Manages all sounds for the Pomodoro timer:
//  • Ambient looping sounds during focus (AVAudioPlayer)
//  • Short notification chimes at session transitions (NSSound)
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import AppKit

// MARK: - Ambient Sound Presets

enum PomodoroAmbientSound: String, CaseIterable, Identifiable {
    case none       = "none"
    case guitar     = "guitar"
    case nature     = "nature"
    case water      = "water"
    case whitenoise = "whitenoise"
    case rain       = "rain"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .guitar:     return "Relaxing Guitar"
        case .nature:     return "Nature"
        case .water:      return "Water Stream"
        case .whitenoise: return "White Noise"
        case .rain:       return "Gentle Rain"
        }
    }

    var icon: String {
        switch self {
        case .none:       return "speaker.slash.fill"
        case .guitar:     return "music.note"
        case .nature:     return "leaf.fill"
        case .water:      return "water.waves"
        case .whitenoise: return "waveform"
        case .rain:       return "cloud.rain.fill"
        }
    }

    /// Bundle resource name (without extension). Add these .mp3 files to the Xcode project.
    var filename: String? {
        switch self {
        case .none:       return nil
        case .guitar:     return "pomo_guitar"
        case .nature:     return "pomo_nature"
        case .water:      return "pomo_water"
        case .whitenoise: return "pomo_whitenoise"
        case .rain:       return "pomo_rain"
        }
    }
}

// MARK: - Notification Chime Presets

enum PomodoroChime: String, CaseIterable, Identifiable {
    case glass = "Glass"
    case ping  = "Ping"
    case pop   = "Pop"
    case tink  = "Tink"
    case blow  = "Blow"
    case hero  = "Hero"
    case purr  = "Purr"
    case none  = "none"

    var id: String { rawValue }
    var displayName: String { rawValue == "none" ? "None" : rawValue }
}

// MARK: - Sound Manager

class PomodoroSoundManager: ObservableObject {
    static let shared = PomodoroSoundManager()

    private let defaults = UserDefaults.standard

    // MARK: - Persisted preferences (UserDefaults-backed @Published)

    @Published var ambientSoundKey: String {
        didSet { defaults.set(ambientSoundKey, forKey: "pomodoro_ambientSound") }
    }
    @Published var ambientVolume: Double {
        didSet { defaults.set(ambientVolume, forKey: "pomodoro_ambientVolume") }
    }
    @Published var chimeStartKey: String {
        didSet { defaults.set(chimeStartKey, forKey: "pomodoro_chimeStart") }
    }
    @Published var chimeCompleteKey: String {
        didSet { defaults.set(chimeCompleteKey, forKey: "pomodoro_chimeComplete") }
    }
    @Published var chimeBreakKey: String {
        didSet { defaults.set(chimeBreakKey, forKey: "pomodoro_chimeBreak") }
    }
    @Published var chimeEnabled: Bool {
        didSet { defaults.set(chimeEnabled, forKey: "pomodoro_chimeEnabled") }
    }

    private var ambientPlayer: AVAudioPlayer?

    private init() {
        let d = UserDefaults.standard
        ambientSoundKey  = d.string(forKey: "pomodoro_ambientSound")   ?? PomodoroAmbientSound.none.rawValue
        ambientVolume    = d.object(forKey: "pomodoro_ambientVolume") as? Double ?? 0.35
        chimeStartKey    = d.string(forKey: "pomodoro_chimeStart")     ?? PomodoroChime.purr.rawValue
        chimeCompleteKey = d.string(forKey: "pomodoro_chimeComplete")  ?? PomodoroChime.glass.rawValue
        chimeBreakKey    = d.string(forKey: "pomodoro_chimeBreak")     ?? PomodoroChime.ping.rawValue
        chimeEnabled     = d.object(forKey: "pomodoro_chimeEnabled") as? Bool ?? true
    }

    // MARK: - Computed helpers

    var ambientSound: PomodoroAmbientSound {
        get { PomodoroAmbientSound(rawValue: ambientSoundKey) ?? .none }
        set { ambientSoundKey = newValue.rawValue }
    }

    // MARK: - Ambient sound (loops for entire focus session)

    func startAmbient() {
        guard ambientSound != .none,
              let filename = ambientSound.filename else { return }

        if ambientPlayer?.isPlaying == true { return }

        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else {
            return
        }

        do {
            ambientPlayer = try AVAudioPlayer(contentsOf: url)
            ambientPlayer?.numberOfLoops = -1         // Loop indefinitely
            ambientPlayer?.volume = Float(ambientVolume)
            ambientPlayer?.prepareToPlay()
            ambientPlayer?.play()
        } catch {
        }
    }

    func stopAmbient() {
        ambientPlayer?.stop()
        ambientPlayer = nil
    }

    func updateAmbientVolume() {
        ambientPlayer?.volume = Float(ambientVolume)
    }

    // MARK: - Chimes (short one-shot sounds at session transitions)

    /// Called when a focus session begins
    func playFocusStart() {
        guard chimeEnabled else { return }
        playChime(chimeStartKey)
    }

    /// Called when focus ends and a break starts
    func playBreakStart() {
        guard chimeEnabled else { return }
        playChime(chimeBreakKey)
    }

    /// Called when a break ends / full session complete
    func playComplete() {
        guard chimeEnabled else { return }
        playChime(chimeCompleteKey)
    }

    private func playChime(_ name: String) {
        guard name != PomodoroChime.none.rawValue else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
