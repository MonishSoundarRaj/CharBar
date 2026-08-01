import SwiftUI

enum UtilityType: String, CaseIterable, Identifiable, Codable {
    case cpu = "CPU"
    case gpu = "GPU"
    case ram = "RAM"
    case battery = "Battery"
    case network = "Network"
    case bluetooth = "Bluetooth"
    case disk = "Disk"
    case music = "Music"
    case pomodoro = "Pomodoro"
    case meetings = "Meetings"
    case toggles = "Toggles"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .cpu: return "cpu.fill"
        case .gpu: return "rectangle.stack.fill"
        case .ram: return "memorychip.fill"
        case .battery: return "battery.100"
        case .network: return "arrow.up.arrow.down.circle.fill"
        case .bluetooth: return "wave.3.right"
        case .disk: return "internaldrive.fill"
        case .music: return "music.note"
        case .pomodoro: return "timer"
        case .meetings: return "calendar.badge.checkmark"
        case .toggles: return "switch.2"
        }
    }
    
    var description: String {
        switch self {
        case .cpu: return "Monitor processor usage"
        case .gpu: return "Track graphics performance"
        case .ram: return "Watch memory consumption"
        case .battery: return "Battery level and charging"
        case .network: return "Network speed & connectivity"
        case .bluetooth: return "Bluetooth connections"
        case .disk: return "Disk space and I/O"
        case .music: return "Now Playing - Music control"
        case .pomodoro: return "Pomodoro Focus Timer"
        case .meetings: return "Smart Meetings with video links"
        case .toggles: return "Quick System Toggles"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .cpu: return Color(red: 0.4, green: 0.6, blue: 1.0) // Modern Blue
        case .gpu: return Color(red: 0.7, green: 0.4, blue: 1.0) // Modern Purple
        case .ram: return Color(red: 0.2, green: 0.95, blue: 0.75) // Modern Mint
        case .battery: return Color(red: 0.3, green: 0.85, blue: 0.4) // Green
        case .network: return Color(red: 0.0, green: 0.85, blue: 0.95) // Modern Cyan
        case .bluetooth: return Color(red: 0.3, green: 0.5, blue: 1.0) // Bluetooth Blue
        case .disk: return Color(red: 1.0, green: 0.55, blue: 0.3) // Modern Orange
        case .music: return Color(red: 1.0, green: 0.4, blue: 0.65) // Modern Pink
        case .pomodoro: return Color(red: 1.0, green: 0.45, blue: 0.35) // Tomato Red
        case .meetings: return Color(red: 0.4, green: 0.75, blue: 1.0) // Calendar Blue
        case .toggles: return Color(red: 0.0, green: 0.85, blue: 0.95) // Cyan
        }
    }
}

enum CharacterType: String, CaseIterable, Identifiable, Codable {
    // Static SF Symbol icons (for each utility type)
    case staticCPU
    case staticGPU
    case staticRAM
    case staticBattery
    case staticNetwork
    case staticBluetooth
    case staticDisk
    case staticMusic
    case staticPomodoro          // Static Icon 1 — uses "timer" SF symbol
    case staticPomodoroHourglass // Static Icon 2 — uses "hourglass" SF symbol
    case staticMeetings
    
    // Classic characters
    case vampire
    case cat
    case bird
    case robot
    case runner
    case ghost
    case dragon
    case rocket
    case fire
    case lightning
    case hourglass // For Pomodoro timer
    
    // Connectivity
    case bluetoothWave // Bluetooth idle/scanning animation
    case bluetoothIcon // Bluetooth icon animation
    case bluetoothThree // Bluetooth animation 3
    case airpods // AirPods connected animation
    case headphones // Over-ear headphones animation
    case dynoDancing // Dino with headphones
    
    // Productivity
    case calendar // Calendar/meetings animation
    case typingCat // Blue Working Cat
    case typingHands // Hands typing on keyboard
    case cartoonTyping // Cartoon typing
    case sleepingCat // Cat is sleeping and rolling
    case restingCat // Cat resting with tail
    
    // Music
    case musicMonster // Music Monster
    case technoPenguin // Techno Penguin
    case music // Generic music
    case musicTwo
    case musicThree
    
    // Hardware
    case hddAnimation // HDD Animation
    case gpuIsometric // GPU isometric
    case ramAnimation // RAM Animation
    case hardware // Generic hardware
    
