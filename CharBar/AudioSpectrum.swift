import AppKit
import SwiftUI
import QuartzCore

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 4 // Thicker bars for better visibility
        let barCount = 4
        let spacing: CGFloat = 3
        let totalWidth = CGFloat(barCount) * (barWidth + spacing) - spacing
        let totalHeight: CGFloat = 24 // Taller visualizer
        
        // Center the view content
        let startX = (frame.width - totalWidth) / 2
        let startY = (frame.height - totalHeight) / 2
        
        for i in 0 ..< barCount {
            let xPosition = startX + CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: startY, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: startY + totalHeight / 2)
            
            // System accent color for better visibility
            barLayer.fillColor = NSColor.systemBlue.cgColor
            barLayer.backgroundColor = NSColor.clear.cgColor
            
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }
    
    private func startAnimating() {
        guard animationTimer == nil else { return }
        
        // Immediate first update
        updateBars()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
    }
    
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }
    
    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            // Random height between 30% and 100%
            let targetScale = CGFloat.random(in: 0.3 ... 1.0)
            barScales[i] = targetScale
            
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.15
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            barLayer.add(animation, forKey: "scaleY")
        }
    }
    
    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.1, 1) // Flat line when paused
            barScales[i] = 0.1
        }
    }
    
    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    
    func makeNSView(context: Context) -> AudioSpectrum {
        // Bigger frame for 4 larger bars
        let spectrum = AudioSpectrum(frame: NSRect(x: 0, y: 0, width: 32, height: 28))
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}


