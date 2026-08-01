//
//  SparklineChart.swift
//  CharBar
//
//  A minimal, attractive sparkline chart for system stats
//

import SwiftUI

// MARK: - Sparkline Chart

struct SparklineChart: View {
    let data: [Double]
    let color: Color
    let fillGradient: Bool
    let maxValue: Double?
    let showCurrentValue: Bool
    let height: CGFloat
    
    init(
        data: [Double],
        color: Color = .blue,
        fillGradient: Bool = true,
        maxValue: Double? = nil,
        showCurrentValue: Bool = false,
        height: CGFloat = 40
    ) {
        self.data = data
        self.color = color
        self.fillGradient = fillGradient
        self.maxValue = maxValue
        self.showCurrentValue = showCurrentValue
        self.height = height
    }
    
    private var normalizedData: [Double] {
        guard !data.isEmpty else { return [] }
        let max = maxValue ?? (data.max() ?? 1)
        let min = data.min() ?? 0
        let range = max - min
        if range == 0 { return data.map { _ in 0.5 } }
        return data.map { ($0 - min) / range }
    }
    
    var body: some View {
        GeometryReader { geo in
            if data.count > 1 {
                ZStack {
                    // Fill gradient
                    if fillGradient {
                        Path { path in
                            let stepX = geo.size.width / CGFloat(max(1, normalizedData.count - 1))
                            
                            path.move(to: CGPoint(x: 0, y: geo.size.height))
                            
                            for (index, value) in normalizedData.enumerated() {
                                let x = CGFloat(index) * stepX
                                let y = geo.size.height - (CGFloat(value) * geo.size.height)
                                
                                if index == 0 {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.3),
                                    color.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    // Line
                    Path { path in
                        let stepX = geo.size.width / CGFloat(max(1, normalizedData.count - 1))
                        
                        for (index, value) in normalizedData.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = geo.size.height - (CGFloat(value) * geo.size.height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Current value dot
                    if showCurrentValue, let lastValue = normalizedData.last {
                        let x = geo.size.width
                        let y = geo.size.height - (CGFloat(lastValue) * geo.size.height)
                        
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                            .shadow(color: color.opacity(0.5), radius: 3)
                    }
                }
            } else {
                // Empty state - show placeholder line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Mini Stats Card with Chart

struct MiniStatsCard: View {
    let title: String
    let value: String
    let data: [Double]
    let color: Color
    let icon: String?
    let maxValue: Double?
    
    init(
        title: String,
        value: String,
        data: [Double],
        color: Color = .blue,
        icon: String? = nil,
        maxValue: Double? = nil
    ) {
        self.title = title
        self.value = value
        self.data = data
        self.color = color
        self.icon = icon
        self.maxValue = maxValue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            
            SparklineChart(
                data: data,
                color: color,
                fillGradient: true,
                maxValue: maxValue,
                showCurrentValue: true,
                height: 35
            )
        }
        .padding(10)
        .glassCard(cornerRadius: 10, opacity: 0.05)
    }
}

// MARK: - Dual Chart Card (for network up/down)

struct DualChartCard: View {
    let title: String
    let upValue: String
    let downValue: String
    let upData: [Double]
    let downData: [Double]
    let upColor: Color
    let downColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            
            HStack(spacing: 8) {
                // Download
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(downColor)
                        Text(downValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(downColor)
                    }
                    SparklineChart(data: downData, color: downColor, height: 25)
                }
                
                // Upload
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(upColor)
                        Text(upValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(upColor)
                    }
                    SparklineChart(data: upData, color: upColor, height: 25)
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 10, opacity: 0.05)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        MiniStatsCard(
            title: "CPU Usage",
            value: "45%",
            data: [20, 35, 45, 30, 55, 40, 45, 50, 42, 45],
            color: .blue,
            icon: "cpu",
            maxValue: 100
        )
        
        MiniStatsCard(
            title: "Memory",
            value: "8.2 GB",
            data: [60, 62, 65, 63, 68, 70, 72, 71, 73, 75],
            color: .orange,
            icon: "memorychip",
            maxValue: 100
        )
        
        DualChartCard(
            title: "Network",
            upValue: "1.2 MB/s",
            downValue: "5.4 MB/s",
            upData: [10, 20, 15, 30, 25, 20, 35, 30],
            downData: [50, 60, 45, 80, 70, 55, 90, 75],
            upColor: .orange,
            downColor: .green
        )
    }
    .padding()
    .frame(width: 280)
    .background(Color.black)
}



