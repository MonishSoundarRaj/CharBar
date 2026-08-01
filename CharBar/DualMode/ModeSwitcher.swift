//
//  ModeSwitcher.swift
//  CharBar
//
//  Orchestrates the transition between Menu Bar and Floating Menu Bar modes
//

import SwiftUI
import AppKit
import Combine

// MARK: - Mode Switcher

/// Manages the lifecycle of the floating menu bar and menu bar state transitions
class ModeSwitcher: ObservableObject {
    static let shared = ModeSwitcher()
    
    // MARK: - Properties
    
    /// Floating menu bar controller
    let floatingMenuBar = FloatingMenuBarController.shared
    
    /// Reference to the main AppDelegate for menu bar updates
    weak var appDelegate: AppDelegate?
    
    /// App mode manager
    private let modeManager = AppModeManager.shared
    private let screenObserver = ScreenObserver.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Listen for mode changes
        modeManager.$activeState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.handleModeChange(newState)
            }
            .store(in: &cancellables)
        
        // Listen for screen changes
        NotificationCenter.default.publisher(for: NSNotification.Name("ScreenConfigurationChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.floatingMenuBar.followsActiveScreen == true {
                    self?.floatingMenuBar.moveToActiveScreen()
                }
            }
            .store(in: &cancellables)
        
        // Listen for settings changes to refresh floating bar
        NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.floatingMenuBar.refresh()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Mode Switching
    
    private func handleModeChange(_ newState: ActiveDisplayState) {
        switch newState {
        case .menuBar:
            // Transition TO full animated menu bar
            transitionToMenuBar()
            
        case .menuBarStatic:
            // Transition TO menu bar with forced static icons
            transitionToMenuBarStatic()
            
        case .floatingBar:
            // Transition TO floating bar mode
            transitionToFloatingBar()
        }
    }
    
    /// Transition to Menu Bar mode with full animations
    private func transitionToMenuBar() {
        // Hide floating menu bar
        floatingMenuBar.hide()
        
        // Notify AppDelegate to restore full animations in menu bar
        NotificationCenter.default.post(
            name: NSNotification.Name("RestoreMenuBarAnimations"),
            object: nil
        )
    }
    
    /// Transition to Menu Bar mode with forced static icons (external display + alwaysMenuBar)
    private func transitionToMenuBarStatic() {
        // Hide floating menu bar
        floatingMenuBar.hide()
        
        // Notify AppDelegate to rebuild menu bar with static icons
        NotificationCenter.default.post(
            name: NSNotification.Name("ForceStaticMenuBarIcons"),
            object: nil
        )
    }
    
    /// Transition from Menu Bar mode to Floating Bar mode
    private func transitionToFloatingBar() {
        // Notify AppDelegate to switch to single static icon
        NotificationCenter.default.post(
            name: NSNotification.Name("UseStaticMenuBarIcon"),
            object: nil
        )
        
        // Show floating menu bar
        floatingMenuBar.appDelegate = appDelegate
        floatingMenuBar.show()
    }
    
    // MARK: - Public Methods
    
    /// Toggle the floating bar visibility (for static icon click)
    func toggleFloatingBar() {
        floatingMenuBar.toggle()
    }
    
    /// Show the floating bar
    func showFloatingBar() {
        floatingMenuBar.show()
    }
    
    /// Hide the floating bar
    func hideFloatingBar() {
        floatingMenuBar.hide()
    }
}
