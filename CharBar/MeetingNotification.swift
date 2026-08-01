//
//  MeetingNotification.swift
//  CharBar
//
//  Meeting Notification Popup - Shows when a meeting is about to start
//

import Cocoa
import SwiftUI

class MeetingNotification {
    static let shared = MeetingNotification()
    
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var dismissTimer: Timer?
    private var lastNotifiedMeetingId: String?
    private var lastNotifiedTime: Date?
    private var notificationPanel: NSPanel?
    private var fallbackWindow: NSPanel?
    private var pendingMeetings: [SmartMeeting] = []
    private var currentMeeting: SmartMeeting?
    
    private init() {}
    
    var isShowing: Bool {
        popover != nil || notificationPanel != nil || fallbackWindow != nil
    }
    
    func show(meeting: SmartMeeting, relativeTo statusItem: NSStatusItem?) {
        guard let settingsManager = sharedSettingsManager else { return }
        guard let config = settingsManager.configurations[.meetings], config.isEnabled == true else { return }
        
        let showNotif = UserDefaults.standard.object(forKey: "meeting_showNotification") as? Bool ?? true
        guard showNotif else { return }
        
        if let lastId = lastNotifiedMeetingId,
           let lastTime = lastNotifiedTime,
           lastId == meeting.id,
           Date().timeIntervalSince(lastTime) < 300 {
            return
        }
        
        // If already showing a notification, queue this one
        if isShowing {
            if !pendingMeetings.contains(where: { $0.id == meeting.id }) {
                pendingMeetings.append(meeting)
            }
            return
        }
        
        dismiss(showNext: false)
        currentMeeting = meeting
        
        let contentView = MeetingNotificationView(meeting: meeting) { [weak self] in
            self?.dismiss()
            MeetingManager.shared.joinMeeting(meeting)
        } onDismiss: { [weak self] in
            self?.dismiss()
        }
        
        guard let finalCheck = sharedSettingsManager?.configurations[.meetings],
              finalCheck.isEnabled == true else {
            return
        }
        
        playNotificationSound()
        
        if let button = statusItem?.button {
            popover = NSPopover()
            popover?.contentSize = NSSize(width: 320, height: 160)
            popover?.behavior = .transient
            popover?.animates = true
            popover?.contentViewController = NSHostingController(rootView: contentView)
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            // No status item available -- show as standalone panel in top-right corner
            showAsStandalonePanel(contentView: contentView)
        }
        
        lastNotifiedMeetingId = meeting.id
        lastNotifiedTime = Date()
        
        let dismissSeconds = MeetingManager.shared.notificationDismissSeconds
        if dismissSeconds > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: Double(dismissSeconds), repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    func showAtFloatingBar(meeting: SmartMeeting, floatingBarFrame: NSRect) {
        guard let settingsManager = sharedSettingsManager else { return }
        guard let config = settingsManager.configurations[.meetings], config.isEnabled == true else { return }
        
        let showNotif = UserDefaults.standard.object(forKey: "meeting_showNotification") as? Bool ?? true
        guard showNotif else { return }
        
        if let lastId = lastNotifiedMeetingId,
           let lastTime = lastNotifiedTime,
           lastId == meeting.id,
           Date().timeIntervalSince(lastTime) < 300 {
            return
        }
        
        // If already showing a notification, queue this one
        if isShowing {
            if !pendingMeetings.contains(where: { $0.id == meeting.id }) {
                pendingMeetings.append(meeting)
            }
            return
        }
        
        dismiss(showNext: false)
        currentMeeting = meeting
        
        let contentView = MeetingNotificationView(meeting: meeting) { [weak self] in
            self?.dismiss()
            MeetingManager.shared.joinMeeting(meeting)
        } onDismiss: { [weak self] in
            self?.dismiss()
        }
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let panelSize = NSSize(width: 320, height: 160)
        let panelX = floatingBarFrame.midX - panelSize.width / 2
        
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let spaceAbove = screen.visibleFrame.maxY - floatingBarFrame.maxY
        
        let panelY: CGFloat
        if spaceAbove >= panelSize.height + 16 {
            panelY = floatingBarFrame.maxY + 8
        } else {
            panelY = floatingBarFrame.minY - panelSize.height - 8
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
        containerView.layer?.cornerRadius = 16
        containerView.layer?.masksToBounds = true
        
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)
        
        hostingController.view.frame = effectView.bounds
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hostingController.view.layer?.cornerRadius = 16
        hostingController.view.layer?.masksToBounds = true
        effectView.addSubview(hostingController.view)
        
        panel.contentView = containerView
        
        guard let finalCheck = sharedSettingsManager?.configurations[.meetings],
              finalCheck.isEnabled == true else {
            return
        }
        
        playNotificationSound()
        
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        
        notificationPanel = panel
        
        lastNotifiedMeetingId = meeting.id
        lastNotifiedTime = Date()
        
        let dismissSeconds = MeetingManager.shared.notificationDismissSeconds
        if dismissSeconds > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: Double(dismissSeconds), repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    /// Show a standalone notification panel in the top-right corner of the screen
    private func showAsStandalonePanel(contentView: some View) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        let panelSize = NSSize(width: 320, height: 160)
        let panelX = screen.visibleFrame.maxX - panelSize.width - 16
        let panelY = screen.visibleFrame.maxY - panelSize.height - 8
        
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
        containerView.layer?.cornerRadius = 16
        containerView.layer?.masksToBounds = true
        
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)
        
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = effectView.bounds
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hostingController.view.layer?.cornerRadius = 16
        hostingController.view.layer?.masksToBounds = true
        effectView.addSubview(hostingController.view)
        
        panel.contentView = containerView
        
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        
        fallbackWindow = panel
    }
    
