import Cocoa

class MusicHoverMonitor {
    private weak var statusItem: NSStatusItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isMenuOpen = false
    private var hoverTimer: Timer?
    private var wasInside = false
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        // Global monitor for when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.checkHover()
        }
        
        // Local monitor for when app is focused  
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.checkHover()
            return event
        }
    }
    
    private func checkHover() {
        guard let button = statusItem?.button,
              let window = button.window,
              !isMenuOpen else { return }
        
        // Get global mouse location
        let mouseLocation = NSEvent.mouseLocation
        
        // Convert button frame to screen coordinates
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        
        // Expand hit area slightly for better UX
        let expandedFrame = buttonFrameOnScreen.insetBy(dx: -5, dy: -5)
        
        let isInside = expandedFrame.contains(mouseLocation)
        
        if isInside && !wasInside {
            // Just entered - start timer
            wasInside = true
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                self?.openMenu()
            }
        } else if !isInside && wasInside {
            // Just exited - cancel timer
            wasInside = false
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }
    
    private func openMenu() {
        guard let button = statusItem?.button,
              let action = button.action,
              let target = button.target,
              !isMenuOpen else { return }
        
        isMenuOpen = true
        
        // Trigger the button's action (opens menu centered)
        NSApp.sendAction(action, to: target, from: button)
        
        // Reset flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isMenuOpen = false
        }
    }
    
    deinit {
        hoverTimer?.invalidate()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
