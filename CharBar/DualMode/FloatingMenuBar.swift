//
//  FloatingMenuBar.swift
//  CharBar
//
//  A floating horizontal menu bar containing all utility animations
//  Same animations and behavior as the macOS menu bar, just floating
//

import SwiftUI
import AppKit
import Lottie
import Combine

// MARK: - Draggable Floating Panel

/// Custom NSPanel subclass that supports dragging from anywhere,
/// even over SwiftUI content that normally intercepts mouse events.
/// Uses sendEvent override (catches ALL events before subview dispatch)
/// with a 3px drag threshold to distinguish drags from clicks.
class DraggableFloatingPanel: NSPanel {
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var windowOriginAtDragStart: NSPoint = .zero
    private let dragThreshold: CGFloat = 3.0
    private var dragPassedThreshold = false
    
    /// Callback when panel is dragged (for saving position)
    var onDragEnd: (() -> Void)?
    /// Callback during drag with delta so attached panels can follow
    var onDragMove: ((CGFloat, CGFloat) -> Void)?
    
    override var canBecomeKey: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStartPoint = NSEvent.mouseLocation
            windowOriginAtDragStart = frame.origin
            isDragging = true
            dragPassedThreshold = false
            // Always pass mouseDown through to SwiftUI content
            super.sendEvent(event)
            
        case .leftMouseDragged:
            if isDragging {
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - dragStartPoint.x
                let dy = currentMouse.y - dragStartPoint.y
                
                if !dragPassedThreshold {
                    if abs(dx) > dragThreshold || abs(dy) > dragThreshold {
                        dragPassedThreshold = true
                    }
                }
                
                if dragPassedThreshold {
                    // Move the window - don't pass event to SwiftUI
                    let newOrigin = NSPoint(
                        x: windowOriginAtDragStart.x + dx,
                        y: windowOriginAtDragStart.y + dy
                    )
                    let prevOrigin = frame.origin
                    setFrameOrigin(newOrigin)
                    onDragMove?(newOrigin.x - prevOrigin.x, newOrigin.y - prevOrigin.y)
                    return // Consume event - don't pass to SwiftUI
                }
            }
            super.sendEvent(event)
            
        case .leftMouseUp:
            let wasDrag = dragPassedThreshold
            isDragging = false
            dragPassedThreshold = false
            
            if wasDrag {
                // Save position after drag ends
                onDragEnd?()
                return // Consume event - don't pass to SwiftUI (prevents accidental click)
            }
            super.sendEvent(event)
            
        default:
            super.sendEvent(event)
        }
    }
}

// MARK: - Dropdown Panel
class DropdownPanel: NSPanel {
    var utility: UtilityType?
    
    override var canBecomeKey: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            FloatingMenuBarController.shared.closeActiveDropdown()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Floating Menu Bar Controller

class FloatingMenuBarController: NSObject, ObservableObject {
    static let shared = FloatingMenuBarController()
    
    // MARK: - Properties
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingMenuBarView>?
    
    /// Active dropdown panel (only one at a time)
    private var activeDropdownPanel: NSPanel?
    
    /// Currently open utility (for toggle behavior)
    private var activeUtility: UtilityType?
    
    /// Click outside monitor for closing dropdown (global + local)
    private var clickOutsideMonitor: Any?
    private var clickLocalMonitor: Any?
    
    /// Whether the floating bar is currently visible
    @Published var isVisible: Bool = false
    
    /// The frame of the floating bar for positioning notifications
    var floatingBarFrame: NSRect {
        return panel?.frame ?? .zero
    }
    
    /// Whether the bar is in compact mode (icons only)
    @Published var isCompact: Bool = false
    
    /// Current position of the bar
    @Published var position: CGPoint = .zero
    
    /// Position key for UserDefaults
    private let positionKey = "FloatingMenuBar_Position"
    
    /// The screen to display on
    @Published var followsActiveScreen: Bool = false
    
    /// Use light mode for floating bar appearance
    @AppStorage("floatingBar_useLightMode") var floatingBarUseLightMode: Bool = true
    
    // Reference to AppDelegate for dropdowns
    weak var appDelegate: AppDelegate?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        loadPosition()
        
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.followsActiveScreen == true {
                    self?.moveToActiveScreen()
                }
            }
            .store(in: &cancellables)
        
