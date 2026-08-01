//
//  PomodoroNotification.swift
//  CharBar
//
//  Pomodoro Timer Completion Popup - Similar to song change notification
//

import Cocoa
import SwiftUI

class PomodoroNotification {
    private var popover: NSPopover?
    private var dismissTimer: Timer?
    
    func show(title: String, body: String, state: String, relativeTo statusItem: NSStatusItem?) {
        // Dismiss existing
        dismiss()
        
        guard let button = statusItem?.button else { return }
        
        // Create popover content
        let contentView = PomodoroNotificationView(title: title, message: body, state: state)
        let hostingController = NSHostingController(rootView: contentView)
        
        // Create popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 90)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        
        self.popover = popover
        
        // Show popover below status item
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Auto-dismiss after 4 seconds (longer for timer notifications)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    /// Show notification relative to floating bar
    func showAtFloatingBar(title: String, body: String, state: String, floatingBarFrame: NSRect) {
        // Dismiss existing
        dismiss()
        
        // Create popover content
        let contentView = PomodoroNotificationView(title: title, message: body, state: state)
        let hostingController = NSHostingController(rootView: contentView)
        
        // Create a panel instead of popover for floating bar
        let panelSize = NSSize(width: 280, height: 90)
        let panelX = floatingBarFrame.midX - panelSize.width / 2
        
        // Check available space above/below and position accordingly
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let spaceAbove = screen.visibleFrame.maxY - floatingBarFrame.maxY
        let spaceBelow = floatingBarFrame.minY - screen.visibleFrame.minY
        
        let panelY: CGFloat
        if spaceAbove >= panelSize.height + 16 {
            panelY = floatingBarFrame.maxY + 8  // Above floating bar
        } else {
            panelY = floatingBarFrame.minY - panelSize.height - 8  // Below floating bar
        }
        
        let panel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        let containerView = NSView(frame: NSRect(origin: .zero, size: panelSize))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)
        
        hostingController.view.frame = effectView.bounds
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hostingController.view.layer?.cornerRadius = 12
        hostingController.view.layer?.masksToBounds = true
        effectView.addSubview(hostingController.view)
        
        panel.contentView = containerView
        
        // Animate in
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        
        // Store for dismissal
        self.notificationPanel = panel
        
        // Auto-dismiss after 4 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    private var notificationPanel: NSPanel?
    
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        popover?.performClose(nil)
        popover = nil
        
        // Dismiss panel if used
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

struct PomodoroNotificationView: View {
    let title: String
    let message: String
    let state: String
    
    var stateColor: Color {
        switch state {
        case "shortBreak": return Color(red: 0.4, green: 0.6, blue: 1.0)
        case "longBreak": return Color(red: 0.8, green: 0.5, blue: 1.0)
        case "complete": return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "breakOver": return .orange
        default: return .gray
        }
    }
    
    var stateIcon: String {
        switch state {
        case "shortBreak": return "cup.and.saucer.fill"
        case "longBreak": return "moon.stars.fill"
        case "complete": return "checkmark.circle.fill"
        case "breakOver": return "flame.fill"
        default: return "timer"
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: stateIcon)
                    .font(.system(size: 22))
                    .foregroundColor(stateColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 280, height: 90)
    }
}

