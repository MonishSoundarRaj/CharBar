import AppKit
import QuartzCore
import CoreText

/// Apple-style rolling/odometer timer view for menu bar - CRISP CATextLayer
class RollingTimerView: NSView {
    
    private var digitLayers: [CATextLayer] = []
    private var separatorLayer: CATextLayer!
    private var containerLayers: [CALayer] = []
    
    private var currentDigits: [Int] = [0, 0, 0, 0] // MM:SS
    private var previousDigits: [Int] = [0, 0, 0, 0]
    
    private let digitWidth: CGFloat = 9
    private let digitHeight: CGFloat = 16
    private let separatorWidth: CGFloat = 5
    private let fontSize: CGFloat = 12
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Update contentsScale when added to window for proper retina rendering
        updateContentsScale()
        updateTextColor()
        
        // Observe appearance changes for dynamic text color
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc private func appearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTextColor()
        }
    }
    
    private func updateTextColor() {
        // Use labelColor which automatically adapts to menu bar's appearance
        // This handles both light/dark wallpapers AND light/dark mode
        let textColor = NSColor.labelColor.cgColor
        
        for digitLayer in digitLayers {
            digitLayer.foregroundColor = textColor
        }
        separatorLayer?.foregroundColor = textColor
        
        // Force redraw
        layer?.setNeedsDisplay()
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTextColor()
    }
    
    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        
        layer?.contentsScale = scale
        for container in containerLayers {
            container.contentsScale = scale
        }
        for digitLayer in digitLayers {
            digitLayer.contentsScale = scale
        }
        separatorLayer?.contentsScale = scale
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = false
        
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        
        // Calculate total width: 4 digits + 1 separator
        let totalWidth = (digitWidth * 4) + separatorWidth
        let xOffset = (bounds.width - totalWidth) / 2
        
        // Create containers with clipping for each digit position
        for i in 0..<4 {
            let xPos: CGFloat
            if i < 2 {
                // Minutes (first two digits)
                xPos = xOffset + (CGFloat(i) * digitWidth)
            } else {
                // Seconds (last two digits, after separator)
                xPos = xOffset + (CGFloat(i) * digitWidth) + separatorWidth
            }
            
            // Container layer that clips content
            let container = CALayer()
            container.frame = CGRect(x: xPos, y: (bounds.height - digitHeight) / 2, width: digitWidth, height: digitHeight)
            container.masksToBounds = true
            container.contentsScale = scale
            layer?.addSublayer(container)
            containerLayers.append(container)
            
            // Digit text layer
            let digitLayer = createDigitLayer()
            digitLayer.frame = CGRect(x: 0, y: 0, width: digitWidth, height: digitHeight)
            container.addSublayer(digitLayer)
            digitLayers.append(digitLayer)
        }
        
        // Create separator (:)
        let separatorX = xOffset + (digitWidth * 2)
        separatorLayer = createDigitLayer()
        separatorLayer.string = ":"
        separatorLayer.frame = CGRect(x: separatorX, y: (bounds.height - digitHeight) / 2, width: separatorWidth, height: digitHeight)
        layer?.addSublayer(separatorLayer)
    }
    
    private func createDigitLayer() -> CATextLayer {
        let layer = CATextLayer()
        
        // Use CTFont for crisp rendering
        let font = CTFontCreateWithName("SFMono-Medium" as CFString, fontSize, nil)
        layer.font = font
        layer.fontSize = fontSize
        
        layer.alignmentMode = .center
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer.foregroundColor = NSColor.labelColor.cgColor
        layer.string = "0"
        
        // Critical for crisp text
        layer.allowsFontSubpixelQuantization = true
        layer.shouldRasterize = false
        
        return layer
    }
    
    /// Update the timer display with animation
    func update(minutes: Int, seconds: Int, animated: Bool = true) {
        let newDigits = [
            minutes / 10,
            minutes % 10,
            seconds / 10,
            seconds % 10
        ]
        
        previousDigits = currentDigits
        currentDigits = newDigits
        
        for i in 0..<4 {
            updateDigit(at: i, from: previousDigits[i], to: newDigits[i], animated: animated)
        }
        
        // Force redraw across all screens
        needsDisplay = true
        layer?.setNeedsDisplay()
    }
    
    private func updateDigit(at index: Int, from oldValue: Int, to newValue: Int, animated: Bool) {
        guard index < digitLayers.count else { return }
        
        let digitLayer = digitLayers[index]
        
        if oldValue == newValue {
            // No change, just ensure the value is correct
            digitLayer.string = "\(newValue)"
            return
        }
        
        if !animated {
            digitLayer.string = "\(newValue)"
            return
        }
        
        // Create the rolling animation
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        // Determine direction: countdown rolls UP (old digit exits top, new enters from bottom)
        let direction: CGFloat = oldValue > newValue ? 1 : -1
        
        // Create a clone layer for the old digit
        let oldLayer = createDigitLayer()
        oldLayer.string = "\(oldValue)"
        oldLayer.frame = digitLayer.frame
        containerLayers[index].addSublayer(oldLayer)
        
        // Animate old layer out (slide up and fade)
        let oldAnimation = CABasicAnimation(keyPath: "position.y")
        oldAnimation.fromValue = digitLayer.position.y
        oldAnimation.toValue = digitLayer.position.y + (digitHeight * direction)
        oldAnimation.duration = 0.25
        oldAnimation.fillMode = .forwards
        oldAnimation.isRemovedOnCompletion = false
        
        let oldFade = CABasicAnimation(keyPath: "opacity")
        oldFade.fromValue = 1.0
        oldFade.toValue = 0.0
        oldFade.duration = 0.25
        oldFade.fillMode = .forwards
        oldFade.isRemovedOnCompletion = false
        
        // Animate new digit in (slide from bottom)
        let newAnimation = CABasicAnimation(keyPath: "position.y")
        newAnimation.fromValue = digitLayer.position.y - (digitHeight * direction)
        newAnimation.toValue = digitLayer.position.y
        newAnimation.duration = 0.25
        
        let newFade = CABasicAnimation(keyPath: "opacity")
        newFade.fromValue = 0.0
        newFade.toValue = 1.0
        newFade.duration = 0.25
        
        // Update the main digit layer value
        digitLayer.string = "\(newValue)"
        
        // Apply animations
        oldLayer.add(oldAnimation, forKey: "slideOut")
        oldLayer.add(oldFade, forKey: "fadeOut")
        digitLayer.add(newAnimation, forKey: "slideIn")
        digitLayer.add(newFade, forKey: "fadeIn")
        
        CATransaction.setCompletionBlock {
            oldLayer.removeFromSuperlayer()
        }
        
        CATransaction.commit()
    }
    
    /// Set the text color
    func setTextColor(_ color: NSColor) {
        for layer in digitLayers {
            layer.foregroundColor = color.cgColor
        }
        separatorLayer?.foregroundColor = color.cgColor
    }
    
    /// Convenience method to update from total seconds
    func updateFromSeconds(_ totalSeconds: Int, animated: Bool = true) {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        update(minutes: minutes, seconds: seconds, animated: animated)
    }
    
    /// Show idle state (dashes or "-- --")
    func showIdle() {
        // Show dashes to indicate timer is not running
        for digitLayer in digitLayers {
            if digitLayer.string as? String != "-" {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.2)
                digitLayer.string = "-"
                CATransaction.commit()
            }
        }
        currentDigits = [-1, -1, -1, -1]
        previousDigits = [-1, -1, -1, -1]
    }
    
    override func layout() {
        super.layout()
        
        // Update text color for proper appearance
        updateTextColor()
        
        // Recalculate positions when bounds change
        let totalWidth = (digitWidth * 4) + separatorWidth
        let xOffset = (bounds.width - totalWidth) / 2
        
        for i in 0..<containerLayers.count {
            let xPos: CGFloat
            if i < 2 {
                xPos = xOffset + (CGFloat(i) * digitWidth)
            } else {
                xPos = xOffset + (CGFloat(i) * digitWidth) + separatorWidth
            }
            containerLayers[i].frame = CGRect(x: xPos, y: (bounds.height - digitHeight) / 2, width: digitWidth, height: digitHeight)
            
            // Reset digit layer frame within container
            if i < digitLayers.count {
                digitLayers[i].frame = CGRect(x: 0, y: 0, width: digitWidth, height: digitHeight)
            }
        }
        
        // Update separator position
        let separatorX = xOffset + (digitWidth * 2)
        separatorLayer?.frame = CGRect(x: separatorX, y: (bounds.height - digitHeight) / 2, width: separatorWidth, height: digitHeight)
        
        // Update scale when layout changes
        updateContentsScale()
    }
    
    override var intrinsicContentSize: NSSize {
        let totalWidth = (digitWidth * 4) + separatorWidth
        return NSSize(width: totalWidth, height: digitHeight)
    }
}
