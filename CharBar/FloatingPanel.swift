//
//  FloatingPanel.swift
//  CharBar
//
//  A borderless floating panel for menu bar dropdowns
//  Replaces NSMenu for a cleaner, centered dropdown experience
//

import SwiftUI
import AppKit

// MARK: - Floating Panel Window

/// A borderless, transparent panel that appears below menu bar items
class FloatingPanel: NSPanel {
    
    private var visualEffectView: NSVisualEffectView?
    private var cornerRadius: CGFloat = 16
    var utility: UtilityType?
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    init(contentRect: NSRect, cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Panel configuration - CRITICAL: these must all be set for proper transparency
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        
        // Animation
        self.animationBehavior = .utilityWindow
        
        // CRITICAL: Set content view background to clear to avoid white corners
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = CGColor.clear
    }
    
    /// Set SwiftUI content with glass effect or custom background
    func setContent(_ hostingView: NSView, size: NSSize) {
        // Check if user has selected a custom background image
        let hasCustomBackground = BackgroundImageManager.shared.selectedBackgroundImage != nil
        let useGlass = !hasCustomBackground  // Use glass only when no custom image

        // CRITICAL: Initialize layer BEFORE adding to view hierarchy
        // This prevents ghosting/black artifacts from Lottie animations rendering
        // before the layer is properly configured
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false

        // Force layer creation now (before content renders)
        _ = hostingView.layer

        if useGlass {
            // GLASS MODE: Use NSVisualEffectView for native glass blur
            let containerView = NSView(frame: NSRect(origin: .zero, size: size))
            containerView.wantsLayer = true
            containerView.layer?.cornerRadius = cornerRadius
            containerView.layer?.masksToBounds = true
            
            let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = cornerRadius
            effectView.layer?.masksToBounds = true
            effectView.layer?.backgroundColor = CGColor.clear
            effectView.autoresizingMask = [.width, .height]
            
            containerView.addSubview(effectView)

            self.contentView = containerView
            self.backgroundColor = NSColor.clear

            // Dark tint ON TOP of the glass for readability on bright backgrounds
            hostingView.frame = effectView.bounds
            hostingView.autoresizingMask = [.width, .height]
            hostingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
            hostingView.layer?.cornerRadius = cornerRadius
            hostingView.layer?.masksToBounds = true
            effectView.addSubview(hostingView)

            self.visualEffectView = effectView
        } else {
            // IMAGE MODE: Just use the SwiftUI view directly (it has its own background)
            let containerView = NSView(frame: NSRect(origin: .zero, size: size))
            containerView.wantsLayer = true
            containerView.layer?.cornerRadius = cornerRadius
            containerView.layer?.masksToBounds = true
            containerView.layer?.backgroundColor = CGColor.clear
            // No border for clean look

            // Set as content view - ensure window background is clear
            self.contentView = containerView
            self.backgroundColor = NSColor.clear

            // Add SwiftUI view - layer already initialized above
            hostingView.frame = containerView.bounds
            hostingView.autoresizingMask = [.width, .height]
            hostingView.layer?.cornerRadius = cornerRadius
            hostingView.layer?.masksToBounds = true
            containerView.addSubview(hostingView)

            self.visualEffectView = nil
        }
    }
    
    /// Close the panel when clicking outside
    override func resignKey() {
        super.resignKey()
        self.close()
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            self.close()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Panel Controller

/// Manages the floating panel lifecycle for a utility
class FloatingPanelController: NSObject {
    static let shared = FloatingPanelController()
    
    private var currentPanel: FloatingPanel?
    private var currentUtility: UtilityType?
    private var eventMonitor: Any?
    
    private override init() {
        super.init()
    }
    
    /// Show a panel with the given SwiftUI content, centered under the button
    func show<Content: View>(
        content: Content,
        utility: UtilityType,
        relativeTo button: NSStatusBarButton,
        size: NSSize
    ) {
        // Close any existing panel
        close()
        
        // Calculate position centered under the button
        guard let screen = NSScreen.main,
              let buttonWindow = button.window else { return }
        
        let buttonFrame = button.convert(button.bounds, to: nil)
        let buttonScreenFrame = buttonWindow.convertToScreen(buttonFrame)
        
        // Center the panel under the button
        let panelX = buttonScreenFrame.midX - (size.width / 2)
        let panelY = buttonScreenFrame.minY - size.height - 5 // 5pt gap below button
        
        // Clamp to screen edges
        let clampedX = max(screen.visibleFrame.minX + 10, min(panelX, screen.visibleFrame.maxX - size.width - 10))
        
        let panelFrame = NSRect(
            x: clampedX,
            y: panelY,
            width: size.width,
            height: size.height
        )
        
        // Create the panel
        let panel = FloatingPanel(contentRect: panelFrame)
        panel.utility = utility
        
        // Wrap content with close action
        let wrappedContent = PanelContentWrapper(content: content) {
            self.close()
        }
        
        let hostingView = NSHostingView(rootView: wrappedContent)
        panel.setContent(hostingView, size: size)
        
        // Show with smooth Apple-like animation
        panel.alphaValue = 0
        
        // Start slightly above and scaled down for smooth entrance
        let originalFrame = panel.frame
        var startFrame = originalFrame
        startFrame.origin.y += 8
        panel.setFrame(startFrame, display: false)
        
        panel.orderFrontRegardless()
        panel.makeKey()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0) // Apple-like spring
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }
        
        currentPanel = panel
        currentUtility = utility
        
        // Monitor for clicks outside the panel
        setupEventMonitor()
    }
    
