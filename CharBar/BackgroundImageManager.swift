//
//  BackgroundImageManager.swift
//  CharBar
//
//  Manages custom background images for menu dropdowns
//

import SwiftUI
import Combine

/// Manages background image selection for menu views
class BackgroundImageManager: ObservableObject {
    static let shared = BackgroundImageManager()
    
    /// The currently selected background image name (nil = glass/default)
    @Published var selectedBackgroundImage: String? {
        didSet {
            // Clear cache when selection changes
            cachedImage = nil
            saveSelection()
            NotificationCenter.default.post(name: NSNotification.Name("BackgroundImageChanged"), object: nil)
        }
    }
    
    /// Blur amount for background images (0-25)
    @Published var blurAmount: Double = 10 {
        didSet {
            UserDefaults.standard.set(blurAmount, forKey: "backgroundImageBlur")
        }
    }
    
    /// Overlay opacity for better text readability (0-1)
    @Published var overlayOpacity: Double = 0.3 {
        didSet {
            UserDefaults.standard.set(overlayOpacity, forKey: "backgroundImageOverlay")
        }
    }
    
    private let defaults = UserDefaults.standard
    private let selectedImageKey = "selectedBackgroundImage"
    
    /// Cache for loaded images
    private var imageCache: [String: NSImage] = [:]
    private var cachedImage: NSImage?
    
    private init() {
        loadSelection()
        scanForImages()
    }
    
    // MARK: - Available Images
    
    /// Cached list of available images
    private var _availableImages: [BackgroundImageOption] = []
    
    /// Get list of available background images from bundle
    var availableImages: [BackgroundImageOption] {
        if _availableImages.count <= 1 {
            scanForImages()
        }
        return _availableImages
    }
    
    /// Scan bundle for available background images
    private func scanForImages() {
        var images: [BackgroundImageOption] = [
            BackgroundImageOption(name: nil, displayName: "Glass (Default)", isDefault: true)
        ]
        
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff"]
        
        // Method 1: Check BackgroundImages folder directly
        if let resourcePath = Bundle.main.resourcePath {
            let imagesPath = (resourcePath as NSString).appendingPathComponent("BackgroundImages")
            
            if FileManager.default.fileExists(atPath: imagesPath) {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesPath) {
                    for file in files.sorted() {
                        let ext = (file as NSString).pathExtension.lowercased()
                        if imageExtensions.contains(ext) {
                            let name = (file as NSString).deletingPathExtension
                            let displayName = name.replacingOccurrences(of: "_", with: " ").capitalized
                            images.append(BackgroundImageOption(name: file, displayName: displayName, isDefault: false))
                        }
                    }
                }
            }
        }
        
