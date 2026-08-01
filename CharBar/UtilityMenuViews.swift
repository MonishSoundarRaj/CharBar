//
//  UtilityMenuViews.swift
//  CharBar
//
//  Modern Apple-style utility menu views
//  Clean, monochromatic design with subtle gradients
//

import SwiftUI

// MARK: - Modern Design System
private struct DesignSystem {
    // Colors - Monochromatic with subtle accents
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.4)
    static let divider = Color.white.opacity(0.08)
    static let cardBackground = Color.white.opacity(0.04)
    static let progressBackground = Color.white.opacity(0.08)
    static let progressFill = Color.white.opacity(0.7)
    
    // Chart colors - Subtle gradients
    static let chartGradient = LinearGradient(
        colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let chartStroke = Color.white.opacity(0.5)
    
    // Fonts
    static func title() -> Font { .system(size: 13, weight: .semibold, design: .rounded) }
    static func headline() -> Font { .system(size: 28, weight: .light, design: .rounded) }
    static func subheadline() -> Font { .system(size: 12, weight: .medium, design: .rounded) }
    static func body() -> Font { .system(size: 11, weight: .regular, design: .rounded) }
    static func caption() -> Font { .system(size: 10, weight: .medium, design: .rounded) }
}

// MARK: - CPU Menu View
struct CPUMenuView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    
    private var uptimeFormatted: String {
        let uptime = systemMonitor.systemUptime
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let mins = (Int(uptime) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
    
    private var tempColor: Color {
        let temp = systemMonitor.cpuTemperature
        if temp > 90 { return Color.red.opacity(0.8) }
        if temp > 75 { return Color.orange.opacity(0.8) }
        return DesignSystem.textSecondary
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Main metric
                VStack(spacing: 4) {
                    Text("CPU")
                        .font(DesignSystem.caption())
                        .foregroundColor(DesignSystem.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    Text(String(format: "%.0f", systemMonitor.cpuUsage))
                        .font(.system(size: 52, weight: .ultraLight, design: .rounded))
                        .foregroundColor(DesignSystem.textPrimary)
                    + Text("%")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .foregroundColor(DesignSystem.textSecondary)
                    
                    if systemMonitor.cpuTemperature > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 10))
                            Text(String(format: "%.0f°C", systemMonitor.cpuTemperature))
                                .font(DesignSystem.subheadline())
                        }
                        .foregroundColor(tempColor)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Progress bar
                ModernProgressBar(value: systemMonitor.cpuUsage / 100)
                    .frame(height: 4)
                    .padding(.horizontal, 20)
                
                // Chart
                if systemMonitor.cpuHistory.count > 2 {
                    ModernAreaChart(data: systemMonitor.cpuHistory, maxValue: 100)
                        .frame(height: 80)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
                
                // CPU Info Section
                ModernDivider()
                
                VStack(spacing: 8) {
                    SectionHeader(title: "PROCESSOR")
                    
                    if !systemMonitor.cpuModelName.isEmpty {
                        MetricRow(label: "Model", value: systemMonitor.cpuModelName)
                    }
                    
                    if systemMonitor.cpuPerformanceCores > 0 && systemMonitor.cpuEfficiencyCores > 0 {
                        MetricRow(label: "Performance", value: "\(systemMonitor.cpuPerformanceCores) cores")
                        MetricRow(label: "Efficiency", value: "\(systemMonitor.cpuEfficiencyCores) cores")
                        MetricRow(label: "Total", value: "\(systemMonitor.cpuCoreCount) cores")
                    } else if systemMonitor.cpuCoreCount > 0 {
                        MetricRow(label: "Cores", value: "\(systemMonitor.cpuCoreCount)")
                    }
                    
                    MetricRow(label: "Uptime", value: uptimeFormatted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Load Breakdown
                ModernDivider()
                
                VStack(spacing: 8) {
                    SectionHeader(title: "LOAD BREAKDOWN")
                    
                    LoadBarRow(label: "System", value: systemMonitor.cpuSystemLoad, maxValue: 100)
                    LoadBarRow(label: "User", value: systemMonitor.cpuUserLoad, maxValue: 100)
                    LoadBarRow(label: "Idle", value: systemMonitor.cpuIdleLoad, maxValue: 100)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Top Processes
                if !systemMonitor.topCPUProcesses.isEmpty {
                    ModernDivider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "TOP PROCESSES")
                        
                        ForEach(Array(systemMonitor.topCPUProcesses.enumerated()), id: \.offset) { _, proc in
                            ProcessRow(name: proc.name, icon: proc.icon, value: String(format: "%.1f%%", proc.usage))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - GPU Menu View
struct GPUMenuView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    
    private var statusText: String {
        systemMonitor.gpuUsage > 80 ? "High Load" : systemMonitor.gpuUsage > 50 ? "Active" : "Idle"
    }
    
    private var statusColor: Color {
        systemMonitor.gpuUsage > 80 ? Color.red.opacity(0.8) :
        systemMonitor.gpuUsage > 50 ? Color.orange.opacity(0.8) :
        Color.green.opacity(0.6)
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Main metric
                VStack(spacing: 4) {
                    Text("GPU")
                        .font(DesignSystem.caption())
                        .foregroundColor(DesignSystem.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    Text(String(format: "%.0f", systemMonitor.gpuUsage))
                        .font(.system(size: 52, weight: .ultraLight, design: .rounded))
                        .foregroundColor(DesignSystem.textPrimary)
                    + Text("%")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .foregroundColor(DesignSystem.textSecondary)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(DesignSystem.subheadline())
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // Progress bar
                ModernProgressBar(value: systemMonitor.gpuUsage / 100)
                    .frame(height: 4)
                    .padding(.horizontal, 20)
                
                // Chart
                if systemMonitor.gpuHistory.count > 2 {
                    ModernAreaChart(data: systemMonitor.gpuHistory, maxValue: 100)
                        .frame(height: 70)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
                
                ModernDivider()
                    .padding(.top, systemMonitor.gpuHistory.count > 2 ? 0 : 16)
                
                // GPU Info
                VStack(spacing: 8) {
                    SectionHeader(title: "GRAPHICS")
                    
                    if !systemMonitor.gpuModelName.isEmpty {
                        MetricRow(label: "Renderer", value: systemMonitor.gpuModelName)
                    }
                    
                    MetricRow(label: "Utilization", value: String(format: "%.1f%%", systemMonitor.gpuUsage))
                    
                    if systemMonitor.gpuTemperature > 0 {
                        MetricRow(label: "Temperature", value: String(format: "%.0f°C", systemMonitor.gpuTemperature))
                    }
                    
                    if systemMonitor.gpuCoreCount > 0 {
                        MetricRow(label: "GPU Cores", value: "\(systemMonitor.gpuCoreCount)")
                    }
                    
                    if systemMonitor.gpuVRAM > 0 {
                        MetricRow(label: "VRAM", value: String(format: "%.0f GB", systemMonitor.gpuVRAM))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Unified Memory note for Apple Silicon
                if systemMonitor.cpuModelName.contains("Apple") || systemMonitor.gpuModelName.contains("Apple") {
                    ModernDivider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textTertiary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unified Memory")
                                .font(DesignSystem.subheadline())
                                .foregroundColor(DesignSystem.textSecondary)
                            Text("GPU shares memory with CPU on Apple Silicon")
                                .font(DesignSystem.caption())
                                .foregroundColor(DesignSystem.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - RAM Menu View
struct RAMMenuView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    
    private var pressureColor: Color {
        switch systemMonitor.ramPressureLevel {
        case 4: return Color.red.opacity(0.8)
        case 2: return Color.orange.opacity(0.8)
        default: return Color.green.opacity(0.6)
        }
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Main metric
                VStack(spacing: 4) {
                    Text("MEMORY")
                        .font(DesignSystem.caption())
                        .foregroundColor(DesignSystem.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", systemMonitor.ramUsed))
                            .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("GB")
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .foregroundColor(DesignSystem.textSecondary)
                        
                        Text("/")
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .foregroundColor(DesignSystem.textTertiary)
                        
                        Text(String(format: "%.0f GB", systemMonitor.ramTotal))
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    
                    // Memory pressure indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(pressureColor)
                            .frame(width: 6, height: 6)
                        Text("Pressure: \(systemMonitor.ramPressure)")
                            .font(DesignSystem.subheadline())
                            .foregroundColor(pressureColor)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Progress bar
                ModernProgressBar(value: systemMonitor.ramUsage / 100)
                    .frame(height: 4)
                    .padding(.horizontal, 20)
                
                // Chart
                if systemMonitor.ramHistory.count > 2 {
                    ModernAreaChart(data: systemMonitor.ramHistory, maxValue: 100)
                        .frame(height: 70)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
                
                ModernDivider()
                
                // Memory Breakdown with visual bars
                VStack(spacing: 10) {
                    SectionHeader(title: "MEMORY BREAKDOWN")
                    
                    MemoryBreakdownRow(label: "App Memory", value: systemMonitor.ramApp, total: systemMonitor.ramTotal, color: Color.blue.opacity(0.6))
                    MemoryBreakdownRow(label: "Wired", value: systemMonitor.ramWired, total: systemMonitor.ramTotal, color: Color.orange.opacity(0.6))
                    MemoryBreakdownRow(label: "Compressed", value: systemMonitor.ramCompressed, total: systemMonitor.ramTotal, color: Color.purple.opacity(0.6))
                    MemoryBreakdownRow(label: "Cached", value: systemMonitor.ramCached, total: systemMonitor.ramTotal, color: Color.green.opacity(0.4))
                    MemoryBreakdownRow(label: "Free", value: systemMonitor.ramFree, total: systemMonitor.ramTotal, color: Color.white.opacity(0.15))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Swap info
                ModernDivider()
                
                VStack(spacing: 8) {
                    SectionHeader(title: "SWAP")
                    
                    if systemMonitor.swapUsed > 0.01 {
                        MetricRow(label: "Used", value: String(format: "%.2f GB", systemMonitor.swapUsed))
                        if systemMonitor.swapTotal > 0 {
                            MetricRow(label: "Total", value: String(format: "%.2f GB", systemMonitor.swapTotal))
                            
                            ModernProgressBar(value: systemMonitor.swapTotal > 0 ? systemMonitor.swapUsed / systemMonitor.swapTotal : 0)
                                .frame(height: 3)
                        }
                    } else {
                        HStack {
                            Text("No swap in use")
                                .font(DesignSystem.body())
                                .foregroundColor(DesignSystem.textTertiary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Top Processes
                if !systemMonitor.topRAMProcesses.isEmpty {
                    ModernDivider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "TOP PROCESSES")
                        
                        ForEach(Array(systemMonitor.topRAMProcesses.enumerated()), id: \.offset) { _, proc in
                            let memGB = proc.usage / (1024 * 1024 * 1024)
                            let memText = memGB > 1 ? String(format: "%.1f GB", memGB) : String(format: "%.0f MB", proc.usage / (1024 * 1024))
                            ProcessRow(name: proc.name, icon: proc.icon, value: memText)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - Battery Menu View
struct BatteryMenuView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    
    private var timeText: String {
        if systemMonitor.isBatteryPowered {
            if systemMonitor.timeToEmpty > 0 {
                let hours = systemMonitor.timeToEmpty / 60
                let mins = systemMonitor.timeToEmpty % 60
                return String(format: "%d:%02d remaining", hours, mins)
            }
            return "Calculating..."
        } else {
            if systemMonitor.isCharged || systemMonitor.batteryLevel >= 1.0 {
                return "Fully Charged"
            } else if systemMonitor.timeToCharge > 0 {
                let hours = systemMonitor.timeToCharge / 60
                let mins = systemMonitor.timeToCharge % 60
                return String(format: "%d:%02d until full", hours, mins)
            }
            return "Charging..."
        }
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header label
                Text("BATTERY")
                    .font(DesignSystem.caption())
                    .foregroundColor(DesignSystem.textTertiary)
                    .textCase(.uppercase)
                    .tracking(1)
                    .padding(.top, 24)
                
                // Main metric with battery ring
                VStack(spacing: 8) {
                    ZStack {
                        // Background ring
                        Circle()
                            .stroke(DesignSystem.progressBackground, lineWidth: 8)
                            .frame(width: 100, height: 100)
                        
                        // Progress ring
                        Circle()
                            .trim(from: 0, to: systemMonitor.batteryLevel)
                            .stroke(
                                DesignSystem.progressFill,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                        
                        // Center content
                        VStack(spacing: 2) {
                            if systemMonitor.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                            
                            Text(String(format: "%.0f", systemMonitor.batteryLevel * 100))
                                .font(.system(size: 28, weight: .light, design: .rounded))
                                .foregroundColor(DesignSystem.textPrimary)
                            + Text("%")
                                .font(.system(size: 12, weight: .light, design: .rounded))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                    
                    Text(timeText)
                        .font(DesignSystem.subheadline())
                        .foregroundColor(DesignSystem.textSecondary)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
                
                // Chart
                if systemMonitor.batteryHistory.count > 2 {
                    ModernAreaChart(data: systemMonitor.batteryHistory, maxValue: 100)
                        .frame(height: 60)
                        .padding(.horizontal, 16)
                }
                
                ModernDivider()
                
                // Battery Health
                VStack(spacing: 8) {
                    SectionHeader(title: "BATTERY HEALTH")
                    
                    HStack {
                        Text("Condition")
                            .font(DesignSystem.body())
                            .foregroundColor(DesignSystem.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(systemMonitor.batteryHealth > 80 ? Color.green.opacity(0.6) : Color.orange.opacity(0.6))
                                .frame(width: 6, height: 6)
                            Text(systemMonitor.batteryHealth > 80 ? "Good" : "Service Recommended")
                                .font(DesignSystem.subheadline())
                                .foregroundColor(DesignSystem.textPrimary)
                        }
                    }
                    
                    MetricRow(label: "Maximum Capacity", value: "\(systemMonitor.batteryHealth)%")
                    MetricRow(label: "Cycle Count", value: "\(systemMonitor.batteryCycles)")
                    
                    if systemMonitor.designedCapacity > 0 {
                        MetricRow(label: "Design Capacity", value: "\(systemMonitor.designedCapacity) mAh")
                        MetricRow(label: "Current Max", value: "\(systemMonitor.maxCapacity) mAh")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                ModernDivider()
                
                // Power Details
                VStack(spacing: 8) {
                    SectionHeader(title: "POWER")
                    
                    MetricRow(label: "Source", value: systemMonitor.isBatteryPowered ? "Battery" : "AC Power")
                    MetricRow(label: "Power Draw", value: String(format: "%.1f W", abs(systemMonitor.batteryPower)))
                    
                    if systemMonitor.batteryTemperature > 0 {
                        MetricRow(label: "Temperature", value: String(format: "%.1f°C", systemMonitor.batteryTemperature))
                    }
                    
                    if systemMonitor.batteryVoltage > 0 {
                        MetricRow(label: "Voltage", value: String(format: "%.2f V", systemMonitor.batteryVoltage))
                    }
                    
                    if systemMonitor.batteryAmperage != 0 {
                        MetricRow(label: "Amperage", value: "\(systemMonitor.batteryAmperage) mA")
                    }
                    
                    if systemMonitor.acWatts > 0 {
                        MetricRow(label: "Adapter", value: "\(systemMonitor.acWatts) W")
                    }
                    
                    if systemMonitor.optimizedCharging {
                        HStack(spacing: 6) {
                            Image(systemName: "battery.100.bolt")
                                .font(.system(size: 10))
                            Text("Optimized Charging Active")
                                .font(DesignSystem.caption())
                        }
                        .foregroundColor(Color.green.opacity(0.6))
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Top Energy Consumers
                if !systemMonitor.topEnergyProcesses.isEmpty {
                    ModernDivider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "ENERGY IMPACT")
                        
                        ForEach(Array(systemMonitor.topEnergyProcesses.enumerated()), id: \.offset) { _, proc in
                            ProcessRow(name: proc.name, icon: proc.icon, value: String(format: "%.1f", proc.usage))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - Network Menu View
struct NetworkMenuView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    @State private var ipCopied = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Speed display
                VStack(spacing: 16) {
                    Text("NETWORK")
                        .font(DesignSystem.caption())
                        .foregroundColor(DesignSystem.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    HStack(spacing: 32) {
                        // Download
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .medium))
                                Text("DOWN")
                                    .font(DesignSystem.caption())
                            }
                            .foregroundColor(DesignSystem.textTertiary)
                            
                            Text(NetworkNative.shared.downloadFormatted)
                                .font(.system(size: 24, weight: .light, design: .rounded))
                                .foregroundColor(DesignSystem.textPrimary)
                            
                            Text("/s")
                                .font(DesignSystem.body())
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                        
                        // Divider
                        Rectangle()
                            .fill(DesignSystem.divider)
                            .frame(width: 1, height: 50)
                        
                        // Upload
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .medium))
                                Text("UP")
                                    .font(DesignSystem.caption())
                            }
                            .foregroundColor(DesignSystem.textTertiary)
                            
                            Text(NetworkNative.shared.uploadFormatted)
                                .font(.system(size: 24, weight: .light, design: .rounded))
                                .foregroundColor(DesignSystem.textPrimary)
                            
                            Text("/s")
                                .font(DesignSystem.body())
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // Chart
                if systemMonitor.networkDownloadHistory.count > 2 {
                    ModernDualAreaChart(
                        upData: systemMonitor.networkUploadHistory,
                        downData: systemMonitor.networkDownloadHistory
                    )
                    .frame(height: 70)
                    .padding(.horizontal, 16)
                }
                
                ModernDivider()
                
                // Total transferred
                VStack(spacing: 8) {
                    SectionHeader(title: "DATA TRANSFERRED")
                    
                    let totalDownloadGB = Double(NetworkNative.shared.totalDownload) / (1024 * 1024 * 1024)
                    let totalUploadGB = Double(NetworkNative.shared.totalUpload) / (1024 * 1024 * 1024)
                    
                    MetricRow(label: "Downloaded", value: formatDataSize(NetworkNative.shared.totalDownload))
                    MetricRow(label: "Uploaded", value: formatDataSize(NetworkNative.shared.totalUpload))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                ModernDivider()
                
                // Connection
                VStack(spacing: 8) {
                    SectionHeader(title: "CONNECTION")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    MetricRow(label: "Interface", value: systemMonitor.networkInterface)
                    
                    // IP Address with copy button
                    if !systemMonitor.networkLocalIP.isEmpty {
                        HStack {
                            Text("IP Address")
                                .font(DesignSystem.body())
                                .foregroundColor(DesignSystem.textSecondary)
                            Spacer()
                            
                            // Copy button with animation
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(systemMonitor.networkLocalIP, forType: .string)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    ipCopied = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation {
                                        ipCopied = false
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(systemMonitor.networkLocalIP)
                                        .font(DesignSystem.subheadline())
                                        .foregroundColor(DesignSystem.textPrimary)
                                    
                                    Image(systemName: ipCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(ipCopied ? .green : DesignSystem.textTertiary)
                                        .scaleEffect(ipCopied ? 1.2 : 1.0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(ipCopied ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !systemMonitor.networkMAC.isEmpty && systemMonitor.networkMAC != "" {
                        MetricRow(label: "MAC", value: systemMonitor.networkMAC)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // WiFi details
                if !systemMonitor.wifiSSID.isEmpty {
                    ModernDivider()
                    
                    VStack(spacing: 8) {
                        SectionHeader(title: "WI-FI")
                        
                        MetricRow(label: "Network", value: systemMonitor.wifiSSID)
                        
                        if !systemMonitor.wifiChannel.isEmpty {
                            MetricRow(label: "Channel", value: systemMonitor.wifiChannel)
                        }
                        
                        if systemMonitor.wifiStrength > 0 {
                            HStack {
                                Text("Signal")
                                    .font(DesignSystem.body())
                                    .foregroundColor(DesignSystem.textSecondary)
                                Spacer()
                                
                                // Signal strength visual
                                HStack(spacing: 2) {
                                    ForEach(0..<4) { bar in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Double(bar) / 4.0 < systemMonitor.wifiStrength ?
                                                  Color.white.opacity(0.7) : Color.white.opacity(0.15))
                                            .frame(width: 4, height: CGFloat(6 + bar * 3))
                                    }
                                }
                                
                                Text("\(Int(systemMonitor.wifiStrength * 100))%")
                                    .font(DesignSystem.subheadline())
                                    .foregroundColor(DesignSystem.textPrimary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                // Speed Test Button
                ModernDivider()
                
                Button(action: {
                    systemMonitor.runSpeedTest()
                }) {
                    HStack(spacing: 8) {
                        if systemMonitor.isSpeedTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.textSecondary))
                        } else {
                            Image(systemName: "speedometer")
                                .font(.system(size: 12))
                        }
                        Text(systemMonitor.isSpeedTesting ? "Testing..." : "Speed Test")
                            .font(DesignSystem.subheadline())
                    }
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DesignSystem.cardBackground)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(systemMonitor.isSpeedTesting)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                if let result = systemMonitor.speedTestResult {
                    Text(String(format: "%.0f Mbps down · %.0f Mbps up · %.0fms", 
                        result.download * 8, result.upload * 8, result.latency))
                        .font(DesignSystem.body())
                        .foregroundColor(DesignSystem.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(width: 280)
    }
}

// MARK: - Disk Menu View
struct DiskMenuView: View {
    @ObservedObject var systemMonitor: SystemMonitor
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header with main metric
                VStack(spacing: 4) {
                    Text("STORAGE")
                        .font(DesignSystem.caption())
                        .foregroundColor(DesignSystem.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    Text(String(format: "%.0f", systemMonitor.diskUsage))
                        .font(.system(size: 52, weight: .ultraLight, design: .rounded))
                        .foregroundColor(DesignSystem.textPrimary)
                    + Text("%")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .foregroundColor(DesignSystem.textSecondary)
                    
                    Text("Used")
                        .font(DesignSystem.subheadline())
                        .foregroundColor(DesignSystem.textSecondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // Disk I/O
                if systemMonitor.diskReadSpeed > 0.01 || systemMonitor.diskWriteSpeed > 0.01 {
                    HStack(spacing: 24) {
                        // Read
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10))
                                Text("READ")
                                    .font(DesignSystem.caption())
                            }
                            .foregroundColor(DesignSystem.textTertiary)
                            
                            Text(String(format: "%.1f MB/s", systemMonitor.diskReadSpeed))
                                .font(DesignSystem.subheadline())
                                .foregroundColor(DesignSystem.textPrimary)
                        }
                        
                        Rectangle()
                            .fill(DesignSystem.divider)
                            .frame(width: 1, height: 30)
                        
                        // Write
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 10))
                                Text("WRITE")
                                    .font(DesignSystem.caption())
                            }
                            .foregroundColor(DesignSystem.textTertiary)
                            
                            Text(String(format: "%.1f MB/s", systemMonitor.diskWriteSpeed))
                                .font(DesignSystem.subheadline())
                                .foregroundColor(DesignSystem.textPrimary)
                        }
                    }
                    .padding(.bottom, 12)
                }
                
                ModernDivider()
                
                // Volumes
                VStack(spacing: 0) {
                    SectionHeader(title: "VOLUMES")
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    
                    if systemMonitor.diskVolumes.isEmpty {
                        // Fallback to simple bar
                        StorageBar(usage: systemMonitor.diskUsage / 100)
                            .frame(height: 24)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(systemMonitor.diskVolumes) { volume in
                            VolumeRow(volume: volume)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            
                            if volume.id != systemMonitor.diskVolumes.last?.id {
                                ModernDivider()
                            }
                        }
                    }
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - Volume Row
struct VolumeRow: View {
    let volume: VolumeInfo
    
    private var statusColor: Color {
        volume.usagePercent > 90 ? Color.red.opacity(0.8) :
        volume.usagePercent > 75 ? Color.orange.opacity(0.8) :
        DesignSystem.textSecondary
    }
    
    private var iconName: String {
        if volume.isRemovable {
            return "externaldrive.fill"
        } else if volume.mountPoint == "/" {
            return "internaldrive.fill"
        } else {
            return "folder.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Volume name and icon
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.textSecondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(DesignSystem.subheadline())
                        .foregroundColor(DesignSystem.textPrimary)
                        .lineLimit(1)
                    
                    Text(volume.fileSystem)
                        .font(DesignSystem.caption())
                        .foregroundColor(DesignSystem.textTertiary)
                }
                
                Spacer()
                
                // Usage percentage
                Text(String(format: "%.0f%%", volume.usagePercent))
                    .font(DesignSystem.subheadline())
                    .foregroundColor(statusColor)
            }
            
            // Usage bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignSystem.progressBackground)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * min(1, volume.usagePercent / 100)))
                }
            }
            .frame(height: 6)
            
            // Size info
            HStack {
                Text(String(format: "%.1f GB used", volume.usedSize))
                    .font(DesignSystem.caption())
                    .foregroundColor(DesignSystem.textTertiary)
                
                Spacer()
                
                Text(String(format: "%.1f GB free", volume.freeSize))
                    .font(DesignSystem.caption())
                    .foregroundColor(DesignSystem.textTertiary)
            }
        }
    }
}

// MARK: - Enhanced Components

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(DesignSystem.caption())
            .foregroundColor(DesignSystem.textTertiary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LoadBarRow: View {
    let label: String
    let value: Double
    let maxValue: Double
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(DesignSystem.body())
                    .foregroundColor(DesignSystem.textSecondary)
                Spacer()
                Text(String(format: "%.1f%%", value))
                    .font(DesignSystem.subheadline())
                    .foregroundColor(DesignSystem.textPrimary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.progressBackground)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: max(0, geometry.size.width * min(1, value / maxValue)))
                }
            }
            .frame(height: 3)
        }
    }
}

struct MemoryBreakdownRow: View {
    let label: String
    let value: Double // GB
    let total: Double // GB
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 16)
            
            Text(label)
                .font(DesignSystem.body())
                .foregroundColor(DesignSystem.textSecondary)
            
            Spacer()
            
            Text(String(format: "%.1f GB", value))
                .font(DesignSystem.subheadline())
                .foregroundColor(DesignSystem.textPrimary)
        }
    }
}

// Format large byte counts to readable strings (KB, MB, GB, TB)
private func formatDataSize(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024
    let gb = mb / 1024
    let tb = gb / 1024
    
    if tb >= 1 { return String(format: "%.2f TB", tb) }
    if gb >= 1 { return String(format: "%.2f GB", gb) }
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", kb)
}

// MARK: - Modern Components

struct ModernProgressBar: View {
    let value: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignSystem.progressBackground)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignSystem.progressFill)
                    .frame(width: max(0, geometry.size.width * min(1, value)))
            }
        }
    }
}

struct ModernDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.divider)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.body())
                .foregroundColor(DesignSystem.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.subheadline())
                .foregroundColor(DesignSystem.textPrimary)
        }
    }
}

struct ProcessRow: View {
    let name: String
    let icon: NSImage?
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textTertiary)
                    .frame(width: 16, height: 16)
            }
            
            Text(name)
                .font(DesignSystem.body())
                .foregroundColor(DesignSystem.textSecondary)
                .lineLimit(1)
            
            Spacer()
            
            Text(value)
                .font(DesignSystem.subheadline())
                .foregroundColor(DesignSystem.textPrimary)
        }
    }
}

struct StorageBar: View {
    let usage: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.progressBackground)
                
                // Used space
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * min(1, usage)))
            }
        }
    }
}

// MARK: - Modern Area Chart
struct ModernAreaChart: View {
    let data: [Double]
    let maxValue: Double
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let points = normalizedPoints(width: width, height: height)
            
            ZStack {
                // Area fill
                Path { path in
                    guard points.count > 1 else { return }
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: points[0])
                    
                    for i in 1..<points.count {
                        let control1 = CGPoint(
                            x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                            y: points[i-1].y
                        )
                        let control2 = CGPoint(
                            x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                            y: points[i].y
                        )
                        path.addCurve(to: points[i], control1: control1, control2: control2)
                    }
                    
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Line stroke
                Path { path in
                    guard points.count > 1 else { return }
                    path.move(to: points[0])
                    
                    for i in 1..<points.count {
                        let control1 = CGPoint(
                            x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                            y: points[i-1].y
                        )
                        let control2 = CGPoint(
                            x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                            y: points[i].y
                        )
                        path.addCurve(to: points[i], control1: control1, control2: control2)
                    }
                }
                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
    
    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let step = width / CGFloat(data.count - 1)
        
        return data.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let normalizedValue = min(1, max(0, value / maxValue))
            let y = height - (CGFloat(normalizedValue) * height)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Modern Dual Area Chart (for Network)
struct ModernDualAreaChart: View {
    let upData: [Double]
    let downData: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            let maxUp = upData.max() ?? 1
            let maxDown = downData.max() ?? 1
            let maxValue = max(maxUp, maxDown, 1)
            
            ZStack {
                // Download area (bottom)
                chartArea(data: downData, width: width, height: height, maxValue: maxValue, opacity: 0.15)
                
                // Upload area (top, more subtle)
                chartArea(data: upData, width: width, height: height, maxValue: maxValue, opacity: 0.08)
            }
        }
    }
    
    @ViewBuilder
    private func chartArea(data: [Double], width: CGFloat, height: CGFloat, maxValue: Double, opacity: Double) -> some View {
        let points = normalizedPoints(data: data, width: width, height: height, maxValue: maxValue)
        
        Path { path in
            guard points.count > 1 else { return }
            path.move(to: CGPoint(x: 0, y: height))
            path.addLine(to: points[0])
            
            for i in 1..<points.count {
                let control1 = CGPoint(
                    x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                    y: points[i-1].y
                )
                let control2 = CGPoint(
                    x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                    y: points[i].y
                )
                path.addCurve(to: points[i], control1: control1, control2: control2)
            }
            
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
        .fill(Color.white.opacity(opacity))
    }
    
    private func normalizedPoints(data: [Double], width: CGFloat, height: CGFloat, maxValue: Double) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let step = width / CGFloat(data.count - 1)
        
        return data.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let normalizedValue = min(1, max(0, value / maxValue))
            let y = height - (CGFloat(normalizedValue) * height)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Legacy component for compatibility

struct ProgressBar: View {
    let value: Double
    let color: Color
    
    var body: some View {
        ModernProgressBar(value: value)
    }
}

