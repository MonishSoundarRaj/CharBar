import SwiftUI
import Combine
import KeyboardShortcuts
import UniformTypeIdentifiers
import Security
import IOKit

// MARK: - Color Mode Environment Key
private struct UseColorsKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var settingsUseColors: Bool {
        get { self[UseColorsKey.self] }
        set { self[UseColorsKey.self] = newValue }
    }
}

extension Color {
    /// Returns the color if useColors is true, otherwise returns a neutral gray.
    func settingsAdapted(_ useColors: Bool) -> Color {
        useColors ? self : .white.opacity(0.5)
    }
}

// Sidebar selection enum to handle both utilities and appearance
enum SettingsSidebarItem: Hashable {
    case general
    case utility(UtilityType)
    case appearance
    case shortcuts
    case about
    case legal
    
    var displayName: String {
        switch self {
        case .general:
            return "General"
        case .utility(let utility):
            return utility.rawValue
        case .appearance:
            return "Appearance"
        case .shortcuts:
            return "Keyboard Shortcuts"
        case .about:
            return "About"
        case .legal:
            return "Legal & Credits"
        }
    }
    
    var icon: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .utility(let utility):
            return utility.icon
        case .appearance:
            return "paintbrush.fill"
        case .shortcuts:
            return "command.square.fill"
        case .about:
            return "info.circle.fill"
        case .legal:
            return "doc.text.fill"
        }
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @State private var selectedItem: SettingsSidebarItem = .general
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @AppStorage("settings_useColors") private var useColors: Bool = true
    
    // Feature utilities — shown first (high-engagement features up top)
    private let featureUtilities: [UtilityType] = [.bluetooth, .meetings, .pomodoro, .music]
    // Stats utilities — battery first, then compute, then storage/network
    private let statsUtilities: [UtilityType] = [.battery, .cpu, .gpu, .ram, .network, .disk]
    
    var filteredStatsUtilities: [UtilityType] {
        if searchText.isEmpty { return statsUtilities }
        return statsUtilities.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredFeatureUtilities: [UtilityType] {
        if searchText.isEmpty { return featureUtilities }
        return featureUtilities.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }
    
    private struct TopItem {
        let icon: String; let color: Color; let title: String; let tag: SettingsSidebarItem
    }
    private let allTopItems: [TopItem] = [
        TopItem(icon: "gearshape.fill",      color: .gray,   title: "General",     tag: .general),
        TopItem(icon: "paintbrush.fill",     color: .orange, title: "Appearance",  tag: .appearance),
        TopItem(icon: "command.square.fill", color: .purple, title: "Shortcuts",   tag: .shortcuts),
    ]
    private let allAppItems: [TopItem] = [
        TopItem(icon: "info.circle.fill", color: .secondary, title: "About",           tag: .about),
        TopItem(icon: "doc.text.fill",    color: .gray,      title: "Legal & Credits", tag: .legal),
    ]
    private var filteredTopItems: [TopItem] {
        if searchText.isEmpty { return allTopItems }
        return allTopItems.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    private var filteredAppItems: [TopItem] {
        if searchText.isEmpty { return allAppItems }
        return allAppItems.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationSplitView {
            // Left Sidebar — single rounded layer (window edge is the only frame)
            ZStack {
                Color(nsColor: NSColor(white: 0.09, alpha: 1.0))
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.modernCyan.opacity(0.10),
                        Color.modernPurple.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .blur(radius: 80)

                sidebarContent
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
            .environment(\.settingsUseColors, useColors)
            .navigationSplitViewColumnWidth(min: 230, ideal: 240, max: 280)

        } detail: {
            // Right Side - Configuration based on selection
            ZStack {
                // Layered backdrop: base + soft directional glow so glass has depth to refract
                Color(nsColor: NSColor(white: 0.09, alpha: 1.0))
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.modernCyan.opacity(0.08),
                        Color.modernPurple.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .blur(radius: 80)

                Group {
                    switch selectedItem {
                    case .general:
                        GeneralSettingsView(launchAtLogin: launchAtLogin, resetAction: resetToDefaults)
                    case .appearance:
                        AppearanceSettingsView()
                    case .shortcuts:
                        ShortcutsSettingsView()
                    case .about:
                        AboutSettingsView()
                    case .legal:
                        LegalCreditsView()
                    case .utility(let utility):
                        if let config = settingsManager.configurations[utility] {
                            UtilityConfigView(
                                utility: utility,
                                configuration: Binding(
                                    get: { config },
                                    set: { newConfig in
                                        settingsManager.updateConfiguration(for: utility, config: newConfig)
                                    }
                                )
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .environment(\.settingsUseColors, useColors)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 650)
    }
    
    private func resetToDefaults() {
        // Disable all except CPU and Battery
        for utility in UtilityType.allCases {
            if var config = settingsManager.configurations[utility] {
                config.isEnabled = (utility == .cpu || utility == .battery)
                settingsManager.updateConfiguration(for: utility, config: config)
            }
        }
    }

    @ViewBuilder
    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundColor(.white.opacity(0.35))
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func sidebarButton(
        tag: SettingsSidebarItem,
        icon: String,
        iconColor: Color,
        title: String,
        isActive: Bool = false
    ) -> some View {
        let isSelected = selectedItem == tag
        Button(action: { selectedItem = tag }) {
            ModernSidebarRow(icon: icon, iconColor: iconColor, title: title, isActive: isActive)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    } else {
                        Color.clear
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .contentShape(.capsule)
            .onTapGesture { isSearchFocused = true }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if !filteredTopItems.isEmpty {
                        VStack(spacing: 2) {
                            ForEach(filteredTopItems, id: \.title) { item in
                                sidebarButton(
                                    tag: item.tag,
                                    icon: item.icon,
                                    iconColor: item.color,
                                    title: item.title
                                )
                            }
                        }
                    }

                    if !filteredFeatureUtilities.isEmpty {
                        sidebarSectionHeader("Features")
                        VStack(spacing: 2) {
                            ForEach(filteredFeatureUtilities) { utility in
                                sidebarButton(
                                    tag: SettingsSidebarItem.utility(utility),
                                    icon: utility.icon,
                                    iconColor: utility.accentColor,
                                    title: utility.rawValue,
                                    isActive: settingsManager.configurations[utility]?.isEnabled == true
                                )
                            }
                        }
                    }

                    if !filteredStatsUtilities.isEmpty {
                        sidebarSectionHeader("System Stats")
                        VStack(spacing: 2) {
                            ForEach(filteredStatsUtilities) { utility in
                                sidebarButton(
                                    tag: SettingsSidebarItem.utility(utility),
                                    icon: utility.icon,
                                    iconColor: utility.accentColor,
                                    title: utility.rawValue,
                                    isActive: settingsManager.configurations[utility]?.isEnabled == true
                                )
                            }
                        }
                    }

                    if !filteredAppItems.isEmpty {
                        sidebarSectionHeader("CharBar")
                        VStack(spacing: 2) {
                            ForEach(filteredAppItems, id: \.title) { item in
                                sidebarButton(
                                    tag: item.tag,
                                    icon: item.icon,
                                    iconColor: item.color,
                                    title: item.title
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .toolbar(removing: .sidebarToggle)

            // Color mode toggle at bottom of sidebar
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { useColors.toggle() } }) {
                HStack(spacing: 9) {
                    Image(systemName: useColors ? "paintpalette.fill" : "paintpalette")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(useColors ? .modernPurple : .white.opacity(0.4))
                    Text(useColors ? "Colors" : "No Colors")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(useColors ? .white.opacity(0.85) : .white.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(
                    .regular.tint(useColors ? Color.modernPurple.opacity(0.18) : Color.white.opacity(0.04)),
                    in: .capsule
                )
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .padding(.top, 4)
        }
    }
}

// MARK: - Modern Sidebar Row (Apple Style)
// MARK: - Modern Sidebar Row (Alcove Style)
struct ModernSidebarRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var isActive: Bool = false
    @Environment(\.settingsUseColors) private var useColors

    private var effectiveColor: Color { iconColor.settingsAdapted(useColors) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(effectiveColor)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            if isActive {
                Circle()
                    .fill(effectiveColor.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .shadow(color: effectiveColor.opacity(0.6), radius: 3)
            }
        }
        .padding(.vertical, 4)
    }
}

// Preference key for scroll offset tracking in General settings
private struct GeneralScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - General Settings (Modern Glass Style)
struct GeneralSettingsView: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin
    let resetAction: () -> Void
    @AppStorage("floatingBar_useLightMode") private var floatingBarUseLightMode: Bool = true
    
    // Display Mode
    @ObservedObject var modeManager = AppModeManager.shared
    @ObservedObject var screenObserver = ScreenObserver.shared
    @ObservedObject var floatingMenuBar = FloatingMenuBarController.shared
    
    /// Badge text for the active display state
    private var displayStateBadge: String {
        switch modeManager.activeState {
        case .menuBar: return "Menu Bar"
        case .menuBarStatic: return "Menu Bar (Static)"
        case .floatingBar: return "Floating"
        }
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                
                // Modern Header
                ModernSettingsHeader(
                    title: "General",
                    subtitle: "Configure app startup and display preferences",
                    icon: "gearshape.fill",
                    gradientColors: [Color.white.opacity(0.95), Color.white.opacity(0.70)]
                )
                
                // Beta Notice — slim inline accent, no big tinted card
                HStack(spacing: 10) {
                    Text("BETA")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                        )
                    Text("Active development — new features on the way")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal)
                
                // MARK: - Startup Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "power",
                            title: "Startup",
                            subtitle: "Launch preferences",
                            iconColor: .modernGreen
                        )
                        
                        ModernToggleRow(
                            icon: "arrow.right.circle.fill",
                            title: "Launch at Login",
                            subtitle: "Start CharBar when you log in",
                            iconColor: .modernGreen,
                            isOn: $launchAtLogin.isEnabled
                        )
                    }
                }
                
                
                // MARK: - Display Mode Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 18) {
                        ModernSectionHeader(
                            icon: "display.2",
                            title: "Display",
                            subtitle: "How CharBar appears on your screens",
                            iconColor: .modernBlue
                        )
                        
                        // Current Status
                        HStack(spacing: 10) {
                            Image(systemName: screenObserver.hasExternalDisplay ? "display.2" : "laptopcomputer")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                            Text(screenObserver.hasExternalDisplay ? "\(screenObserver.screenCount) displays connected" : "Built-in display only")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Spacer()
                            
                            // Active state badge
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(modeManager.isTemporaryStaticMode ? Color.orange : Color.green)
                                    .frame(width: 6, height: 6)
                                Text(displayStateBadge)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .glassEffect(.regular, in: .capsule)
                        }
                        .padding(.bottom, 4)
                        
                        // Mode Selection - 3 clear options
                        VStack(spacing: 6) {
                            DisplayModeCard(
                                icon: "sparkles.rectangle.stack",
                                title: "Smart Auto",
                                description: "Animated menu bar on your Mac. Switches to floating bar when a monitor is connected.",
                                badge: "Recommended",
                                isSelected: modeManager.preferredMode == .smartAuto
                            ) {
                                modeManager.preferredMode = .smartAuto
                            }
                            
                            DisplayModeCard(
                                icon: "menubar.rectangle",
                                title: "Always Menu Bar",
                                description: "Keeps the menu bar on all screens. Animations are automatically replaced with static icons on all displays.",
                                badge: nil,
                                isSelected: modeManager.preferredMode == .alwaysMenuBar
                            ) {
                                modeManager.preferredMode = .alwaysMenuBar
                            }
                            
                            DisplayModeCard(
                                icon: "macwindow",
                                title: "Always Floating",
                                description: "Uses the floating bar regardless of display setup.",
                                badge: nil,
                                isSelected: modeManager.preferredMode == .alwaysFloating
                            ) {
                                modeManager.preferredMode = .alwaysFloating
                            }
                        }
                        
                        // Temporary static indicator
                        if modeManager.isTemporaryStaticMode {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                Text("Animations temporarily paused on all displays. They will restore when you disconnect.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .padding(12)
                            .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 12))
                        }
                        
                        // Floating Bar Settings
                        Divider().background(Color.white.opacity(0.1))
                        
                        // ModernToggleRow(
                        //     icon: "arrow.left.and.right",
                        //     title: "Follow Active Screen",
                        //     subtitle: "Move floating bar to your active display",
                        //     iconColor: .modernPurple,
                        //     isOn: $floatingMenuBar.followsActiveScreen
                        // )
                        
                        ModernToggleRow(
                            icon: "cursorarrow.click.2",
                            title: "Pop at Cursor Position",
                            subtitle: "When toggled via shortcut, appear where your cursor is",
                            iconColor: .modernCyan,
                            isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "floatingBar_popAtCursor") },
                                set: { UserDefaults.standard.set($0, forKey: "floatingBar_popAtCursor") }
                            )
                        )
                        
                        // Hint about the shortcut
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            Text("Use ⌘⇧F to toggle the floating bar from anywhere")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.leading, 4)
                    }
                }
                
                // MARK: - Updates Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "arrow.down.circle.fill",
                            title: "Updates",
                            subtitle: "Keep CharBar up to date",
                            iconColor: .modernBlue
                        )
                        
                        UpdateSettingsView()
                    }
                }
                
                // MARK: - Reset Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "arrow.counterclockwise",
                            title: "Data & Reset",
                            subtitle: "Reset app to default settings",
                            iconColor: .modernRed
                        )
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reset to Defaults")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("This will reset all settings to their default values")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer()
                            Button(action: resetAction) {
                                Text("Reset")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.modernRed)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .glassEffect(.regular.tint(.modernRed.opacity(0.20)), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}

