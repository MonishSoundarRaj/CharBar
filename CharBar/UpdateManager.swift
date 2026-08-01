//
//  UpdateManager.swift
//  CharBar
//
//  Auto-update system powered by Sparkle (https://sparkle-project.org)
//

import SwiftUI
import Combine
import Sparkle

// MARK: - Update Manager (Sparkle Wrapper)
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    
    var updater: SPUUpdater {
        updaterController.updater
    }
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

// MARK: - Update Settings View (for Settings window)
struct UpdateSettingsView: View {
    @ObservedObject var updateManager = UpdateManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Current Version:")
                    .foregroundColor(.secondary)
                Text("\(updateManager.currentVersion) (\(updateManager.currentBuildNumber))")
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: { updateManager.checkForUpdates() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Check for Updates")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .disabled(!updateManager.canCheckForUpdates)
            }
            
            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { updateManager.updater.automaticallyChecksForUpdates },
                    set: { updateManager.updater.automaticallyChecksForUpdates = $0 }
                )
            )
            .toggleStyle(.switch)
            .tint(Color.gray)
            
            Toggle(
                "Auto-download updates when available",
                isOn: Binding(
                    get: { updateManager.updater.automaticallyDownloadsUpdates },
                    set: { updateManager.updater.automaticallyDownloadsUpdates = $0 }
                )
            )
            .toggleStyle(.switch)
            .tint(Color.gray)
            
            if let lastCheck = updateManager.updater.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
