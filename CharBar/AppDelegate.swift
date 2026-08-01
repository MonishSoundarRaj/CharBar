import Cocoa
import SwiftUI
import Lottie
import Combine
import UserNotifications

// Custom views that pass through mouse events to parent (for hover to work)
class MousePassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to pass through mouse events to parent
        return nil
    }
}

class MousePassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to pass through mouse events to parent
        return nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    // Support multiple status items - one per utility
    // view can be LottieAnimationView OR AudioSpectrum
    var statusItems: [(item: NSStatusItem, view: NSView, utility: UtilityType)] = []
    
    // Track if meeting is in "Join Mode" (transforms into clickable button)
    var meetingInJoinMode = false
    
    // Settings window controller (needs to be retained)
    var settingsWindow: SettingsWindowController?
    var welcomeWindow: NSWindow?
    
    var systemMonitor: SystemMonitor!
    var settingsManager: SettingsManager!
    var mediaObserver: MediaObserver!
    var pomodoroManager: PomodoroManager!
    var bluetoothManager: BluetoothManager!
    var meetingManager: MeetingManager!
    
    private var cancellables = Set<AnyCancellable>()
    private var songNotification = SongChangeNotification()
    private var pomodoroNotification = PomodoroNotification()
    private var lastSongTitle: String = ""
    private var startupTime: Date = Date()
    private var pendingNotificationWorkItem: DispatchWorkItem?
    
    // Debounce work item for settings changes to prevent rapid status item recreation
    private var settingsChangeWorkItem: DispatchWorkItem?
    private var isUpdatingStatusItems = false
    
    // Debounce work item for updateMusicDisplay to coalesce rapid publisher firings
    private var musicDisplayWorkItem: DispatchWorkItem?
    
    // Rolling timer view for Pomodoro (Apple-style odometer animation)
    private var pomodoroTimerView: RollingTimerView?
    // Rolling timer view for Meetings countdown (same style as Pomodoro)
    private var meetingTimerView: RollingTimerView?
    private var meetingUpdateTimer: Timer?
    // Saved button image/position before entering join mode so we can restore on exit
    private var meetingJoinSavedImage: NSImage? = nil
    private var meetingJoinSavedImagePosition: NSButton.ImagePosition = .imageLeft
    
    // Timer for updating Pomodoro animation progress in menu bar
    private var pomodoroAnimationTimer: Timer?
    
    // Global shortcut manager for all utilities
    private var shortcutManager: ShortcutManager?
    
    // Dual-mode: Screen observer and mode manager
    private var modeManager: AppModeManager?
    private var modeSwitcher: ModeSwitcher?
    
    // MARK: - Crash Recovery
    
    private static let crashSentinelPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("CharBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".crashed").path
    }()
    
    /// `~/Library/Logs/CharBar/` — crash logs are written here on uncaught exceptions.
    static let crashLogDirectory: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Logs/CharBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func setupCrashHandlers() {
        let writeSentinelAndExit: @convention(c) (Int32) -> Void = { sig in
            FileManager.default.createFile(atPath: AppDelegate.crashSentinelPath, contents: Data(), attributes: nil)
            signal(sig, SIG_DFL)
            raise(sig)
        }
        signal(SIGABRT, writeSentinelAndExit)
        signal(SIGSEGV, writeSentinelAndExit)
        signal(SIGBUS,  writeSentinelAndExit)
        signal(SIGILL,  writeSentinelAndExit)
        signal(SIGFPE,  writeSentinelAndExit)

        // Uncaught Obj-C / Swift exceptions: write a full log + sentinel.
        // (Safe to call Swift runtime here; signal handlers must stay minimal.)
        NSSetUncaughtExceptionHandler { exception in
            FileManager.default.createFile(atPath: AppDelegate.crashSentinelPath, contents: Data(), attributes: nil)
            AppDelegate.writeCrashLog(exception: exception)
        }

        atexit {
            try? FileManager.default.removeItem(atPath: AppDelegate.crashSentinelPath)
        }
    }

    /// Persist a crash log next to the sentinel so the user can attach it to a support email.
    private static func writeCrashLog(exception: NSException) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date())
        let safeStamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let logURL = crashLogDirectory.appendingPathComponent("crash-\(safeStamp).log")

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os      = ProcessInfo.processInfo.operatingSystemVersionString

        var body = """
        CharBar crash report
        --------------------
        Timestamp : \(timestamp)
        App       : \(version) (build \(build))
        macOS     : \(os)

        Exception : \(exception.name.rawValue)
        Reason    : \(exception.reason ?? "(none)")
        UserInfo  : \(exception.userInfo ?? [:])

        Call stack:
        """
        for line in exception.callStackSymbols {
            body += "\n  \(line)"
        }
        try? body.write(to: logURL, atomically: true, encoding: .utf8)
    }
    
    private func checkForPreviousCrash() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.crashSentinelPath) else { return }
        try? fm.removeItem(atPath: Self.crashSentinelPath)
        
        DispatchQueue.main.async {
            self.showCrashRecoveryPanel()
        }
    }
    
    private func showCrashRecoveryPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        
        let crashView = NSHostingView(rootView: CrashRecoveryView(
            onContinue: { [weak panel] in
                panel?.orderOut(nil)
            },
            onRestart: { [weak panel] in
                panel?.orderOut(nil)
                let url = URL(fileURLWithPath: Bundle.main.bundlePath)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApp.terminate(nil)
                    }
                }
            }
        ))
        
        panel.contentView = crashView
        
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 190
            let y = screenFrame.minY + 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)
        
        // Setup crash detection and check for previous crash
        setupCrashHandlers()
        checkForPreviousCrash()
        
        // DON'T request accessibility permissions on startup
        // Only request when user enables a shortcut
        
        // Initialize system monitor and settings
        systemMonitor = SystemMonitor()
        settingsManager = SettingsManager()
        mediaObserver = MediaObserver.shared  // Use shared instance for floating bar
        pomodoroManager = PomodoroManager.shared
        bluetoothManager = BluetoothManager.shared
        meetingManager = MeetingManager.shared
        
        // Configure floating player controller with media observer
        FloatingPlayerController.shared.configure(with: mediaObserver)
        
        // Initialize dual-mode system (screen observer + mode switcher)
        modeManager = AppModeManager.shared
        modeSwitcher = ModeSwitcher.shared
        modeSwitcher?.appDelegate = self
        
        // Listen for mode change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRestoreMenuBarAnimations),
            name: NSNotification.Name("RestoreMenuBarAnimations"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUseStaticMenuBarIcon),
            name: NSNotification.Name("UseStaticMenuBarIcon"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForceStaticMenuBarIcons),
            name: NSNotification.Name("ForceStaticMenuBarIcons"),
            object: nil
        )
        
        // Rebuild status items after system wake — macOS can drop NSStatusItem buttons on sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Connect meeting manager to get status item for notifications
        meetingManager.getStatusItem = { [weak self] in
            return self?.statusItems.first(where: { $0.utility == .meetings })?.item
        }
        
        // React immediately when calendar access state changes (exclamation -> checkmark)
        meetingManager.$accessState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMeetingDisplay()
                self?.scheduleMeetingUpdate()
            }
            .store(in: &cancellables)
        
        // Start system monitoring (CPU, RAM, Battery, Network, etc.)
        systemMonitor.startMonitoring()
        
        // Store globally for Settings window
        sharedSystemMonitor = systemMonitor
        sharedSettingsManager = settingsManager
        
        // Setup global keyboard shortcuts
        setupGlobalShortcuts()
        
        // Setup menu bar
        setupMenuBar()
        
        // Update animation speed based on metrics (every 2 seconds)
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateAnimationSpeed()
        }
        
        // Update network speed display faster (every 1 second)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshNetworkSpeed()
        }
        
        // Show premium onboarding on first launch; otherwise open settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
                self.openSettings()
            } else {
                self.showWelcomeWindow()
            }
        }
        
        // Sparkle handles update checks automatically on launch via SPUStandardUpdaterController
        _ = UpdateManager.shared
        
        // Subscribe to media changes for immediate updates
        mediaObserver.$title
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTitle in
                guard let self = self else { return }
                
                // Skip notifications during first 3 seconds (startup)
                let timeSinceStartup = Date().timeIntervalSince(self.startupTime)
                if timeSinceStartup < 3.0 {
                    self.lastSongTitle = newTitle
                    self.scheduleMusicDisplayUpdate()
                    return
                }
                
                // Show notification if song changed (debounced to prevent duplicates)
                if !newTitle.isEmpty && newTitle != "Not Playing" && newTitle != self.lastSongTitle {
                    self.lastSongTitle = newTitle
                    
                    // Only show notification if user hasn't disabled it AND music utility is enabled
                    let showNotification = UserDefaults.standard.object(forKey: "music_showChangeNotification") as? Bool ?? true
                    let musicEnabled = self.settingsManager.configurations[.music]?.isEnabled == true
                    if showNotification && musicEnabled {
                        // Cancel any pending notification
                        self.pendingNotificationWorkItem?.cancel()
                        
                        // Create debounced notification
                        let workItem = DispatchWorkItem { [weak self] in
                            guard let self = self else { return }
                            
                            // Check if floating bar is visible - show notification relative to it
                            if FloatingMenuBarController.shared.isVisible {
                                self.songNotification.showAtFloatingBar(
                                    title: self.mediaObserver.title,
                                    artist: self.mediaObserver.artist,
                                    artwork: self.mediaObserver.artworkImage,
                                    floatingBarFrame: FloatingMenuBarController.shared.floatingBarFrame
                                )
                            } else {
                                // Find the music status item
                                let musicStatusItem = self.statusItems.first(where: { $0.utility == .music })?.item
                                
                                self.songNotification.show(
                                    title: self.mediaObserver.title,
                                    artist: self.mediaObserver.artist,
                                    artwork: self.mediaObserver.artworkImage,
                                    relativeTo: musicStatusItem
                                )
                            }
                        }
                        self.pendingNotificationWorkItem = workItem
                        
                        // Delay notification to ensure artwork loads and prevent rapid duplicates
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
                    }
                }
                
                self.scheduleMusicDisplayUpdate()
            }
            .store(in: &cancellables)
            
        mediaObserver.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleMusicDisplayUpdate()
            }
            .store(in: &cancellables)
            
        mediaObserver.$artworkImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleMusicDisplayUpdate()
            }
            .store(in: &cancellables)
        
        // Subscribe to Pomodoro updates for timer display
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePomodoroDisplay),
            name: NSNotification.Name("PomodoroTick"),
            object: nil
        )
        
        // Meeting countdown timer - adaptive interval
        scheduleMeetingUpdate()
        
        // Subscribe to global hotkey refresh notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyRefresh),
            name: NSNotification.Name("RefreshGlobalHotkey"),
            object: nil
        )
        
        // Subscribe to Pomodoro state changes for immediate UI update
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePomodoroStateChange),
            name: NSNotification.Name("PomodoroStateChanged"),
            object: nil
        )
        
        // Subscribe to Pomodoro timer completion for popup notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePomodoroComplete(_:)),
            name: NSNotification.Name("PomodoroTimerComplete"),
            object: nil
        )
        
        // Subscribe to Bluetooth device changes for dynamic animation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBluetoothChange),
            name: NSNotification.Name("BluetoothDevicesChanged"),
            object: nil
        )
        
        // Subscribe to OpenSettings notification from floating panels
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: NSNotification.Name("OpenSettings"),
            object: nil
        )
    }
    
    @objc func handleBluetoothChange() {
        // Update Bluetooth menu bar item animation based on connected audio device
        updateBluetoothAnimation()
    }
    
    func updateBluetoothAnimation() {
        guard let config = settingsManager.configurations[.bluetooth], config.isEnabled else { return }
        
        for (index, entry) in statusItems.enumerated() {
            if entry.utility == .bluetooth {
                let button = entry.item.button
                
                if let audioDevice = bluetoothManager.connectedAudioDevice {
                    // CONNECTED: Fixed compact width - same as disconnected
                    entry.item.length = 24
                    
                    // Get correct animation for device type
                    let animationName = bluetoothManager.currentMenuBarAnimation
                    
                    if let animationView = entry.view as? LottieAnimationView {
                        // Load the correct animation (headphones or airpods)
                        if let animation = LottieAnimation.named(animationName) {
                            animationView.animation = animation
                            animationView.loopMode = .loop
                            animationView.play()
                        }
                        
                        // Make sure animation is visible
                        if animationView.superview == nil, let btn = button {
                            let spacer = NSImage(size: NSSize(width: 24, height: 22))
                            spacer.lockFocus()
                            NSColor.clear.set()
                            NSRect(origin: .zero, size: spacer.size).fill()
                            spacer.unlockFocus()
                            btn.image = spacer
                            btn.imagePosition = .imageLeft
                            
                            animationView.translatesAutoresizingMaskIntoConstraints = false
                            animationView.wantsLayer = true
                            btn.addSubview(animationView)
                            
                            let animSize = config.character.menuBarAnimationSize
                            NSLayoutConstraint.activate([
                                animationView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                                animationView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                                animationView.widthAnchor.constraint(equalToConstant: animSize.width),
                                animationView.heightAnchor.constraint(equalToConstant: animSize.height)
                            ])
                        }
                    }
                    
                    // No battery display (coming soon)
                    button?.title = ""
                    
                } else {
                    // DISCONNECTED: Show user's selected default character animation
                    entry.item.length = 24
                    
                    if let animationView = entry.view as? LottieAnimationView, let btn = button {
                        // Load the user's selected default animation (from config.character)
                        let defaultAnimationName = config.character.lottieFileName ?? "bluetooth"
                        if let animation = LottieAnimation.named(defaultAnimationName) {
                            animationView.animation = animation
                            animationView.loopMode = .loop
                            animationView.play()
                        }
                        
                        // Use unified size from CharacterType
                        let animSize = config.character.menuBarAnimationSize
                        
                        // Make sure animation is visible
                        if animationView.superview == nil {
                            let spacer = NSImage(size: NSSize(width: min(animSize.width, 24), height: 22))
                            spacer.lockFocus()
                            NSColor.clear.set()
                            NSRect(origin: .zero, size: spacer.size).fill()
                            spacer.unlockFocus()
                            btn.image = spacer
                            btn.imagePosition = .imageOnly
                            
                            animationView.translatesAutoresizingMaskIntoConstraints = false
                            animationView.wantsLayer = true
                            btn.addSubview(animationView)
                            
                            NSLayoutConstraint.activate([
                                animationView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                                animationView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                                animationView.widthAnchor.constraint(equalToConstant: animSize.width),
                                animationView.heightAnchor.constraint(equalToConstant: animSize.height)
                            ])
                        }
                        
                        btn.title = ""
                    }
                }
            }
        }
    }
    
    /// Unified width calculation for Pomodoro status item
    private func pomodoroWidths() -> (running: CGFloat, idle: CGFloat, timerLeading: CGFloat, timerWidth: CGFloat, isStatic: Bool, showTimer: Bool) {
        let config = settingsManager.configurations[.pomodoro]
        let showTimer = (config?.displayOption != DisplayOption.none) && (config?.displayOption != nil)
        
        // Determine if static icon — use resting character during break states so width matches the
        // animation that PomodoroManager.currentMenuBarAnimation will display.
        let isResting = pomodoroManager?.isRestingState ?? false
        let activeChar: String = isResting
            ? (UserDefaults.standard.string(forKey: "pomo_restingCharacter") ?? "sleepingCat")
            : (UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass")
        var isStatic = config?.character.isStaticIcon ?? false
        if let charType = CharacterType(rawValue: activeChar) {
            isStatic = charType.isStaticIcon
        }
        if AppModeManager.shared.isTemporaryStaticMode { isStatic = true }
        
        if isStatic {
            // Static: pad(2) + icon(16) + gap(6) + timer(38) + pad(2)
            let timerW: CGFloat = 38
            let timerLead: CGFloat = 24 // 2 + 16 + 6
            let runW: CGFloat = showTimer ? timerLead + timerW + 2 : 24
            return (running: runW, idle: 24, timerLeading: timerLead, timerWidth: timerW, isStatic: true, showTimer: showTimer)
        } else {
            // Lottie: use actual animation size
            let animSize = CharacterType(rawValue: activeChar)?.menuBarAnimationSize ?? CGSize(width: 24, height: 24)
            let timerW: CGFloat = 44
            let timerLead: CGFloat = 4 + animSize.width + 8 // pad + anim + gap
            let runW: CGFloat = showTimer ? timerLead + timerW + 4 : animSize.width + 8
            let idleW: CGFloat = animSize.width + 8
            return (running: runW, idle: idleW, timerLeading: timerLead, timerWidth: timerW, isStatic: false, showTimer: showTimer)
        }
    }
    
    /// Unified width calculation for Meetings status item (mirrors pomodoroWidths)
    private func meetingWidths() -> (withTimer: CGFloat, idle: CGFloat, timerLeading: CGFloat, timerWidth: CGFloat, isStatic: Bool, showTimer: Bool) {
        let config = settingsManager.configurations[.meetings]
        let showTimer = (config?.displayOption != DisplayOption.none) && (config?.displayOption != nil)
        var isStatic = config?.character.isStaticIcon ?? false
        if AppModeManager.shared.isTemporaryStaticMode { isStatic = true }
        
        if isStatic {
            let timerW: CGFloat = 38
            let timerLead: CGFloat = 28  // 1 + 20 + 7  (icon lead + icon width + gap)
            let withTimerW: CGFloat = showTimer ? timerLead + timerW + 2 : 26
            return (withTimer: withTimerW, idle: 26, timerLeading: timerLead, timerWidth: timerW, isStatic: true, showTimer: showTimer)
        } else {
            let animSize = config?.character.menuBarAnimationSize ?? CGSize(width: 24, height: 24)
            let timerW: CGFloat = 44
            let timerLead: CGFloat = 4 + animSize.width + 10
            let withTimerW: CGFloat = showTimer ? timerLead + timerW + 4 : animSize.width + 8
            let idleW: CGFloat = animSize.width + 8
            return (withTimer: withTimerW, idle: idleW, timerLeading: timerLead, timerWidth: timerW, isStatic: false, showTimer: showTimer)
        }
    }
    
    @objc func handlePomodoroStateChange() {
        guard let entry = statusItems.first(where: { $0.utility == .pomodoro }),
              let button = entry.item.button else {
            if pomodoroManager.isRunning { startPomodoroAnimationTimer() } else { stopPomodoroAnimationTimer() }
            return
        }
        
        let statusItem = entry.item
        let w = pomodoroWidths()
        
        if pomodoroManager.isRunning {
            statusItem.length = w.showTimer ? w.running : (w.isStatic ? 24 : w.idle)
            
            if pomodoroTimerView == nil && w.showTimer {
                let timerView = RollingTimerView(frame: NSRect(x: 0, y: 0, width: w.timerWidth, height: 18))
                timerView.translatesAutoresizingMaskIntoConstraints = false
                timerView.wantsLayer = true
                button.addSubview(timerView)
                
                NSLayoutConstraint.activate([
                    timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: w.timerLeading),
                    timerView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    timerView.widthAnchor.constraint(equalToConstant: w.timerWidth),
                    timerView.heightAnchor.constraint(equalToConstant: 18)
                ])
                
                pomodoroTimerView = timerView
            }
            
            if let timerView = pomodoroTimerView {
                let totalSeconds = Int(pomodoroManager.timeRemaining)
                timerView.updateFromSeconds(totalSeconds, animated: false)
                timerView.isHidden = !w.showTimer
            }
            
            if let animationView = entry.view as? LottieAnimationView {
                // Swap animation to match work/break state
                let animName = pomodoroManager.currentMenuBarAnimation
                if let newAnim = LottieAnimation.named(animName) {
                    animationView.animation = newAnim
                }
                animationView.currentProgress = pomodoroManager.sandProgress
            }
        } else {
            statusItem.length = w.idle
            
            if let timerView = pomodoroTimerView {
                timerView.removeFromSuperview()
                pomodoroTimerView = nil
            }
            
            if let animationView = entry.view as? LottieAnimationView {
                // Reset to working character when idle
                let animName = pomodoroManager.currentMenuBarAnimation
                if let newAnim = LottieAnimation.named(animName) {
                    animationView.animation = newAnim
                }
                animationView.currentProgress = 0.0
            }
        }
        
        if pomodoroManager.isRunning {
            startPomodoroAnimationTimer()
        } else {
            stopPomodoroAnimationTimer()
        }
    }
    
    private func startPomodoroAnimationTimer() {
        pomodoroAnimationTimer?.invalidate()
        pomodoroAnimationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePomodoroAnimationProgress()
        }
    }
    
    private func stopPomodoroAnimationTimer() {
        pomodoroAnimationTimer?.invalidate()
        pomodoroAnimationTimer = nil
    }
    
    private func updatePomodoroAnimationProgress() {
        guard let entry = statusItems.first(where: { $0.utility == .pomodoro }),
              let animationView = entry.view as? LottieAnimationView else { return }
        
        // Update animation progress based on sandProgress (0 = full, 1 = empty)
        let progress = pomodoroManager.sandProgress
        animationView.currentProgress = progress
        animationView.forceDisplayUpdate()
    }
    
    private var systemStatAnimationTimer: Timer?
    
    private func startSystemStatAnimationTimer() {
        // Update animation speeds every 5 seconds based on system usage
        systemStatAnimationTimer?.invalidate()
        systemStatAnimationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateSystemStatAnimationSpeeds()
        }
    }
    
    private func updateSystemStatAnimationSpeeds() {
        // Update animation speeds for all system stat utilities based on current usage
        for entry in statusItems {
            guard let animationView = entry.view as? LottieAnimationView else { continue }
            
            switch entry.utility {
            case .cpu:
                animationView.animationSpeed = 0.6 + (systemMonitor.cpuUsage / 100.0) * 0.6
            case .ram:
                animationView.animationSpeed = 0.6 + (systemMonitor.ramUsage / 100.0) * 0.6
            case .gpu:
                animationView.animationSpeed = 0.6 + (systemMonitor.gpuUsage / 100.0) * 0.6
            case .disk:
                animationView.animationSpeed = 0.6 + (systemMonitor.diskUsage / 100.0) * 0.6
            case .battery:
                animationView.animationSpeed = 0.6 + (systemMonitor.batteryLevel) * 0.4
            default:
                break
            }
        }
    }
    
    @objc func handlePomodoroComplete(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let title = userInfo["title"] as? String,
              let body = userInfo["body"] as? String,
              let state = userInfo["state"] as? String else { return }
        
        // Check if floating bar is visible - show notification relative to it
        if FloatingMenuBarController.shared.isVisible {
            pomodoroNotification.showAtFloatingBar(
                title: title,
                body: body,
                state: state,
                floatingBarFrame: FloatingMenuBarController.shared.floatingBarFrame
            )
        } else {
        // Find the pomodoro status item
        let pomodoroStatusItem = statusItems.first(where: { $0.utility == .pomodoro })?.item
        
        // Show popup notification
        pomodoroNotification.show(
            title: title,
            body: body,
            state: state,
            relativeTo: pomodoroStatusItem
        )
        }
    }
    
    @objc func updatePomodoroDisplay() {
        if let timerView = pomodoroTimerView {
            if pomodoroManager.isRunning {
                let totalSeconds = Int(pomodoroManager.timeRemaining)
                timerView.updateFromSeconds(totalSeconds, animated: false)
            } else {
                timerView.showIdle()
            }
            // Force redraw on button so all screens get the update
            timerView.needsDisplay = true
            if let entry = statusItems.first(where: { $0.utility == .pomodoro }) {
                entry.item.button?.needsDisplay = true
            }
        }
    }
    
    // MARK: - Meeting Adaptive Timer
    
    private func scheduleMeetingUpdate() {
        meetingUpdateTimer?.invalidate()
        let interval: TimeInterval
        if let meeting = meetingManager.displayMeeting {
            let t = meeting.timeUntilStart
            let state = meetingManager.menuBarState
            if state == .countdown || state == .action || meeting.isHappeningNow || t <= 60 {
                // 1s updates whenever the timer or join button is visible
                interval = 1.0
            } else {
                // Poll every 5s when within 2 minutes of the countdown threshold so we
                // catch the .upcoming → .countdown transition quickly (no 30s lag)
                let countdownThreshold = Double(meetingManager.countdownMinutes * 60)
                if t <= countdownThreshold + 120 {
                    interval = 5.0
                } else {
                    interval = 30.0
                }
            }
        } else {
            interval = 30.0
        }
        meetingUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMeetingDisplay()
                self?.scheduleMeetingUpdate()
            }
        }
    }
    
    // MARK: - Meeting Display Update (State Machine using RollingTimerView)
    
    private func removeMeetingTimerView() {
        meetingTimerView?.removeFromSuperview()
        meetingTimerView = nil
    }
    
    private func ensureMeetingTimerView(button: NSStatusBarButton, mw: (withTimer: CGFloat, idle: CGFloat, timerLeading: CGFloat, timerWidth: CGFloat, isStatic: Bool, showTimer: Bool)) {
        guard meetingTimerView == nil, mw.showTimer else { return }
        let timerView = RollingTimerView(frame: NSRect(x: 0, y: 0, width: mw.timerWidth, height: 18))
        timerView.translatesAutoresizingMaskIntoConstraints = false
        timerView.wantsLayer = true
        timerView.setTextColor(.systemOrange)
        button.addSubview(timerView)
        
        NSLayoutConstraint.activate([
            timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: mw.timerLeading),
            timerView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            timerView.widthAnchor.constraint(equalToConstant: mw.timerWidth),
            timerView.heightAnchor.constraint(equalToConstant: 18)
        ])
        meetingTimerView = timerView
    }
    
    /// Update the NSImageView (tag 778) to reflect the current calendar icon symbol
    private func updateMeetingIconView(_ button: NSStatusBarButton) {
        let symbolName = meetingManager.calendarIconSymbol
        let iconCfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        if let iconView = button.subviews.first(where: { $0.tag == 778 }) as? NSImageView,
           let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Meetings")?
               .withSymbolConfiguration(iconCfg) {
            img.isTemplate = true
            iconView.image = img
        }
    }
    
    func updateMeetingDisplay() {
        guard let itemTuple = statusItems.first(where: { $0.utility == .meetings }) else { return }
        let statusItem = itemTuple.item
        let animationView = itemTuple.view
        guard let button = statusItem.button else { return }
        
        // Snapshot the state and meeting ONCE to avoid timing inconsistencies
        let meeting = meetingManager.displayMeeting
        let state = meetingManager.menuBarState
        let mw = meetingWidths()
        // Icon is an NSImageView subview (tag 778) — update its SF symbol dynamically
        updateMeetingIconView(button)
        // No text padding needed — the icon speaks for itself in idle state
        let textPad = ""
        
        // Remove timer view when not in countdown state
        let needsTimerView = (state == .countdown && mw.showTimer && meeting != nil)
        if !needsTimerView {
            removeMeetingTimerView()
        }
        
        switch state {
        case .idle, .upcoming:
            // Icon (tag 778 subview) already shows the calendar state — no extra text needed
            exitJoinMode(statusItem: statusItem, animationView: animationView, button: button)
            statusItem.length = mw.idle
            button.attributedTitle = NSAttributedString(string: "")
            
        case .countdown:
            exitJoinMode(statusItem: statusItem, animationView: animationView, button: button)
            
            guard let m = meeting else { return }
            let totalSeconds = Int(max(0, m.timeUntilStart))
            
            if mw.showTimer {
                // Clear text FIRST, then show timer view
                button.attributedTitle = NSAttributedString(string: "")
                ensureMeetingTimerView(button: button, mw: mw)
                statusItem.length = mw.withTimer
                
                if let timerView = meetingTimerView {
                    timerView.setTextColor(.systemOrange)
                    timerView.updateFromSeconds(totalSeconds, animated: false)
                    timerView.isHidden = false
                    timerView.needsDisplay = true
                    timerView.layer?.setNeedsDisplay()
                }
            } else {
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                let countdownText = String(format: "%d:%02d", mins, secs)
                let textWidth = (countdownText as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)]).width
                statusItem.length = mw.idle + textWidth + 8
                
                let combined = NSMutableAttributedString()
                combined.append(NSAttributedString(string: textPad, attributes: [.font: NSFont.systemFont(ofSize: 10)]))
                combined.append(NSAttributedString(
                    string: countdownText,
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor.systemOrange
                    ]
                ))
                button.attributedTitle = combined
            }
            
        case .action:
            guard let m = meeting else { return }
            
            if m.hasVideoLink {
                // Video meeting: show Join button with countdown timer inside it
                removeMeetingTimerView()
                enterJoinMode(statusItem: statusItem, animationView: animationView, button: button, meeting: m, timeUntil: m.timeUntilStart)
            } else if m.isHappeningNow {
                // Non-video meeting that has started: show red dot
                exitJoinMode(statusItem: statusItem, animationView: animationView, button: button)
                removeMeetingTimerView()
                statusItem.length = 36
                
                let dotAttr = NSMutableAttributedString()
                dotAttr.append(NSAttributedString(string: "  ", attributes: [.font: NSFont.systemFont(ofSize: 8)]))
                dotAttr.append(NSAttributedString(
                    string: "●",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                        .foregroundColor: NSColor.systemRed
                    ]
                ))
                button.attributedTitle = dotAttr
            } else {
                // Non-video meeting not yet started: keep showing countdown timer
                exitJoinMode(statusItem: statusItem, animationView: animationView, button: button)
                
                let totalSeconds = Int(max(0, m.timeUntilStart))
                
                if mw.showTimer {
                    button.attributedTitle = NSAttributedString(string: "")
                    ensureMeetingTimerView(button: button, mw: mw)
                    statusItem.length = mw.withTimer
                    
                    if let timerView = meetingTimerView {
                        timerView.setTextColor(.systemOrange)
                        timerView.updateFromSeconds(totalSeconds, animated: false)
                        timerView.isHidden = false
                        timerView.needsDisplay = true
                        timerView.layer?.setNeedsDisplay()
                    }
                } else {
                    removeMeetingTimerView()
                    let mins = totalSeconds / 60
                    let secs = totalSeconds % 60
                    let countdownText = String(format: "%d:%02d", mins, secs)
                    let textWidth = (countdownText as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)]).width
                    statusItem.length = mw.idle + textWidth + 8
                    
                    let combined = NSMutableAttributedString()
                    combined.append(NSAttributedString(
                        string: countdownText,
                        attributes: [
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                            .foregroundColor: NSColor.systemOrange
                        ]
                    ))
                    button.attributedTitle = combined
                }
            }
        }
        
        button.needsDisplay = true
    }
    
    // MARK: - Join Mode (Transform meeting item into clickable button)
    private func enterJoinMode(statusItem: NSStatusItem, animationView: NSView, button: NSStatusBarButton, meeting: SmartMeeting, timeUntil: TimeInterval) {
        
        // Save the button image/position so we can restore them when exiting join mode
        if meetingJoinSavedImage == nil {
            meetingJoinSavedImage = button.image
            meetingJoinSavedImagePosition = button.imagePosition
        }
        
        // Hide the static calendar icon subview (tag 778) and the Lottie animation
        button.subviews.first(where: { $0.tag == 778 })?.isHidden = true
        animationView.isHidden = true
        
        // Format: show countdown until meeting starts, then "Join" once it has
        let displayText: String
        if meeting.isHappeningNow {
            displayText = "  Join  "
        } else {
            let totalSecs = Int(max(0, timeUntil))
            let mins = totalSecs / 60
            let secs = totalSecs % 60
            let timeText = String(format: "%d:%02d", mins, secs)
            displayText = "  \(timeText)  "
        }
        
        // Style button with glassy gradient background
        button.wantsLayer = true
        
        // Create gradient layer for modern look
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = button.bounds
        gradientLayer.cornerRadius = 10
        
        // Choose colors based on urgency - with glass effect
        if meeting.isHappeningNow {
            gradientLayer.colors = [
                NSColor.systemGreen.withAlphaComponent(0.9).cgColor,
                NSColor.systemGreen.withAlphaComponent(0.7).cgColor
            ]
        } else if timeUntil <= 60 {
            gradientLayer.colors = [
                NSColor.systemRed.withAlphaComponent(0.9).cgColor,
                NSColor.systemOrange.withAlphaComponent(0.7).cgColor
            ]
        } else if timeUntil <= 120 {
            gradientLayer.colors = [
                NSColor.systemOrange.withAlphaComponent(0.9).cgColor,
                NSColor.systemYellow.withAlphaComponent(0.7).cgColor
            ]
        } else {
            gradientLayer.colors = [
                NSColor.systemBlue.withAlphaComponent(0.9).cgColor,
                NSColor.systemCyan.withAlphaComponent(0.7).cgColor
            ]
        }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        
        // Apply gradient as background color (simplified approach)
        let bgColor: NSColor
        if meeting.isHappeningNow {
            bgColor = NSColor.systemGreen
        } else if timeUntil <= 60 {
            bgColor = NSColor.systemRed
        } else if timeUntil <= 120 {
            bgColor = NSColor.systemOrange
        } else {
            bgColor = NSColor.systemBlue
        }
        
        button.layer?.backgroundColor = bgColor.withAlphaComponent(0.85).cgColor
        button.layer?.cornerRadius = 10
        button.layer?.masksToBounds = true
        // Add subtle border for glass effect
        button.layer?.borderWidth = 0.5
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        
        // White bold text - centered
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        button.attributedTitle = NSAttributedString(string: displayText, attributes: attributes)
        button.image = nil
        button.imagePosition = .noImage
        
        if !meetingInJoinMode {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(joinMeetingClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            meetingInJoinMode = true
        }
        
        let textWidth = (displayText as NSString).size(withAttributes: attributes).width
        statusItem.length = max(60, textWidth + 8)
    }
    
    private func exitJoinMode(statusItem: NSStatusItem, animationView: NSView, button: NSStatusBarButton) {
        // Show animation and static icon subview again
        animationView.isHidden = false
        button.subviews.first(where: { $0.tag == 778 })?.isHidden = false
        
        // Restore button image and position that were cleared in enterJoinMode
        if let savedImage = meetingJoinSavedImage {
            button.image = savedImage
            button.imagePosition = meetingJoinSavedImagePosition
        }
        meetingJoinSavedImage = nil
        
        // Reset button style completely
        button.wantsLayer = true
        button.layer?.backgroundColor = nil
        button.layer?.cornerRadius = 0
        button.layer?.borderWidth = 0
        button.layer?.borderColor = nil
        button.attributedTitle = NSAttributedString(string: "")
        
        // Restore floating panel click handler
        statusItem.menu = nil
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        
        // Make sure the button tag is set for meetings
        if buttonTagToUtility[button.tag] == nil {
            let tag = nextButtonTag
            nextButtonTag += 1
            button.tag = tag
            buttonTagToUtility[tag] = .meetings
        }
        
        meetingInJoinMode = false
        
        let mw = meetingWidths()
        statusItem.length = mw.idle
    }
    
    @objc func joinMeetingClicked(_ sender: Any?) {
        // Check if option key is held OR right-click - show calendar instead
        let event = NSApp.currentEvent
        let isOptionClick = event?.modifierFlags.contains(.option) ?? false
        let isRightClick = event?.type == .rightMouseUp
        
        if isOptionClick || isRightClick {
            // Open the calendar panel
            if let itemTuple = statusItems.first(where: { $0.utility == .meetings }),
               let button = itemTuple.item.button {
                showFloatingPanel(for: .meetings, button: button)
            }
        } else {
            // Normal click - join the meeting
            if let meeting = meetingManager.displayMeeting, meeting.hasVideoLink {
                meetingManager.joinMeeting(meeting)
            }
        }
    }
    
    // Track previous artwork to detect changes
    private var previousMusicArtwork: NSImage? = nil

    /// Debounced wrapper: coalesces rapid publisher firings into a single display update
    private func scheduleMusicDisplayUpdate() {
        musicDisplayWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.updateMusicDisplay()
        }
        musicDisplayWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    func updateMusicDisplay() {
        for (statusItem, view, utility) in statusItems {
            if utility == .music {
                guard let button = statusItem.button else { continue }
                
                // Update album artwork in the NSImageView (tag 888)
                if let artworkView = button.viewWithTag(888) as? NSImageView {
                    let artworkSize: CGFloat = 22
                    let newArtwork = mediaObserver.artworkImage
                    
                    // Check if artwork changed for spin animation
                    let artworkChanged = (previousMusicArtwork == nil && newArtwork != nil) ||
                                         (previousMusicArtwork != nil && newArtwork != nil &&
                                          previousMusicArtwork?.tiffRepresentation != newArtwork?.tiffRepresentation)
                    
                    if artworkChanged && newArtwork != nil {
                        // Spin animation: rotate out, change image, rotate in
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.2
                            context.allowsImplicitAnimation = true
                            artworkView.layer?.transform = CATransform3DMakeRotation(.pi / 2, 0, 1, 0)
                            artworkView.alphaValue = 0.3
                        }, completionHandler: {
                            // Update image at midpoint
                            artworkView.image = newArtwork?.resized(to: NSSize(width: artworkSize, height: artworkSize))
                            
                            // Rotate in with new image
                            NSAnimationContext.runAnimationGroup({ context in
                                context.duration = 0.25
                                context.allowsImplicitAnimation = true
                                artworkView.layer?.transform = CATransform3DIdentity
                                artworkView.alphaValue = 1.0
                            })
                        })
                    } else if let artwork = newArtwork {
                        // No animation, just update
                        artworkView.image = artwork.resized(to: NSSize(width: artworkSize, height: artworkSize))
                    } else {
                        // Match floating bar style: gray rounded rectangle with music note
                        let placeholderSize = NSSize(width: artworkSize, height: artworkSize)
                        let placeholder = NSImage(size: placeholderSize)
                        placeholder.lockFocus()
                        let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: placeholderSize), xRadius: 3, yRadius: 3)
                        NSColor.gray.withAlphaComponent(0.3).setFill()
                        bgPath.fill()
                        if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: artworkSize * 0.5, weight: .regular)) {
                            let symSize = symbol.size
                            symbol.draw(at: NSPoint(x: (placeholderSize.width - symSize.width) / 2, y: (placeholderSize.height - symSize.height) / 2), from: .zero, operation: .sourceOver, fraction: 0.5)
                        }
                        placeholder.unlockFocus()
                        artworkView.image = placeholder
                    }
                    
                    previousMusicArtwork = newArtwork
                    
                    // Dim artwork when paused (iPhone-like visual cue)
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        context.allowsImplicitAnimation = true
                        artworkView.alphaValue = mediaObserver.isPlaying ? 1.0 : 0.5
                    }
                }
                
                // Update play/pause indicator for static mode (tag 889)
                if let playPauseView = button.viewWithTag(889) as? NSImageView {
                    let playSymbol = mediaObserver.isPlaying ? "pause.fill" : "play.fill"
                    let playConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                    playPauseView.image = NSImage(systemSymbolName: playSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(playConfig)
                    playPauseView.contentTintColor = .labelColor
                }
                
                // Keep wave animation visible and animate based on playing state (for non-static mode)
                if let animView = view as? LottieAnimationView {
                    animView.isHidden = false
                    if mediaObserver.isPlaying {
                        if !animView.isAnimationPlaying {
                            animView.play()
                        }
                    } else {
                        animView.stop()
                    }
                }
            }
        }
    }
    
    func setupMenuBar() {
        // Ensure we're on the main thread for all NSStatusItem operations
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setupMenuBar()
            }
            return
        }
        
        // Remove existing settings change observer to prevent duplicates
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SettingsChanged"), object: nil)
        
        // Clear existing items safely
        cleanupStatusItems()
        
        // Create a status item for EACH enabled utility
        let enabledUtilities = settingsManager.enabledUtilities()
        
        guard !enabledUtilities.isEmpty else {
            // Create a single fallback item
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "..."
            statusItems.append((item, LottieAnimationView(), .cpu))
            setupMenuForItem(item, utility: .cpu)
            return
        }
        
        for (_, (utility, config)) in enabledUtilities.enumerated() {
            // 1. Create a status item with DYNAMIC width based on utility
            // Compact sizes to match static icons - Animation=30px, With text=55px
            // When in temporary static mode, treat all icons as static for width calculations
            let effectivelyStatic = config.character.isStaticIcon || AppModeManager.shared.isTemporaryStaticMode
            
            var itemLength: CGFloat = config.displayOption != .none ? 55 : 30
            
            // Stats utilities (CPU, GPU, RAM, Disk) - wider when Lottie + percentage
            // Only increase width for Lottie mode, not static icons
            let statsUtilities: [UtilityType] = [.cpu, .gpu, .ram, .disk]
            if statsUtilities.contains(utility) && config.displayOption != .none && !effectivelyStatic {
                itemLength = 62 // Animation + percentage with % sign (e.g., "45%")
            }
            
            // Music shows album artwork LEFT + wave RIGHT
            if utility == .music {
                itemLength = 56 // Artwork (22) + spacing (8) + wave
            }
            
            // Network - only show speed text if displayOption is .speed
            if utility == .network {
                if config.displayOption == .speed {
                    itemLength = 65 // Animation + speed text (e.g., "7.4 M") - wider for Lottie
                } else {
                    itemLength = 30 // Just animation
                }
            }
            
            // Meetings - animation + compact time display
            if utility == .meetings {
                itemLength = config.displayOption != .none ? 55 : 35
            }
            
            // Bluetooth - Fixed compact width
            if utility == .bluetooth {
                itemLength = 22 // Compact animation
            }
            
            // Battery - animation + percentage (wider for Lottie with "⚡100%")
            if utility == .battery && config.displayOption != .none && !effectivelyStatic {
                itemLength = 74 // Lottie animation + bolt + percentage
            } else if utility == .battery && config.displayOption != .none {
                itemLength = 65 // Static icon + percentage
            }
            
            if utility == .pomodoro {
                let pw = pomodoroWidths()
                let isRunning = pomodoroManager.isRunning
                itemLength = (pw.showTimer && isRunning) ? pw.running : pw.idle
            }
            
            let statusItem = NSStatusBar.system.statusItem(withLength: itemLength)
            statusItem.isVisible = true // Ensure visibility
            statusItem.behavior = .removalAllowed // Allow system to manage
            
            guard let button = statusItem.button else { continue }
            
            // 2. Check if using static icon (SF Symbol) instead of Lottie animation
            // SPECIAL CASES: Music and Pomodoro need custom handling even with static icons
            // POMODORO: Check pomo_workingCharacter from UserDefaults (not config.character)
            var isUsingStaticIcon = config.character.isStaticIcon
            if utility == .pomodoro {
                let workingChar = UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass"
                if let charType = CharacterType(rawValue: workingChar) {
                    isUsingStaticIcon = charType.isStaticIcon
                }
            }
            
            // TEMPORARY STATIC OVERRIDE: When in alwaysMenuBar + external display mode,
            // force all icons to static even if user has Lottie selected.
            // This does NOT change saved settings - just the runtime rendering.
            if AppModeManager.shared.isTemporaryStaticMode {
                isUsingStaticIcon = true
            }
            
            if isUsingStaticIcon {
                
                // MUSIC STATIC: Still show album art + play/pause indicator (compact, no side padding)
                if utility == .music {
                    // Tight width - just artwork + play/pause, no side padding
                    statusItem.length = 36  // Compact width: artwork 22px + 2px gap + play/pause 14px
                    
                    button.title = ""
                    button.imagePosition = .imageOnly
                    button.wantsLayer = true
                    button.layer?.masksToBounds = false // Prevent clipping
                    
                    // Album artwork on LEFT side - use Auto Layout for vertical centering
                    let artworkSize: CGFloat = 22  // Smaller artwork
                    let artworkView = MousePassThroughImageView(frame: .zero)
                    artworkView.translatesAutoresizingMaskIntoConstraints = false
                    artworkView.wantsLayer = true
                    artworkView.layer?.cornerRadius = 3
                    artworkView.layer?.masksToBounds = true
                    artworkView.imageScaling = .scaleProportionallyUpOrDown
                    artworkView.tag = 888
                    
                    if let artwork = mediaObserver.artworkImage {
                        artworkView.image = artwork.resized(to: NSSize(width: artworkSize, height: artworkSize))
                    } else {
                        // Match floating bar style: gray rounded rectangle with music note
                        let placeholderSize = NSSize(width: artworkSize, height: artworkSize)
                        let placeholder = NSImage(size: placeholderSize)
                        placeholder.lockFocus()
                        // Draw rounded rectangle background
                        let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: placeholderSize), xRadius: 3, yRadius: 3)
                        NSColor.gray.withAlphaComponent(0.3).setFill()
                        bgPath.fill()
                        // Draw music note symbol centered
                        if let musicSymbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)) {
                            let symbolSize = musicSymbol.size
                            let symbolOrigin = NSPoint(
                                x: (placeholderSize.width - symbolSize.width) / 2,
                                y: (placeholderSize.height - symbolSize.height) / 2
                            )
                            musicSymbol.draw(at: symbolOrigin, from: .zero, operation: .sourceOver, fraction: 0.5)
                        }
                        placeholder.unlockFocus()
                        artworkView.image = placeholder
                    }
                    button.addSubview(artworkView)
                    NSLayoutConstraint.activate([
                        artworkView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0),
                        artworkView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        artworkView.widthAnchor.constraint(equalToConstant: artworkSize),
                        artworkView.heightAnchor.constraint(equalToConstant: artworkSize)
                    ])
                    
                    // Play/pause indicator on RIGHT side - tight spacing
                    let playPauseView = NSImageView(frame: .zero)
                    playPauseView.translatesAutoresizingMaskIntoConstraints = false
                    playPauseView.wantsLayer = true
                    playPauseView.tag = 889 // Tag to find for updates
                    let playSymbol = mediaObserver.isPlaying ? "pause.fill" : "play.fill"
                    let playConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)  // Smaller
                    playPauseView.image = NSImage(systemSymbolName: playSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(playConfig)
                    playPauseView.contentTintColor = .labelColor  // Adapts to menu bar appearance
                    button.addSubview(playPauseView)
                    NSLayoutConstraint.activate([
                        playPauseView.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 2),
                        playPauseView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        playPauseView.widthAnchor.constraint(equalToConstant: 14),
                        playPauseView.heightAnchor.constraint(equalToConstant: 16)
                    ])
                    
                    setupMenuForItem(statusItem, utility: utility)
                    statusItems.append((statusItem, NSView(), utility))
                    continue
                }
                
                if utility == .pomodoro {
                    let pw = pomodoroWidths()
                    let isRunning = pomodoroManager.isRunning
                    statusItem.length = (pw.showTimer && isRunning) ? pw.running : pw.idle
                    
                    // Static pomodoro icon — read user's selection dynamically
                    let pomoWorkingChar = UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass"
                    let pomoSymbolName = CharacterType(rawValue: pomoWorkingChar)?.sfSymbolName ?? "timer"
                    let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                    if let icon = NSImage(systemSymbolName: pomoSymbolName, accessibilityDescription: "Pomodoro")?.withSymbolConfiguration(iconConfig) {
                        icon.isTemplate = true
                        let spacer = NSImage(size: NSSize(width: 18, height: 22))
                        spacer.isTemplate = true
                        button.image = spacer
                        button.imagePosition = .imageLeft
                        
                        let iconView = NSImageView(frame: .zero)
                        iconView.translatesAutoresizingMaskIntoConstraints = false
                        iconView.image = icon
                        iconView.contentTintColor = .labelColor
                        iconView.tag = 777
                        button.addSubview(iconView)
                        NSLayoutConstraint.activate([
                            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                            iconView.widthAnchor.constraint(equalToConstant: 16),
                            iconView.heightAnchor.constraint(equalToConstant: 16)
                        ])
                    }
                    
                    if pw.showTimer && isRunning {
                        let timerView = RollingTimerView(frame: NSRect(x: 0, y: 0, width: pw.timerWidth, height: 18))
                        timerView.translatesAutoresizingMaskIntoConstraints = false
                        timerView.wantsLayer = true
                        button.addSubview(timerView)
                        
                        NSLayoutConstraint.activate([
                            timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: pw.timerLeading),
                            timerView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                            timerView.widthAnchor.constraint(equalToConstant: pw.timerWidth),
                            timerView.heightAnchor.constraint(equalToConstant: 18)
                        ])
                        
                        let totalSeconds = Int(pomodoroManager.timeRemaining)
                        timerView.updateFromSeconds(totalSeconds, animated: false)
                        self.pomodoroTimerView = timerView
                    }
                    
                    setupMenuForItem(statusItem, utility: utility)
                    statusItems.append((statusItem, NSView(), utility))
                    continue
                }
                
                // MEETINGS STATIC: Dedicated path like Pomodoro - transparent spacer + NSImageView subview + optional timer subview
                if utility == .meetings {
                    let mw = meetingWidths()
                    let state = meetingManager.menuBarState
                    let isCountdownOrAction = (state == .countdown || state == .action)
                    statusItem.length = (isCountdownOrAction && mw.showTimer) ? mw.withTimer : mw.idle

                    let spacer = NSImage(size: NSSize(width: 18, height: 22))
                    spacer.isTemplate = true
                    button.image = spacer
                    button.imagePosition = .imageLeft
                    button.title = ""

                    let calSymbol = meetingManager.calendarIconSymbol
                    let iconCfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
                    if let calIcon = NSImage(systemSymbolName: calSymbol,
                                            accessibilityDescription: "Meetings")?
                        .withSymbolConfiguration(iconCfg) {
                        calIcon.isTemplate = true
                        let iconView = NSImageView(frame: .zero)
                        iconView.translatesAutoresizingMaskIntoConstraints = false
                        iconView.image = calIcon
                        iconView.contentTintColor = .labelColor
                        iconView.tag = 778
                        button.addSubview(iconView)
                        NSLayoutConstraint.activate([
                            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 1),
                            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                            iconView.widthAnchor.constraint(equalToConstant: 20),
                            iconView.heightAnchor.constraint(equalToConstant: 20)
                        ])
                    }

                    // If meeting is already counting down on launch/mode-switch, add timer now
                    if isCountdownOrAction && mw.showTimer && meetingTimerView == nil {
                        let timerView = RollingTimerView(frame: NSRect(x: 0, y: 0, width: mw.timerWidth, height: 18))
                        timerView.translatesAutoresizingMaskIntoConstraints = false
                        timerView.wantsLayer = true
                        timerView.setTextColor(.systemOrange)
                        button.addSubview(timerView)
                        NSLayoutConstraint.activate([
                            timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: mw.timerLeading),
                            timerView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                            timerView.widthAnchor.constraint(equalToConstant: mw.timerWidth),
                            timerView.heightAnchor.constraint(equalToConstant: 18)
                        ])
                        if let meeting = meetingManager.displayMeeting {
                            let totalSeconds = Int(max(0, meeting.timeUntilStart))
                            timerView.updateFromSeconds(totalSeconds, animated: false)
                        }
                        meetingTimerView = timerView
                    }

                    setupMenuForItem(statusItem, utility: utility)
                    statusItems.append((statusItem, NSView(), utility))
                    continue
                }

                // OTHER STATIC ICONS: Use SF Symbol (compact, no side padding)
                // When in temporary static mode, the user's character may be Lottie (no sfSymbolName),
                // so fall back to the static icon for this utility type
                let sfSymbol: String? = config.character.sfSymbolName ?? (AppModeManager.shared.isTemporaryStaticMode ? CharacterType.staticIcon(for: utility).sfSymbolName : nil)
                if let sfSymbol = sfSymbol {
                    // Set TIGHT width based on utility type - minimal side padding
                    var itemWidth: CGFloat = 18 // Default icon-only width (compact)
                    
                    if config.displayOption != .none {
                        // Calculate tight width based on utility - icon + space + text only
                        switch utility {
                        case .battery:
                            itemWidth = 58 // Icon + "100%" (bigger icon to match native)
                        case .network:
                            itemWidth = 46 // Icon + "0.0"
                        case .disk:
                            itemWidth = 48 // Icon + "77%"
                        case .bluetooth:
                            itemWidth = 16 // Compact icon
                        case .meetings:
                            itemWidth = 32 // Icon + checkmark
                        case .cpu, .gpu, .ram:
                            itemWidth = 52 // Icon + "100%"
                        default:
                            itemWidth = 52 // Icon + percentage
                        }
                    }
                    
                    statusItem.length = itemWidth
                    
                    // Resolve dynamic battery icon based on actual battery level and charging state
                    var resolvedSymbol = sfSymbol
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
                        resolvedSymbol = isPlugged ? "battery.100.bolt" : base
                    }
                    
                    let iconSize: CGFloat = (utility == .battery) ? 17 : 14
                    let iconWeight: NSFont.Weight = (utility == .battery) ? .regular : .medium
                    let iconConfig = NSImage.SymbolConfiguration(pointSize: iconSize, weight: iconWeight)
                    if let icon = NSImage(systemSymbolName: resolvedSymbol, accessibilityDescription: utility.rawValue)?
                        .withSymbolConfiguration(iconConfig) {
                        icon.isTemplate = true
                        
                        if config.displayOption != .none {
                            button.image = icon
                            button.imagePosition = .imageLeft
                            let displayText = getDisplayText(for: utility, config: config)
                            button.title = displayText
                            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                        } else {
                            button.image = icon
                            button.imagePosition = .imageOnly
                            button.title = ""
                        }
                    }
                    setupMenuForItem(statusItem, utility: utility)
                    statusItems.append((statusItem, NSView(), utility))
                    continue
                }
            }
            
            // 3. Get the character's Lottie file
            // POMODORO SPECIAL: Use currentMenuBarAnimation which handles work/break state
            var lottieFile: String
            if utility == .pomodoro {
                lottieFile = pomodoroManager.currentMenuBarAnimation
            } else {
                // NOTE: Music will use "music.json" (mapped to .lightning character)
                guard let file = config.character.lottieFileName else {
                    // Fallback to emoji indicator if no Lottie
                    button.title = config.character.icon + "  "
                    setupMenuForItem(statusItem, utility: utility)
                    statusItems.append((statusItem, LottieAnimationView(), utility))
                    continue
                }
                lottieFile = file
            }
            
            // 4. Configure the Lottie View
            let animationView = LottieAnimationView(name: lottieFile)
            animationView.contentMode = .scaleAspectFit
            animationView.wantsLayer = true
            animationView.layer?.shouldRasterize = false  // Crisp on all displays
            
            // Set animation mode based on utility type
            switch utility {
            case .pomodoro:
                // Pomodoro uses progress-based animation (sand reduces with timer)
                animationView.loopMode = .playOnce
                if pomodoroManager.isRunning {
                    animationView.currentProgress = pomodoroManager.sandProgress
                    startPomodoroAnimationTimer()
                } else {
                    animationView.currentProgress = 0.0
                }
            case .meetings:
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.3
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            case .bluetooth:
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.6
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            case .music:
                animationView.loopMode = .loop
                animationView.animationSpeed = 1.0
                animationView.backgroundBehavior = .pauseAndRestore
                if mediaObserver.isPlaying {
                    animationView.play()
                } else {
                    animationView.stop()
                }
            case .battery:
                // Battery uses running characters - speed based on battery level
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.6 + (systemMonitor.batteryLevel * 0.4)
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            case .cpu:
                // CPU speed based on usage
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.6 + (systemMonitor.cpuUsage / 100.0) * 0.6
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            case .ram:
                // RAM speed based on usage
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.6 + (systemMonitor.ramUsage / 100.0) * 0.6
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            case .gpu:
                // GPU speed based on usage
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.6 + (systemMonitor.gpuUsage / 100.0) * 0.6
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            case .disk:
                // Disk speed based on usage
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.6 + (systemMonitor.diskUsage / 100.0) * 0.6
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            default:
                animationView.loopMode = .loop
                animationView.animationSpeed = 0.7
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.play()
            }
            
            let customView: NSView = animationView
            customView.wantsLayer = true
            let statusBarScreen = button.window?.screen ?? NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor })
            let scaleFactor = statusBarScreen?.backingScaleFactor ?? 2.0
            customView.layer?.contentsScale = scaleFactor
            
            // 4. Setup button layout - Special handling for Music
            if utility == .music {
                // Music: Album art LEFT, Wave animation RIGHT (bigger)
                button.title = ""
                button.imagePosition = .imageOnly
                button.wantsLayer = true
                customView.wantsLayer = true
                
                // Set album artwork or placeholder on LEFT side
                let artworkSize: CGFloat = 22
                let artworkFrame = NSRect(x: 4, y: 0, width: artworkSize, height: artworkSize)
                
                // Create artwork view positioned on LEFT
                let artworkView = MousePassThroughImageView(frame: artworkFrame)
                artworkView.wantsLayer = true
                artworkView.layer?.cornerRadius = 4
                artworkView.layer?.masksToBounds = true
                artworkView.imageScaling = .scaleProportionallyUpOrDown
                artworkView.tag = 888 // Tag to find later for updates
                
                // Set image with high quality
                if let artwork = mediaObserver.artworkImage {
                    // Use high-quality resizing for real artwork
                    artworkView.image = artwork.resized(to: NSSize(width: artworkSize, height: artworkSize))
                } else {
                    // Match floating bar style: gray rounded rectangle with music note
                    let placeholderSize = NSSize(width: artworkSize, height: artworkSize)
                    let placeholder = NSImage(size: placeholderSize)
                    placeholder.lockFocus()
                    let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: placeholderSize), xRadius: 4, yRadius: 4)
                    NSColor.gray.withAlphaComponent(0.3).setFill()
                    bgPath.fill()
                    if let musicSymbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)) {
                        let symbolSize = musicSymbol.size
                        let symbolOrigin = NSPoint(
                            x: (placeholderSize.width - symbolSize.width) / 2,
                            y: (placeholderSize.height - symbolSize.height) / 2
                        )
                        musicSymbol.draw(at: symbolOrigin, from: .zero, operation: .sourceOver, fraction: 0.5)
                    }
                    placeholder.unlockFocus()
                    artworkView.image = placeholder
                }
                
                button.addSubview(artworkView)
                
                // Position wave animation on RIGHT side - use unified size from CharacterType
                let animSize = config.character.menuBarAnimationSize
                customView.frame = NSRect(x: 30, y: -7, width: animSize.width, height: animSize.height)
                // Wrap animation in a mouse pass-through container
                let container = MousePassThroughView(frame: customView.frame)
                container.addSubview(animationView)
                animationView.frame = container.bounds
                button.addSubview(container)
                
            } else if utility == .bluetooth {
                // --- BLUETOOTH SETUP (Dynamic) ---
                if let audioDevice = bluetoothManager.connectedAudioDevice {
                    // CONNECTED: Load correct animation (headphones/airpods) immediately
                    button.wantsLayer = true
                    customView.wantsLayer = true
                    
                    // Load the CORRECT animation based on device type
                    let correctAnimationName = bluetoothManager.currentMenuBarAnimation
                    if let correctAnimation = LottieAnimation.named(correctAnimationName) {
                        animationView.animation = correctAnimation
                        animationView.loopMode = .loop
                        animationView.play()
                    }
                    
                    // Use unified size from CharacterType
                    let animSize = config.character.menuBarAnimationSize
                    
                    // Create spacer for animation
                    let spacer = NSImage(size: NSSize(width: animSize.width, height: 22))
                    spacer.lockFocus()
                    NSColor.clear.set()
                    NSRect(origin: .zero, size: spacer.size).fill()
                    spacer.unlockFocus()
                    button.image = spacer
                    button.imagePosition = .imageLeft
                    
                    // Pin the animation
                    customView.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(customView)
                    
                    NSLayoutConstraint.activate([
                        customView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0),
                        customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        customView.widthAnchor.constraint(equalToConstant: animSize.width),
                        customView.heightAnchor.constraint(equalToConstant: animSize.height)
                    ])
                    
                    // No battery display (coming soon)
                    button.title = ""
                } else {
                    // DISCONNECTED: Show the user's selected default character animation
                    button.wantsLayer = true
                    customView.wantsLayer = true
                    
                    // Load the configured character animation (user's preference)
                    let animationName = config.character.lottieFileName ?? "bluetooth"
                    if let animation = LottieAnimation.named(animationName) {
                        animationView.animation = animation
                        animationView.loopMode = .loop
                        animationView.play()
                    }
                    
                    // Use unified size from CharacterType
                    let animSize = config.character.menuBarAnimationSize
                    
                    // Create spacer for animation
                    let spacer = NSImage(size: NSSize(width: animSize.width, height: 22))
                    spacer.lockFocus()
                    NSColor.clear.set()
                    NSRect(origin: .zero, size: spacer.size).fill()
                    spacer.unlockFocus()
                    button.image = spacer
                    button.imagePosition = .imageOnly
                    button.title = ""
                    
                    // Pin the animation - use unified size
                    customView.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(customView)
                    
                    NSLayoutConstraint.activate([
                        customView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                        customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        customView.widthAnchor.constraint(equalToConstant: animSize.width),
                        customView.heightAnchor.constraint(equalToConstant: animSize.height)
                    ])
                    
                    // Set status item to width based on animation size
                    statusItem.length = animSize.width + 10
                }
                
            } else if utility == .network && config.displayOption == .speed {
                // --- NETWORK SETUP (Robust Mode) ---
                // Use unified size from CharacterType
                let animSize = config.character.menuBarAnimationSize
                
                // 1. FIX GHOSTING: Force layer-backing on button AND animation
                button.wantsLayer = true
                customView.wantsLayer = true
                
                // 2. FIX FLICKERING: Create a "Spacer" Image
                let spacer = NSImage(size: NSSize(width: animSize.width, height: 22))
                spacer.lockFocus()
                NSColor.clear.set()
                NSRect(origin: .zero, size: spacer.size).fill()
                spacer.unlockFocus()
                button.image = spacer
                button.imagePosition = .imageLeft
                
                // 3. PIN THE ANIMATION - use unified size
                customView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(customView)
                
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0),
                    customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    customView.widthAnchor.constraint(equalToConstant: animSize.width),
                    customView.heightAnchor.constraint(equalToConstant: animSize.height)
                ])
                
                // 4. Initialize Text - Same size as other stats
                button.title = "0"
                button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                
            } else if utility == .pomodoro {
                let pw = pomodoroWidths()
                let workingChar = UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass"
                let animSize = CharacterType(rawValue: workingChar)?.menuBarAnimationSize ?? CGSize(width: 24, height: 24)
                let isRunning = pomodoroManager.isRunning
                
                button.wantsLayer = true
                customView.wantsLayer = true
                
                let spacer = NSImage(size: NSSize(width: animSize.width, height: 22))
                spacer.lockFocus()
                NSColor.clear.set()
                NSRect(origin: .zero, size: spacer.size).fill()
                spacer.unlockFocus()
                button.image = spacer
                button.imagePosition = .imageLeft
                button.title = ""
                
                customView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(customView)
                
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                    customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    customView.widthAnchor.constraint(equalToConstant: animSize.width),
                    customView.heightAnchor.constraint(equalToConstant: animSize.height)
                ])
                
                if pw.showTimer && isRunning {
                    let timerView = RollingTimerView(frame: NSRect(x: 0, y: 0, width: pw.timerWidth, height: 18))
                    timerView.translatesAutoresizingMaskIntoConstraints = false
                    timerView.wantsLayer = true
                    button.addSubview(timerView)
                    
                    NSLayoutConstraint.activate([
                        timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: pw.timerLeading),
                        timerView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        timerView.widthAnchor.constraint(equalToConstant: pw.timerWidth),
                        timerView.heightAnchor.constraint(equalToConstant: 18)
                    ])
                    
                    let totalSeconds = Int(pomodoroManager.timeRemaining)
                    timerView.updateFromSeconds(totalSeconds, animated: false)
                    self.pomodoroTimerView = timerView
                }
                
            } else if utility == .meetings {
                // MEETINGS LOTTIE: mirrors Pomodoro Lottie exactly
                let animSize = config.character.menuBarAnimationSize
                let mw = meetingWidths()
                let state = meetingManager.menuBarState
                let isCountdownOrAction = (state == .countdown || state == .action)

                button.wantsLayer = true
                customView.wantsLayer = true

                // Transparent spacer — same width as the animation
                let spacer = NSImage(size: NSSize(width: animSize.width, height: 22))
                spacer.lockFocus()
                NSColor.clear.set()
                NSRect(origin: .zero, size: spacer.size).fill()
                spacer.unlockFocus()
                button.image = spacer
                button.imagePosition = .imageLeft
                button.title = ""
                button.alignment = .left

                // Pin Lottie animation at +4 (matches Pomodoro Lottie offset)
                customView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(customView)
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                    customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    customView.widthAnchor.constraint(equalToConstant: animSize.width),
                    customView.heightAnchor.constraint(equalToConstant: animSize.height)
                ])

                // If already in countdown on launch/mode-switch, add timer now
                if isCountdownOrAction && mw.showTimer && meetingTimerView == nil {
                    let timerView = RollingTimerView(frame: NSRect(x: 0, y: 0, width: mw.timerWidth, height: 18))
                    timerView.translatesAutoresizingMaskIntoConstraints = false
                    timerView.wantsLayer = true
                    timerView.setTextColor(.systemOrange)
                    button.addSubview(timerView)
                    NSLayoutConstraint.activate([
                        timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: mw.timerLeading),
                        timerView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        timerView.widthAnchor.constraint(equalToConstant: mw.timerWidth),
                        timerView.heightAnchor.constraint(equalToConstant: 18)
                    ])
                    if let meeting = meetingManager.displayMeeting {
                        let totalSeconds = Int(max(0, meeting.timeUntilStart))
                        timerView.updateFromSeconds(totalSeconds, animated: false)
                    }
                    meetingTimerView = timerView
                }
                
            } else if config.displayOption != .none {
                // Standard utilities: Show animation + Text side by side
                // Use character's preferred animation size
                let animSize = config.character.menuBarAnimationSize
                
                let displayText = getDisplayText(for: utility, config: config)
                let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                
                // For battery in Lottie mode: embed a native bolt.fill SF Symbol when charging
                let isLottieBatteryCharging = utility == .battery
                    && !config.character.isStaticIcon
                    && (systemMonitor.isCharging || !systemMonitor.isBatteryPowered)
                
                if isLottieBatteryCharging {
                    let boldConf = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                    let boltImg = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(boldConf)
                    let attachment = NSTextAttachment()
                    attachment.image = boltImg
                    attachment.bounds = CGRect(x: 0, y: -1, width: 8, height: 10)
                    let attrStr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
                    attrStr.append(NSAttributedString(string: displayText,
                        attributes: [.font: monoFont, .foregroundColor: NSColor.labelColor]))
                    button.attributedTitle = attrStr
                } else {
                    button.title = displayText
                    button.font = monoFont
                }
                button.imagePosition = .imageLeft
                button.alignment = .left
                button.wantsLayer = true
                customView.wantsLayer = true
                
                // Create transparent spacer for animation (tight, minimal extra space)
                let spacerWidth = animSize.width + 2
                let iconImage = NSImage(size: NSSize(width: spacerWidth, height: 22))
                iconImage.lockFocus()
                NSColor.clear.set()
                NSRect(x: 0, y: 0, width: spacerWidth, height: 22).fill()
                iconImage.unlockFocus()
                button.image = iconImage
                button.imagePosition = .imageLeft
                
                // Pin animation with Auto Layout using character's size (no left padding)
                customView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(customView)
                
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0),
                    customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    customView.widthAnchor.constraint(equalToConstant: animSize.width),
                    customView.heightAnchor.constraint(equalToConstant: animSize.height)
                ])
            } else {
                // Show animation only - use character's preferred size
                let animSize = config.character.menuBarAnimationSize
                
                button.wantsLayer = true
                customView.wantsLayer = true
                
                let size = NSSize(width: animSize.width + 8, height: 22)
                let image = NSImage(size: size)
                image.lockFocus()
                NSColor.clear.set()
                NSRect(origin: .zero, size: size).fill()
                image.unlockFocus()
                button.image = image
                button.imagePosition = .imageOnly
                button.title = ""
                
                // Pin animation with Auto Layout using character's size
                customView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(customView)
                
                NSLayoutConstraint.activate([
                    customView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    customView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    customView.widthAnchor.constraint(equalToConstant: animSize.width),
                    customView.heightAnchor.constraint(equalToConstant: animSize.height)
                ])
            }
            
            // 5. Store reference
            statusItems.append((statusItem, animationView, utility))
            
            // 6. Setup Menu
            setupMenuForItem(statusItem, utility: utility)
        }
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
        
        // Start timer to update system stat animation speeds
        startSystemStatAnimationTimer()
    }
    
    // Map button tags to utility types
    private var buttonTagToUtility: [Int: UtilityType] = [:]
    private var nextButtonTag = 1000
    
    func setupMenuForItem(_ statusItem: NSStatusItem, utility: UtilityType) {
        // Use floating panel approach - no NSMenu, just click handlers
            statusItem.menu = nil
            
            if let button = statusItem.button {
                button.target = self
            
            // Store the utility type using a unique tag
            let tag = nextButtonTag
            nextButtonTag += 1
            button.tag = tag
            buttonTagToUtility[tag] = utility
            
            // Special handling for Bluetooth with right-click support
            if utility == .bluetooth {
                button.action = #selector(handleBluetoothClick(_:))
                // Enable right-click events on the button
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
                button.action = #selector(handleStatusItemClick(_:))
            }
        }
    }
    
    @objc func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let utility = buttonTagToUtility[sender.tag] else { return }
        showFloatingPanel(for: utility, button: sender)
    }
    
    /// Handle Bluetooth quick connect with right-click support
    @objc func handleBluetoothClick(_ sender: NSStatusBarButton) {
        let quickConnectMode = UserDefaults.standard.bool(forKey: "bluetooth_quickConnectMode")
        
        if !quickConnectMode {
            showFloatingPanel(for: .bluetooth, button: sender)
            return
        }
        
        // Check for right-click using clickCount (right-click is typically 0 or separate event)
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.type == .rightMouseDown
        let isOptionClick = event?.modifierFlags.contains(.option) ?? false
        let isControlClick = event?.modifierFlags.contains(.control) ?? false
        
        if isRightClick || isOptionClick || isControlClick {
            // Right-click/Option-click/Control-click: Show full menu
            showFloatingPanel(for: .bluetooth, button: sender)
            return
        }
        
        // Left-click in Quick Connect mode
        if let device = bluetoothManager.connectedAudioDevice {
            // Already connected - show disconnect menu
            showBluetoothQuickMenu(for: device, button: sender)
        } else if bluetoothManager.hasLastConnectedDevice {
            // Not connected - connect to last device with loading feedback
            showBluetoothConnectingState(on: sender)
            bluetoothManager.connectToLastDevice()
            
            // Show connection popup below the menu bar Bluetooth icon
            if let entry = statusItems.first(where: { $0.utility == .bluetooth }) {
                let deviceName = bluetoothManager.lastConnectedDevice?.name ?? "Device"
                BluetoothConnectionNotification.shared.show(deviceName: deviceName, relativeTo: entry.item)
            }
        } else {
            // No last device - show full menu
            showFloatingPanel(for: .bluetooth, button: sender)
        }
    }
    
    /// Show a loading spinner on the Bluetooth status bar button during connection
    private func showBluetoothConnectingState(on button: NSStatusBarButton) {
        guard let entry = statusItems.first(where: { $0.utility == .bluetooth }) else { return }
        
        // Save current icon to restore later if connection fails
        let originalImage = button.image
        let originalTitle = button.title
        
        // Hide the lottie view temporarily
        if let animationView = entry.view as? LottieAnimationView {
            animationView.isHidden = true
        }
        
        // Show loading spinner symbol
        let spinnerAttachment = NSTextAttachment()
        spinnerAttachment.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        let spinnerString = NSMutableAttributedString(attachment: spinnerAttachment)
        spinnerString.addAttributes([
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 14)
        ], range: NSRange(location: 0, length: spinnerString.length))
        
        button.attributedTitle = spinnerString
        button.image = nil
        entry.item.length = 28
        
        // Observe connection state changes
        var connectionObserver: NSObjectProtocol?
        connectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BluetoothDevicesChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            if self.bluetoothManager.connectedAudioDevice != nil {
                // Connected! Show tick briefly
                if let connectionObserver = connectionObserver {
                    NotificationCenter.default.removeObserver(connectionObserver)
                }
                
                let tickAttachment = NSTextAttachment()
                tickAttachment.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                let tickString = NSMutableAttributedString(attachment: tickAttachment)
                tickString.addAttributes([
                    .foregroundColor: NSColor.systemGreen,
                    .font: NSFont.systemFont(ofSize: 14)
                ], range: NSRange(location: 0, length: tickString.length))
                
                button.attributedTitle = tickString
                button.image = nil
                
                // After 1 second, restore to the connected animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    button.attributedTitle = NSAttributedString(string: "")
                    button.image = originalImage
                    button.title = originalTitle
                    if let animView = entry.view as? LottieAnimationView {
                        animView.isHidden = false
                    }
                    // Trigger the normal Bluetooth update which sets correct animation
                    self.updateBluetoothAnimation()
                }
            }
        }
        
        // Timeout: if no connection after 8 seconds, restore original state
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self else { return }
            if self.bluetoothManager.connectedAudioDevice == nil {
                // Connection failed or timed out
                if let connectionObserver = connectionObserver {
                    NotificationCenter.default.removeObserver(connectionObserver)
                }
                button.attributedTitle = NSAttributedString(string: "")
                button.image = originalImage
                button.title = originalTitle
                if let animView = entry.view as? LottieAnimationView {
                    animView.isHidden = false
                }
            }
        }
    }
    
    /// Show a quick Bluetooth menu when connected (for quick connect mode)
    private func showBluetoothQuickMenu(for device: BluetoothDevice, button: NSStatusBarButton) {
        let menu = NSMenu()
        
        // Device name header
        let headerItem = NSMenuItem(title: "✓ \(device.name)", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
        
        if device.battery.hasBattery {
            let batteryItem = NSMenuItem(title: "Battery: \(device.battery.displayString)", action: nil, keyEquivalent: "")
            batteryItem.isEnabled = false
            menu.addItem(batteryItem)
        }
            
            menu.addItem(NSMenuItem.separator())
            
        // Disconnect button
        let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnectCurrentDevice), keyEquivalent: "")
        disconnectItem.target = self
        menu.addItem(disconnectItem)
        
                menu.addItem(NSMenuItem.separator())
        
        // Open full menu option
        let fullMenuItem = NSMenuItem(title: "More Options...", action: #selector(openBluetoothFullMenu(_:)), keyEquivalent: "")
        fullMenuItem.target = self
        fullMenuItem.representedObject = button
        menu.addItem(fullMenuItem)
        
        // Show the menu as a popup
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }
    
    @objc private func disconnectCurrentDevice() {
        bluetoothManager.disconnectCurrentDevice()
    }
    
    @objc private func openBluetoothFullMenu(_ sender: NSMenuItem) {
        guard let button = sender.representedObject as? NSStatusBarButton else { return }
        showFloatingPanel(for: .bluetooth, button: button)
    }
    
    func showFloatingPanel(for utility: UtilityType, button: NSStatusBarButton) {
        // Refresh data before showing
        switch utility {
        case .network:
            NetworkNative.shared.update()
        case .bluetooth:
            bluetoothManager.refreshDevices()
        default:
            break
        }
        
        // Get the view and size for this utility
        let (view, size) = getViewForUtility(utility)
        
        FloatingPanelController.shared.toggle(
            content: view,
            utility: utility,
            relativeTo: button,
            size: size
        )
    }
    
    func getViewForUtility(_ utility: UtilityType) -> (AnyView, NSSize) {
        switch utility {
        case .cpu:
            let view = CPUMenuView(systemMonitor: systemMonitor).withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 600))
            
        case .gpu:
            let view = GPUMenuView(systemMonitor: systemMonitor).withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 460))
            
        case .ram:
            let view = RAMMenuView(systemMonitor: systemMonitor).withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 620))
            
        case .battery:
            let view = BatteryMenuView(systemMonitor: systemMonitor).withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 620))
            
        case .network:
            let view = NetworkMenuView(systemMonitor: systemMonitor).withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 560))
            
        case .disk:
            let view = DiskMenuView(systemMonitor: systemMonitor).withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 460))
            
        case .bluetooth:
            let view = BluetoothMenuView().withPanelFooter()
            return (AnyView(view), NSSize(width: 320, height: 420))
            
        case .music:
            // Panel height is tuned to NowPlayingTile's natural content + footer:
            //   player card  ~298pt  (album art 100 + 4 rows + spacing + padding)
            //   PanelFooter  ~61pt   (divider + 32pt button + 12 top + 16 bottom)
            //   total        ~359pt
            // Setting 360 makes the player fit edge-to-edge with no stretch and
            // no dead space between player and footer.
            let view = NowPlayingTile(mediaObserver: mediaObserver).withPanelFooter()
            return (AnyView(view), NSSize(width: 340, height: 360))
            
        case .pomodoro:
            let view = PomodoroTile().withPanelFooter()
            return (AnyView(view), NSSize(width: 300, height: 540))
            
        case .meetings:
            let view = MeetingMenuView().withPanelFooter()
            return (AnyView(view), NSSize(width: 380, height: 720))
            
        case .toggles:
            let view = QuickTogglesView().withPanelFooter()
            return (AnyView(view), NSSize(width: 280, height: 400))
        }
    }
    
    // MARK: - Legacy NSMenu code removed
    // Now using FloatingPanelController for all dropdowns
    
    private func createProgressBar(percent: Double, width: Int = 20) -> String {
        let filledBlocks = Int((percent / 100.0) * Double(width))
        let emptyBlocks = width - filledBlocks
        
        var bar = "["
        bar += String(repeating: "█", count: filledBlocks)
        bar += String(repeating: "░", count: emptyBlocks)
        bar += "]"
        
        return bar
    }
    
    private func createMenuItem(_ attributed: NSAttributedString) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = attributed
        item.isEnabled = false
        return item
    }
    
    func updateAnimationSpeed() {
        // Update each status item's animation speed based on its utility
        for (statusItem, view, utility) in statusItems {
            
            // Update animation speed if the view is a LottieAnimationView
            if let animationView = view as? LottieAnimationView {
                if utility == .music {
                    // Control Music Animation Play/Pause
                    if mediaObserver.isPlaying {
                        if !animationView.isAnimationPlaying {
                            animationView.play()
                        }
                        // Slower wave animation (0.6x speed)
                        animationView.animationSpeed = 0.6
                    } else {
                        animationView.stop()
                    }
                } else if utility == .pomodoro {
                    // Control Pomodoro Animation - Pause when timer is paused
                    if pomodoroManager.isRunning && !pomodoroManager.isPaused {
                        // Timer is actively running - play animation
                        animationView.loopMode = .loop
                        
                        if !animationView.isAnimationPlaying {
                            animationView.play()
                        }
                        
                        // Speed based on state: faster during focus, slower during break
                        let speed: CGFloat = pomodoroManager.state == .focus ? 1.0 : 0.7
                        animationView.animationSpeed = speed
                    } else {
                        // Timer is paused or not running - stop animation
                        animationView.stop()
                        animationView.loopMode = .playOnce
                        if !pomodoroManager.isRunning {
                            animationView.currentProgress = 0 // Reset only when fully stopped
                        }
                    }
                } else if utility == .battery {
                    // BATTERY ANIMATION - Speed = Battery Level (intuitive!)
                    // Full battery = FAST animation (happy/energetic)
                    // Low battery = SLOW animation (tired/dying)
                    if !animationView.isAnimationPlaying {
                        animationView.play()
                    }
                    
                    let level = systemMonitor.batteryLevel // 0.0 to 1.0
                    
                    if systemMonitor.isCharging || systemMonitor.isCharged {
                        // Charging or Full: FAST animation (excited!)
                        // Speed: 2.0x at 0% → 3.0x at 100%
                        animationView.animationSpeed = CGFloat(2.0 + level)
                    } else {
                        // Discharging: Speed matches battery level
                        // 100% = 2.0x (fast/happy), 0% = 0.2x (very slow/dying)
                        animationView.animationSpeed = CGFloat(0.2 + level * 1.8)
                    }
                } else {
                    // Standard Utility Animation Speed
                    let value = getValue(for: utility)
                    // Low value = 0.5x speed, High value = 3.0x speed
                    let speed = 0.5 + (value * 2.5)
                    animationView.animationSpeed = speed
                }
            }
            
            // Update display text if configured (FOR BOTH STATIC AND DYNAMIC ICONS)
            // NOTE: We don't need to do this here for Music, Pomodoro, or Meetings
            // Meetings is managed entirely by updateMeetingDisplay() / scheduleMeetingUpdate()
            if utility != .music && utility != .pomodoro && utility != .meetings,
               let config = settingsManager.configurations[utility],
               config.displayOption != .none {
                
                // Special handling for Network two-line display
                if utility == .network && config.displayOption == .speed {
                    // Find the speed label by tag and update it
                    if let speedLabel = statusItem.button?.subviews.first(where: { $0.tag == 999 }) as? NSTextField {
                        // Use compact short format (e.g. "156K", "2.4M") — never wraps to two lines
                        let dl = NetworkNative.formatSpeedShort(systemMonitor.networkDownload)
                        let ul = NetworkNative.formatSpeedShort(systemMonitor.networkUpload)
                        speedLabel.stringValue = "↓\(dl)\n↑\(ul)"
                    } else {
                        // Static icon mode - just update button title
                        statusItem.button?.title = getDisplayText(for: utility, config: config)
                    }
                } else {
                    statusItem.button?.title = getDisplayText(for: utility, config: config)
                }
            }
        }
    }
    
    // MARK: - Dual-Mode Handlers
    
    /// Called when transitioning TO Menu Bar mode - restore full animations
    @objc func handleRestoreMenuBarAnimations() {
        // Remove static status item if it exists
        if let staticItem = staticStatusItem {
            NSStatusBar.system.removeStatusItem(staticItem)
            staticStatusItem = nil
        }
        
        // Rebuild full menu bar with all animations (isTemporaryStaticMode is false)
        setupMenuBar()
    }
    
    /// Called when in alwaysMenuBar mode + external display detected.
    /// Rebuilds menu bar with all Lottie icons replaced by static SF Symbols.
    /// Does NOT change user's saved settings - purely a runtime override.
    @objc func handleForceStaticMenuBarIcons() {
        // Safety: ensure the flag is set before rebuilding
        guard AppModeManager.shared.isTemporaryStaticMode else {
            // Race condition fallback - wait and retry once
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard AppModeManager.shared.isTemporaryStaticMode else { return }
                self?.handleForceStaticMenuBarIcons()
            }
            return
        }
        
        // Remove static status item if it exists (from floating mode)
        if let staticItem = staticStatusItem {
            NSStatusBar.system.removeStatusItem(staticItem)
            staticStatusItem = nil
        }
        
        // Rebuild menu bar - setupMenuBar() now checks isTemporaryStaticMode
        // and will render all items as static when that flag is true
        setupMenuBar()
    }
    
    /// The single static status item used in floating bar mode
    private var staticStatusItem: NSStatusItem?
    
    /// Called when the system wakes from sleep — validate and recreate status items if needed
    @objc private func handleSystemWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.validateAndRebuildStatusItems()
        }
    }
    
    private func validateAndRebuildStatusItems() {
        let isInFloatingMode = AppModeManager.shared.activeState == .floatingBar
        if isInFloatingMode {
            // In floating bar mode the single static icon may have lost its button on wake
            if staticStatusItem == nil || staticStatusItem?.button == nil {
                handleUseStaticMenuBarIcon()
            }
        } else {
            // In menu bar mode rebuild any ghost status items (button == nil)
            let hasGhostItems = statusItems.contains { $0.item.button == nil }
            if hasGhostItems || statusItems.isEmpty {
                setupMenuBar()
            }
        }
    }
    
    /// Called when transitioning TO Floating Bar mode - use single static icon
    @objc func handleUseStaticMenuBarIcon() {
        // Clear timer view references before removing items
        meetingTimerView = nil
        pomodoroTimerView = nil
        
        // Remove all current status items
        for (statusItem, _, _) in statusItems {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItems.removeAll()
        
        // Create ONE static status item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let customIcon = NSImage(named: "AppFloatingBarIcon") {
                customIcon.isTemplate = true
                customIcon.size = NSSize(width: 14, height: 14)
                button.image = customIcon
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let icon = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "CharBar")?
                    .withSymbolConfiguration(config)
                button.image = icon
            }
            button.imagePosition = .imageOnly
            
            // Click toggles floating menu bar
            button.target = self
            button.action = #selector(toggleFloatingMenuBar)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        staticStatusItem = statusItem
    }
    
    @objc private func toggleFloatingMenuBar(_ sender: NSStatusBarButton) {
        // Get current event to check for right-click
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp {
                // Right-click: show context menu
                showFloatingBarContextMenu()
            } else {
                // Left-click: toggle floating bar
                ModeSwitcher.shared.toggleFloatingBar()
            }
        }
    }
    
    private func showFloatingBarContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Show Floating Bar", action: #selector(showFloatingBar), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CharBar", action: #selector(quitApp), keyEquivalent: "q"))
        
        if let button = staticStatusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }
    
    @objc private func showFloatingBar() {
        ModeSwitcher.shared.showFloatingBar()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    /// Show dropdown for a utility from the floating bar (called by FloatingMenuBarController)
    func showDropdownForFloatingBar(utility: UtilityType, at point: NSPoint) {
        // The FloatingMenuBarController now handles dropdown creation directly
        // This method is kept for backwards compatibility
        FloatingMenuBarController.shared.handleItemClick(utility: utility)
    }
    
    @objc func settingsChanged() {
        // Cancel any pending settings change to debounce rapid updates
        settingsChangeWorkItem?.cancel()
        
        // Prevent re-entrant calls
        guard !isUpdatingStatusItems else { return }
        
        // Create a new debounced work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Mark as updating to prevent re-entrant calls
            self.isUpdatingStatusItems = true
            
            // Ensure we're on the main thread for all NSStatusItem operations
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Rebuild menu bar (already has cleanup built in)
                self.setupMenuBar()
                
                // Reset flag after a small delay to allow system to stabilize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.isUpdatingStatusItems = false
                }
            }
        }
        
        settingsChangeWorkItem = workItem
        
        // Debounce: Wait 0.25 seconds before applying changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
    
    /// Safely clean up all existing status items
    private func cleanupStatusItems() {
        // Must be on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { [weak self] in
                self?.cleanupStatusItems()
            }
            return
        }
        
        // Stop all animations first and prepare items for removal
        for (item, view, _) in statusItems {
            // Stop Lottie animations
            if let lottieView = view as? LottieAnimationView {
                lottieView.stop()
            }
            
            // Hide the item first to reduce scene-related warnings
            item.isVisible = false
            
            // Remove all subviews from button
            if let button = item.button {
                button.subviews.forEach { $0.removeFromSuperview() }
                button.target = nil
                button.action = nil
                button.image = nil
                button.title = ""
            }
            
            view.removeFromSuperview()
        }
        
        // Clear button tag mappings
        buttonTagToUtility.removeAll()
        nextButtonTag = 1000
        
        // Clear rolling timer references
        pomodoroTimerView = nil
        meetingTimerView = nil
        meetingJoinSavedImage = nil
        
        // Remove status items from the system status bar (items are already hidden)
        for (item, _, _) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        
        // Clear our reference array
        statusItems.removeAll()
    }
    
    @objc func openSettings() {
        // Force app to front (switch to regular app temporarily)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Create or show settings window
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }

        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// Present the premium first-launch onboarding window.
    func showWelcomeWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if welcomeWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = ""
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.center()

            let view = WelcomeView { [weak self] in
                self?.dismissWelcomeWindow()
                self?.openSettings()
            }
            window.contentView = NSHostingView(rootView: view)
            welcomeWindow = window
        }

        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    private func dismissWelcomeWindow() {
        welcomeWindow?.close()
        welcomeWindow = nil
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func runSpeedTest() {
        systemMonitor.runSpeedTest()
    }
    
    func refreshNetworkSpeed() {
        // Update network readings (calls getifaddrs)
        NetworkNative.shared.update()
        
        // Only update display if network is configured to show speed
        guard let config = settingsManager.configurations[.network],
              config.displayOption == .speed else { return }
        
        // Find the Network Status Item
        guard let networkItemTuple = statusItems.first(where: { $0.utility == .network }),
              let button = networkItemTuple.item.button else { return }
        
        // Get SHORT formatted speed for menubar (compact, consistent width)
        let speed = NetworkNative.shared.downloadShort
        
        // Update button title
        button.title = speed
    }
    
    // Helper methods
    private func getValue(for utility: UtilityType) -> Double {
        switch utility {
        case .cpu: return systemMonitor.cpuUsage / 100.0
        case .gpu: return systemMonitor.gpuUsage / 100.0
        case .ram: return systemMonitor.ramUsage / 100.0
        case .battery: return systemMonitor.batteryLevel
        case .network:
            // Normalize network speed (0 = idle, 1 = high activity)
            let total = NetworkNative.shared.downloadSpeed + NetworkNative.shared.uploadSpeed
            return min(total / (1024 * 1024), 1.0) // 1MB/s = max speed
        case .bluetooth: return bluetoothManager.connectedAudioDevice != nil ? 1.0 : 0.3
        case .disk: return systemMonitor.diskUsage / 100.0
        case .music: return mediaObserver.isPlaying ? 1.0 : 0.0
        case .pomodoro: return pomodoroManager.progress // Sand level (1.0 = full, 0.0 = empty)
        case .meetings: 
            // If meeting is happening now or starting soon, animate faster
            if let meeting = meetingManager.displayMeeting {
                return meeting.isHappeningNow || meeting.isStartingSoon ? 1.0 : 0.5
            }
            return 0.3
        case .toggles:
            return 0.5
        }
    }
    
    private func getDisplayText(for utility: UtilityType, config: UtilityConfiguration) -> String {
        switch config.displayOption {
        case .none:
            return ""
        case .percentage:
            switch utility {
            case .cpu: return String(format: "%.0f%%", systemMonitor.cpuUsage)
            case .gpu: return String(format: "%.0f%%", systemMonitor.gpuUsage)
            case .ram: return String(format: "%.0f%%", systemMonitor.ramUsage)
            case .battery:
                return String(format: "%.0f%%", systemMonitor.batteryLevel * 100)
            case .disk: return String(format: "%.0f%%", systemMonitor.diskUsage)
            default: return ""
            }
        case .batteryLevel:
            // For Bluetooth - show connected audio device battery
            if utility == .bluetooth {
                return bluetoothManager.menuBarDisplayText
            }
            return ""
        case .absolute:
            switch utility {
            case .ram: return String(format: "%.1fG", systemMonitor.ramUsed)
            case .music:
                if mediaObserver.isPlaying {
                    let trackName = mediaObserver.title
                    return trackName.count > 20 ? String(trackName.prefix(20)) + "..." : trackName
                } else {
                    return "Paused"
                }
            default: return ""
            }
        case .speed:
            switch utility {
            case .network:
                return NetworkNative.shared.downloadShort
            default: return ""
            }
        case .timer:
            switch utility {
            case .pomodoro:
                if pomodoroManager.isRunning {
                    return pomodoroManager.timeRemainingFormatted
                } else {
                    return "Ready"
                }
            case .meetings:
                if let meeting = meetingManager.displayMeeting {
                    if meeting.isHappeningNow {
                        return "●"  // Just red dot for "now" - no text needed
                    } else {
                        // Just show time remaining (e.g., "10m" or "3h")
                        return meeting.compactTimeString
                    }
                }
                return ""
            default: return ""
            }
        }
    }
    
    private func getDisplayValue(for utility: UtilityType) -> String {
        switch utility {
        case .cpu: return String(format: "%.1f%%", systemMonitor.cpuUsage)
        case .gpu: return String(format: "%.1f%%", systemMonitor.gpuUsage)
        case .ram: return String(format: "%.1f/%.1f GB", systemMonitor.ramUsed, systemMonitor.ramTotal)
        case .battery:
            let percent = systemMonitor.batteryLevel * 100
            let chargingIcon = systemMonitor.isCharging ? "⚡" : ""
            return String(format: "%@%.0f%%", chargingIcon, percent)
        case .network: return "DL " + NetworkNative.shared.downloadFormatted + " UL " + NetworkNative.shared.uploadFormatted
        case .bluetooth: 
            if let device = bluetoothManager.connectedAudioDevice {
                return device.battery.hasBattery ? device.battery.shortDisplayString : device.name
            }
            return "No Device"
        case .disk: return String(format: "%.1f%%", systemMonitor.diskUsage)
        case .music: return mediaObserver.isPlaying ? mediaObserver.title : "Not Playing"
        case .pomodoro: return pomodoroManager.isRunning ? pomodoroManager.timeRemainingFormatted : pomodoroManager.state.displayName
        case .meetings: 
            if let meeting = meetingManager.displayMeeting {
                return meeting.isHappeningNow ? "●" : meeting.compactTimeString  // Just dot for "now"
            }
            return "✓"
        case .toggles:
            return "Quick Toggles"
        }
    }
    
    // MARK: - Accessibility Permissions (Simple like Maccy)
    
    /// Check if we have accessibility permission - pass nil to never trigger prompt
    func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrustedWithOptions(nil)
    }
    
    // MARK: - Global Shortcuts for All Utilities
    
    private func setupGlobalShortcuts() {
        shortcutManager = ShortcutManager.shared
        
        // Quick Join Meeting
        shortcutManager?.onQuickJoinMeeting = { [weak self] in
            self?.quickJoinCurrentMeeting()
        }
        
        // Connect Last Bluetooth
        shortcutManager?.onConnectLastBluetooth = { [weak self] in
            self?.connectLastBluetooth()
        }
        
        // Toggle Music Play/Pause
        shortcutManager?.onToggleMusic = { [weak self] in
            self?.toggleMusicPlayback()
        }
        
        // Toggle Pomodoro
        shortcutManager?.onTogglePomodoro = { [weak self] in
            self?.togglePomodoro()
        }
        
        // Toggle Floating Bar (popup at cursor if enabled)
        shortcutManager?.onToggleFloatingBar = {
            FloatingMenuBarController.shared.toggleAtCursor()
        }
    }
    
    // MARK: - Shortcut Actions
    
    /// Quick Join - instantly open the current meeting link
    @objc func quickJoinCurrentMeeting() {
        guard let meeting = meetingManager.displayMeeting else {
            showNotification(title: "No Meeting", message: "There's no upcoming meeting to join right now.")
            return
        }
        
        if meeting.hasVideoLink {
            meetingManager.joinMeeting(meeting)
            showNotification(title: "Joining Meeting", message: meeting.title)
        } else {
            showNotification(title: meeting.title, message: "This meeting doesn't have a video link.")
        }
    }
    
    /// Connect to last Bluetooth device (also triggered by keyboard shortcut)
    func connectLastBluetooth() {
        if let device = bluetoothManager.lastConnectedDevice {
            // Show loading state on the menu bar Bluetooth button
            if let entry = statusItems.first(where: { $0.utility == .bluetooth }),
               let button = entry.item.button {
                showBluetoothConnectingState(on: button)
            }
            bluetoothManager.connectToLastDevice()
            
            // Show connection popup - use menu bar icon if visible, otherwise at cursor
            if let entry = statusItems.first(where: { $0.utility == .bluetooth }) {
                BluetoothConnectionNotification.shared.show(deviceName: device.name, relativeTo: entry.item)
            } else {
                // Floating bar mode - show at cursor position
                let mousePos = NSEvent.mouseLocation
                let frame = NSRect(x: mousePos.x - 130, y: mousePos.y, width: 260, height: 70)
                BluetoothConnectionNotification.shared.showAtFloatingBar(deviceName: device.name, floatingBarFrame: frame)
            }
        } else {
            showNotification(title: "No Device", message: "No previously connected Bluetooth device found.")
        }
    }
    
    /// Toggle music play/pause
    func toggleMusicPlayback() {
        mediaObserver.togglePlayPause()
        let status = mediaObserver.isPlaying ? "Playing" : "Paused"
        showNotification(title: status, message: mediaObserver.title.isEmpty ? "Music" : mediaObserver.title)
    }
    
    /// Toggle Pomodoro timer
    func togglePomodoro() {
        pomodoroManager.toggleStartPause()
        if pomodoroManager.isRunning {
            showNotification(title: "Pomodoro Started", message: "\(pomodoroManager.focusDuration) minute session")
        } else {
            showNotification(title: "Pomodoro Paused", message: pomodoroManager.timeRemainingFormatted)
        }
    }
    
    /// Show a brief notification
    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = nil
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    @objc private func handleHotkeyRefresh() {
        // Re-register shortcuts if needed
        for action in ShortcutAction.allCases {
            if ShortcutManager.shared.isEnabled(action) {
                ShortcutManager.shared.registerShortcut(for: action)
            }
        }
    }
    
    // MARK: - Clean Termination
    
    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(atPath: Self.crashSentinelPath)
        
        FloatingMenuBarController.shared.hide()
        
        for entry in statusItems {
            NSStatusBar.system.removeStatusItem(entry.item)
        }
        statusItems.removeAll()
        
        songNotification.dismiss()
        pomodoroNotification.dismiss()
        MeetingNotification.shared.dismiss()
        
        pomodoroAnimationTimer?.invalidate()
        meetingUpdateTimer?.invalidate()
        settingsChangeWorkItem?.cancel()
        musicDisplayWorkItem?.cancel()
    }
}

// NSImage extension for resizing
extension NSImage {
    func resized(to newSize: NSSize) -> NSImage {
        // Use high-quality interpolation for better image quality
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        // Set high-quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        
        let rect = NSRect(origin: .zero, size: newSize)
        draw(in: rect, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        // Set backing scale factor for retina displays
        newImage.cacheMode = .always
        
        return newImage
    }
}

// Window controller for settings
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        
        if let monitor = sharedSystemMonitor, let manager = sharedSettingsManager {
            let settingsView = SettingsWindowView()
                .environmentObject(monitor)
                .environmentObject(manager)
            window.contentView = NSHostingView(rootView: settingsView)
        }
        
        self.init(window: window)
        window.delegate = self
    }
    
    // Switch back to accessory mode when window closes
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Crash Recovery Banner
struct CrashRecoveryView: View {
    var onContinue: () -> Void
    var onRestart: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("CharBar quit unexpectedly")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("An error caused the app to close. Your settings are safe.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button("Restart") { onRestart() }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
            
            Button("Dismiss") { onContinue() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