// MARK: - Floating Bar Style Button
struct FloatingBarStyleButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassEffect(
                .regular.tint(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.05)),
                in: .rect(cornerRadius: 12)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About View
struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("CharBar - Your Menu Bar Companion")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // App Info Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "app.badge.fill",
                            title: "App Info",
                            subtitle: "Version and build details",
                            iconColor: .modernCyan
                        )
                        
                        HStack {
                            Image(systemName: "number")
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 24)
                            Text("Version")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.modernCyan)
                        }
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 24)
                            Text("Build")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(buildNumber)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                
                        }
                    }
                }
                
                // Links Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "link",
                            title: "Links",
                            subtitle: "Useful resources",
                            iconColor: .modernPurple
                        )
                        
                        ModernLinkRow(icon: "globe", title: "Website", url: "https://charbar.app", iconColor: .white.opacity(0.4))
                        ModernLinkRow(icon: "lock.shield.fill", title: "Privacy Policy", url: "https://charbar.app/privacy", iconColor: .white.opacity(0.4))
                    }
                }
                
                // Help Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "questionmark.circle.fill",
                            title: "Help",
                            subtitle: "Get in touch with us",
                            iconColor: .modernGreen
                        )
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CharBar \(appVersion) (\(buildNumber))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Have a question or want to report a bug?")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                if let link = URL(string: "https://github.com/MonishSoundarRaj/CharBar/issues") {
                                    NSWorkspace.shared.open(link)
                                }
                            }) {
                                Text("Report an Issue")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .glassEffect(.regular.tint(.modernGreen.opacity(0.2)), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Credits Card
                GlassCard(opacity: 0.03) {
                    VStack(alignment: .center, spacing: 12) {
                        Text("Created with Claude Code and ❤️")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("© 2026 CharBar. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Legal & Credits View

struct LegalCreditsView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ModernSettingsHeader(
                    title: "Legal & Credits",
                    subtitle: "Licenses and acknowledgments",
                    icon: "doc.text.fill",
                    gradientColors: [Color.white.opacity(0.95), Color.white.opacity(0.70)]
                )
                
                // Design & Media Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "paintbrush.pointed.fill",
                            title: "Design & Media",
                            subtitle: "Visual assets and animations",
                            iconColor: .modernCyan
                        )
                        
                        Text("The beautiful visuals in this app were made possible by the generous communities at:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        
                        VStack(alignment: .leading, spacing: 12) {
                            creditLink(
                                name: "Unsplash",
                                detail: "Royalty-free images",
                                url: "https://unsplash.com/license"
                            )
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            creditLink(
                                name: "LottieFiles",
                                detail: "Open-source animations",
                                url: "https://lottiefiles.com/page/license"
                            )
                        }
                    }
                }
                
                // Open Source Software Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "Open Source Software",
                            subtitle: "Libraries used in this application",
                            iconColor: .modernCyan
                        )
                        
                        Text("This application utilizes the following open-source libraries:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        
                        // mediaremote-adapter
                        licenseSection(
                            name: "mediaremote-adapter",
                            copyright: "Copyright (c) Jonas van den Berg (ungive). All rights reserved.",
                            license: """
                            Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

                            1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

                            2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

                            3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

                            THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
                            """
                        )
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // stats
                        licenseSection(
                            name: "stats",
                            copyright: "Copyright (c) 2019 Serhiy Mytrovtsiy",
                            license: """
                            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                            The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                            """
                        )
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .ignoresSafeArea(.all, edges: .top)
    }
    
    private func creditLink(name: String, detail: String, url: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            if let link = URL(string: url) {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundColor(.modernCyan)
                }
            }
        }
    }
    
    private func licenseSection(name: String, copyright: String, license: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.modernCyan)
            
            Text(copyright)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            Text(license)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Modern Link Row
