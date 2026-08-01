//
//  ScreenObserver.swift
//  CharBar
//
//  Observes screen configuration changes to detect external monitor connection/disconnection
//

import Foundation
import AppKit
import Combine

/// Observes system screen changes and publishes updates
class ScreenObserver: ObservableObject {
    static let shared = ScreenObserver()
    
    // MARK: - Published Properties
    
    /// Whether an external display is currently connected
    @Published private(set) var hasExternalDisplay: Bool = false
    
    /// Number of screens currently connected
    @Published private(set) var screenCount: Int = 1
    
    /// The main screen (usually the one with menu bar)
    @Published private(set) var mainScreen: NSScreen?
    
    /// All connected screens
    @Published private(set) var allScreens: [NSScreen] = []
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Initial check
        updateScreenInfo()
        
        // Listen for screen configuration changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main) // Debounce rapid changes
            .sink { [weak self] _ in
                self?.updateScreenInfo()
            }
            .store(in: &cancellables)
        
        // Also listen for workspace notifications (display wake/sleep)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.updateScreenInfo()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Screen Detection
    
    private func updateScreenInfo() {
        let screens = NSScreen.screens
        
        screenCount = screens.count
        allScreens = screens
        mainScreen = NSScreen.main
        
        // Determine if external display is connected
        // External = any screen that's not the built-in Retina display
        hasExternalDisplay = detectExternalDisplay(screens: screens)
        
        // Post notification for other components
        NotificationCenter.default.post(
            name: NSNotification.Name("ScreenConfigurationChanged"),
            object: nil,
            userInfo: ["hasExternal": hasExternalDisplay, "count": screenCount]
        )
    }
    
    /// Detect if any connected screen is an external display
    private func detectExternalDisplay(screens: [NSScreen]) -> Bool {
        // If only one screen, check if it's the built-in display
        if screens.count == 1 {
            return !isBuiltInDisplay(screens[0])
        }
        
        // Multiple screens - at least one must be external
        if screens.count > 1 {
            return true
        }
        
        return false
    }
    
    /// Check if a screen is the built-in display (laptop screen)
    private func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        
        // Check if this is the built-in display using CGDisplayIsBuiltin
        return CGDisplayIsBuiltin(screenNumber) != 0
    }
    
    // MARK: - Public Methods
    
    /// Force a refresh of screen information
    func refresh() {
        updateScreenInfo()
    }
    
    /// Get the best screen for the floating widget
    /// Prefers external display, falls back to main screen
    func preferredWidgetScreen() -> NSScreen? {
        // If external display exists, prefer it
        for screen in allScreens {
            if !isBuiltInDisplay(screen) {
                return screen
            }
        }
        
        // Fall back to main screen
        return mainScreen ?? NSScreen.main
    }
    
    /// Check if a specific screen is the built-in display
    func isBuiltIn(_ screen: NSScreen) -> Bool {
        return isBuiltInDisplay(screen)
    }
}