        // Trigger 2: Periodically check if cursor moved to a different screen
        // (catches cases where user moves mouse without changing apps)
        Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.followsActiveScreen, self.isVisible else { return }
                self.moveToActiveScreen()
            }
            .store(in: &cancellables)
        
        // Persist followsActiveScreen changes to UserDefaults
        $followsActiveScreen
            .dropFirst() // Skip initial value from loadPosition()
            .sink { newValue in
                UserDefaults.standard.set(newValue, forKey: "FloatingMenuBar_FollowsActive")
            }
            .store(in: &cancellables)
        
        // Observe light/dark mode changes to recreate the panel
        // Track the current value so we only react when it actually changes
        _lastKnownLightMode = UserDefaults.standard.bool(forKey: "floatingBar_useLightMode")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(floatingBarAppearanceDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    private var _lastKnownLightMode: Bool = true
    
    @objc private func floatingBarAppearanceDidChange() {
        // Only react if the SPECIFIC light/dark mode setting changed
        let currentValue = UserDefaults.standard.bool(forKey: "floatingBar_useLightMode")
        guard currentValue != _lastKnownLightMode else { return }
        _lastKnownLightMode = currentValue
        
        // Only recreate if floating bar is visible
        guard isVisible else { return }
        
        // Recreate the panel to apply new appearance
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let currentPosition = self.panel?.frame.origin ?? self.position
            self.panel?.close()
            self.panel = nil
            self.hostingView = nil
            self.position = currentPosition
            self.createPanel()
            self.show()
        }
    }
    
    // MARK: - Panel Creation
    
    private func createPanel() {
        guard panel == nil else { return }
        
        // Calculate width based on enabled utilities and their display options
        let utilities = getEnabledUtilities()
        let sidePadding: CGFloat = 60 // Extra breathing room on left and right
        var totalWidth: CGFloat = 52 + sidePadding // Base padding (22 + 22 horizontal + some buffer) + side padding
        
        for utility in utilities {
            let config = sharedSettingsManager?.configurations[utility]
            let showText = config?.displayOption != DisplayOption.none
            
            switch utility {
            case .music:
                totalWidth += 50
            case .pomodoro:
                // Always allocate max width so bar doesn't resize when timer starts/stops
                totalWidth += showText ? 65 : 28
            case .meetings:
                totalWidth += showText ? 80 : 45
            case .bluetooth:
                totalWidth += 28
            case .network:
                totalWidth += showText ? 55 : 28
            case .cpu, .gpu, .ram, .battery, .disk:
                totalWidth += showText ? 55 : 28
            default:
                totalWidth += showText ? 55 : 28
            }
            totalWidth += 6
        }
        
        let height: CGFloat = 42  // Slightly taller for better padding
        let size = NSSize(width: max(totalWidth, 150), height: height)
        
        // Create borderless floating panel with custom drag support
        let newPanel = DraggableFloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel behavior
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isOpaque = false
        newPanel.backgroundColor = NSColor.clear
        newPanel.hasShadow = true
        newPanel.isMovableByWindowBackground = true
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.hidesOnDeactivate = false
        newPanel.animationBehavior = .utilityWindow
        newPanel.acceptsMouseMovedEvents = true
        
        // Always use dark appearance for the floating bar
        newPanel.appearance = NSAppearance(named: .darkAqua)
        
        // Create a container view for proper corner clipping
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        
        // Glass effect background
        let effectView = NSVisualEffectView(frame: containerView.bounds)
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        
        containerView.addSubview(effectView)
        
        // Create SwiftUI content with dark tint ON TOP of the glass
        let contentView = FloatingMenuBarView(controller: self)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = containerView.bounds
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hosting.layer?.isOpaque = false
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        hosting.autoresizingMask = [.width, .height]
        
        effectView.addSubview(hosting)
        
        newPanel.contentView = containerView
        newPanel.setContentSize(size)
        
        // Restore saved position
        if position != .zero {
            newPanel.setFrameOrigin(position)
        } else {
            // Default: center-bottom of screen
            if let screen = NSScreen.main {
                let x = (screen.visibleFrame.width - size.width) / 2 + screen.visibleFrame.origin.x
                let y = screen.visibleFrame.origin.y + 50
                newPanel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        
        // Connect drag end callback for position saving
        newPanel.onDragEnd = { [weak self] in
            guard let self = self, let panel = self.panel else { return }
            self.position = panel.frame.origin
            self.savePosition()
        }
        
        // Move any open dropdown/notification along with the floating bar
        newPanel.onDragMove = { [weak self] dx, dy in
            guard let self = self, let dropdown = self.activeDropdownPanel else { return }
            var origin = dropdown.frame.origin
            origin.x += dx
            origin.y += dy
            dropdown.setFrameOrigin(origin)
        }
        
        self.panel = newPanel
        self.hostingView = hosting
    }
    
    // MARK: - Show/Hide
    
    func show() {
        if panel == nil {
            createPanel()
        }
        
        // Only proceed if panel was successfully created
        guard let panel = panel else {
            return
        }
        
        panel.alphaValue = 0
        panel.orderFront(nil)
        panel.makeKey()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        
        isVisible = true
    }
    
    /// Show the floating bar at the current mouse/cursor position
    /// Pops up right where the user is working
    func showAtCursorPosition() {
        if panel == nil {
            createPanel()
        }
        
        guard let panel = panel else { return }
        
        // Get mouse position
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        
        // Get the screen the mouse is on
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        
        // Position centered above the cursor
        var panelX = mouseLocation.x - (panelSize.width / 2)
        var panelY = mouseLocation.y + 15 // 15pt above cursor
        
        // If not enough space above, show below
        if panelY + panelSize.height > screen.visibleFrame.maxY {
            panelY = mouseLocation.y - panelSize.height - 15
        }
        
        // Clamp to screen edges
        panelX = max(screen.visibleFrame.minX + 5, min(panelX, screen.visibleFrame.maxX - panelSize.width - 5))
        panelY = max(screen.visibleFrame.minY + 5, min(panelY, screen.visibleFrame.maxY - panelSize.height - 5))
        
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        
        // Animate in with a subtle spring-like effect
        panel.alphaValue = 0
        let originalFrame = panel.frame
        var startFrame = originalFrame
        startFrame.origin.y -= 6
        panel.setFrame(startFrame, display: false)
        
        panel.orderFront(nil)
        panel.makeKey()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }
        
        isVisible = true
        position = panel.frame.origin
        savePosition()
    }
    
    /// Toggle floating bar at cursor position (for keyboard shortcut)
    func toggleAtCursor() {
        let popAtCursor = UserDefaults.standard.bool(forKey: "floatingBar_popAtCursor")
        if isVisible {
            hide()
        } else if popAtCursor {
            showAtCursorPosition()
        } else {
            show()
        }
    }
    
    func hide() {
        closeActiveDropdown()
        isVisible = false
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }
    
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    // MARK: - Dropdown Management
    
    func closeActiveDropdown() {
        // Remove both monitors first
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = clickLocalMonitor {
            NSEvent.removeMonitor(monitor)
            clickLocalMonitor = nil
        }
        
        // Animate out the dropdown
        if let dropdown = activeDropdownPanel {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                dropdown.animator().alphaValue = 0
            } completionHandler: {
                dropdown.orderOut(nil)
            }
        }
        
        activeDropdownPanel = nil
        activeUtility = nil
    }
    
    // MARK: - Position Management
    
    private func loadPosition() {
        if let dict = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"] {
            position = CGPoint(x: x, y: y)
        }
        followsActiveScreen = UserDefaults.standard.bool(forKey: "FloatingMenuBar_FollowsActive")
        isCompact = UserDefaults.standard.bool(forKey: "FloatingMenuBar_Compact")
    }
    
    private func savePosition() {
        let dict: [String: CGFloat] = ["x": position.x, "y": position.y]
        UserDefaults.standard.set(dict, forKey: positionKey)
    }
    
    func toggleCompact() {
        isCompact.toggle()
        UserDefaults.standard.set(isCompact, forKey: "FloatingMenuBar_Compact")
        refresh()
    }
    
    func moveToActiveScreen() {
        guard let panel = panel else { return }
        
        // Determine the "active" screen:
        // 1. Try the screen containing the mouse cursor (most reliable)
        // 2. Try the screen of the frontmost app's key window
        // 3. Fall back to NSScreen.main
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen: NSScreen? = {
            // Check which screen the mouse is on
            if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
                return mouseScreen
            }
            // Check the frontmost app's window
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
                var focusedWindow: CFTypeRef?
                if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
                   let windowRef = focusedWindow {
                    let windowElement = unsafeBitCast(windowRef, to: AXUIElement.self)
                    var windowPosition: CFTypeRef?
                    if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &windowPosition) == .success,
                       let posRef = windowPosition {
                        let positionValue = unsafeBitCast(posRef, to: AXValue.self)
                        var point = CGPoint.zero
                        AXValueGetValue(positionValue, .cgPoint, &point)
                        // Convert to NSScreen coordinates (flip Y)
                        let nsPoint = NSPoint(x: point.x, y: point.y)
                        if let windowScreen = NSScreen.screens.first(where: { $0.frame.contains(nsPoint) }) {
                            return windowScreen
                        }
                    }
                }
            }
            return NSScreen.main ?? NSScreen.screens.first
        }()
        
        guard let targetScreen = targetScreen else { return }
        
        // Check if panel is already on the target screen
        // Use center point of panel for more reliable screen detection
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
        guard currentScreen != targetScreen else { return }
        
        // Position at top-center of the target screen, just below the menu bar
        let size = panel.frame.size
        let x = (targetScreen.visibleFrame.width - size.width) / 2 + targetScreen.visibleFrame.origin.x
        let y = targetScreen.visibleFrame.maxY - size.height - 8
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Save the new position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.position = panel.frame.origin
            self?.savePosition()
        }
    }
    
    // MARK: - Utility Management
    
    func getEnabledUtilities() -> [UtilityType] {
        // Use position-based sorting (same as menu bar) for consistent ordering
        if let settingsManager = appDelegate?.settingsManager {
            let sorted = settingsManager.enabledUtilities().map { $0.0 }
            if !sorted.isEmpty {
                return sorted
            }
        }
        
        if let sharedManager = sharedSettingsManager {
            let sorted = sharedManager.enabledUtilities().map { $0.0 }
            if !sorted.isEmpty {
                return sorted
            }
        }
        
        // Fallback to common utilities
        return [.music, .pomodoro, .meetings, .bluetooth]
    }
    
    /// Refresh the panel when utilities change
    func refresh() {
        let wasVisible = isVisible
        
        // Always recreate panel to recalculate width for new utility set
        panel?.close()
        panel = nil
        hostingView = nil
        
        // Only show again if it was previously visible
        if wasVisible {
            createPanel()
            show()
        }
    }
    
    // MARK: - Item Click Handling
    
    func handleItemClick(utility: UtilityType, itemCenterX: CGFloat? = nil) {
        // Toggle behavior: if same utility is clicked, close dropdown
        if activeUtility == utility && activeDropdownPanel != nil {
            closeActiveDropdown()
            return
        }
        
        // Close any existing dropdown first
        if activeDropdownPanel != nil {
            // Quick close without animation for switching
            if let monitor = clickOutsideMonitor {
                NSEvent.removeMonitor(monitor)
                clickOutsideMonitor = nil
            }
            activeDropdownPanel?.orderOut(nil)
            activeDropdownPanel = nil
        }
        
        // Get the view and size for this utility
        guard let appDelegate = appDelegate else { return }
        let (contentView, size) = appDelegate.getViewForUtility(utility)
        
        // Create the dropdown panel
        let dropdownPanel = DropdownPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dropdownPanel.utility = utility
        dropdownPanel.isMovableByWindowBackground = true // Allow moving the dropdown
        
        dropdownPanel.level = .popUpMenu
        dropdownPanel.backgroundColor = .clear
        dropdownPanel.isOpaque = false
        dropdownPanel.hasShadow = true
        dropdownPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        dropdownPanel.appearance = NSAppearance(named: .darkAqua)
        
        // AppKit container for corner clipping
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        
        let effectView = NSVisualEffectView(frame: containerView.bounds)
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = effectView.bounds
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hostingView.layer?.isOpaque = false
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)
        
        dropdownPanel.contentView = containerView
        
        // Calculate position based on available space — never overlap the bar
        if let floatingPanel = panel {
            let floatingFrame = floatingPanel.frame
            guard let screen = floatingPanel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
            let screenFrame = screen.visibleFrame

            // X: center on clicked icon, clamped to screen
            var panelX: CGFloat
            if let centerX = itemCenterX {
                panelX = centerX - size.width / 2
            } else {
                panelX = floatingFrame.midX - size.width / 2
            }
            panelX = max(screenFrame.minX + 8, min(panelX, screenFrame.maxX - size.width - 8))

            // Y: pick direction with more room, cap height to that space.
            // The bar is treated as an obstacle — panel never crosses its frame.
            let gap: CGFloat = 8
            let edgeMargin: CGFloat = 4
            let minPanelHeight: CGFloat = 280

            let availableBelow = max(0, floatingFrame.minY - screenFrame.minY - gap - edgeMargin)
            let availableAbove = max(0, screenFrame.maxY - floatingFrame.maxY - gap - edgeMargin)

            let fitsBelow = availableBelow >= size.height
            let fitsAbove = availableAbove >= size.height

            let openAbove: Bool
            if fitsAbove && fitsBelow {
                // Both fit — prefer the side with more room (matches user expectation
                // when the bar is closer to one edge of the screen).
                openAbove = availableAbove >= availableBelow
            } else if fitsAbove {
                openAbove = true
            } else if fitsBelow {
                openAbove = false
            } else {
                // Neither side has full height — pick the side with more room and cap.
                openAbove = availableAbove >= availableBelow
            }

            let availableForChosenSide = openAbove ? availableAbove : availableBelow
            let clampedHeight = min(size.height, max(minPanelHeight, availableForChosenSide))

            let panelY: CGFloat
            if openAbove {
                panelY = floatingFrame.maxY + gap
            } else {
                panelY = floatingFrame.minY - clampedHeight - gap
            }

            // Final safety clamp to screen edges (only kicks in if min height > available
            // on tiny screens — content scrolls internally either way).
            let safeY = max(screenFrame.minY + edgeMargin, min(panelY, screenFrame.maxY - clampedHeight - edgeMargin))

            dropdownPanel.setFrame(
                NSRect(x: panelX, y: safeY, width: size.width, height: clampedHeight),
                display: false
            )
        }
        
        // Animate in
        dropdownPanel.alphaValue = 0
        dropdownPanel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dropdownPanel.animator().alphaValue = 1
        }
        
        activeDropdownPanel = dropdownPanel
        activeUtility = utility
        
        // Remove any existing monitors first
        if let existingMonitor = clickOutsideMonitor {
            NSEvent.removeMonitor(existingMonitor)
            clickOutsideMonitor = nil
        }
        if let existingMonitor = clickLocalMonitor {
            NSEvent.removeMonitor(existingMonitor)
            clickLocalMonitor = nil
        }
        
        // Helper to check if click should close dropdown
        let shouldCloseDropdown: () -> Bool = { [weak self] in
            guard let self = self,
                  let dropdown = self.activeDropdownPanel,
                  let floating = self.panel else { return false }
            
            let screenPoint = NSEvent.mouseLocation
            let dropdownFrame = dropdown.frame
            let floatingFrame = floating.frame
            
            return !dropdownFrame.contains(screenPoint) && !floatingFrame.contains(screenPoint)
        }
        
        // Global monitor - for clicks outside the app
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if shouldCloseDropdown() {
                self?.closeActiveDropdown()
            }
        }
        
        // Local monitor - for clicks inside the app (other windows)
        clickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if shouldCloseDropdown() {
                self?.closeActiveDropdown()
            }
            return event
        }
    }
}

