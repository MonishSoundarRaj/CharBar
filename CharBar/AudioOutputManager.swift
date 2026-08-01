//
//  AudioOutputManager.swift
//  CharBar
//
//  CoreAudio-based Audio Output Device Manager
//  Provides Control Center-style audio output switching
//

import Foundation
import CoreAudio
import Combine
import AppKit

// MARK: - Audio Output Device Model

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let isDefault: Bool
    let transportType: AudioDeviceTransportType
    
    var icon: String {
        switch transportType {
        case .bluetooth, .bluetoothLE:
            return "headphones"
        case .airPlay:
            return "airplayaudio"
        case .builtIn:
            return "laptopcomputer"
        case .displayPort, .hdmi:
            return "tv"
        case .usb:
            return "cable.connector"
        case .thunderbolt:
            return "bolt.horizontal"
        default:
            return "hifispeaker"
        }
    }
    
    enum AudioDeviceTransportType: UInt32 {
        case unknown = 0
        case builtIn = 1651274862       // 'bltn'
        case aggregate = 1735554416     // 'grup'
        case virtual = 1986622068       // 'virt'
        case pci = 1885563168           // 'pci '
        case usb = 1970496032           // 'usb '
        case firewire = 1718775668      // 'fire'
        case bluetooth = 1651275109     // 'blue'
        case bluetoothLE = 1651271009   // 'blea'
        case hdmi = 1751412840          // 'hdmi'
        case displayPort = 1685090932   // 'dprt'
        case airPlay = 1634300528       // 'airp'
        case avb = 1635087714           // 'eavb'
        case thunderbolt = 1953002862   // 'thun'
    }
}

// MARK: - Audio Output Manager

class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()
    
    @Published var outputDevices: [AudioOutputDevice] = []
    @Published var currentDevice: AudioOutputDevice?
    
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    private init() {
        refreshDevices()
        setupDeviceChangeListener()
    }
    
    deinit {
        removeDeviceChangeListener()
    }
    
    // MARK: - Refresh Devices
    
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let devices = self?.getAllOutputDevices() ?? []
            let defaultDeviceID = self?.getDefaultOutputDeviceID() ?? 0
            
            DispatchQueue.main.async {
                self?.outputDevices = devices
                self?.currentDevice = devices.first { $0.id == defaultDeviceID }
            }
        }
    }
    
    // MARK: - Get All Output Devices
    
    private func getAllOutputDevices() -> [AudioOutputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return [] }
        
        let defaultDeviceID = getDefaultOutputDeviceID()
        
        return deviceIDs.compactMap { deviceID -> AudioOutputDevice? in
            // Check if device has output streams
            guard hasOutputStreams(deviceID) else { return nil }
            
            // Get device name
            guard let name = getDeviceName(deviceID) else { return nil }
            
            // Skip aggregate devices and internal system devices
            if name.lowercased().contains("aggregate") { return nil }
            
            // Get UID
            let uid = getDeviceUID(deviceID) ?? ""
            
            // Get transport type
            let transportType = getDeviceTransportType(deviceID)
            
            return AudioOutputDevice(
                id: deviceID,
                name: name,
                uid: uid,
                isDefault: deviceID == defaultDeviceID,
                transportType: AudioOutputDevice.AudioDeviceTransportType(rawValue: transportType) ?? .unknown
            )
        }
    }
    
    // MARK: - Check Output Streams
    
    private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        return status == noErr && dataSize > 0
    }
    
    // MARK: - Get Device Name
    
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )
        
        guard status == noErr, let cfName = name?.takeRetainedValue() else { return nil }
        return cfName as String
    }
    
    // MARK: - Get Device UID
    
    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )
        
        guard status == noErr, let cfUID = uid?.takeRetainedValue() else { return nil }
        return cfUID as String
    }
    
    // MARK: - Get Device Transport Type
    
    private func getDeviceTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        
        return status == noErr ? transportType : 0
    }
    
    // MARK: - Get Default Output Device
    
    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return status == noErr ? deviceID : 0
    }
    
    // MARK: - Set Default Output Device
    
    func setDefaultOutputDevice(_ device: AudioOutputDevice) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID = device.id
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )
        
        if status == noErr {
            DispatchQueue.main.async {
                self.currentDevice = device
                self.refreshDevices() // Refresh to update isDefault flags
            }
        }
    }
    
    // MARK: - Device Change Listener
    
    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        listenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )
        
        // Also listen for default device changes
        var defaultPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultPropertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )
    }
    
    private func removeDeviceChangeListener() {
        guard let listener = listenerBlock else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listener
        )
    }
}

