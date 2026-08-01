//
//  ShortcutManager.swift
//  CharBar
//
//  Global Shortcut Manager - Handles keyboard shortcuts for all utilities
//

import Cocoa
import Carbon
import SwiftUI
import Combine

// MARK: - Shortcut Action Types
enum ShortcutAction: String, CaseIterable {
    case quickJoinMeeting = "Quick Join Meeting"
    case connectLastBluetooth = "Connect Last Bluetooth"
    case toggleMusic = "Play/Pause Music"
    case togglePomodoro = "Start/Stop Pomodoro"
    case toggleFloatingBar = "Toggle Floating Bar"
    
    var icon: String {
        switch self {
        case .quickJoinMeeting: return "video.fill"
        case .connectLastBluetooth: return "airpodspro"
        case .toggleMusic: return "play.fill"
        case .togglePomodoro: return "timer"
        case .toggleFloatingBar: return "macwindow"
        }
    }
    
    var defaultShortcut: KeyboardShortcut? {
        switch self {
        case .quickJoinMeeting: return KeyboardShortcut(key: "j", modifiers: [.command, .shift])
        case .connectLastBluetooth: return KeyboardShortcut(key: "b", modifiers: [.command, .shift])
        case .toggleMusic: return KeyboardShortcut(key: "p", modifiers: [.command, .shift])
        case .togglePomodoro: return KeyboardShortcut(key: "t", modifiers: [.command, .shift])
        case .toggleFloatingBar: return KeyboardShortcut(key: "f", modifiers: [.command, .shift])
        }
    }
    
    var storageKey: String {
        return "shortcut_\(self.rawValue.replacingOccurrences(of: " ", with: "_").lowercased())"
    }
    
    var enabledKey: String {
        return "shortcut_enabled_\(self.rawValue.replacingOccurrences(of: " ", with: "_").lowercased())"
    }
}

// MARK: - Keyboard Shortcut Model
struct KeyboardShortcut: Codable, Equatable {
    var key: String
    var modifiers: ModifierSet
    
    struct ModifierSet: OptionSet, Codable {
        let rawValue: Int
        
        static let command = ModifierSet(rawValue: 1 << 0)
        static let shift = ModifierSet(rawValue: 1 << 1)
        static let option = ModifierSet(rawValue: 1 << 2)
        static let control = ModifierSet(rawValue: 1 << 3)
        
        var carbonModifiers: UInt32 {
            var result: UInt32 = 0
            if contains(.command) { result |= UInt32(cmdKey) }
            if contains(.shift) { result |= UInt32(shiftKey) }
            if contains(.option) { result |= UInt32(optionKey) }
            if contains(.control) { result |= UInt32(controlKey) }
            return result
        }
        
        var displayString: String {
            var parts: [String] = []
            if contains(.control) { parts.append("⌃") }
            if contains(.option) { parts.append("⌥") }
            if contains(.shift) { parts.append("⇧") }
            if contains(.command) { parts.append("⌘") }
            return parts.joined()
        }
    }
    
    var displayString: String {
        return "\(modifiers.displayString)\(key.uppercased())"
    }
    
    var keyCode: UInt32? {
        return ShortcutManager.keyCodeForCharacter(key.lowercased())
    }
}

