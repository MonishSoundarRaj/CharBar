//
//  DisplayModeSettingsView.swift
//  CharBar
//
//  Settings UI for Display Mode configuration
//

import SwiftUI

// Preference key for scroll offset tracking
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DisplayModeSettingsView: View {
    @ObservedObject var modeManager = AppModeManager.shared
    @ObservedObject var screenObserver = ScreenObserver.shared
    @ObservedObject var floatingMenuBar = FloatingMenuBarController.shared
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Spacer for header
                    Color.clear.frame(height: 56)
                    
                    // Current Status
                    DarkCard {
                        HStack {
                            Image(systemName: screenObserver.hasExternalDisplay ? "display.2" : "laptopcomputer")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                            Text(screenObserver.hasExternalDisplay 
                                 ? "\(screenObserver.screenCount) displays"
                                 : "Built-in only")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                            Text(modeManager.activeState.isFloating ? "Floating" : "Menu Bar")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    
                    // Mode Selection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mode")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        VStack(spacing: 8) {
                            ForEach(AppDisplayMode.allCases, id: \.self) { mode in
                                DarkModeOption(
                                    title: mode.displayName,
                                    isSelected: modeManager.preferredMode == mode,
                                    action: { modeManager.preferredMode = mode }
                                )
                            }
                        }
                    }
                    
                    // Temporary static mode indicator
                    if modeManager.isTemporaryStaticMode {
                        DarkCard {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                                Text("Animations temporarily replaced with static icons on all displays")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    
                    // // Floating Bar Settings (if active)
                    // if modeManager.shouldUseFloatingBar {
                    //     VStack(alignment: .leading, spacing: 10) {
                    //         Text("Floating Bar")
                    //             .font(.system(size: 12, weight: .medium))
                    //             .foregroundColor(.white.opacity(0.5))
                            
                    //         DarkCard {
                    //             HStack {
                    //                 Text("Follow active screen")
                    //                     .font(.system(size: 13))
                    //                     .foregroundColor(.white.opacity(0.7))
                    //                 Spacer()
                    //                 Toggle("", isOn: $floatingMenuBar.followsActiveScreen)
                    //                     .labelsHidden()
                    //                     .toggleStyle(.switch)
                    //                     .tint(Color.gray)
                    //             }
                    //         }
                    //     }
                    // }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: -geo.frame(in: .named("scroll")).minY)
                })
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
            .coordinateSpace(name: "scroll")
            
            // Frosted glass header overlay
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white)
                    }
                    Text("Display Mode")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .opacity(scrollOffset > 10 ? 1 : 0)
                )
                .background(
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(scrollOffset > 10 ? 0.7 : 0)
                )
                
                // Subtle separator when scrolled
                Rectangle()
                    .fill(Color.white.opacity(scrollOffset > 10 ? 0.1 : 0))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Dark UI Components
struct DarkCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(14)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
    }
}

struct DarkModeOption: View {
    let title: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isDisabled ? .white.opacity(0.3) : .white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(14)
            .background(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.04))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// Legacy compatibility
struct ModeOptionRow: View {
    let mode: AppDisplayMode
    let isSelected: Bool
    var isDisabled: Bool = false
    var disabledReason: String? = nil
    let action: () -> Void
    
    var body: some View {
        DarkModeOption(title: mode.displayName, isSelected: isSelected, isDisabled: isDisabled, action: action)
    }
}
