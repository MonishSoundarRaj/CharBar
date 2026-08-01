import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    @Published var configurations: [UtilityType: UtilityConfiguration] = [:]
    
    private let defaults = UserDefaults.standard
    private let configKey = "utilityConfigurations"
    
    init() {
        loadConfigurations()
    }
    
    func loadConfigurations() {
        // 1. Define Defaults (WiFi removed - Network covers it)
        let defaultConfigs: [UtilityType: UtilityConfiguration] = [
            .cpu: UtilityConfiguration(isEnabled: true, character: .cat, position: 0, displayOption: .percentage),
            .ram: UtilityConfiguration(isEnabled: false, character: .robot, position: 1, displayOption: .percentage),
            .battery: UtilityConfiguration(isEnabled: true, character: .vampire, position: 2, displayOption: .percentage),
            .network: UtilityConfiguration(isEnabled: true, character: .rocket, position: 3, displayOption: .speed),
            .gpu: UtilityConfiguration(isEnabled: false, character: .fire, position: 4, displayOption: .percentage),
            .disk: UtilityConfiguration(isEnabled: false, character: .dragon, position: 5, displayOption: .percentage),
            .bluetooth: UtilityConfiguration(isEnabled: false, character: .bluetoothWave, position: 6, displayOption: .none),
            .music: UtilityConfiguration(isEnabled: false, character: .lightning, position: 7, displayOption: .absolute),
            .pomodoro: UtilityConfiguration(isEnabled: false, character: .hourglass, position: 8, displayOption: .timer),
            .meetings: UtilityConfiguration(isEnabled: false, character: .calendar, position: 9, displayOption: .timer)
            // Toggles removed - not working reliably
        ]
        
        // 2. Try to load saved settings
        if let data = defaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode([String: UtilityConfiguration].self, from: data) {
            
            // Convert saved string keys back to UtilityType
            var loadedConfigs: [UtilityType: UtilityConfiguration] = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let utilityType = UtilityType(rawValue: key) else { return nil }
                return (utilityType, value)
            })
            
            // 3. MERGE: Add any missing utilities (like Music!) from defaults
            for (key, defaultConfig) in defaultConfigs {
                if loadedConfigs[key] == nil {
                    loadedConfigs[key] = defaultConfig
                }
            }
            
            configurations = loadedConfigs
            
        } else {
            // No saved settings, use all defaults
            configurations = defaultConfigs
        }
        
        // 4. Validate - if NO utilities are enabled, enable defaults (CPU + Battery)
        let enabled = configurations.filter { $0.value.isEnabled }
        if enabled.isEmpty {
            if var cpuConfig = configurations[.cpu] {
                cpuConfig.isEnabled = true
                configurations[.cpu] = cpuConfig
            }
            if var batteryConfig = configurations[.battery] {
                batteryConfig.isEnabled = true
                configurations[.battery] = batteryConfig
            }
            saveConfigurations()
        }
        
        // 5. Ensure Network uses .speed display if enabled (fix for old configs)
        if var networkConfig = configurations[.network], networkConfig.isEnabled {
            if networkConfig.displayOption == .none {
                networkConfig.displayOption = .speed
                configurations[.network] = networkConfig
                saveConfigurations()
            }
        }
    }
    
    func saveConfigurations() {
        // Convert enum keys to strings for encoding
        let stringDict = Dictionary(uniqueKeysWithValues: configurations.map { ($0.key.rawValue, $0.value) })
        if let encoded = try? JSONEncoder().encode(stringDict) {
            defaults.set(encoded, forKey: configKey)
        }
    }
    
    func updateConfiguration(for utility: UtilityType, config: UtilityConfiguration) {
        // If enabling Meetings, check Calendar permission first
        if utility == .meetings && config.isEnabled {
            requestCalendarPermissionIfNeeded { granted in
                if granted {
                    self.applyConfiguration(for: utility, config: config)
                } else {
                    // Permission denied - don't enable
                    var deniedConfig = config
                    deniedConfig.isEnabled = false
                    self.applyConfiguration(for: utility, config: deniedConfig)
                }
            }
        } else {
            applyConfiguration(for: utility, config: config)
        }
    }
    
    private func applyConfiguration(for utility: UtilityType, config: UtilityConfiguration) {
        configurations[utility] = config
        saveConfigurations()
        objectWillChange.send() // Force UI update
        
        // Notify menu bar controller - ensure on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
    }
    
    /// Request Calendar permission when enabling Meetings
    private func requestCalendarPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        let status = MeetingManager.shared.accessState
        
        if status == .authorized {
            completion(true)
            return
        }
        
        // Request access - this shows the system dialog
        MeetingManager.shared.requestAccess()
        
        // Check after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let granted = MeetingManager.shared.accessState == .authorized
            completion(granted)
        }
    }
    
    func enabledUtilities() -> [(UtilityType, UtilityConfiguration)] {
        return configurations
            .filter { $0.value.isEnabled }
            .sorted { $0.value.position < $1.value.position }
    }
}

