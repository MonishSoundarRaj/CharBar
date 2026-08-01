//
//  AppModeManager.swift
//  CharBar
//
//  Manages the app's display mode (Menu Bar vs Floating Menu Bar)
//

import Foundation
import SwiftUI
import Combine

// MARK: - App Display Mode

enum AppDisplayMode: String, CaseIterable, Codable {
    case smartAuto = "smartAuto"
    case alwaysMenuBar = "alwaysMenuBar"
    case alwaysFloating = "alwaysFloating"
    
    var displayName: String {
        switch self {
        case .smartAuto: return "Smart Auto"
        case .alwaysMenuBar: return "Always Menu Bar"
        case .alwaysFloating: return "Always Floating"
        }
    }
    
    var description: String {
        switch self {
        case .smartAuto: return "Animated menu bar on your Mac. Automatically switches to a floating bar when you connect a monitor."
        case .alwaysMenuBar: return "Keeps the menu bar on all screens. Animations are automatically replaced with static icons on all displays."
        case .alwaysFloating: return "Always uses the floating bar, regardless of how many displays are connected."
        }
    }
    
    var icon: String {
        switch self {
        case .smartAuto: return "sparkles.rectangle.stack"
        case .alwaysMenuBar: return "menubar.rectangle"
        case .alwaysFloating: return "macwindow"
        }
    }
}

// MARK: - Active Display State

enum ActiveDisplayState: Equatable {
    case menuBar          // Full animations in macOS menu bar
    case menuBarStatic    // Menu bar but all icons forced to static (external display + alwaysMenuBar)
    case floatingBar      // Single static icon + floating menu bar
    
    var isFloating: Bool { self == .floatingBar }
    var isMenuBar: Bool { self == .menuBar || self == .menuBarStatic }
    var isMenuBarStatic: Bool { self == .menuBarStatic }
}

// MARK: - App Mode Manager

class AppModeManager: ObservableObject {
    static let shared = AppModeManager()
    
    // MARK: - Published Properties
    
    /// User's preferred display mode
    @Published var preferredMode: AppDisplayMode {
        didSet {
            UserDefaults.standard.set(preferredMode.rawValue, forKey: "appDisplayMode")
            // Refresh static icon check BEFORE updating state so the value is current
            checkAllStaticIcons()
            updateActiveState()
        }
    }
    
    /// The currently active display state
    @Published private(set) var activeState: ActiveDisplayState = .menuBar
    
    /// Whether the floating bar should be used
    @Published private(set) var shouldUseFloatingBar: Bool = false
    
    /// Whether the menu bar should show full animations (not just static icon)
    @Published private(set) var shouldShowMenuBarAnimations: Bool = true
    
    /// Whether all utilities have static icons selected
    @Published private(set) var allUtilitiesUseStaticIcons: Bool = false
    
    /// Whether we are in temporary static mode (alwaysMenuBar + external display + animated icons)
    /// This does NOT change user's saved settings - it's a runtime override
    @Published private(set) var isTemporaryStaticMode: Bool = false
    
    // MARK: - Private Properties
    
    private let screenObserver = ScreenObserver.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Load saved preferences - migrate old "auto" to "smartAuto"
        let savedMode = UserDefaults.standard.string(forKey: "appDisplayMode") ?? AppDisplayMode.smartAuto.rawValue
        let resolved = AppDisplayMode(rawValue: savedMode) ?? .smartAuto
        // Migrate old "auto" value
        if savedMode == "auto" {
            self.preferredMode = .smartAuto
            UserDefaults.standard.set(AppDisplayMode.smartAuto.rawValue, forKey: "appDisplayMode")
        } else {
            self.preferredMode = resolved
        }
        
