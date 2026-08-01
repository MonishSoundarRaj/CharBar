//
//  FloatingCalendarController.swift
//  CharBar
//
//  Pop-out Calendar Window - Modern Apple-style floating calendar
//

import SwiftUI
import AppKit
import EventKit
import Combine

// MARK: - Floating Calendar Controller
class FloatingCalendarController: ObservableObject {
    static let shared = FloatingCalendarController()
    
    private var window: NSWindow?
    @Published var isVisible: Bool = false
    
    private init() {}
    
    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isVisible = true
            return
        }
        
        let contentView = FloatingCalendarView()
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        
        // Round the NSPanel content view layer so AppKit doesn't draw square corners
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.cornerCurve = .continuous
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            let x = screenRect.midX - windowRect.width / 2
            let y = screenRect.midY - windowRect.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.delegate = WindowDelegate(onClose: { [weak self] in
            self?.isVisible = false
        })
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }
    
    func hide() {
        window?.close()
        window = nil
        isVisible = false
    }
    
    func toggle() {
        isVisible ? hide() : show()
    }
    
    private class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

// MARK: - Floating Calendar View (uses same MeetingMenuView as dropdown)
struct FloatingCalendarView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle + close button
            HStack {
                Spacer()
                
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 36, height: 5)
                
                Spacer()
                
                Button(action: { FloatingCalendarController.shared.hide() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary, Color.primary.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            
            // Reuse the exact same MeetingMenuView from the dropdown (popout mode)
            MeetingMenuView(isPopout: true)
        }
        .frame(width: 380)
        .background(
            ZStack {
                CalendarBlurView()
                Color(colorScheme == .dark ? .black : .white)
                    .opacity(colorScheme == .dark ? 0.6 : 0.8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 25, y: 10)
    }
}


// MARK: - Blur View
struct CalendarBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        // Round corners to match the SwiftUI clipShape so the blur
        // doesn't bleed past the rounded rectangle bounds
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