    /// Close the current panel
    func close() {
        guard let panel = currentPanel else { return }
        
        removeEventMonitor()
        
        // Smooth fade out and slight upward movement
        var endFrame = panel.frame
        endFrame.origin.y += 5
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: {
            panel.close()
        })
        
        currentPanel = nil
        currentUtility = nil
    }
    
    /// Toggle panel for a utility
    func toggle<Content: View>(
        content: Content,
        utility: UtilityType,
        relativeTo button: NSStatusBarButton,
        size: NSSize
    ) {
        if currentUtility == utility && currentPanel?.isVisible == true {
            close()
        } else {
            show(content: content, utility: utility, relativeTo: button, size: size)
        }
    }
    
    /// Show panel at a specific screen position (at cursor)
    func showAtPosition<Content: View>(
        content: Content,
        utility: UtilityType,
        position: NSPoint,
        size: NSSize
    ) {
        // Close any existing panel
        close()
        
        guard let screen = NSScreen.main else { return }
        
        // Position panel centered above the cursor point
        var panelX = position.x - (size.width / 2)
        var panelY = position.y + 10  // 10pt above cursor
        
        // Clamp to screen edges
        panelX = max(screen.visibleFrame.minX + 10, min(panelX, screen.visibleFrame.maxX - size.width - 10))
        panelY = max(screen.visibleFrame.minY + 10, min(panelY, screen.visibleFrame.maxY - size.height - 10))
        
        // If not enough space above, show below
        if panelY + size.height > screen.visibleFrame.maxY {
            panelY = position.y - size.height - 10
        }
        
        let panelFrame = NSRect(
            x: panelX,
            y: panelY,
            width: size.width,
            height: size.height
        )
        
        // Create the panel
        let panel = FloatingPanel(contentRect: panelFrame)
        panel.utility = utility
        
        // Wrap content with close action
        let wrappedContent = PanelContentWrapper(content: content) {
            self.close()
        }
        
        let hostingView = NSHostingView(rootView: wrappedContent)
        panel.setContent(hostingView, size: size)
        
        // Show with smooth Apple-like animation
        panel.alphaValue = 0
        
        let originalFrame = panel.frame
        var startFrame = originalFrame
        startFrame.origin.y -= 8 // Start below for upward motion
        panel.setFrame(startFrame, display: false)
        
        panel.orderFrontRegardless()
        panel.makeKey()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }
        
        currentPanel = panel
        currentUtility = utility
        
        // Monitor for clicks outside the panel
        setupEventMonitor()
    }
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Check if click is outside the panel
            guard let panel = self?.currentPanel else { return }
            
            let clickLocation = event.locationInWindow
            if event.window != panel {
                self?.close()
            } else {
                // Check if click is inside the panel frame
                let panelFrame = panel.frame
                let screenLocation = NSEvent.mouseLocation
                if !panelFrame.contains(screenLocation) {
                    self?.close()
                }
            }
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Panel Content Wrapper

/// Wraps content and provides a close action
struct PanelContentWrapper<Content: View>: View {
    let content: Content
    let onClose: () -> Void
    
    var body: some View {
        content
            .environment(\.panelCloseAction, onClose)
    }
}

// MARK: - Environment Key for Close Action

private struct PanelCloseActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var panelCloseAction: (() -> Void)? {
        get { self[PanelCloseActionKey.self] }
        set { self[PanelCloseActionKey.self] = newValue }
    }
}

// MARK: - Common Footer for All Panels

/// A compact footer with icon-only Settings and Quit buttons
struct PanelFooter: View {
    @Environment(\.panelCloseAction) var closePanel
    @State private var settingsHover = false
    @State private var quitHover = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Subtle separator
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            
            HStack(spacing: 12) {
                // Settings Button - Icon only
                Button(action: {
                    closePanel?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(settingsHover ? .white : .white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(settingsHover ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        settingsHover = hovering
                    }
                }
                .help("Settings (⌘,)")
                
                Spacer()
                
                // Quit Button - Icon only
                Button(action: {
                    closePanel?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.terminate(nil)
                    }
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(quitHover ? .white : .white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(quitHover ? Color.red.opacity(0.3) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        quitHover = hovering
                    }
                }
                .help("Quit (⌘Q)")
            }
            .padding(.horizontal, 18) // More margin on left/right
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - View Extension for Panel Footer

extension View {
    /// Add the standard panel footer with Settings and Quit - integrated into the menu
    func withPanelFooter() -> some View {
        VStack(spacing: 0) {
            self
            PanelFooter()
        }
        .menuBackground(cornerRadius: 16, innerPadding: 0)
    }
}

