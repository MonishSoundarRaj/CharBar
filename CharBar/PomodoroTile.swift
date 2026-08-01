//
//  PomodoroTile.swift
//  CharBar
//
//  Premium Pomodoro Timer UI - Apple Watch Focus-inspired design
//

import SwiftUI
import Lottie

struct PomodoroTile: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @ObservedObject var soundManager = SoundManager.shared
    @AppStorage("pomodoro_lastOpenedDate") private var lastOpenedDate: Double = Date().timeIntervalSince1970
    @State private var selectedDuration: Int = 25
    @State private var showSettings: Bool = true
    
    private let presetDurations = [15, 25, 30, 45, 60]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                timerDisplay
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                controlsSection
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                statsSection
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 500)
        .padding(8)
        .onAppear {
            let lastDate = Date(timeIntervalSince1970: lastOpenedDate)
            if !Calendar.current.isDateInToday(lastDate) {
                pomodoro.resetTodayStats()
            }
            lastOpenedDate = Date().timeIntervalSince1970
        }
    }
    
    // MARK: - Timer Display
    private var timerDisplay: some View {
        VStack(spacing: 16) {
            // State Label - Minimal
            Text(pomodoro.state.displayName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(pomodoro.state == .idle ? .white.opacity(0.5) : .white.opacity(0.8))
                .padding(.top, 20)
            
            // Apple Watch Focus-style Ring Timer
            ZStack {
                // Tick marks ring
                AppleFocusRing(
                    progress: pomodoro.progress,
                    isRunning: pomodoro.isRunning && !pomodoro.isPaused,
                    isPaused: pomodoro.isPaused,
                    state: pomodoro.state
                )
                .frame(width: 160, height: 160)
                
                // Center content
                VStack(spacing: 6) {
                    if pomodoro.isRunning || pomodoro.isPaused {
                        // Show countdown timer
                        Text(pomodoro.timeRemainingFormatted)
                            .font(.system(size: 38, weight: .light, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                        
                        // Paused indicator
                        if pomodoro.isPaused {
                            Text("Paused")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else {
                        // Idle state - show icon
                        Image(systemName: "timer")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text("Focus")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            
            // Duration Selector (only when idle)
            if !pomodoro.isRunning {
                HStack(spacing: 6) {
                    ForEach(presetDurations, id: \.self) { duration in
                        durationButton(duration)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 20)
    }
    
    private func durationButton(_ duration: Int) -> some View {
        Button(action: {
            selectedDuration = duration
            pomodoro.focusDuration = duration
        }) {
            Text("\(duration)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(selectedDuration == duration ? .white : .white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selectedDuration == duration 
                              ? Color.white.opacity(0.15) 
                              : Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(selectedDuration == duration ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        HStack(spacing: 24) {
            // Skip/Reset Button
            Button(action: {
                if pomodoro.isRunning {
                    pomodoro.skip()
                } else {
                    pomodoro.stop()
                }
            }) {
                Image(systemName: pomodoro.isRunning ? "forward.fill" : "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!pomodoro.isRunning && pomodoro.state == .idle)
            .opacity((!pomodoro.isRunning && pomodoro.state == .idle) ? 0.4 : 1)
            
            // Main Start/Pause Button
            Button(action: {
                pomodoro.toggleStartPause()
            }) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(pomodoro.isRunning && !pomodoro.isPaused ? .black : .white)
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(
                                pomodoro.isRunning && !pomodoro.isPaused
                                    ? Color.white
                                    : Color.white.opacity(0.12)
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            
            // Stop Button
            Button(action: {
                pomodoro.stop()
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!pomodoro.isRunning)
            .opacity(!pomodoro.isRunning ? 0.4 : 1)
        }
        .padding(.vertical, 20)
    }
    
    private var buttonIcon: String {
        if pomodoro.state == .idle {
            return "play.fill"
        } else if pomodoro.isPaused {
            return "play.fill"
        } else {
            return "pause.fill"
        }
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(spacing: 12) {
            // Today's Progress
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's Sessions")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                    
                    HStack(spacing: 5) {
                        ForEach(0..<pomodoro.pomodorosUntilLongBreak, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(index < pomodoro.todayPomodoros % pomodoro.pomodorosUntilLongBreak 
                                      ? Color.white.opacity(0.8)
                                      : Color.white.opacity(0.15))
                                .frame(width: 18, height: 6)
                        }
                        
                        Text("\(pomodoro.todayPomodoros)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.leading, 6)
                    }
                    .contextMenu {
                        Button("Reset Today's Count") {
                            pomodoro.resetTodayStats()
                        }
                    }
                }
                
                Spacer()
                
                // Quick Settings Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSettings.toggle()
                    }
                }) {
                    Image(systemName: showSettings ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            // Settings Panel (expandable)
            if showSettings {
                settingsPanel
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Settings Panel
    private var settingsPanel: some View {
        VStack(spacing: 10) {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 16)
            
            // Focus Duration
            settingsRow(
                title: "Focus",
                value: "\(pomodoro.focusDuration) min",
                decrease: { if pomodoro.focusDuration > 5 { pomodoro.focusDuration -= 5 } },
                increase: { if pomodoro.focusDuration < 60 { pomodoro.focusDuration += 5 } }
            )
            
            // Short Break Duration
            settingsRow(
                title: "Short Break",
                value: "\(pomodoro.shortBreakDuration) min",
                decrease: { if pomodoro.shortBreakDuration > 1 { pomodoro.shortBreakDuration -= 1 } },
                increase: { if pomodoro.shortBreakDuration < 15 { pomodoro.shortBreakDuration += 1 } }
            )
            
            // Long Break Duration
            settingsRow(
                title: "Long Break",
                value: "\(pomodoro.longBreakDuration) min",
                decrease: { if pomodoro.longBreakDuration > 5 { pomodoro.longBreakDuration -= 5 } },
                increase: { if pomodoro.longBreakDuration < 30 { pomodoro.longBreakDuration += 5 } }
            )
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            
            // Toggle Options
            Toggle(isOn: $pomodoro.autoStartBreak) {
                Text("Auto-start breaks")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.white.opacity(0.8)))
            .padding(.horizontal, 16)
            
            Toggle(isOn: $pomodoro.soundEnabled) {
                Text("Sound effects")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.white.opacity(0.8)))
            .padding(.horizontal, 16)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            
            // Soundscape Picker
            soundscapeSection
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Soundscape Section
    private var soundscapeSection: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("Focus Soundscape")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                // Current soundscape indicator
                if soundManager.isPlaying && soundManager.currentSoundscape != .silent {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Playing")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
            .padding(.horizontal, 16)
            
            // Soundscape Options
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Soundscape.allCases) { soundscape in
                        SoundscapeChip(
                            soundscape: soundscape,
                            isSelected: soundManager.currentSoundscape == soundscape,
                            isPlaying: soundManager.isPlaying && soundManager.currentSoundscape == soundscape
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                soundManager.currentSoundscape = soundscape
                                if soundscape != .silent && pomodoro.isRunning {
                                    soundManager.playSound()
                                } else if soundscape == .silent {
                                    soundManager.stopSound()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Volume Slider (when not silent)
            if soundManager.currentSoundscape != .silent {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Slider(value: $soundManager.volume, in: 0...1)
                        .accentColor(Color.white.opacity(0.6))
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
        .onChange(of: pomodoro.isRunning) { _, isRunning in
            // Auto-play soundscape when timer starts
            if isRunning && soundManager.currentSoundscape != .silent {
                soundManager.playSound()
            } else if !isRunning {
                soundManager.stopSound()
            }
        }
    }
    
    private func settingsRow(title: String, value: String, decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            HStack(spacing: 10) {
                Button(action: decrease) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 55)
                    .monospacedDigit()
                
                Button(action: increase) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Apple Focus Ring (Apple Watch-style tick marks)
struct AppleFocusRing: View {
    let progress: Double
    let isRunning: Bool
    let isPaused: Bool
    let state: PomodoroState
    
    private let tickCount = 60
    private let ringRadius: CGFloat = 70
    
    var body: some View {
        ZStack {
            // Background ticks
            ForEach(0..<tickCount, id: \.self) { index in
                TickMark(
                    index: index,
                    total: tickCount,
                    isActive: isTickActive(index),
                    isCurrent: isCurrentTick(index),
                    isPaused: isPaused,
                    radius: ringRadius
                )
            }
            
            // Inner glow ring
            Circle()
                .stroke(
                    Color.white.opacity(isRunning && !isPaused ? 0.1 : 0.05),
                    lineWidth: 1
                )
                .frame(width: ringRadius * 2 - 20, height: ringRadius * 2 - 20)
        }
    }
    
    private func isTickActive(_ index: Int) -> Bool {
        let tickProgress = Double(index) / Double(tickCount)
        return tickProgress < progress
    }
    
    private func isCurrentTick(_ index: Int) -> Bool {
        let currentTickIndex = Int(progress * Double(tickCount))
        return index == currentTickIndex || index == currentTickIndex - 1
    }
}

struct TickMark: View {
    let index: Int
    let total: Int
    let isActive: Bool
    let isCurrent: Bool
    let isPaused: Bool
    let radius: CGFloat
    
    private var angle: Double {
        // Start at 12 o'clock (top), go clockwise
        return (Double(index) / Double(total)) * 360 - 90
    }
    
    private var tickHeight: CGFloat {
        // Every 5th tick is longer
        return index % 5 == 0 ? 12 : 8
    }
    
    private var tickWidth: CGFloat {
        return index % 5 == 0 ? 3 : 2.5
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: tickWidth / 2)
            .fill(tickColor)
            .frame(width: tickWidth, height: tickHeight)
            .offset(y: -radius + tickHeight / 2)
            .rotationEffect(.degrees(angle + 90))
            .animation(isPaused ? nil : .easeInOut(duration: 0.15), value: isActive)
    }
    
    private var tickColor: Color {
        if isActive {
            if isCurrent && !isPaused {
                // Current tick glows
                return Color.white
            }
            // Active ticks are bright white
            return Color.white.opacity(0.85)
        } else {
            // Inactive ticks are dim
            return Color.white.opacity(0.15)
        }
    }
}

// MARK: - Soundscape Chip
struct SoundscapeChip: View {
    let soundscape: Soundscape
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    // Icon background
                    Circle()
                        .fill(
                            isSelected 
                                ? Color.white.opacity(0.15) 
                                : Color.white.opacity(isHovering ? 0.1 : 0.05)
                        )
                        .frame(width: 38, height: 38)
                    
                    // Icon
                    Image(systemName: soundscape.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.5))
                    
                    // Playing indicator
                    if isPlaying {
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 38, height: 38)
                            .scaleEffect(pulseScale)
                            .opacity(2 - pulseScale)
                            .onAppear {
                                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                    pulseScale = 1.5
                                }
                            }
                            .onDisappear {
                                pulseScale = 1.0
                            }
                    }
                }
                
                // Label
                Text(soundscape == .whiteNoise ? "Noise" : soundscape.rawValue)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .white.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(width: 52)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.15) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Compact Menu Bar View (for displaying in menu bar dropdown)
struct PomodoroCompactView: View {
    @ObservedObject var pomodoro: PomodoroManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Mini progress indicator with tick style
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2)
                    .frame(width: 18, height: 18)
                
                Circle()
                    .trim(from: 0, to: pomodoro.progress)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(-90))
            }
            
            Text(pomodoro.timeRemainingFormatted)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .monospacedDigit()
        }
    }
}

#Preview {
    PomodoroTile()
        .frame(width: 300, height: 520)
        .background(Color.black.opacity(0.9))
}

