import SwiftUI
import Cocoa

// Shared instances accessible from AppDelegate
var sharedSystemMonitor: SystemMonitor?
var sharedSettingsManager: SettingsManager?

@main
struct CharBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We don't actually show any windows by default
        // Settings window is opened via menu bar
        Settings {
            EmptyView()
        }
    }
}
