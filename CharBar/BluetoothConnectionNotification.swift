//
//  BluetoothConnectionNotification.swift
//  CharBar
//
//  Bluetooth Connection Notification Popup
//

import Cocoa
import SwiftUI
import Combine

class BluetoothConnectionNotification {
    static let shared = BluetoothConnectionNotification()
    
    private var notificationPanel: NSPanel?
    private var notificationPopover: NSPopover?
    private var dismissTimer: Timer?
    private var connectionObserver: Any?
    private var hostingController: NSHostingController<BluetoothConnectingView>?
    private var stateModel = BluetoothNotificationState()
    
    private init() {}
    
    /// Show notification when connecting to a device (at floating bar)
    func showAtFloatingBar(deviceName: String, floatingBarFrame: NSRect) {
        dismiss()
        
        stateModel.phase = .connecting
        stateModel.deviceName = deviceName
        
        let contentView = BluetoothConnectingView(state: stateModel) { [weak self] in
            self?.dismiss()
        }
        
        let controller = NSHostingController(rootView: contentView)
        hostingController = controller
        
        let compactSize = NSSize(width: 280, height: 76)
        let panelX = floatingBarFrame.midX - compactSize.width / 2
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let spaceAbove = screen.visibleFrame.maxY - floatingBarFrame.maxY
        
        let panelY: CGFloat
        if spaceAbove >= 220 {
            panelY = floatingBarFrame.maxY + 8
        } else {
            panelY = floatingBarFrame.minY - compactSize.height - 8
        }
        
        let panel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: compactSize.width, height: compactSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        let containerView = NSView(frame: NSRect(origin: .zero, size: compactSize))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: compactSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)
        
        controller.view.frame = effectView.bounds
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        controller.view.layer?.cornerRadius = 14
        controller.view.layer?.masksToBounds = true
        controller.view.autoresizingMask = [.width, .height]
        effectView.addSubview(controller.view)
        
        panel.contentView = containerView
        
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        
        notificationPanel = panel
        
        connectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BluetoothDevicesChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let device = BluetoothManager.shared.connectedAudioDevice {
                self?.transitionToConnected(device: device)
            }
        }
        
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    /// Show at status item (for menu bar mode)
    func show(deviceName: String, relativeTo statusItem: NSStatusItem?) {
        dismiss()
        
        guard let button = statusItem?.button else { return }
        
        stateModel.phase = .connecting
        stateModel.deviceName = deviceName
        
        let contentView = BluetoothConnectingView(state: stateModel) { [weak self] in
            self?.dismiss()
        }
        
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 76)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        notificationPopover = popover
        
        connectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BluetoothDevicesChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let device = BluetoothManager.shared.connectedAudioDevice {
                self?.transitionToConnected(device: device, isPopover: true)
            }
        }
        
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    private func transitionToConnected(device: BluetoothDevice, isPopover: Bool = false) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        stateModel.deviceName = device.name
        stateModel.deviceType = device.type
        stateModel.phase = .connected
        
        let expandedSize = NSSize(width: 280, height: 200)
        
        if isPopover, let popover = notificationPopover {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.allowsImplicitAnimation = true
                popover.contentSize = expandedSize
            }
        } else if let panel = notificationPanel {
            let currentFrame = panel.frame
            let newX = currentFrame.midX - expandedSize.width / 2
            let newY = currentFrame.origin.y
            let newFrame = NSRect(x: newX, y: newY, width: expandedSize.width, height: expandedSize.height)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            }
        }
        
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        if let observer = connectionObserver {
            NotificationCenter.default.removeObserver(observer)
            connectionObserver = nil
        }
        
        stateModel.phase = .connecting
        hostingController = nil
        
        if let popover = notificationPopover {
            popover.close()
            notificationPopover = nil
        }
        
        if let panel = notificationPanel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            notificationPanel = nil
        }
    }
}

// MARK: - State Model

class BluetoothNotificationState: ObservableObject {
    @Published var phase: Phase = .connecting
    @Published var deviceName: String = ""
    @Published var deviceType: BluetoothDeviceType = .headphones
    
    enum Phase {
        case connecting, connected
    }
}

// MARK: - Notification View

struct BluetoothConnectingView: View {
    @ObservedObject var state: BluetoothNotificationState
    let onDismiss: () -> Void
    
    @ObservedObject var bluetoothManager = BluetoothManager.shared
    
    private var deviceIcon: String {
        switch state.deviceType {
        case .airpods: return "airpods.gen3"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        default: return "headphones"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if state.phase == .connected {
                connectedView
            } else {
                connectingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.phase)
    }
    
    // MARK: - Connecting (compact banner)
    private var connectingView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Connecting...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(NSColor.labelColor))
                Text(state.deviceName)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
    
    // MARK: - Connected (expanded card)
    private var connectedView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            
            Image(systemName: deviceIcon)
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(spacing: 8) {
                Text(state.deviceName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Connected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.18))
                            .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))
                    )
            }
            
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