struct ModernLinkRow: View {
    let icon: String
    let title: String
    let url: String
    let iconColor: Color
    
    var body: some View {
        Button(action: { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AlcoveLinkButton: View {
    let title: String
    let url: String
    
    var body: some View {
        Button(action: { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alcove Style UI Components
struct AlcoveHeader: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, alignment: .center)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.bottom, 8)
    }
}

struct AlcoveCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// Legacy components for compatibility
struct SettingsHeader: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var body: some View {
        AlcoveHeader(icon: icon, title: title)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        AlcoveCard { content }
    }
}

struct AlcoveToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.gray)
        }
    }
}

struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String
    var body: some View {
        AlcoveLinkButton(title: title, url: url)
    }
}

struct GeneralToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.gray)
        }
    }
}

struct UtilityConfigView: View {
    let utility: UtilityType
    @Binding var configuration: UtilityConfiguration
    
    private func getDisplayOptionDescription(for option: DisplayOption) -> String {
        switch option {
        case .none:
            return "Show only the animated character"
        case .percentage:
            return "Display as percentage (e.g., 45%)"
        case .absolute:
            return "Display actual value (e.g., 8.5 GB)"
        case .speed:
            return "Display transfer speeds"
        case .timer:
            return "Display countdown or time"
        case .batteryLevel:
            return "Display device battery level"
        }
    }
    
    private var headerGradientColors: [Color] {
        switch utility {
        case .cpu: return [.modernOrange, .modernRed]
        case .gpu: return [.modernPurple, .modernPink]
        case .ram: return [.modernBlue, .modernCyan]
        case .battery: return [.modernGreen, .modernMint]
        case .network: return [.modernCyan, .modernBlue]
        case .disk: return [.modernOrange, .modernYellow]
        case .bluetooth: return [.modernBlue, .modernCyan]
        case .music: return [.modernPink, .modernPurple]
        case .pomodoro: return [.modernRed, .modernOrange]
        case .meetings: return [.modernOrange, .modernYellow]
        default: return [.modernCyan, .modernBlue]
        }
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // Modern Header
                ModernSettingsHeader(
                    title: utility.rawValue,
                    subtitle: utility.description,
                    icon: utility.icon,
                    gradientColors: headerGradientColors
                )
                
                // Enable Toggle Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "eye.fill",
                            title: "Visibility",
                            subtitle: "Control menu bar display",
                            iconColor: .modernCyan
                        )
                        
                        ModernToggleRow(
                            icon: "menubar.rectangle",
                            title: "Show in Menu Bar",
                            subtitle: "Display this utility in your menu bar",
                            iconColor: headerGradientColors[0],
                            isOn: $configuration.isEnabled
                        )
                    }
                }
                
                if configuration.isEnabled {
                    // Bluetooth-specific character panels
                    if utility == .bluetooth {
                        BluetoothCharacterSettings(configuration: $configuration)
                    }
                    
                    // Pomodoro-specific character panels
                    if utility == .pomodoro {
                        PomodoroCharacterSettings()
                    }
                    
                    // Character Selection Card (for non-special utilities)
                    if utility != .bluetooth && utility != .pomodoro {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 18) {
                                ModernSectionHeader(
                                    icon: "person.fill",
                                    title: "Character",
                                    subtitle: "Choose the animated character",
                                    iconColor: .modernPurple
                                )
                                
                                ModernCharacterPicker(
                                    selectedCharacter: $configuration.character,
                                    utilityType: utility
                                )
                            }
                        }
                    }
                    
                    // Display Options Card
                    if DisplayOption.options(for: utility).count > 1 && utility != .music {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 18) {
                                ModernSectionHeader(
                                    icon: "textformat",
                                    title: "Display Format",
                                    subtitle: "Choose what to show next to the character",
                                    iconColor: .modernOrange
                                )
                                
                                VStack(spacing: 4) {
                                    ForEach(DisplayOption.options(for: utility), id: \.self) { option in
                                        ModernRadioOption(
                                            title: option.rawValue,
                                            subtitle: getDisplayOptionDescription(for: option),
                                            isSelected: configuration.displayOption == option
                                        ) {
                                            configuration.displayOption = option
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if utility == .music {
                        MusicSpecificSettings()
                    }
                    
                    if utility == .meetings {
                        MeetingSpecificSettings()
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}

// MARK: - Modern Character Picker (Visual Card Selection)
struct ModernCharacterPicker: View {
    @Binding var selectedCharacter: CharacterType
    let utilityType: UtilityType
    @State private var showLottieWarning = false
    @State private var pendingCharacter: CharacterType?
    
    private var availableCharacters: [CharacterType] {
        AnimationManifest.characters(for: utilityType)
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 90), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(availableCharacters, id: \.self) { character in
                    ModernCharacterCard(
                        character: character,
                        isSelected: selectedCharacter == character
                    ) {
                        if !character.isStaticIcon && AppModeManager.shared.isTemporaryStaticMode {
                            pendingCharacter = character
                            showLottieWarning = true
                        } else {
                            selectedCharacter = character
                        }
                    }
                }
            }
            
            if showLottieWarning {
                LottieWarningCard(
                    onKeepStatic: {
                        pendingCharacter = nil
                        showLottieWarning = false
                    },
                    onSwitchToFloating: {
                        if let pending = pendingCharacter {
                            selectedCharacter = pending
                        }
                        AppModeManager.shared.preferredMode = .smartAuto
                        pendingCharacter = nil
                        showLottieWarning = false
                    }
                )
            }
        }
    }
}

// MARK: - Modern Character Card
struct ModernCharacterCard: View {
    let character: CharacterType
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .glassEffect(
                        .regular.tint(
                            isSelected ? Color.modernCyan.opacity(0.18)
                                       : Color.white.opacity(isHovering ? 0.06 : 0.02)
                        ),
                        in: .rect(cornerRadius: 14)
                    )
                    .frame(height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ?
                                    LinearGradient(colors: [.modernCyan, .modernPurple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color.white.opacity(isHovering ? 0.2 : 0.08)], startPoint: .top, endPoint: .bottom),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                if character.isStaticIcon {
                    // Static icon
                    Image(systemName: character.sfSymbolName ?? "questionmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(isSelected ? .modernCyan : .white.opacity(0.6))
                } else if character.hasLottieAnimation, let lottieFile = character.lottieFileName {
                    // Lottie animation
                    LottieCharacterView(
                        animationName: lottieFile,
                        value: 0.5,
                        isConnected: true,
                        color: isSelected ? .modernCyan : .white.opacity(0.6)
                    )
                    .frame(width: 40, height: 40)
                }
            }
            
            Text(character.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .modernCyan : .white.opacity(0.6))
                .lineLimit(1)
        }
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }
    }
}

// MARK: - Modern Settings Components

/// A clean settings row with title, subtitle, and accessory
struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: () -> Accessory
    
    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

