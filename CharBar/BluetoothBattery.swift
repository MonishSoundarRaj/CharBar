//
//  BluetoothBattery.swift
//  CharBar
//
//  CoreBluetooth Battery Reader - Gets battery level from Bluetooth headphones
//  Uses the standard GATT Battery Service (0x180F)
//

import Foundation
import CoreBluetooth

class BluetoothBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BluetoothBattery()
    
    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [String: CBPeripheral] = [:] // name -> peripheral
    private var batteryLevels: [String: Int] = [:] // name -> battery level
    private var targetDeviceNames: Set<String> = [] // Names we're looking for
    
    // UUIDs for the standard Battery Service
    let BatteryServiceUUID = CBUUID(string: "180F")
    let BatteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    
    // Callback to send battery level back to your app#imageLiteral(resourceName: "SCR-20260114-plid.png")
    var onBatteryUpdate: ((String, Int) -> Void)?
    
    private override init() {
        super.init()
        // Start the Bluetooth Manager (runs on background queue)
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "bluetooth.battery"))
    }
    
    /// Get cached battery level for a device
    func getBatteryLevel(for deviceName: String) -> Int? {
        return batteryLevels[deviceName]
    }
    
    /// Start scanning for a specific device to get its battery
    func startScanning(forName name: String) {
        // Add to target names
        targetDeviceNames.insert(name)
        
        guard centralManager.state == .poweredOn else {
            return
        }
        
        // Check if we already have this device connected via CoreBluetooth
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [BatteryServiceUUID])
        
        if let device = connected.first(where: { matchesName($0.name, target: name) }) {
            connect(to: device, deviceName: name)
        } else {
            // Scan for peripherals with Battery Service
            centralManager.scanForPeripherals(withServices: [BatteryServiceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
            
            // Also try scanning without service filter (some devices hide battery service)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if self.batteryLevels[name] == nil {
                    self.centralManager.scanForPeripherals(withServices: nil, options: [
                        CBCentralManagerScanOptionAllowDuplicatesKey: false
                    ])
                }
            }
        }
    }
    
    /// Check if discovered name matches our target
    private func matchesName(_ discoveredName: String?, target: String) -> Bool {
        guard let discovered = discoveredName, !discovered.isEmpty else { return false }
        return discovered.lowercased().contains(target.lowercased()) || 
               target.lowercased().contains(discovered.lowercased())
    }
    
    /// Check if discovered name matches any target
    private func matchesAnyTarget(_ discoveredName: String?) -> String? {
        guard let discovered = discoveredName, !discovered.isEmpty else { return nil }
        return targetDeviceNames.first { target in
            discovered.lowercased().contains(target.lowercased()) || 
            target.lowercased().contains(discovered.lowercased())
        }
    }
    
    /// Scan for all known connected audio devices
    func scanForConnectedAudioDevices() {
        guard centralManager.state == .poweredOn else { return }
        
        // Get all connected peripherals that have battery service
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [BatteryServiceUUID])
        
        for peripheral in connected {
            if let name = peripheral.name {
                connect(to: peripheral, deviceName: name)
            }
        }
    }
    
    private func connect(to peripheral: CBPeripheral, deviceName: String) {
        connectedPeripherals[deviceName] = peripheral
        peripheral.delegate = self
        
        if peripheral.state == .connected {
            // Already connected, discover services
            peripheral.discoverServices([BatteryServiceUUID])
        } else {
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    // MARK: - Central Manager Delegates
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Scan for any connected devices
            scanForConnectedAudioDevices()
            
            // Retry scanning for any pending target devices
            for targetName in targetDeviceNames {
                if batteryLevels[targetName] == nil {
                    startScanning(forName: targetName)
                }
            }
        case .poweredOff, .unauthorized, .unsupported:
            break
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        
        // Check if this matches any of our target devices
        if let targetName = matchesAnyTarget(name) {
            connect(to: peripheral, deviceName: targetName)
            centralManager.stopScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Discover ALL services to see what Sony exposes
        peripheral.discoverServices(nil) // nil = discover all services
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    }
    
    // MARK: - Peripheral Delegates
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            return
        }
        
        guard let services = peripheral.services else {
            return
        }
        
        for service in services {
            if service.uuid == BatteryServiceUUID {
                peripheral.discoverCharacteristics([BatteryLevelCharacteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            if characteristic.uuid == BatteryLevelCharacteristicUUID {
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            return
        }
        
        if characteristic.uuid == BatteryLevelCharacteristicUUID, let data = characteristic.value, !data.isEmpty {
            // The first byte is the battery percentage (0-100)
            let batteryLevel = Int(data[0])
            let deviceName = peripheral.name ?? "Unknown"
            
            // Cache the battery level
            batteryLevels[deviceName] = batteryLevel
            
            // Notify listeners
            DispatchQueue.main.async { [weak self] in
                self?.onBatteryUpdate?(deviceName, batteryLevel)
            }
        }
    }
}