// MARK: - Shortcut Manager
class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    
    // Registered hotkey references
    private var hotkeyRefs: [ShortcutAction: EventHotKeyRef] = [:]
    
    // Published for UI updates
    @Published var shortcuts: [ShortcutAction: KeyboardShortcut] = [:]
    @Published var enabledShortcuts: Set<ShortcutAction> = []
    @Published var isRecording: Bool = false
    @Published var recordingAction: ShortcutAction?
    
    // Callbacks for each action
    var onQuickJoinMeeting: (() -> Void)?
    var onConnectLastBluetooth: (() -> Void)?
    var onToggleMusic: (() -> Void)?
    var onTogglePomodoro: (() -> Void)?
    var onToggleFloatingBar: (() -> Void)?
    
    private var eventHandlerInstalled = false
    
    private init() {
        loadShortcuts()
        installEventHandler()
        registerEnabledShortcuts()
    }
    
    deinit {
        unregisterAllShortcuts()
    }
    
    // MARK: - Load/Save
    
    private func loadShortcuts() {
        for action in ShortcutAction.allCases {
            // Load enabled state
            if UserDefaults.standard.bool(forKey: action.enabledKey) {
                enabledShortcuts.insert(action)
            }
            
            // Load shortcut or use default
            if let data = UserDefaults.standard.data(forKey: action.storageKey),
               let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
                shortcuts[action] = shortcut
            } else if let defaultShortcut = action.defaultShortcut {
                shortcuts[action] = defaultShortcut
            }
        }
    }
    
    func saveShortcut(_ shortcut: KeyboardShortcut, for action: ShortcutAction) {
        shortcuts[action] = shortcut
        
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: action.storageKey)
        }
        
        // Re-register if enabled
        if enabledShortcuts.contains(action) {
            unregisterShortcut(for: action)
            registerShortcut(for: action)
        }
    }
    
    func setEnabled(_ enabled: Bool, for action: ShortcutAction) {
        if enabled {
            enabledShortcuts.insert(action)
            registerShortcut(for: action)
        } else {
            enabledShortcuts.remove(action)
            unregisterShortcut(for: action)
        }
        UserDefaults.standard.set(enabled, forKey: action.enabledKey)
        
        // When enabling Bluetooth shortcut, also enable quick connect mode
        if action == .connectLastBluetooth && enabled {
            UserDefaults.standard.set(true, forKey: "bluetooth_quickConnectMode")
        }
    }
    
    func isEnabled(_ action: ShortcutAction) -> Bool {
        return enabledShortcuts.contains(action)
    }
    
    // MARK: - Carbon Event Handler
    
    private func installEventHandler() {
        guard !eventHandlerInstalled else { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                
                // Check signature
                let expectedSignature = ShortcutManager.makeFourCharCode("CBAR")
                guard hotkeyID.signature == expectedSignature else { return noErr }
                
                // Map ID to action
                let actionIndex = Int(hotkeyID.id)
                guard actionIndex < ShortcutAction.allCases.count else { return noErr }
                let action = ShortcutAction.allCases[actionIndex]
                
                // Execute on main thread
                DispatchQueue.main.async {
                    ShortcutManager.shared.executeAction(action)
                }
                
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        
        eventHandlerInstalled = true
    }
    
    // MARK: - Register/Unregister
    
    func registerEnabledShortcuts() {
        for action in enabledShortcuts {
            registerShortcut(for: action)
        }
    }
    
    func registerShortcut(for action: ShortcutAction) {
        // Check accessibility permission first
        guard checkAccessibilityPermission() else {
            return
        }
        
        unregisterShortcut(for: action)
        
        guard let shortcut = shortcuts[action],
              let keyCode = shortcut.keyCode else {
            return
        }
        
        let actionIndex = ShortcutAction.allCases.firstIndex(of: action) ?? 0
        let hotkeyID = EventHotKeyID(signature: ShortcutManager.makeFourCharCode("CBAR"), id: UInt32(actionIndex))
        
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.modifiers.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status == noErr, let ref = hotkeyRef {
            hotkeyRefs[action] = ref
        }
    }
    
    func unregisterShortcut(for action: ShortcutAction) {
        if let ref = hotkeyRefs[action] {
            UnregisterEventHotKey(ref)
            hotkeyRefs.removeValue(forKey: action)
        }
    }
    
    func unregisterAllShortcuts() {
        for (_, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
    }
    
    // MARK: - Execute Actions
    
    private func executeAction(_ action: ShortcutAction) {
        switch action {
        case .quickJoinMeeting:
            onQuickJoinMeeting?()
        case .connectLastBluetooth:
            onConnectLastBluetooth?()
        case .toggleMusic:
            onToggleMusic?()
        case .togglePomodoro:
            onTogglePomodoro?()
        case .toggleFloatingBar:
            onToggleFloatingBar?()
        }
    }
    
    // MARK: - Shortcut Recording
    
    func startRecording(for action: ShortcutAction) {
        isRecording = true
        recordingAction = action
    }
    
    func stopRecording() {
        isRecording = false
        recordingAction = nil
    }
    
    func recordShortcut(from event: NSEvent) -> KeyboardShortcut? {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1 else { return nil }
        
        var modifiers: KeyboardShortcut.ModifierSet = []
        let flags = event.modifierFlags
        
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        
        // Require at least Command or Control
        guard modifiers.contains(.command) || modifiers.contains(.control) else { return nil }
        
        return KeyboardShortcut(key: characters, modifiers: modifiers)
    }
    
    // MARK: - Permissions (Simplified like Maccy)
    
    /// Check if we have accessibility permission - pass nil to never trigger prompt
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrustedWithOptions(nil)
    }
    
    /// Opens System Settings to Accessibility pane - no dialogs
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    // MARK: - Helpers
    
    static func makeFourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = result << 8 + FourCharCode(char)
        }
        return result
    }
    
    static func keyCodeForCharacter(_ character: String) -> UInt32? {
        let keyMap: [String: UInt32] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
            "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
            "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F,
            "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
            "n": 0x2D, "m": 0x2E
        ]
        return keyMap[character]
    }
}