/// A section with title and content
struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content
    
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            content()
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
}

/// Radio button style option row
struct RadioOptionRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Radio button circle
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 10, height: 10)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sidebar row component
struct SidebarRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let isActive: Bool
    
    init(icon: String, iconColor: Color = .secondary, title: String, subtitle: String? = nil, isActive: Bool = false) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isActive {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }
}

// Dark Toggle Row (Legacy - kept for compatibility)
struct DarkToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.modernCyan)
        }
    }
}

struct MusicSpecificSettings: View {
    var body: some View {
        MusicConfigView()
    }
}

// MARK: - Meeting Specific Settings
struct MeetingSpecificSettings: View {
    @ObservedObject var meetingManager = MeetingManager.shared
    
    @AppStorage("meeting_joinButtonMinutes") private var joinButtonMinutes: Int = 5
    @AppStorage("meeting_countdownMinutes") private var countdownMinutes: Int = 15
    @AppStorage("meeting_notificationDismissSeconds") private var notificationDismissSeconds: Int = 0
    @AppStorage("meeting_showNotification") private var showNotification: Bool = true
    @AppStorage("meeting_notificationSound") private var notificationSound: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Join Button Timing Card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "hand.tap.fill",
                        title: "Join Button",
                        subtitle: "One-click meeting join from the menu bar",
                        iconColor: .modernGreen
                    )
                    
                    ModernInfoBox(
                        icon: "info.circle",
                        message: "When a meeting with a video link (Zoom, Google Meet, Teams, etc.) is coming up, a Join button appears in the calendar dropdown. Choose how early it shows up.",
                        iconColor: .modernGreen
                    )

                    VStack(spacing: 4) {
                        ModernRadioOption(title: "2 minutes before", subtitle: "Show join button very close to start time", isSelected: joinButtonMinutes == 2) { joinButtonMinutes = 2 }
                        ModernRadioOption(title: "5 minutes before", subtitle: "Recommended — gives you time to prepare", isSelected: joinButtonMinutes == 5) { joinButtonMinutes = 5 }
                        ModernRadioOption(title: "10 minutes before", subtitle: "Extra buffer for back-to-back meetings", isSelected: joinButtonMinutes == 10) { joinButtonMinutes = 10 }
                    }
                }
            }
            
            // Countdown Display Card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "timer",
                        title: "Countdown Timer",
                        subtitle: "Live countdown in the menu bar before meetings",
                        iconColor: .modernOrange
                    )
                    
                    ModernInfoBox(
                        icon: "info.circle",
                        message: "A live countdown timer appears next to the calendar icon in your menu bar, so you always know how long until your next meeting starts.",
                        iconColor: .modernOrange
                    )
                    
                    VStack(spacing: 4) {
                        ModernRadioOption(title: "10 minutes before", subtitle: "Show countdown closer to meeting time", isSelected: countdownMinutes == 10) { countdownMinutes = 10 }
                        ModernRadioOption(title: "15 minutes before", subtitle: "Recommended — enough time to wrap up", isSelected: countdownMinutes == 15) { countdownMinutes = 15 }
                        ModernRadioOption(title: "30 minutes before", subtitle: "Extended notice for important meetings", isSelected: countdownMinutes == 30) { countdownMinutes = 30 }
                    }
                }
            }
            
            // Notification Card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "bell.fill",
                        title: "Notifications",
                        subtitle: "Meeting reminder alerts",
                        iconColor: .modernPink
                    )
                    
                    ModernToggleRow(
                        icon: "bell.badge.fill",
                        title: "Show Meeting Notifications",
                        subtitle: "Display a popup when a meeting is about to start",
                        iconColor: .modernPink,
                        isOn: $showNotification
                    )
                    
                    if showNotification {
                        ModernToggleRow(
                            icon: "speaker.wave.2.fill",
                            title: "Notification Sound",
                            subtitle: "Play a sound when a meeting notification appears",
                            iconColor: .modernPink,
                            isOn: $notificationSound
                        )
                        Divider().background(Color.white.opacity(0.08))
                        
                        ModernInfoBox(
                            icon: "info.circle",
                            message: "Choose whether the notification stays on screen until you dismiss it, or disappears automatically.",
                            iconColor: .modernPink
                        )
                        
                        VStack(spacing: 4) {
                            ModernRadioOption(title: "Manual dismiss", subtitle: "Notification stays until you close it", isSelected: notificationDismissSeconds == 0) { notificationDismissSeconds = 0 }
                            ModernRadioOption(title: "Auto-dismiss (10s)", subtitle: "Quick glance — disappears after 10 seconds", isSelected: notificationDismissSeconds == 10) { notificationDismissSeconds = 10 }
                            ModernRadioOption(title: "Auto-dismiss (30s)", subtitle: "More time to read before auto-closing", isSelected: notificationDismissSeconds == 30) { notificationDismissSeconds = 30 }
                        }
                    }
                }
            }
            
            // Google Calendar URL Subscription
            GoogleCalendarSubscriptionSection()
        }
    }
}

// MARK: - Smart Link Info Row
struct SmartLinkInfoRow: View {
    let icon: String
    let label: String
    let detail: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color.opacity(0.7))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 100, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

// MARK: - Google Calendar URL Subscription (Coming Soon)
struct GoogleCalendarSubscriptionSection: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                ModernSectionHeader(
                    icon: "calendar.badge.plus",
                    title: "Calendar Subscriptions (Coming Soon)",
                    subtitle: "Google Calendar, Outlook & ICS feeds",
                    iconColor: .modernBlue
                )
                
                // Tip - currently use system Calendar
                ModernInfoBox(
                    icon: "lightbulb",
                    title: "Tip",
                    message: "For now, add your Google Calendar account in System Settings → Internet Accounts → Google. Your events will appear here automatically.",
                    iconColor: .modernYellow
                )
            }
        }
    }
}

// MARK: - Bluetooth Character Settings (Modern Glass Style)
struct BluetoothCharacterSettings: View {
    @Binding var configuration: UtilityConfiguration
    @AppStorage("bluetooth_headphoneCharacter") private var headphoneCharacter: String = "dynoDancing"
    @AppStorage("bluetooth_quickConnectMode") private var quickConnectMode: Bool = false
    
    private var isStaticMode: Bool {
        configuration.character.isStaticIcon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Quick Connect Mode Card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "bolt.fill",
                        title: "Quick Connect",
                        subtitle: "One-click device connection",
                        iconColor: .modernYellow
                    )
                    
                    ModernToggleRow(
                        icon: "hand.tap.fill",
                        title: "Enable Quick Connect",
                        subtitle: "Left-click connects • Right-click opens menu",
                        iconColor: .modernYellow,
                        isOn: $quickConnectMode
                    )
                    