        // Subscribe to screen changes
        screenObserver.$hasExternalDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveState()
            }
            .store(in: &cancellables)
        
        // Subscribe to settings changes to check for static icons
        NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkAllStaticIcons()
                self?.updateActiveState()
            }
            .store(in: &cancellables)
        
        // Initial state
        checkAllStaticIcons()
        updateActiveState()
    }
    
    // MARK: - Static Icon Check
    
    /// Check if all enabled utilities have static icons selected
    func checkAllStaticIcons() {
        guard let settingsManager = sharedSettingsManager else {
            allUtilitiesUseStaticIcons = false
            return
        }
        
        let enabledUtilities = settingsManager.enabledUtilities()
        guard !enabledUtilities.isEmpty else {
            allUtilitiesUseStaticIcons = false
            return
        }
        
        // Check if ALL enabled utilities use static icons
        // Special handling for Pomodoro and Bluetooth which use separate UserDefaults
        allUtilitiesUseStaticIcons = enabledUtilities.allSatisfy { (utility, config) in
            switch utility {
            case .pomodoro:
                // Check pomo_workingCharacter from UserDefaults
                let workingChar = UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass"
                if let charType = CharacterType(rawValue: workingChar) {
                    return charType.isStaticIcon
                }
                return false
            case .bluetooth:
                let connectedChar = UserDefaults.standard.string(forKey: "bluetooth_headphoneCharacter") ?? "dynoDancing"
                if let charType = CharacterType(rawValue: connectedChar) {
                    return charType.isStaticIcon
                }
                return false
            default:
                return config.character.isStaticIcon
            }
        }
    }
    
    /// Set all utilities to use static icons
    func setAllToStaticIcons() {
        guard let settingsManager = sharedSettingsManager else { return }
        
        // Map utility types to their static icon character
        let staticIconMap: [UtilityType: CharacterType] = [
            .cpu: .staticCPU,
            .gpu: .staticGPU,
            .ram: .staticRAM,
            .battery: .staticBattery,
            .network: .staticNetwork,
            .disk: .staticDisk,
            .music: .staticMusic,
            .meetings: .staticMeetings
        ]
        
        // Update each utility's configuration
        for (utility, staticChar) in staticIconMap {
            if var config = settingsManager.configurations[utility] {
                config.character = staticChar
                settingsManager.updateConfiguration(for: utility, config: config)
            }
        }
        
        // Special handling for Bluetooth
        UserDefaults.standard.set("staticBluetooth", forKey: "bluetooth_headphoneCharacter")
        if var config = settingsManager.configurations[.bluetooth] {
            config.character = .staticBluetooth
            settingsManager.updateConfiguration(for: .bluetooth, config: config)
        }
        
        // Special handling for Pomodoro
        UserDefaults.standard.set("staticPomodoro", forKey: "pomo_workingCharacter")
        UserDefaults.standard.set("staticPomodoro", forKey: "pomo_restingCharacter")
        if var config = settingsManager.configurations[.pomodoro] {
            config.character = .staticPomodoro
            settingsManager.updateConfiguration(for: .pomodoro, config: config)
        }
        
        // Refresh check
        checkAllStaticIcons()
        updateActiveState()
        
        // Notify settings changed
        NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
    }
    
    // MARK: - State Computation
    
    private func updateActiveState() {
        let previousState = activeState
        let previousTempStatic = isTemporaryStaticMode
        
        // Reset temporary static mode - will be set below if needed
        var newTempStatic = false
        var newState: ActiveDisplayState
        
        switch preferredMode {
        case .smartAuto:
            // Smart Auto: Menu bar on laptop, floating bar on external display
            // Exception: If all icons are already static, keep menu bar everywhere
            if screenObserver.hasExternalDisplay {
                if allUtilitiesUseStaticIcons {
                    // All static icons - safe to keep menu bar on all screens
                    newState = .menuBar
                } else {
                    // Has animated icons - switch to floating bar
                    newState = .floatingBar
                }
            } else {
                // Laptop only - full animated menu bar
                newState = .menuBar
            }
            
        case .alwaysMenuBar:
            // Always keep menu bar visible
            // When external display is connected and user has Lottie animations,
            // force static icons. Restore Lottie when external display is disconnected.
            if screenObserver.hasExternalDisplay && !allUtilitiesUseStaticIcons {
                // External display + animated icons = force static temporarily
                newState = .menuBarStatic
                newTempStatic = true
            } else {
                // Laptop only OR all already static - normal menu bar
                newState = .menuBar
            }
            
        case .alwaysFloating:
            // Always use floating bar
            newState = .floatingBar
        }
        
        // Apply state - set temp static FIRST so it's ready when Combine subscribers fire
        isTemporaryStaticMode = newTempStatic
        activeState = newState  // This triggers ModeSwitcher's Combine subscriber
        
        // Update derived states
        shouldUseFloatingBar = activeState.isFloating
        shouldShowMenuBarAnimations = activeState == .menuBar
        
        // Log state change
        if previousState != activeState || previousTempStatic != isTemporaryStaticMode {
            // Notify observers of mode change
            NotificationCenter.default.post(
                name: NSNotification.Name("AppDisplayModeChanged"),
                object: nil,
                userInfo: [
                    "previousState": "\(previousState)",
                    "newState": "\(activeState)",
                    "shouldUseFloatingBar": shouldUseFloatingBar,
                    "shouldShowMenuBarAnimations": shouldShowMenuBarAnimations,
                    "isTemporaryStaticMode": isTemporaryStaticMode
                ]
            )
        }
    }
    
    // MARK: - Public Methods
    
    /// Force refresh the active state
    func refresh() {
        screenObserver.refresh()
        checkAllStaticIcons()
        updateActiveState()
    }
    
    /// Toggle between menu bar and floating bar modes
    func toggleMode() {
        switch activeState {
        case .menuBar, .menuBarStatic:
            preferredMode = .alwaysFloating
        case .floatingBar:
            preferredMode = .smartAuto
        }
    }
    
    /// Reset to smart auto mode
    func resetToAuto() {
        preferredMode = .smartAuto
    }
}
