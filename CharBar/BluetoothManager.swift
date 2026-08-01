//
//  BluetoothManager.swift
//  CharBar
//
//  Bluetooth Manager using IOBluetooth framework ONLY
//  No terminal commands - App Store compliant
//

import Foundation
import IOBluetooth
import SwiftUI
import Combine

// MARK: - Device Types
enum BluetoothDeviceType: String, Codable {
    case airpods = "AirPods"
    case headphones = "Headphones"
    case mouse = "Mouse"
    case keyboard = "Keyboard"
    case speaker = "Speaker"
    case gameController = "Game Controller"
    case appleTV = "Apple TV"
    case appleWatch = "Apple Watch"
    case mac = "Mac"
    case iPhone = "iPhone"
    case iPad = "iPad"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .airpods:        return "airpods"
        case .headphones:     return "headphones"
        case .mouse:          return "computermouse.fill"
        case .keyboard:       return "keyboard.fill"
        case .speaker:        return "hifispeaker.fill"
        case .gameController: return "gamecontroller.fill"
        case .appleTV:        return "appletv.fill"
        case .appleWatch:     return "applewatch"
        case .mac:            return "desktopcomputer"
        case .iPhone:         return "iphone"
        case .iPad:           return "ipad"
        case .other:          return "wave.3.right.circle.fill"
        }
    }
    
    var isAudioDevice: Bool {
        switch self {
        case .airpods, .headphones, .speaker:
            return true
        default:
            return false
        }
    }
}

// MARK: - Battery Info
struct BatteryInfo {
    var mainLevel: Int?
    var leftLevel: Int?
    var rightLevel: Int?
    var caseLevel: Int?
    
    var displayString: String {
        if let left = leftLevel, let right = rightLevel {
            var str = "L: \(left)% R: \(right)%"
            if let caseL = caseLevel {
                str += " Case: \(caseL)%"
            }
            return str
        } else if let main = mainLevel {
            return "\(main)%"
        }
        return ""
    }
    
    var shortDisplayString: String {
        if let left = leftLevel, let right = rightLevel {
            return "L:\(left)% R:\(right)%"
        } else if let main = mainLevel {
            return "\(main)%"
        }
        return ""
    }
    
    var hasBattery: Bool {
        return mainLevel != nil || leftLevel != nil || rightLevel != nil
    }
}