// MARK: - Floating Menu Bar View (SwiftUI)

struct FloatingMenuBarView: View {
    @ObservedObject var controller: FloatingMenuBarController
    @AppStorage("floatingBar_useLightMode") private var useLightMode: Bool = true
    
    var body: some View {
        let utilities = controller.getEnabledUtilities()
        
        // Simple content - glass effect comes from NSPanel's effectView
        HStack(spacing: 8) {
            if utilities.isEmpty {
                Text("CharBar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ForEach(utilities, id: \.self) { utility in
                    FloatingMenuBarItem(utility: utility, controller: controller, isCompact: controller.isCompact, useLightMode: useLightMode)
                }
            }
        }
        .padding(.horizontal, 30) // Extra breathing room on left and right
        .padding(.vertical, 10)
    }
}

// MARK: - Individual Menu Bar Item

struct FloatingMenuBarItem: View {
    let utility: UtilityType
    let controller: FloatingMenuBarController
    var isCompact: Bool = false
    var useLightMode: Bool = true
    
    // Dynamic text color based on light/dark mode
    private var textColor: Color {
        .white.opacity(0.9)
    }
    
    private var secondaryTextColor: Color {
        .white.opacity(0.6)
    }
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            // Special handling for Bluetooth quick connect
            if utility == .bluetooth {
                handleBluetoothClick()
            } else {
                // Use mouse location for accurate positioning
                let mouseLocation = NSEvent.mouseLocation
                controller.handleItemClick(utility: utility, itemCenterX: mouseLocation.x)
            }
        }) {
            itemContent
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        // Right-click to open dropdown for Bluetooth
        .contextMenu(utility == .bluetooth ? ContextMenu {
            Button("Open Bluetooth Menu") {
                let mouseLocation = NSEvent.mouseLocation
                controller.handleItemClick(utility: .bluetooth, itemCenterX: mouseLocation.x)
            }
            if BluetoothManager.shared.hasLastConnectedDevice {
                Button("Connect to \(BluetoothManager.shared.lastConnectedDevice?.name ?? "Device")") {
                    BluetoothManager.shared.connectToLastDevice()
                    showBluetoothConnectingNotification()
                }
            }
            Divider()
            Button("Bluetooth Settings...") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.bluetooth")!)
            }
        } : nil)
    }
    
    private func handleBluetoothClick() {
        let quickConnectMode = UserDefaults.standard.bool(forKey: "bluetooth_quickConnectMode")
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.type == .rightMouseDown
        let isOptionClick = event?.modifierFlags.contains(.option) ?? false
        let isControlClick = event?.modifierFlags.contains(.control) ?? false
        
        // Right-click or option/control-click always opens the dropdown
        if isRightClick || isOptionClick || isControlClick {
            let mouseLocation = NSEvent.mouseLocation
            controller.handleItemClick(utility: .bluetooth, itemCenterX: mouseLocation.x)
            return
        }
        
        // If quick connect is enabled and we have a last device
        if quickConnectMode && BluetoothManager.shared.hasLastConnectedDevice {
            // If already connected, show dropdown to disconnect
            if BluetoothManager.shared.connectedAudioDevice != nil {
                let mouseLocation = NSEvent.mouseLocation
                controller.handleItemClick(utility: .bluetooth, itemCenterX: mouseLocation.x)
            } else {
                // Connect to last device
                BluetoothManager.shared.connectToLastDevice()
                showBluetoothConnectingNotification()
            }
        } else {
            // Normal behavior - open dropdown
            let mouseLocation = NSEvent.mouseLocation
            controller.handleItemClick(utility: .bluetooth, itemCenterX: mouseLocation.x)
        }
    }
    
    private func showBluetoothConnectingNotification() {
        guard let deviceName = BluetoothManager.shared.lastConnectedDevice?.name else { return }
        
        // Show a notification popup near the floating bar
        if controller.isVisible {
            BluetoothConnectionNotification.shared.showAtFloatingBar(
                deviceName: deviceName,
                floatingBarFrame: controller.floatingBarFrame
            )
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        switch utility {
        case .music:
            MusicFloatingItem()
        case .pomodoro:
            PomodoroFloatingItem()
        case .meetings:
            MeetingsFloatingItem()
        case .bluetooth:
            BluetoothFloatingItem()
        case .cpu, .ram, .battery, .disk, .network, .gpu:
            SystemStatFloatingItem(utility: utility)
        default:
            Image(systemName: utility.icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Utility-Specific Floating Items
// Uses EXACT SAME logic as AppDelegate - observes the same data sources

struct MusicFloatingItem: View {
    @ObservedObject var mediaObserver = MediaObserver.shared
    @AppStorage("floatingBar_useLightMode") private var useLightMode: Bool = true
    @State private var animationName: String = "music"
    @State private var isStaticIcon: Bool = false
    @State private var animSize: CGSize = CGSize(width: 24, height: 24)
    
    private var trackID: String {
        "\(mediaObserver.title)-\(mediaObserver.artist)"
    }
    
    private var iconColor: Color {
        .white
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Album artwork
            if let artwork = mediaObserver.artworkImage {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .opacity(mediaObserver.isPlaying ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.25), value: mediaObserver.isPlaying)
                    .id(trackID)
                    .transition(.push(from: .leading).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: trackID)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundColor(iconColor.opacity(0.5))
                    )
            }
            
            // Static icon mode
            if isStaticIcon {
                Image(systemName: mediaObserver.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor.opacity(mediaObserver.isPlaying ? 0.9 : 0.5))
                    .frame(width: animSize.width, height: animSize.height)
            }
            // Animation
            else if let anim = LottieAnimation.named(animationName) {
                if mediaObserver.isPlaying {
                    LottieView(animation: anim)
                        .playing(loopMode: .loop)
                        .animationSpeed(0.6)
                        .frame(width: animSize.width, height: animSize.height)
                } else {
                    LottieView(animation: anim)
                        .currentProgress(0.5)
                        .frame(width: animSize.width, height: animSize.height)
                        .opacity(0.4)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))) { _ in
            loadSettings()
        }
    }
    
    private func loadSettings() {
        if let config = sharedSettingsManager?.configurations[.music] {
            isStaticIcon = config.character.isStaticIcon
            animationName = config.character.lottieFileName ?? "music"
            animSize = config.character.floatingBarAnimationSize
        }
    }
}

struct PomodoroFloatingItem: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @AppStorage("floatingBar_useLightMode") private var useLightMode: Bool = true
    @State private var animationName: String = "timer"
    @State private var isStaticIcon: Bool = false
    @State private var animSize: CGSize = CGSize(width: 24, height: 24)
    @State private var showTimer: Bool = true
    
    @State private var staticIconSymbol: String = "timer"
    
    private var iconColor: Color {
        .white
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if isStaticIcon {
                Image(systemName: staticIconSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor.opacity(pomodoro.isRunning ? (pomodoro.isPaused ? 0.5 : 0.9) : 0.5))
                    .frame(width: 20, height: 20)
            }
            else if let anim = LottieAnimation.named(animationName) {
                if pomodoro.isRunning && !pomodoro.isPaused {
                    LottieView(animation: anim)
                        .playing(loopMode: .loop)
                        .animationSpeed(pomodoro.isRestingState ? 0.7 : 1.0)
                        .frame(width: animSize.width, height: animSize.height)
                } else {
                    LottieView(animation: anim)
                        .currentProgress(pomodoro.isRunning ? pomodoro.sandProgress : 0.0)
                        .frame(width: animSize.width, height: animSize.height)
                        .opacity(pomodoro.isRunning ? 0.7 : 0.5)
                }
            }
            
            if showTimer && pomodoro.isRunning {
                Text(pomodoro.timeRemainingFormatted)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(iconColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .onAppear {
            loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PomodoroStateChanged"))) { _ in
            loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))) { _ in
            loadSettings()
        }
    }
    
    private func loadSettings() {
        if let config = sharedSettingsManager?.configurations[.pomodoro] {
            showTimer = config.displayOption != DisplayOption.none
        }
        // Use currentMenuBarAnimation which handles work/break state
        let animFileName = pomodoro.currentMenuBarAnimation
        animationName = animFileName
        
        // Determine static vs animated based on current state
        if pomodoro.isRestingState {
            let restingChar = UserDefaults.standard.string(forKey: "pomo_restingCharacter") ?? "sleepingCat"
            if let charType = CharacterType(rawValue: restingChar) {
                isStaticIcon = charType.isStaticIcon
                animSize = charType.floatingBarAnimationSize
                staticIconSymbol = charType.sfSymbolName ?? "timer"
            }
        } else {
            let workingChar = UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass"
            if let charType = CharacterType(rawValue: workingChar) {
                isStaticIcon = charType.isStaticIcon
                animSize = charType.floatingBarAnimationSize
                staticIconSymbol = charType.sfSymbolName ?? "timer"
            }
        }
    }
}

