import Cocoa
import SwiftUI

// This creates an expanding mini-menu from the status item
class SongChangeNotification {
    private var popover: NSPopover?
    private var dismissTimer: Timer?
    
    func show(title: String, artist: String, artwork: NSImage?, relativeTo statusItem: NSStatusItem?) {
        // Dismiss existing
        dismiss()
        
        guard let button = statusItem?.button else { return }
        
        // Create popover content
        let contentView = MiniSongView(title: title, artist: artist, artwork: artwork)
        let hostingController = NSHostingController(rootView: contentView)
        
        // Create popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 70)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        
        self.popover = popover
        
        // Show popover below status item
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Auto-dismiss after 2.5 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    /// Show notification relative to floating bar
    func showAtFloatingBar(title: String, artist: String, artwork: NSImage?, floatingBarFrame: NSRect) {
        // Dismiss existing
        dismiss()
        
        // Create popover content
        let contentView = MiniSongView(title: title, artist: artist, artwork: artwork)
        let hostingController = NSHostingController(rootView: contentView)
        
        // Create a panel instead of popover for floating bar
        let panelSize = NSSize(width: 280, height: 70)
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
        
        // Auto-dismiss after 2.5 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    private var notificationPanel: NSPanel?
    
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
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
        popover?.performClose(nil)
        popover = nil
    }
}

struct MiniSongView: View {
    let title: String
    let artist: String
    let artwork: NSImage?
    @State private var offset: CGFloat = 0
    @State private var scrollCount = 0
    
    var body: some View {
        HStack(spacing: 14) {
            // Album Artwork
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Scrolling title - clipped so it doesn't go over artwork
                ScrollingText(text: title, font: .system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .clipped() // Clip text that goes outside bounds
                
                Text(artist)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .clipped() // Clip the entire VStack
            
            Spacer()
            
            // Now Playing indicator
            Image(systemName: "waveform")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .symbolEffect(.variableColor.iterative.reversing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 280, height: 70)
    }
}

// Scrolling text component for long titles
struct ScrollingText: View {
    let text: String
    let font: Font
    @State private var offset: CGFloat = 0
    @State private var needsScrolling = false
    
    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false) // Allow text to be its natural width
                .offset(x: offset)
                .onAppear {
                    // Check if text needs scrolling
                    let textWidth = text.widthOfString(usingFont: NSFont.systemFont(ofSize: 13, weight: .semibold))
                    let containerWidth = geometry.size.width
                    
                    if textWidth > containerWidth {
                        needsScrolling = true
                        // Scroll 2 times with delays
                        scrollText(textWidth: textWidth, containerWidth: containerWidth)
                    }
                }
        }
        .frame(height: 18)
        .clipped() // IMPORTANT: Clip scrolling text to container bounds
    }
    
    private func scrollText(textWidth: CGFloat, containerWidth: CGFloat) {
        let scrollDistance = textWidth - containerWidth + 10
        
        // First scroll after 0.8s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.linear(duration: Double(scrollDistance / 25))) {
                offset = -scrollDistance
            }
            
            // Reset and scroll again after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(scrollDistance / 25) + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    offset = 0
                }
            }
        }
    }
}

