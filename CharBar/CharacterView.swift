import SwiftUI

struct CharacterView: View {
    let type: CharacterType
    let value: Double // 0.0 to 1.0
    let isConnected: Bool
    
    @State private var animationPhase: Double = 0.0
    
    var body: some View {
        // Use Lottie animations if available, otherwise fall back to emojis
        if type.hasLottieAnimation, let lottieFile = type.lottieFileName {
            LottieCharacterView(
                animationName: lottieFile,
                value: value,
                isConnected: isConnected,
                color: type.color
            )
        } else {
            // Emoji fallback
            ZStack {
                // Background glow
                Circle()
                    .fill(type.color.opacity(0.15))
                    .scaleEffect(0.7 + (0.3 * value))
                    .blur(radius: 3)
                
                // Main character
                Text(type.icon)
                    .font(.system(size: baseFontSize * scaleFactor))
                    .scaleEffect(scale)
                    .offset(x: xOffset, y: yOffset)
                    .shadow(color: type.color.opacity(0.6), radius: 3, x: 0, y: 2)
                    .opacity(opacity)
                
                // Status indicator
                if !isConnected {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 8))
                        .offset(x: 12, y: -12)
                }
            }
            .frame(width: 32, height: 32)
            .onAppear {
                startAnimation()
            }
        }
    }
    
    // MARK: - Animation Properties
    
    private var baseFontSize: CGFloat { 20 }
    
    private var scaleFactor: CGFloat {
        switch type.animationStyle {
        case .scale:
            // Character size changes with value (e.g., battery level)
            return 0.7 + (0.6 * value)
        default:
            return 1.0
        }
    }
    
    private var scale: CGFloat {
        switch type.animationStyle {
        case .pulse:
            // Breathing effect
            return 1.0 + (0.15 * value * sin(animationPhase * .pi * 2))
        case .flicker:
            return 1.0 + (0.1 * sin(animationPhase * .pi * 8))
        default:
            return 1.0
        }
    }
    
    private var xOffset: CGFloat {
        switch type.animationStyle {
        case .run:
            // Faster movement with higher values
            let speed = 1 + (value * 5)
            return sin(animationPhase * .pi * speed) * 8
        default:
            return 0
        }
    }
    
    private var yOffset: CGFloat {
        switch type.animationStyle {
        case .fly:
            // Height varies with value
            let baseOffset = sin(animationPhase * .pi * 2) * 5
            let valueOffset = -5 * value // Higher value = flies higher
            return baseOffset + valueOffset
        case .float:
            return sin(animationPhase * .pi * 1.5) * 6
        default:
            return 0
        }
    }
    
    private var opacity: Double {
        switch type.animationStyle {
        case .flicker:
            return 0.8 + (0.2 * abs(sin(animationPhase * .pi * 4)))
        default:
            return 1.0
        }
    }
    
    private var animationDuration: Double {
        // Animation speed based on value
        switch type.animationStyle {
        case .run, .fly:
            // Higher values = faster animation
            return max(0.3, 2.0 - (value * 1.5))
        case .pulse:
            return 2.0
        case .float:
            return 3.0
        case .flicker:
            return max(0.5, 2.0 - (value * 1.5))
        default:
            return 1.5
        }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: animationDuration).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
    }
}

// Menu Bar Label View - Shows Lottie animations directly
struct MenuBarCharactersView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    @ObservedObject var settingsManager: SettingsManager
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(settingsManager.enabledUtilities().prefix(5), id: \.0) { utility, config in
                if config.character.hasLottieAnimation, let lottieFile = config.character.lottieFileName {
                    LottieCharacterView(
                        animationName: lottieFile,
                        value: getValue(for: utility),
                        isConnected: getConnectionStatus(for: utility),
                        color: config.character.color
                    )
                    .frame(width: 28, height: 22)
                } else {
                    Text(config.character.icon)
                        .font(.system(size: 14))
                }
            }
            
            if settingsManager.enabledUtilities().isEmpty {
                Text("📊")
                    .font(.system(size: 14))
            }
        }
    }
    
    private func getValue(for utility: UtilityType) -> Double {
        switch utility {
        case .cpu: return systemMonitor.cpuUsage / 100.0
        case .gpu: return systemMonitor.gpuUsage / 100.0
        case .ram: return systemMonitor.ramUsage / 100.0
        case .battery: return systemMonitor.batteryLevel
        case .network:
            let total = systemMonitor.networkDownload + systemMonitor.networkUpload
            return min(total / (1024 * 1024), 1.0) // Normalize (1MB/s = max)
        case .bluetooth: return BluetoothManager.shared.connectedAudioDevice != nil ? 1.0 : 0.3
        case .disk: return systemMonitor.diskUsage / 100.0
        case .music: return 0.5 // Music handled separately by MediaObserver
        case .pomodoro: return PomodoroManager.shared.progress // Sand level for timer
        case .meetings:
            if let meeting = MeetingManager.shared.currentMeeting {
                return meeting.isHappeningNow || meeting.isStartingSoon ? 1.0 : 0.5
            }
            return 0.3
        case .toggles:
            return 0.5
        }
    }
    
    private func getConnectionStatus(for utility: UtilityType) -> Bool {
        switch utility {
        case .battery: return systemMonitor.isCharging
        case .network: return systemMonitor.wifiStrength > 0.1 // Use WiFi signal as connection indicator
        case .bluetooth: return BluetoothManager.shared.connectedAudioDevice != nil
        case .music: return true // Music handled by MediaObserver
        case .meetings: return MeetingManager.shared.currentMeeting != nil
        case .toggles: return true // System toggles always available
        default: return true
        }
    }
}