struct MeetingsFloatingItem: View {
    @ObservedObject var meetingManager = MeetingManager.shared
    @AppStorage("floatingBar_useLightMode") private var useLightMode: Bool = true
    @AppStorage("meeting_joinButtonMinutes") private var joinButtonMinutes: Int = 5
    @State private var animationName: String = "timer"
    @State private var isStaticIcon: Bool = false
    @State private var animSize: CGSize = CGSize(width: 24, height: 24)
    @State private var showText: Bool = true
    @State private var now = Date()
    @State private var adaptiveTimer: Timer?
    
    private var iconColor: Color {
        .white
    }
    
    private var activeMeeting: SmartMeeting? {
        meetingManager.displayMeeting
    }
    
    private var hasPendingItems: Bool {
        meetingManager.currentMeeting != nil || !meetingManager.upcomingMeetings.isEmpty
    }
    
    private func timeUntil(_ meeting: SmartMeeting) -> TimeInterval {
        meeting.startDate.timeIntervalSince(now)
    }
    
    private var isActionState: Bool {
        guard let meeting = activeMeeting else { return false }
        let joinThreshold = Double(joinButtonMinutes * 60)
        let t = timeUntil(meeting)
        return meeting.isHappeningNow || (t > 0 && t <= joinThreshold)
    }
    