// MARK: - Bluetooth Device Model
struct BluetoothDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: BluetoothDeviceType
    var isConnected: Bool
    var battery: BatteryInfo
    var ioDevice: IOBluetoothDevice?
    
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Bluetooth Manager (IOBluetooth Only)
class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()
    
    // MARK: - Published Properties
    @Published var pairedDevices: [BluetoothDevice] = []
    @Published var connectedAudioDevice: BluetoothDevice? = nil
    @Published var isBluetoothEnabled: Bool = true
    @Published var isConnecting: Bool = false
    
    // MARK: - Settings
    @AppStorage("bluetooth_showBatteryInMenuBar") var showBatteryInMenuBar: Bool = true
    @AppStorage("bluetooth_lastConnectedDeviceAddress") private var lastConnectedDeviceAddress: String = ""
    @AppStorage("bluetooth_lastConnectedDeviceName") private var lastConnectedDeviceName: String = ""
    
    // MARK: - Private
    private var refreshTimer: Timer?
    private var connectionNotification: IOBluetoothUserNotification?
    
    // MARK: - Last Connected Device Info
    var lastConnectedDevice: (name: String, address: String)? {
        guard !lastConnectedDeviceAddress.isEmpty && !lastConnectedDeviceName.isEmpty else { return nil }
        return (lastConnectedDeviceName, lastConnectedDeviceAddress)
    }
    
    var hasLastConnectedDevice: Bool {
        return !lastConnectedDeviceAddress.isEmpty && connectedAudioDevice == nil
    }
    
    // MARK: - Computed Properties
    
    /// Get the user's preferred character for the current connection state
    var currentMenuBarAnimation: String {
        guard let audioDevice = connectedAudioDevice else {
            // No audio device connected - use default bluetooth icon
            // The configuration character is used instead (handled in AppDelegate)
            return "bluetooth"
        }
        
        switch audioDevice.type {
        case .airpods, .headphones, .speaker:
            let connectedChar = UserDefaults.standard.string(forKey: "bluetooth_headphoneCharacter") ?? "dynoDancing"
            if let charType = CharacterType(rawValue: connectedChar),
               let filename = charType.lottieFileName {
                return filename
            }
            return "dyno_dancing_with_headphones"
            
        default:
            return "bluetooth"
        }
    }
    
    var menuBarDisplayText: String {
        guard showBatteryInMenuBar,
              let audioDevice = connectedAudioDevice,
              audioDevice.battery.hasBattery else {
            return ""
        }
        return audioDevice.battery.shortDisplayString
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        // Register for Bluetooth connection notifications
        setupBluetoothNotifications()
        
        // Initial fetch
        refreshDevices()
        
        // Refresh every 10 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
        connectionNotification?.unregister()
    }
    
    // MARK: - Setup Notifications
    private func setupBluetoothNotifications() {
        // Register for device connection notifications
        connectionNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }
    
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        // Register for disconnect notification
        device?.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        
        // Refresh device list
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshDevices()
        }
    }
    
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        // Refresh device list
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshDevices()
        }
    }
    
    // MARK: - Public Methods
    
    func refreshDevices() {
        var newDevices: [BluetoothDevice] = []
        var newConnectedAudioDevice: BluetoothDevice? = nil
        
        // Get paired devices using IOBluetooth
        guard let ioDevices = IOBluetoothDevice.pairedDevices() else {
            DispatchQueue.main.async {
                self.pairedDevices = []
                self.connectedAudioDevice = nil
                NotificationCenter.default.post(name: NSNotification.Name("BluetoothDevicesChanged"), object: nil)
            }
            return
        }
        
        for item in ioDevices {
            guard let ioDevice = item as? IOBluetoothDevice else { continue }
            
            let deviceName = ioDevice.name ?? "Unknown Device"
            let deviceAddress = ioDevice.addressString ?? UUID().uuidString
            let isConnected = ioDevice.isConnected()
            
            // Skip system devices (iPhone, Apple Watch for Continuity)
            let lowerName = deviceName.lowercased()
            if lowerName.contains("iphone") || lowerName.contains("apple watch") {
                continue
            }
            
            let deviceType = determineDeviceType(ioDevice)
            let battery = fetchBatteryInfo(for: ioDevice, type: deviceType)
            
            let device = BluetoothDevice(
                id: deviceAddress,
                name: deviceName,
                type: deviceType,
                isConnected: isConnected,
                battery: battery,
                ioDevice: ioDevice
            )
            
            newDevices.append(device)
            
            // Track connected audio device for menu bar icon
            if isConnected && deviceType.isAudioDevice {
                newConnectedAudioDevice = device
            }
        }
        
        // Sort: connected first, then by name
        newDevices.sort { (a, b) -> Bool in
            if a.isConnected != b.isConnected {
                return a.isConnected
            }
            return a.name < b.name
        }
        
        DispatchQueue.main.async {
            self.pairedDevices = newDevices
            self.connectedAudioDevice = newConnectedAudioDevice
            
            // Store last connected audio device for quick reconnect
            if let audioDevice = newConnectedAudioDevice {
                self.lastConnectedDeviceAddress = audioDevice.id
                self.lastConnectedDeviceName = audioDevice.name
            }
            
            NotificationCenter.default.post(name: NSNotification.Name("BluetoothDevicesChanged"), object: nil)
        }
    }
    
    /// Quick connect to the last connected audio device
    func connectToLastDevice() {
        guard !lastConnectedDeviceAddress.isEmpty else {
            return
        }
        
        // Find the device in paired devices
        guard let device = pairedDevices.first(where: { $0.id == lastConnectedDeviceAddress }),
              let ioDevice = device.ioDevice else {
            return
        }
        
        // Don't try to connect if already connected
        guard !device.isConnected else {
            return
        }
        
        isConnecting = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ioDevice.openConnection()
            
            DispatchQueue.main.async {
                self?.isConnecting = false
                
                // Refresh after connection attempt
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.refreshDevices()
                }
            }
        }
    }
    
    func toggleConnection(for device: BluetoothDevice) {
        guard let ioDevice = device.ioDevice else {
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if device.isConnected {
                // Disconnect
                _ = ioDevice.closeConnection()
            } else {
                // Connect
                _ = ioDevice.openConnection()
            }
            
            // Refresh after connection change
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.refreshDevices()
            }
        }
    }
    
    /// Disconnect the currently connected audio device
    func disconnectCurrentDevice() {
        guard let device = connectedAudioDevice,
              let ioDevice = device.ioDevice else {
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = ioDevice.closeConnection()
            
            // Refresh after disconnect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshDevices()
            }
        }
    }
    
    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Device Type Detection
    
    private func determineDeviceType(_ device: IOBluetoothDevice) -> BluetoothDeviceType {
        let name = device.name?.lowercased() ?? ""
        
        // Apple products first
        if name.contains("airpods") { return .airpods }
        if name.contains("apple tv") || name.contains("appletv") { return .appleTV }
        if name.contains("apple watch") || name.contains("applewatch") { return .appleWatch }
        if name.contains("iphone") { return .iPhone }
        if name.contains("ipad") { return .iPad }
        if name.contains("mac mini") || name.contains("macbook") || name.contains("imac") ||
           name.contains("mac pro") || name.contains("mac studio") || name.contains("'s mac") { return .mac }
        
        // Audio devices
        if name.contains("wh-") || name.contains("headphone") || name.contains("beats") ||
           name.contains("bose") || name.contains("sony") || name.contains("jabra") ||
           name.contains("sennheiser") || name.contains("audio-technica") || name.contains("headset") {
            return .headphones
        }
        if name.contains("homepod") || name.contains("speaker") || name.contains("soundbar") ||
           name.contains("jbl") || name.contains("ue boom") || name.contains("sonos") ||
           name.contains("living room") || name.contains("bedroom") || name.contains("kitchen") {
            return .speaker
        }
        
        // Input devices
        if name.contains("mouse") || name.contains("mx master") || name.contains("trackpad") ||
           name.contains("magic mouse") || name.contains("logitech m") || name.contains("mx anywhere") {
            return .mouse
        }
        if name.contains("keyboard") || name.contains("keychron") || name.contains("magic keyboard") {
            return .keyboard
        }
        if name.contains("controller") || name.contains("dualshock") || name.contains("xbox") ||
           name.contains("joy-con") || name.contains("dualsense") {
            return .gameController
        }
        
        // Fall back to Bluetooth device class
        let majorClass = device.deviceClassMajor
        let minorClass = device.deviceClassMinor
        
        // Major Device Class (Bluetooth spec)
        // 0x04 = Audio/Video, 0x05 = Peripheral
        switch majorClass {
        case 0x04: // Audio/Video
            switch minorClass {
            case 0x01, 0x02, 0x06: // Headset, Hands-free, Headphones
                return .headphones
            case 0x05, 0x07, 0x08: // Loudspeaker, Portable Audio, Car Audio
                return .speaker
            default:
                return .headphones
            }
            
        case 0x05: // Peripheral
            let peripheralType = (minorClass >> 4) & 0x03
            switch peripheralType {
            case 0x01:
                return .keyboard
            case 0x02:
                return .mouse
            default:
                if (minorClass & 0x08) != 0 {
                    return .gameController
                }
                return .other
            }
            
        default:
            return .other
        }
    }
    
    // MARK: - Battery Info
    
    private func fetchBatteryInfo(for device: IOBluetoothDevice, type: BluetoothDeviceType) -> BatteryInfo {
        var info = BatteryInfo()
        
        // Try to get battery from IORegistry
        if let address = device.addressString {
            info.mainLevel = getBatteryFromRegistry(deviceAddress: address)
        }
        
        // For AirPods, try granular battery
        if type == .airpods, let address = device.addressString {
            let airPodsInfo = getAirPodsBattery(deviceAddress: address)
            if let left = airPodsInfo.left { info.leftLevel = left }
            if let right = airPodsInfo.right { info.rightLevel = right }
            if let caseLevel = airPodsInfo.caseLevel { info.caseLevel = caseLevel }
        }
        
        return info
    }
    
    private func getBatteryFromRegistry(deviceAddress: String) -> Int? {
        let matchingDict = IOServiceMatching("IOBluetoothDevice")
        var iterator: io_iterator_t = 0
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            // Check device address
            if let addressRef = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0) {
                let address = addressRef.takeRetainedValue() as? String
                if address?.lowercased() == deviceAddress.lowercased() {
                    // Get battery
                    if let batteryRef = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0) {
                        return batteryRef.takeRetainedValue() as? Int
                    }
                }
            }
        }
        
        return nil
    }
    
    private func getAirPodsBattery(deviceAddress: String) -> (left: Int?, right: Int?, caseLevel: Int?) {
        let matchingDict = IOServiceMatching("AppleHSBluetoothDevice")
        var iterator: io_iterator_t = 0
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return (nil, nil, nil)
        }
        
        defer { IOObjectRelease(iterator) }
        
        var left: Int? = nil
        var right: Int? = nil
        var caseLevel: Int? = nil
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            if let leftRef = IORegistryEntryCreateCFProperty(service, "LeftBatteryPercent" as CFString, kCFAllocatorDefault, 0) {
                left = leftRef.takeRetainedValue() as? Int
            }
            if let rightRef = IORegistryEntryCreateCFProperty(service, "RightBatteryPercent" as CFString, kCFAllocatorDefault, 0) {
                right = rightRef.takeRetainedValue() as? Int
            }
            if let caseRef = IORegistryEntryCreateCFProperty(service, "CaseBatteryPercent" as CFString, kCFAllocatorDefault, 0) {
                caseLevel = caseRef.takeRetainedValue() as? Int
            }
        }
        
        return (left, right, caseLevel)
    }
}
