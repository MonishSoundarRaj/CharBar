//
//  PomodoroManager.swift
//  CharBar
//
//  Pomodoro Timer Manager - Modern implementation inspired by TomatoBar
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

// MARK: - Pomodoro States
enum PomodoroState: String, Codable {
    case idle       // Not running
    case focus      // Work session
    case shortBreak // Short break (5 min)
    case longBreak  // Long break (15-30 min)
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
    
    var color: Color {
        // Neutral, monochromatic color scheme
        switch self {
        case .idle: return Color(white: 0.35)
        case .focus: return Color(white: 0.9) // Clean white for focus
        case .shortBreak: return Color(white: 0.7) // Soft gray for short break
        case .longBreak: return Color(white: 0.6) // Medium gray for long break
        }
    }
}

// MARK: - Pomodoro Manager
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()
    
    // MARK: - Published State
    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var progress: Double = 0.0 // 0.0 to 1.0 (for sand animation)
    @Published var completedPomodoros: Int = 0
    @Published var todayPomodoros: Int = 0
    @Published var isPaused: Bool = false // Track pause state for UI
    
    // MARK: - Settings (persisted)
    @AppStorage("pomodoro_focusDuration") var focusDuration: Int = 25 // minutes
    @AppStorage("pomodoro_shortBreakDuration") var shortBreakDuration: Int = 5
    @AppStorage("pomodoro_longBreakDuration") var longBreakDuration: Int = 15
    @AppStorage("pomodoro_pomodorosUntilLongBreak") var pomodorosUntilLongBreak: Int = 4
    @AppStorage("pomodoro_autoStartBreak") var autoStartBreak: Bool = true
    @AppStorage("pomodoro_autoStartFocus") var autoStartFocus: Bool = false
    @AppStorage("pomodoro_soundEnabled") var soundEnabled: Bool = true
    
    // MARK: - Private
    private var timer: DispatchSourceTimer?
    private(set) var totalDuration: TimeInterval = 0
    private var notificationCenter = UNUserNotificationCenter.current()
    private var isCompletionInProgress = false
    
    // MARK: - Computed Properties
    var timeRemainingFormatted: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var sandProgress: Double {
        // For Lottie - returns 0 at start, 1 at end (sand falls down)
        return 1.0 - progress
    }
    
    var isRunning: Bool {
        return state != .idle
    }
    
    var isTimerActive: Bool {
        return timer != nil
    }
    
    /// Is the current state a break/resting state?
    var isRestingState: Bool {
        return state == .shortBreak || state == .longBreak
    }
    
    /// Get the current menu bar animation name based on working/resting state
    var currentMenuBarAnimation: String {
        if isRestingState {
            // Use user's preference for resting
            let restingChar = UserDefaults.standard.string(forKey: "pomo_restingCharacter") ?? "sleepingCat"
            if let charType = CharacterType(rawValue: restingChar),
               let filename = charType.lottieFileName {
                return filename
            }
            return "Cat is sleeping and rolling"
        } else {
            // Use user's preference for working (or idle)
            let workingChar = UserDefaults.standard.string(forKey: "pomo_workingCharacter") ?? "hourglass"
            if let charType = CharacterType(rawValue: workingChar),
               let filename = charType.lottieFileName {
                return filename
            }
            return "timer"
        }
    }
    
    private var midnightTimer: Timer?
    
    // MARK: - Initialization
    init() {
        requestNotificationPermission()
        loadTodayStats()
        scheduleMidnightReset()
    }
    
    // MARK: - Public Methods
    
    func startFocus() {
        loadTodayStats()
        stopTimer()
        state = .focus
        isPaused = false
        totalDuration = TimeInterval(focusDuration * 60)
        timeRemaining = totalDuration
        progress = 1.0
        startTimer()
        objectWillChange.send()
        
        PomodoroSoundManager.shared.playFocusStart()
        SoundManager.shared.playSound()
        
        NotificationCenter.default.post(name: NSNotification.Name("PomodoroStateChanged"), object: nil)
    }
    
    func startShortBreak() {
        stopTimer()
        state = .shortBreak
        isPaused = false
        totalDuration = TimeInterval(shortBreakDuration * 60)
        timeRemaining = totalDuration
        progress = 1.0
        startTimer()
        objectWillChange.send()
        
        SoundManager.shared.stopSound()
        PomodoroSoundManager.shared.playBreakStart()
        
        // Show popup notification instead of system notification
        NotificationCenter.default.post(
            name: NSNotification.Name("PomodoroTimerComplete"),
            object: nil,
            userInfo: ["title": "Time for a short break!", "body": "Great work! Take \(shortBreakDuration) minutes to rest.", "state": "shortBreak"]
        )
    }
    
    func startLongBreak() {
        stopTimer()
        state = .longBreak
        isPaused = false
        totalDuration = TimeInterval(longBreakDuration * 60)
        timeRemaining = totalDuration
        progress = 1.0
        startTimer()
        objectWillChange.send()
        
        SoundManager.shared.stopSound()
        PomodoroSoundManager.shared.playBreakStart()
        
        // Show popup notification instead of system notification
        NotificationCenter.default.post(
            name: NSNotification.Name("PomodoroTimerComplete"),
            object: nil,
            userInfo: ["title": "Time for a long break!", "body": "You've completed \(pomodorosUntilLongBreak) pomodoros! Take \(longBreakDuration) minutes to recharge.", "state": "longBreak"]
        )
    }
    
    func pause() {
        stopTimer()
        isPaused = true
        objectWillChange.send()
        SoundManager.shared.stopSound()
    }
    
    func resume() {
        if state != .idle && timeRemaining > 0 {
            isPaused = false
            startTimer()
            objectWillChange.send()
            if state == .focus { SoundManager.shared.playSound() }
        }
    }
    
    func stop() {
        stopTimer()
        state = .idle
        timeRemaining = 0
        progress = 0
        isPaused = false
        objectWillChange.send()
        
        SoundManager.shared.stopSound()
        
        // Post notification for immediate UI update
        NotificationCenter.default.post(name: NSNotification.Name("PomodoroStateChanged"), object: nil)
    }
    
    func skip() {
        handleTimerComplete()
    }
    
    func toggleStartPause() {
        if state == .idle {
            startFocus()
        } else if timer == nil {
            resume()
        } else {
            pause()
        }
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        let queue = DispatchQueue(label: "PomodoroTimer", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        
        timer?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        
        timer?.resume()
    }
    
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
    
    private func tick() {
        guard timeRemaining > 0.05 else {
            guard !isCompletionInProgress else { return }
            handleTimerComplete()
            return
        }
        
        timeRemaining -= 0.1
        progress = max(0, timeRemaining / totalDuration)
        
        NotificationCenter.default.post(name: NSNotification.Name("PomodoroTick"), object: nil)
    }
    
    private func handleTimerComplete() {
        guard !isCompletionInProgress else { return }
        isCompletionInProgress = true
        defer { isCompletionInProgress = false }
        
        stopTimer()
        
        if soundEnabled {
            PomodoroSoundManager.shared.playComplete()
        }
        
        switch state {
        case .focus:
            // Completed a pomodoro!
            completedPomodoros += 1
            todayPomodoros += 1
            saveTodayStats()
            
            // Check if time for long break
            if completedPomodoros >= pomodorosUntilLongBreak {
                completedPomodoros = 0
                if autoStartBreak {
                    startLongBreak()
                } else {
                    state = .idle
                    objectWillChange.send()
                    // Show popup notification
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PomodoroTimerComplete"),
                        object: nil,
                        userInfo: ["title": "Pomodoro Complete!", "body": "Time for a \(longBreakDuration) minute long break. You earned it!", "state": "complete"]
                    )
                }
            } else {
                if autoStartBreak {
                    startShortBreak()
                } else {
                    state = .idle
                    objectWillChange.send()
                    // Show popup notification
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PomodoroTimerComplete"),
                        object: nil,
                        userInfo: ["title": "Pomodoro Complete!", "body": "Take a \(shortBreakDuration) minute break. \(pomodorosUntilLongBreak - completedPomodoros) more until long break!", "state": "complete"]
                    )
                }
            }
            
        case .shortBreak, .longBreak:
            if autoStartFocus {
                startFocus()
            } else {
                state = .idle
                objectWillChange.send()
                // Show popup notification
                NotificationCenter.default.post(
                    name: NSNotification.Name("PomodoroTimerComplete"),
                    object: nil,
                    userInfo: ["title": "Break Over!", "body": "Ready to focus again?", "state": "breakOver"]
                )
            }
            
        case .idle:
            break
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("PomodoroStateChanged"), object: nil)
    }
    
    // MARK: - Notifications
    
    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundEnabled ? .default : nil
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
        }
    }
    
    // Sound is handled by PomodoroSoundManager
    
    func resetTodayStats() {
        todayPomodoros = 0
        completedPomodoros = 0
        saveTodayStats()
        objectWillChange.send()
    }
    
    // MARK: - Stats Persistence
    
    private func loadTodayStats() {
        let defaults = UserDefaults.standard
        let lastDate = defaults.string(forKey: "pomodoro_lastDate") ?? ""
        let today = dateString()
        
        if lastDate == today {
            todayPomodoros = defaults.integer(forKey: "pomodoro_todayCount")
        } else {
            todayPomodoros = 0
            defaults.set(today, forKey: "pomodoro_lastDate")
        }
    }
    
    private func saveTodayStats() {
        let defaults = UserDefaults.standard
        defaults.set(dateString(), forKey: "pomodoro_lastDate")
        defaults.set(todayPomodoros, forKey: "pomodoro_todayCount")
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func scheduleMidnightReset() {
        midnightTimer?.invalidate()
        
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) else { return }
        let interval = tomorrow.timeIntervalSinceNow + 1
        
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.loadTodayStats()
            self?.objectWillChange.send()
            self?.scheduleMidnightReset()
        }
    }
}