    private var shouldShowJoinButton: Bool {
        guard let meeting = activeMeeting else { return false }
        return meeting.hasVideoLink && isActionState
    }
    
    private var shouldShowRedDot: Bool {
        guard let meeting = activeMeeting else { return false }
        return !meeting.hasVideoLink && meeting.isHappeningNow
    }
    
    private var joinButtonColor: Color {
        guard let meeting = activeMeeting else { return .blue }
        if meeting.isHappeningNow {
            return .green
        } else if timeUntil(meeting) <= 60 {
            return .red
        } else {
            return .orange
        }
    }
    
    private var joinButtonText: String {
        guard let meeting = activeMeeting else { return "Join" }
        if meeting.isHappeningNow {
            return "Join"
        } else {
            let t = timeUntil(meeting)
            let mins = Int(t) / 60
            let secs = Int(t) % 60
            return String(format: "%d:%02d", mins, secs)
        }
    }
    
    /// Adaptive update interval: 1s whenever the timer/join-button is visible, 5s near threshold, 30s idle
    private var currentInterval: TimeInterval {
        // 1s when the live countdown text or join button is showing
        if isInCountdownThreshold || shouldShowJoinButton || shouldShowRedDot {
            return 1.0
        }
        let state = meetingManager.menuBarState
        if state == .countdown || state == .action || activeMeeting?.isHappeningNow == true {
            return 1.0
        }
        if let meeting = activeMeeting {
            let t = timeUntil(meeting)
            let countdownThreshold = Double(MeetingManager.shared.countdownMinutes * 60)
            // Switch to 5s when within 60s of entering the countdown zone
            if t <= countdownThreshold + 60 {
                return 5.0
            }
        }
        return 30.0
    }
    