        // Method 2: Try Bundle.main.urls for images
        for ext in imageExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "BackgroundImages") {
                for url in urls {
                    let fileName = url.lastPathComponent
                    // Check if already added
                    if !images.contains(where: { $0.name == fileName }) {
                        let name = (fileName as NSString).deletingPathExtension
                        let displayName = name.replacingOccurrences(of: "_", with: " ").capitalized
                        images.append(BackgroundImageOption(name: fileName, displayName: displayName, isDefault: false))
                    }
                }
            }
        }
        
        // Method 3: Also check root bundle for images starting with "background" or "bg"
        for ext in imageExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    let fileName = url.lastPathComponent.lowercased()
                    if fileName.hasPrefix("background") || fileName.hasPrefix("bg_") || fileName.hasPrefix("image") {
                        let name = url.lastPathComponent
                        if !images.contains(where: { $0.name == name }) {
                            let displayName = (name as NSString).deletingPathExtension
                                .replacingOccurrences(of: "_", with: " ").capitalized
                            images.append(BackgroundImageOption(name: name, displayName: displayName, isDefault: false))
                        }
                    }
                }
            }
        }
        
        // Method 4: Try source directory (development fallback)
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            let appDir = bundlePath.deletingLastPathComponent
            let possibleSourcePaths = [
                "\(appDir)/CharBar/BackgroundImages",
                "\(appDir)/../CharBar/BackgroundImages",
                "\(appDir)/../../CharBar/BackgroundImages",
                "\(appDir)/../../../CharBar/BackgroundImages",
                // Also try the typical DerivedData build location pattern
                "/Users/monishsoundarraj/Projects/CharBar/CharBar/BackgroundImages"
            ]
            
            for sourcePath in possibleSourcePaths {
                let standardPath = (sourcePath as NSString).standardizingPath
                if FileManager.default.fileExists(atPath: standardPath) {
                    if let files = try? FileManager.default.contentsOfDirectory(atPath: standardPath) {
                        for file in files.sorted() {
                            let ext = (file as NSString).pathExtension.lowercased()
                            if imageExtensions.contains(ext) {
                                if !images.contains(where: { $0.name == file }) {
                                    let name = (file as NSString).deletingPathExtension
                                    let displayName = name.replacingOccurrences(of: "_", with: " ").capitalized
                                    images.append(BackgroundImageOption(name: file, displayName: displayName, isDefault: false))
                                }
                            }
                        }
                    }
                    break // Found the source directory, stop searching
                }
            }
        }
        
        // Method 5: Scan user-uploaded backgrounds
        let userDir = userBackgroundsDir.path
        if FileManager.default.fileExists(atPath: userDir),
           let files = try? FileManager.default.contentsOfDirectory(atPath: userDir) {
            for file in files.sorted() {
                let ext = (file as NSString).pathExtension.lowercased()
                if imageExtensions.contains(ext) {
                    if !images.contains(where: { $0.name == file }) {
                        let name = (file as NSString).deletingPathExtension
                        let displayName = name.replacingOccurrences(of: "_", with: " ").capitalized
                        images.append(BackgroundImageOption(name: file, displayName: displayName, isDefault: false, isUserImage: true))
                    }
                }
            }
        }
        
        _availableImages = images
    }
    
    /// Load the selected background image as NSImage
    func loadSelectedImage() -> NSImage? {
        guard let imageName = selectedBackgroundImage else { return nil }
        
        // Return cached if available
        if let cached = cachedImage {
            return cached
        }
        
        let image = loadImage(named: imageName)
        cachedImage = image
        return image
    }
    
    /// Load a specific background image by name
    func loadImage(named imageName: String) -> NSImage? {
        // Check cache first
        if let cached = imageCache[imageName] {
            return cached
        }
        
        let baseName = (imageName as NSString).deletingPathExtension
        let ext = (imageName as NSString).pathExtension
        
        // Method 1: Try with full name in BackgroundImages folder
        if let path = Bundle.main.path(forResource: imageName, ofType: nil, inDirectory: "BackgroundImages"),
           let image = NSImage(contentsOfFile: path) {
            imageCache[imageName] = image
            return image
        }
        
        // Method 2: Try with base name and extension in BackgroundImages folder
        if !ext.isEmpty,
           let path = Bundle.main.path(forResource: baseName, ofType: ext, inDirectory: "BackgroundImages"),
           let image = NSImage(contentsOfFile: path) {
            imageCache[imageName] = image
            return image
        }
        
        // Method 3: Try common extensions in BackgroundImages folder
        for tryExt in ["jpg", "jpeg", "png", "heic", "webp"] {
            if let path = Bundle.main.path(forResource: baseName, ofType: tryExt, inDirectory: "BackgroundImages"),
               let image = NSImage(contentsOfFile: path) {
                imageCache[imageName] = image
                return image
            }
        }
        
        // Method 4: Try direct bundle resource (no subdirectory)
        if let path = Bundle.main.path(forResource: baseName, ofType: ext.isEmpty ? "jpg" : ext),
           let image = NSImage(contentsOfFile: path) {
            imageCache[imageName] = image
            return image
        }
        
        // Method 5: Try using URL
        if let url = Bundle.main.url(forResource: baseName, withExtension: ext.isEmpty ? nil : ext, subdirectory: "BackgroundImages"),
           let image = NSImage(contentsOf: url) {
            imageCache[imageName] = image
            return image
        }
        
        // Method 6: Build path manually and check filesystem
        if let resourcePath = Bundle.main.resourcePath {
            let directPath = (resourcePath as NSString).appendingPathComponent("BackgroundImages/\(imageName)")
            if FileManager.default.fileExists(atPath: directPath),
               let image = NSImage(contentsOfFile: directPath) {
                imageCache[imageName] = image
                return image
            }
        }
        
        // Method 7: Try from source directory (development fallback)
        // This helps when images exist in source but aren't in bundle yet
        let sourceBasePaths = [
            "/Users/monishsoundarraj/Projects/CharBar/CharBar/BackgroundImages"
        ]
        
        // Also try paths relative to bundle
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            let appDir = bundlePath.deletingLastPathComponent
            let relativePaths = [
                "\(appDir)/CharBar/BackgroundImages/\(imageName)",
                "\(appDir)/../CharBar/BackgroundImages/\(imageName)",
                "\(appDir)/../../CharBar/BackgroundImages/\(imageName)",
                "\(appDir)/../../../CharBar/BackgroundImages/\(imageName)"
            ]
            
            for sourcePath in relativePaths {
                let standardPath = (sourcePath as NSString).standardizingPath
                if FileManager.default.fileExists(atPath: standardPath),
                   let image = NSImage(contentsOfFile: standardPath) {
                    imageCache[imageName] = image
                    return image
                }
            }
        }
        
        // Try known source path directly
        for basePath in sourceBasePaths {
            let fullPath = "\(basePath)/\(imageName)"
            if FileManager.default.fileExists(atPath: fullPath),
               let image = NSImage(contentsOfFile: fullPath) {
                imageCache[imageName] = image
                return image
            }
        }
        
        // Method 8: Try user backgrounds directory
        let userPath = userBackgroundsDir.appendingPathComponent(imageName).path
        if FileManager.default.fileExists(atPath: userPath),
           let image = NSImage(contentsOfFile: userPath) {
            imageCache[imageName] = image
            return image
        }
        
        return nil
    }
    
    // MARK: - Persistence
    
    private func saveSelection() {
        if let imageName = selectedBackgroundImage {
            defaults.set(imageName, forKey: selectedImageKey)
        } else {
            defaults.removeObject(forKey: selectedImageKey)
        }
    }
    
    private func loadSelection() {
        selectedBackgroundImage = defaults.string(forKey: selectedImageKey)
        blurAmount = defaults.double(forKey: "backgroundImageBlur")
        if blurAmount == 0 { blurAmount = 10 } // Default blur
        
        overlayOpacity = defaults.double(forKey: "backgroundImageOverlay")
        if overlayOpacity == 0 { overlayOpacity = 0.3 } // Default overlay
    }
    
    /// Reset to default glass background
    func resetToDefault() {
        selectedBackgroundImage = nil
        blurAmount = 10
        overlayOpacity = 0.3
    }
    
    /// Force rescan for images
    func rescanImages() {
        _availableImages = []
        imageCache.removeAll()
        scanForImages()
    }
    
    // MARK: - User Backgrounds
    
    private var userBackgroundsDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("CharBar/UserBackgrounds")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Import an image from disk, center-crop to 16:9, and store in UserBackgrounds
    func importImage(from sourceURL: URL) {
        guard let image = NSImage(contentsOf: sourceURL) else { return }
        
        let targetAspect: CGFloat = 16.0 / 9.0
        let size = image.size
        let srcAspect = size.width / size.height
        
        var cropRect: NSRect
        if srcAspect > targetAspect {
            let cropW = size.height * targetAspect
            cropRect = NSRect(x: (size.width - cropW) / 2, y: 0, width: cropW, height: size.height)
        } else {
            let cropH = size.width / targetAspect
            cropRect = NSRect(x: 0, y: (size.height - cropH) / 2, width: size.width, height: cropH)
        }
        
        let cropped = NSImage(size: cropRect.size)
        cropped.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: cropRect.size), from: cropRect, operation: .copy, fraction: 1.0)
        cropped.unlockFocus()
        
        let fileName = "user_\(UUID().uuidString.prefix(8)).jpg"
        let destURL = userBackgroundsDir.appendingPathComponent(fileName)
        
        guard let tiffData = cropped.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        
        try? jpegData.write(to: destURL)
        
        imageCache.removeAll()
        rescanImages()
        selectedBackgroundImage = fileName
    }
    
    /// Delete a user-uploaded background image
    func deleteUserImage(named fileName: String) {
        let fileURL = userBackgroundsDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        
        if selectedBackgroundImage == fileName {
            selectedBackgroundImage = nil
        }
        imageCache[fileName] = nil
        rescanImages()
    }
}