                    if quickConnectMode {
                        ModernInfoBox(
                            icon: "info.circle.fill",
                            title: "How it works",
                            message: "Clicking the menu bar icon will connect to your last paired device. Right-click or two-finger tap to open the full menu.",
                            iconColor: .modernBlue
                        )
                    }
                }
            }
            
            // Default Character Card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "keyboard",
                        title: "Default Character",
                        subtitle: "Shows when no audio device is connected",
                        iconColor: .modernBlue
                    )
                    
                    ModernCharacterGrid(
                        selectedCharacter: $configuration.character,
                        characters: AnimationManifest.bluetoothIcons
                    )
                    
                    if isStaticMode {
                        ModernInfoBox(
                            icon: "info.circle.fill",
                            title: "Static Icon Mode",
                            message: "Connected device icons will use standard SF Symbols. No animations will be shown.",
                            iconColor: .modernCyan
                        )
                    }
                }
            }
            
            if !isStaticMode {
                // Connected Device Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "headphones",
                            title: "Audio Device Connected",
                            subtitle: "Animation shown when an audio device is connected",
                            iconColor: .modernPurple
                        )
                        
                        ModernCharacterGrid(
                            selectedCharacter: Binding(
                                get: { CharacterType(rawValue: headphoneCharacter) ?? .dynoDancing },
                                set: { headphoneCharacter = $0.rawValue }
                            ),
                            characters: AnimationManifest.bluetoothConnected
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Pomodoro Character Settings (Modern Glass Style)
struct PomodoroCharacterSettings: View {
    @AppStorage("pomo_workingCharacter") private var workingCharacter: String = "hourglass"
    @AppStorage("pomo_restingCharacter") private var restingCharacter: String = "sleepingCat"
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var chimeSoundManager = PomodoroSoundManager.shared
    
    private var isStaticMode: Bool {
        CharacterType(rawValue: workingCharacter)?.isStaticIcon ?? false
    }
    
    private func notifySettingsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Focus Mode Card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModernSectionHeader(
                        icon: "laptopcomputer",
                        title: "Focus Mode",
                        subtitle: "Character shown during work sessions",
                        iconColor: .modernOrange
                    )
                    
                    ModernCharacterGrid(
                        selectedCharacter: Binding(
                            get: { CharacterType(rawValue: workingCharacter) ?? .hourglass },
                            set: { newValue in
                                workingCharacter = newValue.rawValue
                                if newValue.isStaticIcon {
                                    // Keep resting icon in sync with the chosen static style
                                    restingCharacter = newValue.rawValue
                                }
                                notifySettingsChanged()
                            }
                        ),
                        characters: AnimationManifest.pomodoroWorking
                    )
                    
                    if isStaticMode {
                        ModernInfoBox(
                            icon: "info.circle.fill",
                            title: "Static Icon Mode",
                            message: "Break mode will also use the static timer icon. No animations will be shown.",
                            iconColor: .modernCyan
                        )
                    }
                }
            }
            
            if !isStaticMode {
                // Break Mode Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ModernSectionHeader(
                            icon: "cup.and.saucer.fill",
                            title: "Break Mode",
                            subtitle: "Character shown during rest periods",
                            iconColor: .modernMint
                        )
                        
                        ModernCharacterGrid(
                            selectedCharacter: Binding(
                                get: { CharacterType(rawValue: restingCharacter) ?? .sleepingCat },
                                set: { newValue in
                                    restingCharacter = newValue.rawValue
                                    notifySettingsChanged()
                                }
                            ),
                            characters: AnimationManifest.pomodoroResting
                        )
                    }
                }
            }
            
            // ── Sounds Card ──────────────────────────────────────────────
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    ModernSectionHeader(
                        icon: "speaker.wave.2.fill",
                        title: "Sounds",
                        subtitle: "Ambient audio and session chimes",
                        iconColor: .modernBlue
                    )
                    
                    // Ambient sound picker — uses unified SoundManager
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Focus Ambient")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Soundscape.allCases) { sound in
                                    Button(action: {
                                        soundManager.currentSoundscape = sound
                                        notifySettingsChanged()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: sound.icon)
                                                .font(.system(size: 12))
                                            Text(sound.rawValue)
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .glassEffect(
                                            .regular.tint(soundManager.currentSoundscape == sound
                                                          ? Color.modernBlue.opacity(0.35)
                                                          : Color.white.opacity(0.04)),
                                            in: .capsule
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(soundManager.currentSoundscape == sound
                                                              ? Color.modernBlue.opacity(0.6)
                                                              : Color.clear, lineWidth: 1)
                                        )
                                        .foregroundColor(soundManager.currentSoundscape == sound
                                                         ? .white : .white.opacity(0.55))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Volume slider
                    if soundManager.currentSoundscape != .silent {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Volume")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                                Spacer()
                                Text("\(Int(soundManager.volume * 100))%")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Slider(value: $soundManager.volume, in: 0...1)
                                .accentColor(.modernBlue)
                        }
                    }
                    
                    Divider().opacity(0.12)
                    
                    // Chimes toggle + pickers — uses PomodoroSoundManager
                    ModernToggleRow(
                        icon: "bell.fill",
                        title: "Session Chimes",
                        subtitle: "Play a sound at each session transition",
                        iconColor: .modernOrange,
                        isOn: $chimeSoundManager.chimeEnabled
                    )
                    
                    if chimeSoundManager.chimeEnabled {
                        VStack(spacing: 10) {
                            PomodoroChimePicker(label: "Focus start",   selection: $chimeSoundManager.chimeStartKey)
                            PomodoroChimePicker(label: "Break start",   selection: $chimeSoundManager.chimeBreakKey)
                            PomodoroChimePicker(label: "Session done",  selection: $chimeSoundManager.chimeCompleteKey)
                        }
                    }
                    
                    // Info box about adding sound files
                    ModernInfoBox(
                        icon: "folder.badge.plus",
                        title: "Adding custom ambient sounds",
                        message: "Place your .mp3 files in the Sounds folder inside the Xcode project: rain.mp3, white_noise.mp3, coffee_shop.mp3, forest.mp3, ocean.mp3, fireplace.mp3. Ensure they're added to the CharBar target.",
                        iconColor: .modernCyan
                    )
                }
            }
        }
    }
}

// MARK: - Pomodoro Chime Row
private struct PomodoroChimePicker: View {
    let label: String
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(PomodoroChime.allCases) { chime in
                    Text(chime.displayName).tag(chime.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }
}

// MARK: - Modern Character Grid (Visual Selection)
struct ModernCharacterGrid: View {
    @Binding var selectedCharacter: CharacterType
    let characters: [CharacterType]
    @State private var showLottieWarning = false
    @State private var pendingCharacter: CharacterType?
    
    let columns = [
        GridItem(.adaptive(minimum: 85), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(characters, id: \.self) { character in
                    ModernCharacterCard(
                        character: character,
                        isSelected: selectedCharacter == character
                    ) {
                        if !character.isStaticIcon && AppModeManager.shared.isTemporaryStaticMode {
                            pendingCharacter = character
                            showLottieWarning = true
                        } else {
                            selectedCharacter = character
                        }
                    }
                }
            }
            
            if showLottieWarning {
                LottieWarningCard(
                    onKeepStatic: {
                        pendingCharacter = nil
                        showLottieWarning = false
                    },
                    onSwitchToFloating: {
                        if let pending = pendingCharacter {
                            selectedCharacter = pending
                        }
                        AppModeManager.shared.preferredMode = .smartAuto
                        pendingCharacter = nil
                        showLottieWarning = false
                    }
                )
            }
        }
    }
}