    /// SF Symbol that reflects access + meeting state (synced with menu bar)
    private var calendarIconSymbol: String { meetingManager.calendarIconSymbol }
    
    private var calendarIcon: some View {
        Group {
            // If no calendar permission, always show static exclamation icon
            if meetingManager.accessState != .authorized {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.orange.opacity(0.7))
                    .frame(width: 26, height: 26)
            } else if isStaticIcon {
                Image(systemName: calendarIconSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor.opacity(hasPendingItems ? 0.9 : 0.5))
                    .frame(width: 26, height: 26)
            } else if let anim = LottieAnimation.named(animationName) {
                if hasPendingItems {
                    LottieView(animation: anim)
                        .playing(loopMode: .loop)
                        .animationSpeed(0.3)
                        .frame(width: animSize.width, height: animSize.height)
                } else {
                    // No pending meetings — show static first frame, dimmed
                    LottieView(animation: anim)
                        .currentProgress(0.0)
                        .frame(width: animSize.width, height: animSize.height)
                        .opacity(0.4)
                }
            } else {
                Image(systemName: calendarIconSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor.opacity(hasPendingItems ? 0.9 : 0.5))
                    .frame(width: 26, height: 26)
            }
        }
    }
    
    /// Formatted countdown string (Pomodoro-style monospaced digits)
    /// True when the meeting is within the countdown threshold the user chose in settings
    private var isInCountdownThreshold: Bool {
        guard let meeting = activeMeeting else { return false }
        if meeting.isHappeningNow { return true }
        let t = timeUntil(meeting)
        let countdownThreshold = Double((sharedSettingsManager?.configurations[.meetings] != nil
            ? MeetingManager.shared.countdownMinutes
            : 15) * 60)
        return t > 0 && t <= countdownThreshold
    }
    
    private var countdownTextView: some View {
        Group {
            if let meeting = activeMeeting, meeting.endDate > now {
                if meeting.isHappeningNow {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Now")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                } else if isInCountdownThreshold {
                    // Within countdown threshold – show MM:SS timer
                    let t = timeUntil(meeting)
                    let totalSec = Int(max(0, t))
                    let mins = totalSec / 60
                    let secs = totalSec % 60
                    Text(String(format: "%d:%02d", mins, secs))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    // Upcoming but beyond threshold – just show checkmark (no time text)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                // No active meeting – checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if shouldShowJoinButton {
                // Left-click: join   Right-click: open the calendar dropdown popup
                Button(action: joinMeeting) {
                    Text(joinButtonText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minWidth: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(joinButtonColor)
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let meeting = activeMeeting {
                        Text(meeting.title)
                            .font(.system(size: 12, weight: .semibold))
                        Divider()
                        Button("View Calendar") { openMeetingsDropdown() }
                        Button("Join Meeting") { joinMeeting() }
                        if meeting.hasVideoLink, let link = meeting.videoLink {
                            Divider()
                            Button("Copy Meeting Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link.absoluteString, forType: .string)
                            }
                        }
                    } else {
                        Button("View Calendar") { openMeetingsDropdown() }
                    }
                }
            }
            else if shouldShowRedDot {
                calendarIcon
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Now")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
            } else {
                calendarIcon
                
                if showText {
                    countdownTextView
                }
            }
        }
        .frame(minHeight: 26)
        .contextMenu {
            Button("Open Calendar") { openCalendar() }
            if let meeting = activeMeeting {
                Divider()
                Text(meeting.title)
                if meeting.hasVideoLink {
                    Button("Join Meeting") { joinMeeting() }
                }
            }
        }
        .onAppear {
            loadSettings()
            startAdaptiveTimer()
        }
        .onDisappear {
            adaptiveTimer?.invalidate()
        }
        .onChange(of: meetingManager.menuBarState) { _ in
            startAdaptiveTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))) { _ in
            loadSettings()
        }
    }
    
    private func startAdaptiveTimer() {
        adaptiveTimer?.invalidate()
        let interval = currentInterval
        adaptiveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async {
                self.now = Date()
                self.startAdaptiveTimer()
            }
        }
    }
    
    private func loadSettings() {
        if let config = sharedSettingsManager?.configurations[.meetings] {
            showText = config.displayOption != DisplayOption.none
            isStaticIcon = config.character.isStaticIcon
            animationName = config.character.lottieFileName ?? "timer"
            animSize = config.character.floatingBarAnimationSize
        }
    }
    
    private func joinMeeting() {
        guard let meeting = activeMeeting else { return }
        meetingManager.joinMeeting(meeting)
    }
    
    /// Open the CharBar calendar dropdown (same popup as tapping the calendar icon)
    private func openMeetingsDropdown() {
        FloatingMenuBarController.shared.handleItemClick(utility: .meetings)
    }
    
    private func openCalendar() {
        FloatingCalendarController.shared.show()
    }
}