    private func playNotificationSound() {
        let soundEnabled = UserDefaults.standard.object(forKey: "meeting_notificationSound") as? Bool ?? true
        guard soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }
    
    func dismiss(showNext: Bool = true) {
        popover?.close()
        popover = nil
        
        if let panel = notificationPanel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            notificationPanel = nil
        }
        
        if let window = fallbackWindow {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
            fallbackWindow = nil
        }
        
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        currentMeeting = nil
        
        // Show next queued notification
        if showNext, let next = pendingMeetings.first {
            pendingMeetings.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if FloatingMenuBarController.shared.isVisible {
                    self.showAtFloatingBar(
                        meeting: next,
                        floatingBarFrame: FloatingMenuBarController.shared.floatingBarFrame
                    )
                } else {
                    self.show(meeting: next, relativeTo: nil)
                }
            }
        }
    }
}

// MARK: - Notification View
struct MeetingNotificationView: View {
    let meeting: SmartMeeting
    let onJoin: () -> Void
    let onDismiss: () -> Void
    
    @State private var countdown: Int = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(NSColor.labelColor))
                        .lineLimit(1)
                    
                    Text(meeting.timeRemainingString)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                .buttonStyle(.plain)
            }
            
            // Meeting info
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(meeting.calendarColor)
                    .frame(width: 4, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(NSColor.labelColor))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if let linkType = meeting.meetingLinkType {
                            Image(systemName: linkType.icon)
                                .font(.system(size: 10))
                                .foregroundColor(linkType.color)
                            
                            Text(linkType.brandName)
                                .font(.system(size: 10))
                                .foregroundColor(linkType.color)
                        }
                        
                        Text(meeting.formattedTimeRange)
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                }
                
                Spacer()
            }
            
            // Buttons row
            HStack(spacing: 8) {
                // Running Late dropdown
                Menu {
                    Button("Running 5 mins late") { sendRunningLateEmail(minutes: 5) }
                    Button("Running 10 mins late") { sendRunningLateEmail(minutes: 10) }
                    Button("Running 15 mins late") { sendRunningLateEmail(minutes: 15) }
                    Button("Running 20 mins late") { sendRunningLateEmail(minutes: 20) }
                    Divider()
                    Button("Open in Calendar") {
                        if let event = meeting.event {
                            EmailHelper.shared.showInCalendar(event: event)
                        } else {
                            MeetingManager.shared.openCalendarToSelectedDate()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 12))
                        Text("Late")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(Color(NSColor.labelColor))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.labelColor).opacity(0.1))
                    )
                }
                .menuStyle(.borderlessButton)
                
                // Share button
                if meeting.hasVideoLink {
                    Button(action: shareMeeting) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundColor(Color(NSColor.labelColor))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.labelColor).opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                // Join button
                if meeting.hasVideoLink {
                    Button(action: onJoin) {
                        HStack(spacing: 6) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 12))
                            
                            if countdown > 0 {
                                Text("Join in \(formatCountdown(countdown))")
                                    .font(.system(size: 12, weight: .semibold))
                            } else {
                                Text("Join Now")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(meeting.meetingLinkType?.color ?? .blue)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startCountdown() {
        countdown = Int(meeting.timeUntilStart)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            }
        }
    }
    
    private func formatCountdown(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d", mins, secs)
        }
    }
    
    private func sendRunningLateEmail(minutes: Int) {
        guard let event = meeting.event else {
            let subject = "Running Late: \(meeting.title)"
            let body = "Hi,\n\nI'm running about \(minutes) minutes late to \(meeting.title).\n\nI'll join as soon as I can!"
            EmailHelper.shared.openMailto(to: [], subject: subject, body: body)
            return
        }
        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: minutes)
    }
    
    private func shareMeeting() {
        var shareText = "\(meeting.title)\n\(meeting.formattedTimeRange)"
        if let link = meeting.meetingLink {
            shareText += "\n\nJoin: \(link.absoluteString)"
        }
        
        let picker = NSSharingServicePicker(items: [shareText])
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
           let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareText, forType: .string)
        }
    }
}