// MARK: - Reusable Character Selection Panel
struct CharacterSelectionPanel: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var selectedCharacter: CharacterType
    let characters: [CharacterType]
    var cardSize: CGFloat = 120
    @State private var showLottieWarning = false
    @State private var pendingCharacter: CharacterType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 4)
            
            // Character Grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(characters) { character in
                        CharacterCardView(
                            character: character,
                            isSelected: selectedCharacter == character,
                            size: cardSize
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if !character.isStaticIcon && AppModeManager.shared.isTemporaryStaticMode {
                                    pendingCharacter = character
                                    showLottieWarning = true
                                } else {
                                    selectedCharacter = character
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
            }
            
            if showLottieWarning {
                LottieWarningCard(
                    onKeepStatic: {
                        pendingCharacter = nil
                        showLottieWarning = false
                    },
                    onSwitchToFloating: {
                        if let pending = pendingCharacter {
                            selectedCharacter = pending
                        }
                        AppModeManager.shared.preferredMode = .smartAuto
                        pendingCharacter = nil
                        showLottieWarning = false
                    }
                )
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Compact Character Picker Panel (legacy, kept for compatibility)
struct CharacterPickerPanel: View {
    @Binding var selectedCharacter: CharacterType
    let characters: [CharacterType]
    var cardSize: CGFloat = 120
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(characters) { character in
                    CharacterCardView(
                        character: character,
                        isSelected: selectedCharacter == character,
                        size: cardSize
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCharacter = character
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
        }
    }
}

struct CharacterPickerView: View {
    @Binding var selectedCharacter: CharacterType
    var utilityType: UtilityType? = nil // Optional: filter by utility semantics
    var cardSize: CGFloat = 140 // Bigger cards
    
    let columns = [
        GridItem(.adaptive(minimum: 145), spacing: 16) // Bigger minimum
    ]
    
    // Get semantically appropriate characters for the utility
    private var availableCharacters: [CharacterType] {
        guard let utility = utilityType else {
            return CharacterType.allCases.map { $0 } // All characters
        }
        
        // Get characters directly from the semantic manifest
        return AnimationManifest.characters(for: utility)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show category hint if utility-specific
            if let utility = utilityType {
                HStack(spacing: 6) {
                    Image(systemName: utility.icon)
                        .font(.system(size: 12))
                        .foregroundColor(utility.accentColor)
                    
                    Text("Recommended for \(utility.rawValue)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(availableCharacters.count) options")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(availableCharacters) { character in
                        CharacterCardView(
                            character: character,
                            isSelected: selectedCharacter == character,
                            size: cardSize
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedCharacter = character
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(minHeight: 280, idealHeight: 400, maxHeight: 500)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

struct CharacterCardView: View {
    let character: CharacterType
    let isSelected: Bool
    var size: CGFloat = 200 // Even bigger default size
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Animation container - takes up most of the card
            ZStack {
                // Subtle background when selected or hovered
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.06 : isHovering ? 0.04 : 0.0))
                
                // Static icons show SF Symbol (no "No Animation" text)
                if character.isStaticIcon, let sfSymbol = character.sfSymbolName {
                    Image(systemName: sfSymbol)
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundColor(.secondary)
                }
                // Use Lottie animation if available
                else if character.hasLottieAnimation, let lottieFile = character.lottieFileName {
                    LottieCharacterView(
                        animationName: lottieFile,
                        value: 0.5, // Demo value
                        isConnected: true,
                        color: character.color
                    )
                    .frame(width: size * 0.75, height: size * 0.75) // Much bigger animation
                } else {
                    Text(character.icon)
                        .font(.system(size: size * 0.45))
                }
            }
            .frame(width: size - 12, height: size - 32)
            
            Text(character.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size)
        .glassEffect(
            .regular.tint(
                isSelected ? Color.modernCyan.opacity(0.18)
                           : Color.white.opacity(isHovering ? 0.04 : 0.0)
            ),
            in: .rect(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.modernCyan.opacity(0.7) : Color.secondary.opacity(isHovering ? 0.4 : 0.18), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isHovering ? 1.04 : isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct CharacterPreviewView: View {
    let character: CharacterType
    @State private var animationValue: Double = 0
    
    var body: some View {
        VStack(spacing: 15) {
            // Use Lottie animation if available, otherwise emoji
            if character.hasLottieAnimation, let lottieFile = character.lottieFileName {
                LottieCharacterView(
                    animationName: lottieFile,
                    value: 0.7, // Demo value for preview
                    isConnected: true,
                    color: character.color
                )
                .frame(width: 150, height: 150)
            } else {
                Text(character.icon)
                    .font(.system(size: 80))
                    .scaleEffect(scale)
                    .offset(x: xOffset, y: yOffset)
                    .shadow(color: character.color.opacity(0.5), radius: 5)
            }
            
            Text("Animates based on \(character.animationStyle.description)")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                animationValue = 1.0
            }
        }
    }
    
    private var scale: CGFloat {
        switch character.animationStyle {
        case .scale: return 1.0 + (0.3 * sin(animationValue * .pi * 2))
        case .pulse: return 1.0 + (0.15 * sin(animationValue * .pi * 4))
        default: return 1.0
        }
    }
    
    private var xOffset: CGFloat {
        switch character.animationStyle {
        case .run: return sin(animationValue * .pi * 4) * 20
        default: return 0
        }
    }
    
    private var yOffset: CGFloat {
        switch character.animationStyle {
        case .fly, .float: return sin(animationValue * .pi * 2) * 15
        case .flicker: return sin(animationValue * .pi * 8) * 5
        default: return 0
        }
    }
}

extension AnimationStyle {
    var description: String {
        switch self {
        case .scale: return "size"
        case .run: return "speed"
        case .fly: return "height"
        case .pulse: return "intensity"
        case .float: return "movement"
        case .flicker: return "activity"
        }
    }
}

// MARK: - Modern Accent Colors
extension Color {
    static let modernCyan = Color(red: 0.0, green: 0.85, blue: 0.95)
    static let modernMint = Color(red: 0.2, green: 0.95, blue: 0.75)
    static let modernPink = Color(red: 1.0, green: 0.4, blue: 0.65)
    static let modernPurple = Color(red: 0.7, green: 0.4, blue: 1.0)
    static let modernOrange = Color(red: 1.0, green: 0.55, blue: 0.3)
    static let modernBlue = Color(red: 0.4, green: 0.6, blue: 1.0)
    static let modernGreen = Color(red: 0.3, green: 0.85, blue: 0.5)
    static let modernRed = Color(red: 1.0, green: 0.35, blue: 0.4)
    static let modernYellow = Color(red: 1.0, green: 0.8, blue: 0.2)
}

// MARK: - Modern Settings Header (Reusable)
struct ModernSettingsHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradientColors: [Color]
    @Environment(\.settingsUseColors) private var useColors
    
    private var effectiveGradient: [Color] {
        useColors ? gradientColors : [Color.white.opacity(0.95), Color.white.opacity(0.70)]
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: effectiveGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }
}

// MARK: - Glass Card (Reusable Container)
struct GlassCard<Content: View>: View {
    let content: () -> Content
    var opacity: Double = 0.05

    init(opacity: Double = 0.05, @ViewBuilder content: @escaping () -> Content) {
        self.opacity = opacity
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .padding(.horizontal)
    }
}

// MARK: - Modern Section Header (Inside Cards)
struct ModernSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconColor: Color
    @Environment(\.settingsUseColors) private var useColors
    
    init(icon: String, title: String, subtitle: String? = nil, iconColor: Color = .modernCyan) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor.settingsAdapted(useColors))
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Modern Toggle Row
struct ModernToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconColor: Color
    @Binding var isOn: Bool
    @Environment(\.settingsUseColors) private var useColors
    
    init(icon: String, title: String, subtitle: String? = nil, iconColor: Color = .white.opacity(0.7), isOn: Binding<Bool>) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor.settingsAdapted(useColors))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.modernCyan)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Modern Selection Card (For Lottie Characters)
struct ModernSelectionCard: View {
    let title: String
    let isSelected: Bool
    let content: AnyView
    let action: () -> Void
    @State private var isHovering = false
    
    init<Content: View>(title: String, isSelected: Bool, @ViewBuilder content: () -> Content, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.content = AnyView(content())
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .glassEffect(
                        .regular.tint(
                            isSelected ? Color.modernCyan.opacity(0.18)
                                       : Color.white.opacity(isHovering ? 0.06 : 0.02)
                        ),
                        in: .rect(cornerRadius: 14)
                    )
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ?
                                    LinearGradient(colors: [.modernCyan, .modernPurple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color.white.opacity(isHovering ? 0.2 : 0.08)], startPoint: .top, endPoint: .bottom),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                content
            }

            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .modernCyan : .white.opacity(0.6))
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }
    }
}

// MARK: - Modern Radio Option
struct ModernRadioOption: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isSelected ? .modernCyan : .white.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .glassEffect(.regular.tint(.modernCyan.opacity(0.14)), in: .rect(cornerRadius: 12))
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        }
    }
}

// MARK: - Display Mode Card
struct DisplayModeCard: View {
    let icon: String
    let title: String
    let description: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .modernCyan : .white.opacity(0.55))
                    .frame(width: 28, alignment: .center)

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .white.opacity(0.2))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .glassEffect(.regular.tint(.white.opacity(0.08)), in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                } else {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Info Box
struct ModernInfoBox: View {
    let icon: String
    let title: String?
    let message: String
    let iconColor: Color

    init(icon: String, title: String? = nil, message: String, iconColor: Color) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor.opacity(0.85))
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                if let title = title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))
                }
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(iconColor.opacity(0.05)), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(iconColor.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Lottie Warning Card (shown when selecting Lottie in static mode)
struct LottieWarningCard: View {
    let onKeepStatic: () -> Void
    let onSwitchToFloating: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.modernYellow)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Animations unavailable")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("You're in Always Menu Bar mode with an external display connected. Lottie animations can't display in the menu bar on external displays.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack(spacing: 10) {
                Button(action: onKeepStatic) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11))
                        Text("Keep Static")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)

                Button(action: onSwitchToFloating) {
                    HStack(spacing: 5) {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 11))
                        Text("Switch to Floating Bar")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.tint(.modernCyan.opacity(0.28)), in: .capsule)
                    .foregroundColor(.modernCyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(.modernYellow.opacity(0.12)), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.modernYellow.opacity(0.22), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: true)
    }
}

