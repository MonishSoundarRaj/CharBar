//
//  AnimationManifest.swift
//  CharBar
//
//  Semantic Animation Categorization - Maps animations to utilities by meaning
//  Allows overlaps (e.g., headphone characters work for both Music AND Bluetooth)
//

import SwiftUI

// MARK: - Animation Item Model
struct AnimationItem: Identifiable, Hashable {
    let id = UUID()
    let filename: String
    let displayName: String
    
    /// Auto-prettify filenames (e.g., "doggie_running" -> "Speedy Dog")
    static func from(_ filename: String) -> AnimationItem {
        let cleanName = filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".json", with: "")
            .capitalized
        return AnimationItem(filename: filename, displayName: cleanName)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(filename)
    }
    
    static func == (lhs: AnimationItem, rhs: AnimationItem) -> Bool {
        lhs.filename == rhs.filename
    }
}

// MARK: - The Semantic Categorization Engine
struct AnimationManifest {
    
    // MARK: - Running/Activity Characters (shared across stats utilities)
    /// High-energy, running characters for system stats
    /// Speed adjusts based on usage level (high usage = fast animation)
    static let runningCharacters: [CharacterType] = [
        .robot, .vampire, .somethingRunning, .runner,
        .fire
    ]
    
    // MARK: - Generic Characters (for general use)
    /// Characters not tied to specific utilities
    /// Removed runner, rocket, bird, fire - they duplicate other utility defaults
    static let genericCharacters: [CharacterType] = [
        .robot, .robotIdle, .vampire, .cat, .sleepingCat, .restingCat,
        .typingCat, .typingHands, .cartoonTyping
    ]
    
    // MARK: - CPU Specific (static icon first)
    static let cpuCharacters: [CharacterType] = [
        .staticCPU,  // Static icon option
        .gpuIsometric // CPU icon (reuse GPU isometric for now)
    ] + runningCharacters
    
    // MARK: - GPU Specific (static icon first)
    static let gpuCharacters: [CharacterType] = [
        .staticGPU,  // Static icon option
        .gpuIsometric // GPU icon
    ] + runningCharacters
    
    // MARK: - RAM Specific (static icon first)
    static let ramCharacters: [CharacterType] = [
        .staticRAM,  // Static icon option
        .ramAnimation // RAM icon
    ] + runningCharacters
    
    // MARK: - Battery Specific (static icon first, no battery animation)
    static let batteryCharacters: [CharacterType] = [
        .staticBattery  // Static icon option
    ] + runningCharacters
    
    // MARK: - Disk Specific (static icon first)
    static let diskCharacters: [CharacterType] = [
        .staticDisk,  // Static icon option
        .hddAnimation // HDD icon
    ] + runningCharacters
    
    // MARK: - Network Specific (static icon first)
    static let networkCharacters: [CharacterType] = [
        .staticNetwork  // Static icon option
    ] + runningCharacters
    
    // MARK: - Audio & Music (static icon first)
    static let music: [CharacterType] = [
        .staticMusic,  // Static icon option
        .dynoDancing, .musicMonster, .musicThree, .music, .headphones
    ]
    
    // MARK: - Bluetooth - Multi-Panel
    /// Panel 1: When nothing/keyboard connected (icons)
    static let bluetoothIcons: [CharacterType] = [
        .staticBluetooth,  // Static icon option
        .bluetoothWave, .bluetoothIcon
    ]
    
    /// When any audio device is connected (headphones, earbuds, speakers)
    static let bluetoothConnected: [CharacterType] = [
        .dynoDancing, .musicMonster, .headphones, .technoPenguin
    ]
    
    /// Legacy arrays kept for compatibility
    static let bluetoothHeadphones: [CharacterType] = bluetoothConnected
    static let bluetoothEarphones: [CharacterType] = bluetoothConnected
    
    // MARK: - Pomodoro - Dual State (static icon first)
    /// Working state characters
    static let pomodoroWorking: [CharacterType] = [
        .staticPomodoro,          // Static Icon 1 — timer SF symbol
        .staticPomodoroHourglass, // Static Icon 2 — hourglass SF symbol
        .hourglass, .typingCat, .cartoonTyping, .typingHands
    ]
    
    /// Resting state characters
    static let pomodoroResting: [CharacterType] = [
        .staticPomodoro,  // Static icon option
        .hourglass, .sleepingCat, .restingCat,
        .typingCat, .cartoonTyping, .typingHands
    ]
    
    // MARK: - Calendar / Meetings (static icon first)
    static let meetings: [CharacterType] = [
        .staticMeetings,  // Static icon option
        .hourglass
    ]
    
    // MARK: - All Characters (for fallback/general use)
    static let allCharacters: [CharacterType] = CharacterType.allCases.filter { !$0.isStaticIcon }
    
    // MARK: - Get Characters for Utility Type
    /// Returns semantically appropriate characters for a utility
    static func characters(for utility: UtilityType) -> [CharacterType] {
        switch utility {
        case .cpu:
            return cpuCharacters
        case .gpu:
            return gpuCharacters
        case .ram:
            return ramCharacters
        case .battery:
            return batteryCharacters
        case .disk:
            return diskCharacters
        case .network:
            return networkCharacters
        case .bluetooth:
            // For default picker, show all bluetooth options
            return bluetoothIcons + bluetoothHeadphones + bluetoothEarphones
        case .music:
            return music
        case .pomodoro:
            return pomodoroWorking // Default to working state
        case .meetings:
            return meetings
        case .toggles:
            return genericCharacters
        }
    }
    
    // MARK: - Pomodoro Dual-State Characters
    static func pomodoroCharacters(forFocus: Bool) -> [CharacterType] {
        return forFocus ? pomodoroWorking : pomodoroResting
    }
}

// MARK: - CharacterType Extension for Semantic Mapping
extension CharacterType {
    /// Get the animation filename for this character type
    var animationFilename: String {
        return self.lottieFileName ?? ""
    }
    
    /// Initialize from animation filename (case-insensitive matching)
    static func from(filename: String) -> CharacterType? {
        let lower = filename.lowercased()
        
        switch lower {
        // Classic
        case "bat_flying": return .vampire
        case "cat_resting_withtail": return .restingCat
        case "robot_running": return .robot
        case "doggie_running": return .dogRunning
        case "amongus_running": return .amongusRunning
        case "something_running": return .somethingRunning
        case "fire_flame": return .fire
        case "timer": return .hourglass
        
        // Connectivity
        case "bluetooth": return .bluetoothWave
        case "bluetooth icon lottie json animation": return .bluetoothIcon
        case "bluetooth_3": return .bluetoothThree
        case "airpods": return .airpods
        case "headphones": return .headphones
        case "dyno_dancing_with_headphones": return .dynoDancing
        
        // Productivity
        case "calendar": return .calendar
        case "blue working cat animation": return .typingCat
        case "hands typing on keyboard": return .typingHands
        case "cartoon_typing": return .cartoonTyping
        case "cat is sleeping and rolling": return .sleepingCat
        
        // Music
        case "music monster": return .musicMonster
        case "techno penguin": return .technoPenguin
        case "music": return .music
        case "music_two": return .musicTwo
        case "music_three": return .musicThree
        
        // Hardware
        case "hdd animation": return .hddAnimation
        case "gpu isometric": return .gpuIsometric
        case "ram animation": return .ramAnimation
        case "hardware": return .hardware
        
        // System
        case "robot_ible": return .robotIdle
        case "battery charging - plugin_green": return .batteryCharging
        
        default: return nil
        }
    }
}

