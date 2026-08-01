//
//  BluetoothMenuView.swift
//  CharBar
//
//  Modern Bluetooth Menu UI - Clean monochromatic Apple-style design
//

import SwiftUI
import Lottie

struct BluetoothMenuView: View {
    @ObservedObject var bluetoothManager = BluetoothManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            ModernDivider()
            
            // Device List
            if bluetoothManager.pairedDevices.isEmpty {
                emptyState
            } else {
                deviceList
            }
            
            ModernDivider()
            
            // Footer
            footerSection
        }
        .frame(width: 300)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Main status
            VStack(spacing: 8) {
                // Icon - only show when device connected
                if let device = bluetoothManager.connectedAudioDevice {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "headphones")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(Color.white.opacity(0.9))
                    }
                    
                    Text(device.name)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                    
                    if device.battery.hasBattery {
                        Text(device.battery.displayString)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    // No device - just show text, no icon
                    Text("Bluetooth")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                    
                    Text("No Audio Connected")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.top, 20)
            
            // Quick Connect Button
            if bluetoothManager.hasLastConnectedDevice, let lastDevice = bluetoothManager.lastConnectedDevice {
                quickConnectButton(deviceName: lastDevice.name)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Quick Connect Button
    private func quickConnectButton(deviceName: String) -> some View {
        Button(action: {
            bluetoothManager.connectToLastDevice()
        }) {
            HStack(spacing: 8) {
                if bluetoothManager.isConnecting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .medium))
                }
                
                Text(bluetoothManager.isConnecting ? "Connecting..." : "Connect to \(deviceName)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(bluetoothManager.isConnecting)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.25))
            
            Text("No Paired Devices")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
            
            Text("Pair devices in System Settings")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(height: 140)
    }
    
    // MARK: - Device List
    private var deviceList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(bluetoothManager.pairedDevices) { device in
                    BluetoothDeviceRow(device: device) {
                        bluetoothManager.toggleConnection(for: device)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(maxHeight: 300)
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        Button(action: {
            bluetoothManager.openBluetoothSettings()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                Text("Bluetooth Settings")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Device Row
struct BluetoothDeviceRow: View {
    let device: BluetoothDevice
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Device Icon
                ZStack {
                    Circle()
                        .fill(device.isConnected 
                              ? Color.white.opacity(0.15) 
                              : Color.white.opacity(0.06))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: device.type.icon)
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(device.isConnected ? .white.opacity(0.9) : .white.opacity(0.5))
                }
                
                // Device Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                    
                    Text(device.isConnected ? "Connected" : device.type.rawValue)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(device.isConnected ? .white.opacity(0.6) : .white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Battery Level
                if device.battery.hasBattery {
                    BatteryIndicator(device: device)
                }
                
                // Connect/Disconnect icon
                Image(systemName: device.isConnected ? "xmark" : "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(device.isConnected ? .white.opacity(0.4) : .white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHovering ? 0.1 : 0.05))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Battery Indicator
struct BatteryIndicator: View {
    let device: BluetoothDevice
    
    var body: some View {
        if let left = device.battery.leftLevel, let right = device.battery.rightLevel {
            // AirPods style - dual battery
            HStack(spacing: 6) {
                SingleBattery(level: left, label: "L")
                SingleBattery(level: right, label: "R")
            }
        } else if let main = device.battery.mainLevel {
            // Single battery
            SingleBattery(level: main, label: nil)
        }
    }
}

struct SingleBattery: View {
    let level: Int
    let label: String?
    
    var body: some View {
        HStack(spacing: 3) {
            if let label = label {
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            // Battery bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 18, height: 7)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(level <= 20 ? 0.5 : 0.7))
                    .frame(width: CGFloat(level) / 100.0 * 18, height: 7)
            }
            
            Text("\(level)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

#Preview {
    BluetoothMenuView()
        .frame(width: 300, height: 450)
        .background(Color.black.opacity(0.9))
}