struct BluetoothFloatingItem: View {
    @ObservedObject var bluetoothManager = BluetoothManager.shared
    @AppStorage("floatingBar_useLightMode") private var useLightMode: Bool = true
    @State private var defaultAnimationName: String = "bluetooth"
    @State private var isStaticIcon: Bool = false
    @State private var staticIconSymbol: String = "dot.radiowaves.right"
    @State private var animSize: CGSize = CGSize(width: 24, height: 24)
    @State private var showConnectedTick: Bool = false
    
    private var iconColor: Color {
        .white
    }
    
    var body: some View {
        Group {
            if bluetoothManager.isConnecting {
                // Show loading spinner during connection
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: animSize.width, height: animSize.height)
            } else if showConnectedTick {
                // Brief tick after successful connection
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
                    .frame(width: animSize.width, height: animSize.height)
            } else if isStaticIcon {
                if let device = bluetoothManager.connectedAudioDevice {
                    Image(systemName: device.type == .airpods ? "airpodspro" : "headphones")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(iconColor.opacity(0.9))
                        .frame(width: animSize.width, height: animSize.height)
                } else {
                    Image(systemName: staticIconSymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(iconColor.opacity(0.5))
                        .frame(width: animSize.width, height: animSize.height)
                }
            } else {
                let animName = bluetoothManager.connectedAudioDevice != nil 
                    ? bluetoothManager.currentMenuBarAnimation 
                    : defaultAnimationName
                
                if let anim = LottieAnimation.named(animName) {
                    LottieView(animation: anim)
                        .playing(loopMode: .loop)
                        .animationSpeed(0.6)
                        .frame(width: animSize.width, height: animSize.height)
                }
            }
        }
        .onAppear {
            if let config = sharedSettingsManager?.configurations[.bluetooth] {
                isStaticIcon = config.character.isStaticIcon
                staticIconSymbol = config.character.sfSymbolName ?? "dot.radiowaves.right"
                defaultAnimationName = config.character.lottieFileName ?? "bluetooth"
                animSize = config.character.floatingBarAnimationSize
            }
        }
        .onChange(of: bluetoothManager.connectedAudioDevice != nil) { oldValue, isConnected in
            if isConnected && !oldValue && !showConnectedTick {
                // Show tick briefly when device connects
                withAnimation { showConnectedTick = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { showConnectedTick = false }
                }
            }
        }
    }
}