// MARK: - Permission Manager (Simplified like Maccy)
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var hasCalendarAccess: Bool = false
    @Published var hasBluetoothAccess: Bool = true // macOS doesn't require special Bluetooth permission
    @Published var hasAccessibilityAccess: Bool = false
    
    private var permissionCheckTimer: Timer?
    
    private init() {
        checkAccessibility()
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
    }
    
    /// Start periodic permission monitoring (checks every 1 second when settings is open)
    func startPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }
    
    /// Stop permission monitoring (when leaving settings)
    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    /// Simple accessibility check like Maccy - pass nil to never trigger system prompt
    private func checkAccessibility() -> Bool {
        // Pass nil - this NEVER shows any system dialog
        return AXIsProcessTrustedWithOptions(nil)
    }
    
    /// Refresh permission status without prompting - NEVER triggers system dialog
    func refreshPermissionStatus() {
        let newAccessibilityAccess = checkAccessibility()
        
        // Only update if changed to avoid unnecessary UI updates
        if newAccessibilityAccess != hasAccessibilityAccess {
            DispatchQueue.main.async {
                self.hasAccessibilityAccess = newAccessibilityAccess
                
                // If permission was just granted, re-register shortcuts
                if newAccessibilityAccess {
                    ShortcutManager.shared.registerEnabledShortcuts()
                }
            }
        }
        
        let newCalendarAccess = MeetingManager.shared.accessState == .authorized
        if newCalendarAccess != hasCalendarAccess {
            DispatchQueue.main.async {
                self.hasCalendarAccess = newCalendarAccess
            }
        }
    }
    
    // MARK: - Calendar Permission (Only request when enabling Meetings)
    
    func requestCalendarPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        // Already have access?
        if MeetingManager.shared.accessState == .authorized {
            hasCalendarAccess = true
            completion(true)
            return
        }
        
        // Request access - this shows the system dialog
        MeetingManager.shared.requestAccess()
        
        // Wait for user response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let granted = MeetingManager.shared.accessState == .authorized
            self?.hasCalendarAccess = granted
            completion(granted)
        }
    }
    
    // MARK: - Bluetooth Permission (Not needed on macOS)
    
    func requestBluetoothPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        // macOS doesn't require special permission for Bluetooth access
        // IOBluetooth framework works without additional permissions
        hasBluetoothAccess = true
        completion(true)
    }
    
    // MARK: - Accessibility Permission (Simple like Maccy - just open settings)
    
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