// MARK: - Instruction Step
struct InstructionStep: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.modernCyan)
                .frame(width: 20, height: 20)
                .glassEffect(.regular.tint(.modernCyan.opacity(0.28)), in: .circle)
            
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @ObservedObject private var backgroundManager = BackgroundImageManager.shared
    @State private var deletingImageName: String? = nil
    @Environment(\.settingsUseColors) private var useColors
    
    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 20)
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ModernSettingsHeader(
                    title: "Appearance",
                    subtitle: "Customize menu dropdown backgrounds",
                    icon: "paintbrush.fill",
                    gradientColors: [.red, .modernPink]
                )
                
                // Background Image Selection Card
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.modernCyan.settingsAdapted(useColors))
                        Text("Menu Background")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Text("Choose a background style for your menu dropdowns")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Image Grid
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(backgroundManager.availableImages) { option in
                            backgroundGridItem(option: option)
                        }
                        
                        uploadCard
                    }
                }
                .padding(22)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.20), radius: 16, y: 5)
                .padding(.horizontal)

                // Image Settings (only show when an image is selected)
                if backgroundManager.selectedBackgroundImage != nil {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.modernOrange.settingsAdapted(useColors))
                            Text("Background Settings")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        // Blur Amount Slider
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "drop.halffull")
                                    .foregroundColor(Color.modernBlue.settingsAdapted(useColors))
                                Text("Blur Amount")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(backgroundManager.blurAmount))")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.modernCyan.settingsAdapted(useColors))
                            }
                            
                            Slider(value: $backgroundManager.blurAmount, in: 0...25, step: 1)
                                .accentColor(Color.modernCyan.settingsAdapted(useColors))
                        }
                        .padding(.horizontal, 4)
                        
                        // Overlay Opacity Slider
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "moon.fill")
                                    .foregroundColor(Color.modernPurple.settingsAdapted(useColors))
                                Text("Darken Overlay")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(backgroundManager.overlayOpacity * 100))%")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.modernPurple.settingsAdapted(useColors))
                            }
                            
                            Slider(value: $backgroundManager.overlayOpacity, in: 0...0.8, step: 0.05)
                                .accentColor(Color.modernPurple.settingsAdapted(useColors))
                        }
                        .padding(.horizontal, 4)
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        // Reset Button
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    backgroundManager.resetToDefault()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Reset to Glass")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .glassEffect(.regular, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(22)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 16, y: 5)
                    .padding(.horizontal)
                }

                // Preview Section
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.modernMint)
                        Text("Preview")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    HStack {
                        Spacer()
                        BackgroundPreviewView()
                        Spacer()
                    }
                }
                .padding(22)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
                .padding(.horizontal)

                Spacer(minLength: 24)
            }
            .padding(.vertical)
        }
    }
    
    @ViewBuilder
    private func backgroundGridItem(option: BackgroundImageOption) -> some View {
        ZStack(alignment: .topTrailing) {
            BackgroundImageCard(
                option: option,
                isSelected: backgroundManager.selectedBackgroundImage == option.name
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    backgroundManager.selectedBackgroundImage = option.name
                }
            }
            
            if option.isUserImage, let name = option.name {
                deleteOverlay(for: name)
            }
        }
    }
    
    @ViewBuilder
    private func deleteOverlay(for name: String) -> some View {
        if deletingImageName == name {
            HStack(spacing: 4) {
                Button(action: {
                    backgroundManager.deleteUserImage(named: name)
                    deletingImageName = nil
                }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button(action: { deletingImageName = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        } else {
            Button(action: { deletingImageName = name }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
    
    private var uploadCard: some View {
        Button(action: openImagePicker) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .foregroundColor(.white.opacity(0.25))
                        )
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Upload")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(height: 90)
                
                Text("Custom Image")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background image"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            backgroundManager.importImage(from: url)
        }
    }
}

// MARK: - Background Image Card
struct BackgroundImageCard: View {
    let option: BackgroundImageOption
    let isSelected: Bool
    @ObservedObject private var backgroundManager = BackgroundImageManager.shared
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 10) {
            // Thumbnail with modern styling
            ZStack {
                if option.isDefault {
                    // Glass effect preview - shows a beautiful blurred gradient
                    ZStack {
                        // Colorful gradient background
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.15, blue: 0.25),
                                Color(red: 0.1, green: 0.1, blue: 0.2),
                                Color(red: 0.2, green: 0.15, blue: 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Blurred colored orbs
                        Circle()
                            .fill(Color.modernPurple.opacity(0.4))
                            .frame(width: 60, height: 60)
                            .blur(radius: 20)
                            .offset(x: -20, y: -15)
                        
                        Circle()
                            .fill(Color.modernCyan.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .blur(radius: 18)
                            .offset(x: 25, y: 20)
                        
                        Circle()
                            .fill(Color.modernPink.opacity(0.25))
                            .frame(width: 40, height: 40)
                            .blur(radius: 15)
                            .offset(x: 10, y: -25)
                        
                        // Glass overlay
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .opacity(0.4)
                        
                        // Icon
                        VStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .modernCyan],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Text("Glass")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if let name = option.name, let nsImage = backgroundManager.loadImage(named: name) {
                    // Image thumbnail with subtle overlay
                    ZStack {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 90)
                        
                        // Gradient overlay for better text visibility
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    // Fallback with modern styling
                    ZStack {
                        LinearGradient(
                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        Image(systemName: "photo.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(height: 90)
            
            // Label with modern styling
            Text(option.displayName)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .modernCyan : .white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(12)
        .glassEffect(
            .regular.tint(
                isSelected ? Color.modernCyan.opacity(0.18)
                           : Color.white.opacity(isHovering ? 0.05 : 0.02)
            ),
            in: .rect(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected
                        ? LinearGradient(colors: [.modernCyan, .modernPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(isHovering ? 0.2 : 0.08), Color.white.opacity(isHovering ? 0.1 : 0.04)], startPoint: .top, endPoint: .bottom),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(Rectangle()) // Ensure the entire card area is tappable
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Background Preview View
struct BackgroundPreviewView: View {
    @ObservedObject private var backgroundManager = BackgroundImageManager.shared
    
    var body: some View {
        // Mini preview of how menu will look
        ZStack {
            // Background based on selection
            if let imageName = backgroundManager.selectedBackgroundImage,
               let nsImage = backgroundManager.loadImage(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: backgroundManager.blurAmount * 0.5)
                    .overlay(Color.black.opacity(backgroundManager.overlayOpacity))
            } else {
                // Glass effect preview
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Blurred colored orbs
                    Circle()
                        .fill(Color.modernPurple.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .blur(radius: 25)
                        .offset(x: -40, y: -30)
                    
                    Circle()
                        .fill(Color.modernCyan.opacity(0.25))
                        .frame(width: 60, height: 60)
                        .blur(radius: 20)
                        .offset(x: 50, y: 40)
                    
                    Circle()
                        .fill(Color.modernMint.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .blur(radius: 18)
                        .offset(x: 20, y: -50)
                }
            }
            
            // Content overlay
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.modernCyan.opacity(0.3), .modernBlue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.modernCyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bluetooth")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Connected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(Color.modernMint)
                        .frame(width: 8, height: 8)
                        .shadow(color: .modernMint.opacity(0.5), radius: 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                
                // Device list
                VStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { index in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: index == 0 ? "headphones" : "keyboard")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                            
                            VStack(alignment: .leading, spacing: 3) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: index == 0 ? 75 : 85, height: 9)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: index == 0 ? 50 : 40, height: 7)
                            }
                            
                            Spacer()
                            
                            Circle()
                                .fill(index == 0 ? Color.modernMint.opacity(0.7) : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 260, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 15, y: 8)
    }
}

// MARK: - Shortcuts Settings View
struct ShortcutsSettingsView: View {
    @ObservedObject private var shortcutManager = ShortcutManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var isRecordingShortcut: ShortcutAction?
    @State private var showingPermissionAlert = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // Modern Header
                ModernSettingsHeader(
                    title: "Shortcuts",
                    subtitle: "Configure global keyboard shortcuts",
                    icon: "command.square.fill",
                    gradientColors: [.modernPurple, .modernPink]
                )
                
                // Permission Status - only show if we DON'T have permission
                if !permissionManager.hasAccessibilityAccess {
                    permissionBanner
                        .padding(.horizontal)
                }
                
                // Shortcuts List Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 18) {
                        ModernSectionHeader(
                            icon: "keyboard",
                            title: "Global Shortcuts",
                            subtitle: "Press keys from anywhere to trigger actions",
                            iconColor: .modernPurple
                        )
                        
                        VStack(spacing: 8) {
                            let visibleActions = ShortcutAction.allCases
                            ForEach(visibleActions, id: \.self) { action in
                                ModernShortcutRow(
                                    action: action,
                                    isRecording: isRecordingShortcut == action,
                                    onToggle: { enabled in
                                        handleToggle(action: action, enabled: enabled)
                                    },
                                    onStartRecording: {
                                        isRecordingShortcut = action
                                    },
                                    onStopRecording: { newShortcut in
                                        if let shortcut = newShortcut {
                                            shortcutManager.saveShortcut(shortcut, for: action)
                                        }
                                        isRecordingShortcut = nil
                                    }
                                )
                                
                                if action != visibleActions.last {
                                    Divider().background(Color.white.opacity(0.06))
                                }
                            }
                        }
                    }
                }
                
                // // Info Card
                // GlassCard(opacity: 0.03) {
                //     ModernInfoBox(
                //         icon: "lightbulb.fill",
                //         title: "Tip",
                //         message: "Use unique key combinations that won't conflict with other apps. Common modifiers: ⌘⇧, ⌥⌘, ⌃⌥",
                //         iconColor: .modernYellow
                //     )
                // }
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            permissionManager.startPermissionMonitoring()
            permissionManager.refreshPermissionStatus()
        }
        .onDisappear {
            permissionManager.stopPermissionMonitoring()
        }
        .onChange(of: showingPermissionAlert) { _, newValue in
            if newValue {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                showingPermissionAlert = false
            }
        }
    }
    
    // Permission banner - Modern Style
    private var permissionBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.modernOrange.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.modernOrange)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility Permission Required")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Grant permission to use global keyboard shortcuts")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Button(action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }) {
                Text("Open Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.modernOrange.opacity(0.45)), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassEffect(.regular.tint(.modernOrange.opacity(0.10)), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.modernOrange.opacity(0.30), lineWidth: 1)
        )
    }
    
    private func handleToggle(action: ShortcutAction, enabled: Bool) {
        if enabled && !permissionManager.hasAccessibilityAccess {
            // Open System Settings and show alert
            showingPermissionAlert = true
        } else {
            shortcutManager.setEnabled(enabled, for: action)
        }
    }
}

// MARK: - Modern Shortcut Row
struct ModernShortcutRow: View {
    let action: ShortcutAction
    let isRecording: Bool
    let onToggle: (Bool) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: (KeyboardShortcut?) -> Void
    
    @ObservedObject private var shortcutManager = ShortcutManager.shared
    @State private var localKeyMonitor: Any?
    
    private var isEnabled: Bool {
        shortcutManager.isEnabled(action)
    }
    
    private var currentShortcut: KeyboardShortcut? {
        shortcutManager.shortcuts[action]
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: action.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isEnabled ? .modernPurple : .white.opacity(0.4))
                .frame(width: 28, alignment: .center)
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(action.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))
                
                Text(descriptionForAction(action))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            // Shortcut recorder
            modernShortcutButton
            
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(Color.modernCyan)
            .labelsHidden()
        }
        .padding(.vertical, 10)
        .onDisappear {
            stopLocalMonitor()
        }
    }
    
    @ViewBuilder
    private var modernShortcutButton: some View {
        if isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.modernRed)
                    .frame(width: 8, height: 8)
                Text("Press keys...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.modernRed)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.modernRed.opacity(0.22)), in: .capsule)
            .onAppear { startLocalMonitor() }
            .onDisappear { stopLocalMonitor() }
        } else if let shortcut = currentShortcut {
            Button(action: onStartRecording) {
                Text(shortcut.displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.modernCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.modernCyan.opacity(0.22)), in: .capsule)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onStartRecording) {
                Text("Set Shortcut")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func startLocalMonitor() {
        stopLocalMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil
        }
    }
    
    private func stopLocalMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onStopRecording(nil)
            return
        }
        
        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else { return }
        
        let nsModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !nsModifiers.isEmpty else { return }
        
        // Convert NSEvent.ModifierFlags to KeyboardShortcut.ModifierSet
        var modSet: KeyboardShortcut.ModifierSet = []
        if nsModifiers.contains(.command) { modSet.insert(.command) }
        if nsModifiers.contains(.shift) { modSet.insert(.shift) }
        if nsModifiers.contains(.option) { modSet.insert(.option) }
        if nsModifiers.contains(.control) { modSet.insert(.control) }
        
        let shortcut = KeyboardShortcut(
            key: characters.uppercased(),
            modifiers: modSet
        )
        
        onStopRecording(shortcut)
    }
    
    private func descriptionForAction(_ action: ShortcutAction) -> String {
        switch action {
        case .quickJoinMeeting: return "Join current meeting instantly"
        case .connectLastBluetooth: return "Connect to last Bluetooth device"
        case .toggleMusic: return "Control music playback"
        case .togglePomodoro: return "Start or pause focus timer"
        case .toggleFloatingBar: return "Show or hide the floating bar"
        }
    }
}

// MARK: - Shortcut Row (Legacy)
struct ShortcutRow: View {
    let action: ShortcutAction
    let isRecording: Bool
    let onToggle: (Bool) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: (KeyboardShortcut?) -> Void
    
    @ObservedObject private var shortcutManager = ShortcutManager.shared
    @State private var localKeyMonitor: Any?
    
    private var isEnabled: Bool {
        shortcutManager.isEnabled(action)
    }
    
    private var currentShortcut: KeyboardShortcut? {
        shortcutManager.shortcuts[action]
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: action.icon)
                .font(.system(size: 18))
                .foregroundColor(isEnabled ? .accentColor : .secondary)
                .frame(width: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(action.rawValue)
                    .font(.body)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Text(descriptionForAction(action))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Shortcut recorder
            shortcutButton
            
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(Color.gray)
            .labelsHidden()
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .onDisappear {
            stopLocalMonitor()
        }
    }

    @ViewBuilder
    private var shortcutButton: some View {
        if isRecording {
            // Recording state
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Press keys...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.red.opacity(0.18)), in: .capsule)
            .onAppear {
                startLocalMonitor()
            }
        } else {
            // Normal state - show current shortcut
            Button(action: onStartRecording) {
                if let shortcut = currentShortcut {
                    Text(shortcut.displayString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    Text("Record")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
    }
    
    private func descriptionForAction(_ action: ShortcutAction) -> String {
        switch action {
        case .quickJoinMeeting:
            return "Instantly join the current meeting"
        case .connectLastBluetooth:
            return "Connect to last used Bluetooth device"
        case .toggleMusic:
            return "Toggle music play/pause"
        case .togglePomodoro:
            return "Start or pause Pomodoro timer"
        case .toggleFloatingBar:
            return "Show or hide the floating bar"
        }
    }
    
    private func startLocalMonitor() {
        stopLocalMonitor()
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                onStopRecording(nil)
                return nil
            }
            
            // Try to create shortcut from event
            if let shortcut = shortcutManager.recordShortcut(from: event) {
                onStopRecording(shortcut)
                return nil
            }
            
            return event
        }
    }
    
    private func stopLocalMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}