    // System
    case robotIdle // robot_ible
    case dogRunning // doggie_running
    case somethingRunning
    case amongusRunning
    case batteryCharging
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        // Static icons
        case .staticCPU: return "Static Icon"
        case .staticGPU: return "Static Icon"
        case .staticRAM: return "Static Icon"
        case .staticBattery: return "Static Icon"
        case .staticNetwork: return "Static Icon"
        case .staticBluetooth: return "Static Icon"
        case .staticDisk: return "Static Icon"
        case .staticMusic: return "Static Icon"
        case .staticPomodoro: return "Static Icon"
        case .staticPomodoroHourglass: return "Static Icon 2"
        case .staticMeetings: return "Static Icon"
        // Animated characters
        case .bluetoothWave: return "Bluetooth Wave"
        case .bluetoothIcon: return "Bluetooth Icon"
        case .bluetoothThree: return "Bluetooth 3"
        case .airpods: return "AirPods"
        case .headphones: return "Headphones"
        case .dynoDancing: return "Dancing Dino"
        case .calendar: return "Calendar"
        case .typingCat: return "Working Cat"
        case .typingHands: return "Typing Hands"
        case .cartoonTyping: return "Cartoon Typing"
        case .sleepingCat: return "Sleeping Cat"
        case .restingCat: return "Resting Cat"
        case .musicMonster: return "Music Monster"
        case .technoPenguin: return "Techno Penguin"
        case .music: return "Music"
        case .musicTwo: return "Music 2"
        case .musicThree: return "Music 3"
        case .hddAnimation: return "HDD"
        case .gpuIsometric: return "GPU"
        case .ramAnimation: return "RAM"
        case .hardware: return "Hardware"
        case .robotIdle: return "Robot Idle"
        case .dogRunning: return "Running Dog"
        case .somethingRunning: return "Runner"
        case .amongusRunning: return "Among Us"
        case .batteryCharging: return "Battery"
        default: return rawValue.capitalized
        }
    }
    
    /// Whether this is a static SF Symbol icon (no Lottie animation)
    var isStaticIcon: Bool {
        switch self {
        case .staticCPU, .staticGPU, .staticRAM, .staticBattery, .staticNetwork,
             .staticBluetooth, .staticDisk, .staticMusic, .staticPomodoro,
             .staticPomodoroHourglass, .staticMeetings:
            return true
        default:
            return false
        }
    }
    
    /// SF Symbol name for static icons
    var sfSymbolName: String? {
        switch self {
        case .staticCPU: return "cpu"
        case .staticGPU: return "rectangle.stack"
        case .staticRAM: return "memorychip"
        case .staticBattery: return "battery.100"
        case .staticNetwork: return "network"
        case .staticBluetooth: return "dot.radiowaves.right"
        case .staticDisk: return "internaldrive"
        case .staticMusic: return "music.note"
        case .staticPomodoro: return "timer"
        case .staticPomodoroHourglass: return "hourglass"
        case .staticMeetings: return "calendar.badge.checkmark"
        default: return nil
        }
    }
    
    var icon: String {
        switch self {
        // Static icons use SF Symbol indicators
        case .staticCPU: return "⚙️"
        case .staticGPU: return "⬛"
        case .staticRAM: return "🔲"
        case .staticBattery: return "🔋"
        case .staticNetwork: return "📶"
        case .staticBluetooth: return "📡"
        case .staticDisk: return "💿"
        case .staticMusic: return "🎵"
        case .staticPomodoro: return "⏱️"
        case .staticPomodoroHourglass: return "⌛"
        case .staticMeetings: return "📅"
        // Animated characters
        case .vampire: return "🧛"
        case .cat: return "🐱"
        case .bird: return "🐦"
        case .robot: return "🤖"
        case .runner: return "🏃"
        case .ghost: return "👻"
        case .dragon: return "🐉"
        case .rocket: return "🚀"
        case .fire: return "🔥"
        case .lightning: return "⚡"
        case .hourglass: return "⏳"
        case .bluetoothWave: return "📶"
        case .bluetoothIcon: return "📶"
        case .bluetoothThree: return "📶"
        case .airpods: return "🎧"
        case .headphones: return "🎧"
        case .dynoDancing: return "🦖"
        case .calendar: return "📅"
        case .typingCat: return "🐱"
        case .typingHands: return "⌨️"
        case .cartoonTyping: return "💻"
        case .sleepingCat: return "😴"
        case .restingCat: return "🐱"
        case .musicMonster: return "👾"
        case .technoPenguin: return "🐧"
        case .music: return "🎵"
        case .musicTwo: return "🎶"
        case .musicThree: return "🎼"
        case .hddAnimation: return "💾"
        case .gpuIsometric: return "🖥️"
        case .ramAnimation: return "💿"
        case .hardware: return "🔧"
        case .robotIdle: return "🤖"
        case .dogRunning: return "🐕"
        case .somethingRunning: return "🏃"
        case .amongusRunning: return "👽"
        case .batteryCharging: return "🔋"
        }
    }
    
    var color: Color {
        switch self {
        // Static icons - use system gray
        case .staticCPU, .staticGPU, .staticRAM, .staticBattery, .staticNetwork,
             .staticBluetooth, .staticDisk, .staticMusic, .staticPomodoro,
             .staticPomodoroHourglass, .staticMeetings:
            return .gray
        // Animated characters
        case .vampire: return .red
        case .cat: return .orange
        case .bird: return .blue
        case .robot: return .green
        case .runner: return .purple
        case .ghost: return .gray
        case .dragon: return .pink
        case .rocket: return .cyan
        case .fire: return .orange
        case .lightning: return .yellow
        case .hourglass: return .teal
        case .bluetoothWave: return .blue
        case .bluetoothIcon: return .blue
        case .bluetoothThree: return .blue
        case .airpods: return .white
        case .headphones: return .purple
        case .dynoDancing: return .green
        case .calendar: return .red
        case .typingCat: return .blue
        case .typingHands: return .gray
        case .cartoonTyping: return .cyan
        case .sleepingCat: return .indigo
        case .restingCat: return .orange
        case .musicMonster: return .purple
        case .technoPenguin: return .cyan
        case .music: return .pink
        case .musicTwo: return .pink
        case .musicThree: return .pink
        case .hddAnimation: return .gray
        case .gpuIsometric: return .green
        case .ramAnimation: return .teal
        case .hardware: return .gray
        case .robotIdle: return .green
        case .dogRunning: return .brown
        case .somethingRunning: return .purple
        case .amongusRunning: return .red
        case .batteryCharging: return .green
        }
    } 
    
    var animationStyle: AnimationStyle {
        switch self {
        // Static icons - no animation
        case .staticCPU, .staticGPU, .staticRAM, .staticBattery, .staticNetwork,
             .staticBluetooth, .staticDisk, .staticMusic, .staticPomodoro,
             .staticPomodoroHourglass, .staticMeetings:
            return .pulse // Not used, but required
        // Animated characters
        case .vampire: return .scale
        case .cat: return .run
        case .bird: return .fly
        case .robot: return .pulse
        case .runner: return .run
        case .ghost: return .float
        case .dragon: return .fly
        case .rocket: return .fly
        case .fire: return .flicker
        case .lightning: return .pulse
        case .hourglass: return .pulse
        case .bluetoothWave: return .pulse
        case .bluetoothIcon: return .pulse
        case .bluetoothThree: return .pulse
        case .airpods: return .pulse
        case .headphones: return .pulse
        case .dynoDancing: return .pulse
        case .calendar: return .pulse
        case .typingCat: return .pulse
        case .typingHands: return .pulse
        case .cartoonTyping: return .pulse
        case .sleepingCat: return .pulse
        case .restingCat: return .pulse
        case .musicMonster: return .pulse
        case .technoPenguin: return .pulse
        case .music: return .pulse
        case .musicTwo: return .pulse
        case .musicThree: return .pulse
        case .hddAnimation: return .pulse
        case .gpuIsometric: return .pulse
        case .ramAnimation: return .pulse
        case .hardware: return .pulse
        case .robotIdle: return .pulse
        case .dogRunning: return .run
        case .somethingRunning: return .run
        case .amongusRunning: return .run
        case .batteryCharging: return .pulse
        }
    }
    
    /// Get the appropriate static icon for a utility type
    static func staticIcon(for utility: UtilityType) -> CharacterType {
        switch utility {
        case .cpu: return .staticCPU
        case .gpu: return .staticGPU
        case .ram: return .staticRAM
        case .battery: return .staticBattery
        case .network: return .staticNetwork
        case .bluetooth: return .staticBluetooth
        case .disk: return .staticDisk
        case .music: return .staticMusic
        case .pomodoro: return .staticPomodoro
        case .meetings: return .staticMeetings
        case .toggles: return .staticCPU // Fallback
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // UNIFIED SIZE CONTROL - Change icon sizes here, they apply EVERYWHERE
    // Menu bar + Floating bar will use these sizes when the user selects that character
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// Preferred animation size for MENU BAR (width, height)
    /// Change these values to control how big each character appears in the menu bar
    var menuBarAnimationSize: CGSize {
        switch self {
        // ─── STATIC ICONS (SF Symbols) ───
        case .staticCPU:        return CGSize(width: 18, height: 18)
        case .staticGPU:        return CGSize(width: 18, height: 18)
        case .staticRAM:        return CGSize(width: 18, height: 18)
        case .staticBattery:    return CGSize(width: 18, height: 18)
        case .staticNetwork:    return CGSize(width: 18, height: 18)
        case .staticBluetooth:  return CGSize(width: 18, height: 18)
        case .staticDisk:       return CGSize(width: 18, height: 18)
        case .staticMusic:      return CGSize(width: 18, height: 18)
        case .staticPomodoro:           return CGSize(width: 18, height: 18)
        case .staticPomodoroHourglass:  return CGSize(width: 18, height: 18)
        case .staticMeetings:           return CGSize(width: 18, height: 18)
            
        // ─── ANIMALS ───
        case .cat:              return CGSize(width: 32, height: 32)
        case .typingCat:        return CGSize(width: 32, height: 32)
        case .sleepingCat:      return CGSize(width: 32, height: 32)
        case .restingCat:       return CGSize(width: 32, height: 32)
        case .dogRunning:       return CGSize(width: 36, height: 36)  // Bigger dog
        case .bird:             return CGSize(width: 32, height: 32)
        case .dragon:           return CGSize(width: 32, height: 32)
        case .technoPenguin:    return CGSize(width: 32, height: 32)
        case .vampire:          return CGSize(width: 32, height: 32)
            
        // ─── ROBOTS & TECH ───
        case .robot:            return CGSize(width: 26, height: 26)  // Smaller
        case .robotIdle:        return CGSize(width: 26, height: 26)  // Smaller
        case .hardware:         return CGSize(width: 32, height: 32)
            
        // ─── SYSTEM STATS ANIMATIONS ───
        case .hddAnimation:     return CGSize(width: 26, height: 26)  // Smaller
        case .gpuIsometric:     return CGSize(width: 26, height: 26)  // Smaller
        case .ramAnimation:     return CGSize(width: 26, height: 26)  // Smaller
        case .batteryCharging:  return CGSize(width: 22, height: 22)  // Compact
            
        // ─── MUSIC & AUDIO ───
        case .music:            return CGSize(width: 32, height: 32)
        case .musicTwo:         return CGSize(width: 32, height: 32)
        case .musicThree:       return CGSize(width: 32, height: 32)
        case .musicMonster:     return CGSize(width: 32, height: 32)
        case .lightning:        return CGSize(width: 32, height: 32)
            
        // ─── BLUETOOTH & AUDIO DEVICES ───
        case .bluetoothWave:    return CGSize(width: 32, height: 32)
        case .bluetoothIcon:    return CGSize(width: 32, height: 32)
        case .bluetoothThree:   return CGSize(width: 36, height: 36)
        case .airpods:          return CGSize(width: 32, height: 32)
        case .headphones:       return CGSize(width: 32, height: 32)
        case .dynoDancing:      return CGSize(width: 32, height: 32)
            
        // ─── PRODUCTIVITY ───
        case .hourglass:        return CGSize(width: 24, height: 24)  // Compact to match static width
        case .calendar:         return CGSize(width: 32, height: 32)
        case .typingHands:      return CGSize(width: 32, height: 32)
        case .cartoonTyping:    return CGSize(width: 32, height: 32)
            
        // ─── RUNNING CHARACTERS ───
        case .runner:           return CGSize(width: 32, height: 32)
        case .somethingRunning: return CGSize(width: 32, height: 32)
        case .amongusRunning:   return CGSize(width: 38, height: 38)  // Bigger for visibility
            
        // ─── FUN / OTHER ───
        case .fire:             return CGSize(width: 26, height: 26)  // Smaller
        case .ghost:            return CGSize(width: 32, height: 32)
        case .rocket:           return CGSize(width: 32, height: 32)
        }
    }
    
    /// Preferred animation size for FLOATING BAR (width, height)
    /// Change these values to control how big each character appears in the floating bar
    var floatingBarAnimationSize: CGSize {
        switch self {
        // ─── STATIC ICONS (SF Symbols) ───
        case .staticCPU:        return CGSize(width: 20, height: 20)
        case .staticGPU:        return CGSize(width: 20, height: 20)
        case .staticRAM:        return CGSize(width: 20, height: 20)
        case .staticBattery:    return CGSize(width: 20, height: 20)
        case .staticNetwork:    return CGSize(width: 20, height: 20)
        case .staticBluetooth:  return CGSize(width: 20, height: 20)
        case .staticDisk:       return CGSize(width: 20, height: 20)
        case .staticMusic:      return CGSize(width: 20, height: 20)
        case .staticPomodoro:           return CGSize(width: 20, height: 20)
        case .staticPomodoroHourglass:  return CGSize(width: 20, height: 20)
        case .staticMeetings:           return CGSize(width: 20, height: 20)
            
        // ─── ANIMALS ───
        case .cat:              return CGSize(width: 28, height: 28)
        case .typingCat:        return CGSize(width: 28, height: 28)
        case .sleepingCat:      return CGSize(width: 32, height: 32)
        case .restingCat:       return CGSize(width: 32, height: 32)
        case .dogRunning:       return CGSize(width: 34, height: 34)  // Bigger dog
        case .bird:             return CGSize(width: 28, height: 28)
        case .dragon:           return CGSize(width: 28, height: 28)
        case .technoPenguin:    return CGSize(width: 28, height: 28)
        case .vampire:          return CGSize(width: 28, height: 28)
            
        // ─── ROBOTS & TECH ───
        case .robot:            return CGSize(width: 24, height: 24)  // Smaller
        case .robotIdle:        return CGSize(width: 24, height: 24)  // Smaller
        case .hardware:         return CGSize(width: 28, height: 28)
            
        // ─── SYSTEM STATS ANIMATIONS ───
        case .hddAnimation:     return CGSize(width: 24, height: 24)  // Smaller
        case .gpuIsometric:     return CGSize(width: 24, height: 24)  // Smaller
        case .ramAnimation:     return CGSize(width: 24, height: 24)  // Smaller
        case .batteryCharging:  return CGSize(width: 20, height: 20)  // Compact
            
        // ─── MUSIC & AUDIO ───
        case .music:            return CGSize(width: 28, height: 28)
        case .musicTwo:         return CGSize(width: 28, height: 28)
        case .musicThree:       return CGSize(width: 28, height: 28)
        case .musicMonster:     return CGSize(width: 28, height: 28)
        case .lightning:        return CGSize(width: 28, height: 28)
            
        // ─── BLUETOOTH & AUDIO DEVICES ───
        case .bluetoothWave:    return CGSize(width: 28, height: 28)
        case .bluetoothIcon:    return CGSize(width: 28, height: 28)
        case .bluetoothThree:   return CGSize(width: 32, height: 32)
        case .airpods:          return CGSize(width: 28, height: 28)
        case .headphones:       return CGSize(width: 28, height: 28)
        case .dynoDancing:      return CGSize(width: 28, height: 28)
            
        // ─── PRODUCTIVITY ───
        case .hourglass:        return CGSize(width: 28, height: 28)  // Bigger for visibility
        case .calendar:         return CGSize(width: 28, height: 28)
        case .typingHands:      return CGSize(width: 28, height: 28)
        case .cartoonTyping:    return CGSize(width: 28, height: 28)
            
        // ─── RUNNING CHARACTERS ───
        case .runner:           return CGSize(width: 28, height: 28)
        case .somethingRunning: return CGSize(width: 28, height: 28)
        case .amongusRunning:   return CGSize(width: 34, height: 34)  // Bigger for visibility
            
        // ─── FUN / OTHER ───
        case .fire:             return CGSize(width: 24, height: 24)  // Smaller
        case .ghost:            return CGSize(width: 28, height: 28)
        case .rocket:           return CGSize(width: 28, height: 28)
        }
    }
}

enum AnimationStyle {
    case scale
    case run
    case fly
    case pulse
    case float
    case flicker
}

// Display options for each utility
enum DisplayOption: String, CaseIterable, Codable {
    case percentage = "Percentage"
    case absolute = "Absolute Value"
    case speed = "Speed"
    case timer = "Timer"
    case batteryLevel = "Battery Level"
    case none = "None"
    
    // Get available options for each utility
    static func options(for utility: UtilityType) -> [DisplayOption] {
        switch utility {
        case .cpu, .gpu, .disk:
            return [.percentage, .none]
        case .ram:
            return [.percentage, .absolute, .none]
        case .battery:
            return [.percentage, .none]
        case .network:
            return [.speed, .none] // Show ↓/↑ speeds in KB/s or MB/s
        case .bluetooth:
            return [.none] // Battery level coming soon
        case .music:
            return [.absolute, .none]
        case .pomodoro:
            return [.timer, .none]
        case .meetings:
            return [.timer, .none]
        case .toggles:
            return [.none]
        }
    }
}

// User Configuration Model
struct UtilityConfiguration: Codable {
    var isEnabled: Bool
    var character: CharacterType
    var position: Int // Order in menu bar
    var displayOption: DisplayOption // What to show next to icon
    
    init(isEnabled: Bool = false, character: CharacterType = .cat, position: Int = 0, displayOption: DisplayOption = .percentage) {
        self.isEnabled = isEnabled
        self.character = character
        self.position = position
        self.displayOption = displayOption
    }
}

