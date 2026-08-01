//
//  QuickTogglesView.swift
//  CharBar
//
//  Quick system toggles - Like "One Switch" app
//  Dark Mode, Keep Awake, Hide Desktop Icons, etc.
//

import SwiftUI
import AppKit
import Combine
import IOKit.pwr_mgt

/// Manages system-level toggles and their states
class SystemTogglesManager: ObservableObject {
    static let shared = SystemTogglesManager()
    
    // MARK: - Toggle States
    
    @Published var isDarkMode: Bool = false {
        didSet {
            if isDarkMode != oldValue {
                toggleDarkMode()
            }
        }
    }
    
    @Published var isKeepAwake: Bool = false {
        didSet {
            if isKeepAwake != oldValue {
                toggleKeepAwake()
            }
        }
    }
    
    @Published var isDesktopHidden: Bool = false {
        didSet {
            if isDesktopHidden != oldValue {
                toggleHideDesktop()
            }
        }
    }
    
    @Published var isDoNotDisturb: Bool = false {
        didSet {
            if isDoNotDisturb != oldValue {
                toggleDoNotDisturb()
            }
        }
    }
    
    @Published var isBluetooth: Bool = true
    @Published var isWiFi: Bool = true
    
    // MARK: - Private Properties
    
    private var caffeinateProcess: Process?
    private var assertionID: IOPMAssertionID = 0
    
    private init() {
        refreshStates()
        
        // Observe appearance changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    deinit {
        // Release caffeinate if active
        if isKeepAwake {
            releaseKeepAwake()
        }
    }
    
    // MARK: - Refresh States
    
    func refreshStates() {
        // Check Dark Mode
        let appearance = NSApp.effectiveAppearance.name
        isDarkMode = appearance == .darkAqua || appearance == .vibrantDark || appearance == .accessibilityHighContrastDarkAqua || appearance == .accessibilityHighContrastVibrantDark
        
        // Check if desktop icons are hidden
        let createDesktop = UserDefaults.standard.persistentDomain(forName: "com.apple.finder")?["CreateDesktop"] as? Bool
        isDesktopHidden = createDesktop == false
    }
    
    @objc private func appearanceChanged() {
        DispatchQueue.main.async {
            let appearance = NSApp.effectiveAppearance.name
            self.isDarkMode = appearance == .darkAqua || appearance == .vibrantDark
        }
    }
    
    // MARK: - Dark Mode Toggle
    
    private func toggleDarkMode() {
        // Use osascript in a subprocess for better reliability
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [
            "-e",
            """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to \(isDarkMode ? "true" : "false")
                end tell
            end tell
            """
        ]
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
            }
        }
    }
    
    // MARK: - Keep Awake Toggle (Caffeinate)
    
    private func toggleKeepAwake() {
        if isKeepAwake {
            enableKeepAwake()
        } else {
            releaseKeepAwake()
        }
    }
    
    private func enableKeepAwake() {
        // Method 1: Use IOPMAssertion (cleaner, no external process)
        let reasonForActivity = "CharBar Keep Awake - Preventing system sleep" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reasonForActivity,
            &assertionID
        )
        
        if success == kIOReturnSuccess {
        } else {
            // Fallback to caffeinate command
            caffeinateProcess = Process()
            caffeinateProcess?.launchPath = "/usr/bin/caffeinate"
            caffeinateProcess?.arguments = ["-di"] // Prevent display and idle sleep
            
            do {
                try caffeinateProcess?.run()
            } catch {
            }
        }
    }
    
    private func releaseKeepAwake() {
        // Release IOPMAssertion
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        
        // Stop caffeinate process
        if let process = caffeinateProcess, process.isRunning {
            process.terminate()
            caffeinateProcess = nil
        }
    }
    
    // MARK: - Hide Desktop Icons
    
    private func toggleHideDesktop() {
        // Use defaults write and then gracefully restart Finder via AppleScript
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", isDesktopHidden ? "false" : "true"]
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    // Restart Finder gracefully using AppleScript (no killall needed)
                    let restartTask = Process()
                    restartTask.launchPath = "/usr/bin/osascript"
                    restartTask.arguments = ["-e", "tell application \"Finder\" to quit", "-e", "delay 0.5", "-e", "tell application \"Finder\" to activate"]
                    try restartTask.run()
                    restartTask.waitUntilExit()
                }
            } catch {
            }
        }
    }
    
    // MARK: - Do Not Disturb Toggle
    
    private func toggleDoNotDisturb() {
        // Toggle Focus/Do Not Disturb using shortcuts app or AppleScript
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        
        // This opens the Focus menu in Control Center
        task.arguments = [
            "-e",
            """
            tell application "System Events"
                tell process "ControlCenter"
                    click menu bar item "Focus" of menu bar 1
                end tell
            end tell
            """
        ]
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
            }
        }
    }
    
    /// Open System Preferences to a specific pane
    func openSystemPreferences(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Quick Toggles View

struct QuickTogglesView: View {
    @ObservedObject var togglesManager = SystemTogglesManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Toggles List
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ToggleRow(
                        icon: "moon.fill",
                        title: "Dark Mode",
                        subtitle: "System appearance",
                        color: .purple,
                        isOn: $togglesManager.isDarkMode
                    )
                    
                    ToggleRow(
                        icon: "cup.and.saucer.fill",
                        title: "Keep Awake",
                        subtitle: "Prevent sleep",
                        color: .orange,
                        isOn: $togglesManager.isKeepAwake
                    )
                    
                    ToggleRow(
                        icon: "eye.slash.fill",
                        title: "Hide Desktop",
                        subtitle: "Hide desktop icons",
                        color: .blue,
                        isOn: $togglesManager.isDesktopHidden
                    )
                    
                    ToggleRow(
                        icon: "moon.zzz.fill",
                        title: "Do Not Disturb",
                        subtitle: "Silence notifications",
                        color: .indigo,
                        isOn: $togglesManager.isDoNotDisturb
                    )
                }
                .padding(.vertical, 8)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Quick Links
            quickLinksSection
        }
        .frame(width: 280)
        .padding(8)
        .onAppear {
            togglesManager.refreshStates()
        }
    }
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "switch.2")
                .font(.system(size: 16))
                .foregroundColor(.cyan)
            
            Text("Quick Toggles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                togglesManager.refreshStates()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private var quickLinksSection: some View {
        HStack(spacing: 12) {
            QuickLinkButton(icon: "gearshape.fill", title: "Settings") {
                togglesManager.openSystemPreferences(pane: "com.apple.preference")
            }
            
            QuickLinkButton(icon: "display", title: "Display") {
                togglesManager.openSystemPreferences(pane: "com.apple.preference.displays")
            }
            
            QuickLinkButton(icon: "speaker.wave.3.fill", title: "Sound") {
                togglesManager.openSystemPreferences(pane: "com.apple.preference.sound")
            }
            
            QuickLinkButton(icon: "battery.100", title: "Battery") {
                togglesManager.openSystemPreferences(pane: "com.apple.preference.battery")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Toggle Row Component

struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @Binding var isOn: Bool
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(isOn ? 0.25 : 0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isOn ? color : .white.opacity(0.5))
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Toggle Switch
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: color))
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.white.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Quick Link Button

struct QuickLinkButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isHovering ? .white : .white.opacity(0.6))
                
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(isHovering ? .white : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    QuickTogglesView()
        .frame(width: 280, height: 350)
        .background(Color.black.opacity(0.8))
}

