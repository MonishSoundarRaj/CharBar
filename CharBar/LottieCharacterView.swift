import SwiftUI
import Lottie

struct LottieCharacterView: View {
    let animationName: String
    let value: Double // 0.0 to 1.0
    let isConnected: Bool
    let color: Color
    
    @State private var isPlaying: Bool = true
    
    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(color.opacity(0.15))
                .scaleEffect(0.7 + (0.3 * value))
                .blur(radius: 3)
            
            // Lottie Animation - Load from bundle
            if let animation = loadAnimation() {
                LottieView(animation: animation)
                    .playing(loopMode: .loop)
                    .animationSpeed(animationSpeed)
                    .frame(width: 32, height: 32)
            } else {
                // Fallback to text if animation doesn't load
                Text("⚠️")
                    .font(.system(size: 20))
            }
            
            // Status indicator
            if !isConnected {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 8))
                    .offset(x: 12, y: -12)
            }
        }
        .frame(width: 32, height: 32)
    }
    
    private func loadAnimation() -> LottieAnimation? {
        // Try multiple ways to load the animation
        
        // Method 1: Try loading by name from bundle
        if let animation = LottieAnimation.named(animationName) {
            return animation
        }
        
        // Method 2: Try finding the file in the bundle
        if let path = Bundle.main.path(forResource: animationName, ofType: "json"),
           let animation = LottieAnimation.filepath(path) {
            return animation
        }
        
        // Method 3: Try in Animations folder
        if let path = Bundle.main.path(forResource: animationName, ofType: "json", inDirectory: "Animations"),
           let animation = LottieAnimation.filepath(path) {
            return animation
        }
        
        return nil
    }
    
    private var animationSpeed: Double {
        // Slow at 0% usage, fast at 100%
        return 0.3 + (value * 2.0) // Range: 0.3x to 2.3x speed
    }
}

// MARK: - NSViewRepresentable wrapper for FloatingBar (uses AppKit like menu bar)

struct LottieAnimationNSView: NSViewRepresentable {
    let animationName: String
    var speed: Double = 1.0
    var loopMode: LottieLoopMode = .loop
    
    func makeNSView(context: Context) -> NSView {
        // Create a container view to properly constrain the animation
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        
        let animationView = LottieAnimationView(name: animationName)
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = loopMode
        animationView.animationSpeed = CGFloat(speed)
        animationView.backgroundBehavior = .pauseAndRestore
        
        // Make background transparent
        animationView.wantsLayer = true
        animationView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Add animation view to container with constraints
        animationView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(animationView)
        
        NSLayoutConstraint.activate([
            animationView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            animationView.widthAnchor.constraint(equalTo: container.widthAnchor),
            animationView.heightAnchor.constraint(equalTo: container.heightAnchor)
        ])
        
        animationView.play()
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Find the animation view inside container
        guard let animationView = nsView.subviews.first as? LottieAnimationView else { return }
        
        animationView.animationSpeed = CGFloat(speed)
        
        // Ensure it's playing
        if !animationView.isAnimationPlaying {
            animationView.play()
        }
    }
}

// Extension to map CharacterType to Lottie animation filenames
// IMPORTANT: Filenames must match exactly (case-sensitive) with files in Animations folder
extension CharacterType {
    var lottieFileName: String? {
        switch self {
        // Static icons - no Lottie animation
        case .staticCPU, .staticGPU, .staticRAM, .staticBattery, .staticNetwork,
             .staticBluetooth, .staticDisk, .staticMusic, .staticPomodoro,
             .staticPomodoroHourglass, .staticMeetings:
            return nil
            
        // Classic characters
        case .cat: return "cat_resting_withtail"
        case .vampire: return "bat_flying"
        case .bird: return "bat_flying"
        case .robot: return "robot_running"
        case .runner: return "doggie_running"
        case .ghost: return "amongus_running"
        case .dragon: return "fire_flame"
        case .rocket: return "something_running"
        case .fire: return "fire_flame"
        case .lightning: return "fire_flame"
        case .hourglass: return "timer"
        
        // Connectivity
        case .bluetoothWave: return "bluetooth"
        case .bluetoothIcon: return "Bluetooth icon Lottie JSON animation"
        case .bluetoothThree: return "Bluetooth_3"
        case .airpods: return "airpods"
        case .headphones: return "headphones"
        case .dynoDancing: return "dyno_dancing_with_headphones"
        
        // Productivity
        case .calendar: return "Calendar"
        case .typingCat: return "Blue Working Cat Animation"
        case .typingHands: return "Hands typing on keyboard"
        case .cartoonTyping: return "cartoon_typing"
        case .sleepingCat: return "Cat is sleeping and rolling"
        case .restingCat: return "cat_resting_withtail"
        
        // Music
        case .musicMonster: return "Music Monster"
        case .technoPenguin: return "Techno Penguin"
        case .music: return "music"
        case .musicTwo: return "music_two"
        case .musicThree: return "music_three"
        
        // Hardware
        case .hddAnimation: return "HDD Animation"
        case .gpuIsometric: return "GPU isometric"
        case .ramAnimation: return "RAM Animation"
        case .hardware: return "hardware"
        
        // System / Activity
        case .robotIdle: return "robot_ible"
        case .dogRunning: return "doggie_running"
        case .somethingRunning: return "something_running"
        case .amongusRunning: return "amongus_running"
        case .batteryCharging: return "Battery Charging - Plugin_Green"
        }
    }
    
    var hasLottieAnimation: Bool {
        // Static icons don't have Lottie animations
        return !isStaticIcon
    }
}