// MARK: - Background Image Option Model

struct BackgroundImageOption: Identifiable {
    let name: String? // nil = default glass
    let displayName: String
    let isDefault: Bool
    var isUserImage: Bool = false
    
    var id: String { name ?? "default" }
}

// MARK: - Background View Modifier

/// A view modifier that applies either a custom background image or transparent (for glass panel)
struct MenuBackgroundModifier: ViewModifier {
    @ObservedObject var backgroundManager = BackgroundImageManager.shared
    let cornerRadius: CGFloat
    let innerPadding: CGFloat
    
    func body(content: Content) -> some View {
        ZStack {
            // Background layer - only shows when image is selected
            if let imageName = backgroundManager.selectedBackgroundImage,
               let nsImage = backgroundManager.loadImage(named: imageName) {
                // Custom image background
                GeometryReader { geo in
                    ZStack {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: backgroundManager.blurAmount)
                        
                        // Dark overlay for text readability
                        Color.black.opacity(backgroundManager.overlayOpacity)
                    }
                }
                .ignoresSafeArea()
            }
            // When glass is selected, background is clear - FloatingPanel handles the glass effect
            
            // Content layer
            content
                .padding(innerPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Card Modifier (for inner components)

/// A view modifier for inner components that should be semi-transparent
struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    @ObservedObject var backgroundManager = BackgroundImageManager.shared
    
    var hasBackgroundImage: Bool {
        backgroundManager.selectedBackgroundImage != nil
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if hasBackgroundImage {
                        // When background image is set, use more transparent card
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(0.25))
                            .background(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(.ultraThinMaterial.opacity(0.3))
                            )
                    } else {
                        // Glass mode - use subtle material
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white.opacity(opacity))
                            .background(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(.ultraThinMaterial.opacity(0.5))
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(hasBackgroundImage ? 0.1 : 0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Blur Button Modifier

/// A view modifier for buttons with blur/glass effect
struct BlurButtonModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let isHovering: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base blur - more visible
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.regularMaterial)
                    
                    // Color tint
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color.opacity(isHovering ? 0.35 : 0.2))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color.opacity(isHovering ? 0.4 : 0.25), lineWidth: 1)
            )
            .shadow(color: color.opacity(isHovering ? 0.2 : 0), radius: 4)
    }
}