struct SystemStatFloatingItem: View {
    let utility: UtilityType
    @ObservedObject var systemMonitor: SystemMonitor
    @AppStorage("floatingBar_useLightMode") private var useLightMode: Bool = true
    @State private var animationName: String = "hardware"
    @State private var isStaticIcon: Bool = false
    @State private var sfSymbolName: String? = nil
    @State private var animSize: CGSize = CGSize(width: 24, height: 24)
    @State private var showValue: Bool = true
    
    private var iconColor: Color {
        .white
    }
    
    // Computed speed tier for animation (forces view recreation on significant changes)
    private var speedTier: Int {
        let speed = getAnimationSpeed()
        // Create tiers: 0.6-0.75=1, 0.75-0.9=2, 0.9-1.05=3, 1.05+=4
        if speed < 0.75 { return 1 }
        else if speed < 0.9 { return 2 }
        else if speed < 1.05 { return 3 }
        else { return 4 }
    }
    
    init(utility: UtilityType) {
        self.utility = utility
        self.systemMonitor = sharedSystemMonitor ?? SystemMonitor()
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Static icon
            if isStaticIcon, let sfName = sfSymbolName {
                Image(systemName: resolvedIconName(sfName))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor.opacity(0.8))
                    .frame(width: animSize.width, height: animSize.height)
            }
            // Animation - speed based on usage level
            else if let anim = LottieAnimation.named(animationName) {
                LottieView(animation: anim)
                    .playing(loopMode: .loop)
                    .animationSpeed(getAnimationSpeed())
                    .frame(width: animSize.width, height: animSize.height)
                    .id("\(utility.rawValue)_\(speedTier)") // Force recreation on speed tier change
            }
            
            // Value text - only show if displayOption is not none
            if showValue {
                let isLottieBatteryCharging = utility == .battery
                    && !isStaticIcon
                    && (systemMonitor.isCharging || !systemMonitor.isBatteryPowered)
                
                HStack(spacing: 1) {
                    if isLottieBatteryCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(iconColor)
                    }
                    Text(getValue())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(iconColor)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .onAppear {
            if let config = sharedSettingsManager?.configurations[utility] {
                showValue = config.displayOption != DisplayOption.none
                isStaticIcon = config.character.isStaticIcon
                sfSymbolName = config.character.sfSymbolName
                animationName = config.character.lottieFileName ?? getDefaultAnimation()
                animSize = config.character.floatingBarAnimationSize
            } else {
                animationName = getDefaultAnimation()
            }
        }
    }
    
    /// Resolves dynamic icon names (e.g. battery level) at render time
    private func resolvedIconName(_ baseName: String) -> String {
        if utility == .battery {
            let level = systemMonitor.batteryLevel * 100
            let isPlugged = systemMonitor.isCharging || !systemMonitor.isBatteryPowered
            let base: String
            switch level {
            case 88...: base = "battery.100"
            case 63..<88: base = "battery.75"
            case 38..<63: base = "battery.50"
            case 13..<38: base = "battery.25"
            default: base = "battery.0"
            }
            return isPlugged ? "battery.100.bolt" : base
        }
        return baseName
    }
    
    private func getDefaultAnimation() -> String {
        switch utility {
        case .cpu: return "robot_ible"
        case .ram: return "RAM Animation"
        case .battery: return "doggie_running" // Running character for battery
        case .gpu: return "GPU isometric"
        case .disk: return "HDD Animation"
        case .network: return "hardware"
        default: return "hardware"
        }
    }
    
    private func getAnimationSpeed() -> Double {
        // Animation speed scales with usage:
        // Base speed 0.6 (normal) + up to 0.6 more based on usage
        // Low usage (0%) = 0.6 (normal)
        // High usage (100%) = 1.2 (fast)
        switch utility {
        case .cpu: 
            return 0.6 + (systemMonitor.cpuUsage / 100.0) * 0.6
        case .ram: 
            return 0.6 + (systemMonitor.ramUsage / 100.0) * 0.6
        case .gpu: 
            return 0.6 + (systemMonitor.gpuUsage / 100.0) * 0.6
        case .disk: 
            return 0.6 + (systemMonitor.diskUsage / 100.0) * 0.6
        case .battery:
            // Battery: 0.6 base + up to 0.4 based on level
            return 0.6 + (systemMonitor.batteryLevel) * 0.4
        case .network:
            return 0.7
        default: 
            return 0.7
        }
    }
    
    private func getValue() -> String {
        switch utility {
        case .cpu: return String(format: "%.0f%%", systemMonitor.cpuUsage)
        case .ram: return String(format: "%.0f%%", systemMonitor.ramUsage)
        case .battery:
            return String(format: "%.0f%%", systemMonitor.batteryLevel * 100)
        case .gpu: return String(format: "%.0f%%", systemMonitor.gpuUsage)
        case .disk: return String(format: "%.0f%%", systemMonitor.diskUsage)
        case .network: return NetworkNative.shared.downloadShort
        default: return "--"
        }
    }
}