// MARK: - View Extension

extension View {
    /// Apply menu background (glass or custom image) with proper containment
    func menuBackground(cornerRadius: CGFloat = 16, innerPadding: CGFloat = 8) -> some View {
        modifier(MenuBackgroundModifier(cornerRadius: cornerRadius, innerPadding: innerPadding))
    }
    
    /// Apply glass card effect for inner components (shows background through)
    func glassCard(cornerRadius: CGFloat = 12, opacity: Double = 0.08) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
    
    /// Apply blur button style
    func blurButton(color: Color = .blue, cornerRadius: CGFloat = 12, isHovering: Bool = false) -> some View {
        modifier(BlurButtonModifier(color: color, cornerRadius: cornerRadius, isHovering: isHovering))
    }
}

// MARK: - NSHostingController Helper for Menu Items

/// Creates an NSMenuItem with a properly configured SwiftUI view that fills the menu
func createMenuItemWithSwiftUIView<Content: View>(
    width: CGFloat,
    height: CGFloat,
    @ViewBuilder content: () -> Content
) -> NSMenuItem {
    let menuItem = NSMenuItem()
    let hostingController = NSHostingController(rootView: content())
    
    // Make hosting view background transparent so SwiftUI background shows
    hostingController.view.wantsLayer = true
    hostingController.view.layer?.backgroundColor = .clear
    
    hostingController.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    menuItem.view = hostingController.view
    
    return menuItem
}

// MARK: - NSHostingView with transparent background

class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Make sure the view and its layer are transparent
        wantsLayer = true
        layer?.backgroundColor = .clear
        
        // Try to make the window background transparent if this is in a menu
        if let window = window {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

/// Creates an NSHostingController with transparent background
class TransparentHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
    }
}