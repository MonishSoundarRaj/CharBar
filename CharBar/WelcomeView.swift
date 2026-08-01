import SwiftUI
import AppKit
import EventKit
import CoreBluetooth

// MARK: - Premium Onboarding (Apple-style multi-step)
//
// Single accent color (cyan) for chrome — colored icons only on row glyphs to keep
// the eye focused. Vertical lists instead of 2x2 grids so subtitles never wrap.
// Tight 680×500 window so steps don't feel sparse.

struct WelcomeView: View {
    var onFinish: () -> Void = {}

    @StateObject private var launchAtLogin = LaunchAtLogin()
    @State private var currentStep: Int = 0
    @State private var animateHero: Bool = false

    // Permission state — drives the button label (Open / Granted / Denied)
    @State private var calendarStatus: PermissionState = .unknown
    @State private var bluetoothStatus: PermissionState = .unknown
    @State private var accessibilityStatus: PermissionState = .unknown
    @State private var bluetoothCentral: CBCentralManager? = nil
    @State private var bluetoothDelegate: BluetoothPermissionDelegate? = nil

    enum PermissionState {
        case unknown, granted, denied, restricted
        var label: String {
            switch self {
            case .granted: return "Granted"
            case .denied, .restricted: return "Open Settings"
            case .unknown: return "Allow"
            }
        }
        var isGranted: Bool { self == .granted }
    }

    private let totalSteps = 4
    private let accent = Color.modernCyan

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                topBar

                ZStack {
                    Group {
                        switch currentStep {
                        case 0: welcomeStep
                        case 1: featuresStep
                        case 2: permissionsStep
                        default: readyStep
                        }
                    }
                    .id(currentStep)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 20, y: 0)),
                        removal: .opacity.combined(with: .offset(x: -20, y: 0))
                    ))
                    .padding(.horizontal, 36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .frame(width: 680, height: 500)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.1)) {
                animateHero = true
            }
        }
    }

    // MARK: Backdrop — single soft cyan glow on near-black
    private var backdrop: some View {
        ZStack {
            Color(nsColor: NSColor(white: 0.06, alpha: 1.0))
                .ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
    }

    // MARK: Top bar — Skip only
    private var topBar: some View {
        HStack {
            Spacer()
            if currentStep < totalSteps - 1 {
                Button(action: finish) {
                    Text("Skip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .frame(height: 46)
    }

    // MARK: Footer — dots + Back/Continue
    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i == currentStep ? Color.white.opacity(0.85) : Color.white.opacity(0.18))
                        .frame(width: i == currentStep ? 22 : 6, height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
                }
            }

            Spacer()

            if currentStep > 0 {
                Button(action: back) {
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }

            Button(action: next) {
                HStack(spacing: 7) {
                    Text(currentStep == totalSteps - 1 ? "Start Using CharBar" : "Continue")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(accent.opacity(0.55)), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    // MARK: Common headline + sub
    @ViewBuilder
    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 1 — Welcome
    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: accent.opacity(0.35), radius: 24, y: 10)
                .scaleEffect(animateHero ? 1.0 : 0.9)
                .opacity(animateHero ? 1.0 : 0.0)

            VStack(spacing: 10) {
                Text("Welcome to CharBar")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Battery, calendar, music, and system stats. In your menu bar, or summon a floating bar anywhere on screen.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 50)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: Step 2 — Features (vertical full-width rows, monochrome icons)
    private var featuresStep: some View {
        VStack(spacing: 18) {
            stepHeader(
                title: "Everything in one place",
                subtitle: "Your menu bar utility, reimagined."
            )

            VStack(spacing: 8) {
                featureRow(icon: "rectangle.portrait.on.rectangle.portrait.angled.fill", title: "Menu bar + floating bar", subtitle: "Live where you need it. In the menu bar, or summon anywhere.")
                featureRow(icon: "calendar",                                              title: "Calendar awareness",     subtitle: "See what's next and join meetings instantly.")
                featureRow(icon: "music.note",                                            title: "Now Playing",            subtitle: "Album-art adaptive media controls.")
                featureRow(icon: "battery.100.bolt",                                      title: "Battery & Bluetooth",    subtitle: "Live battery for Mac and connected devices.")
                featureRow(icon: "cpu",                                                   title: "System stats",           subtitle: "CPU, GPU, RAM, network, disk at a glance.")
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 26, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: Step 3 — Permissions (real native prompts)
    private var permissionsStep: some View {
        VStack(spacing: 18) {
            stepHeader(
                title: "A few permissions",
                subtitle: "CharBar only asks for what each feature needs."
            )

            VStack(spacing: 8) {
                permissionRow(
                    icon: "calendar",
                    title: "Calendar",
                    subtitle: "See your meetings and detect video links.",
                    state: calendarStatus,
                    action: requestCalendar
                )
                permissionRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Bluetooth",
                    subtitle: "Show battery levels for connected devices.",
                    state: bluetoothStatus,
                    action: requestBluetooth
                )
                permissionRow(
                    icon: "command.square.fill",
                    title: "Accessibility",
                    subtitle: "Required for global keyboard shortcuts.",
                    state: accessibilityStatus,
                    action: openAccessibilityPane
                )
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .onAppear { refreshPermissionStatuses() }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        state: PermissionState,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 26, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if state.isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Granted")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.modernGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                Button(action: action) {
                    Text(state.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: Permission requests — real native prompts where possible

    private func refreshPermissionStatuses() {
        // Calendar
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        calendarStatus = mapCalendarStatus(calStatus)

        // Bluetooth (read-only check — actual prompt only fires on first CBCentralManager init)
        switch CBManager.authorization {
        case .allowedAlways: bluetoothStatus = .granted
        case .denied:        bluetoothStatus = .denied
        case .restricted:    bluetoothStatus = .restricted
        case .notDetermined: bluetoothStatus = .unknown
        @unknown default:    bluetoothStatus = .unknown
        }

        // Accessibility — check trust without prompting
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .unknown
    }

    private func mapCalendarStatus(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .denied:                  return .denied
        case .restricted:              return .restricted
        case .notDetermined:           return .unknown
        case .writeOnly:               return .denied // We need full access for read.
        @unknown default:              return .unknown
        }
    }

    private func requestCalendar() {
        let store = EKEventStore()
        let current = EKEventStore.authorizationStatus(for: .event)

        // If already determined, only path is System Settings.
        if current != .notDetermined {
            openSystemSettings("Privacy_Calendars")
            return
        }

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async {
                    calendarStatus = granted ? .granted : .denied
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async {
                    calendarStatus = granted ? .granted : .denied
                }
            }
        }
    }

    private func requestBluetooth() {
        // If already determined, jump to Settings.
        if CBManager.authorization != .notDetermined {
            openSystemSettings("Privacy_Bluetooth")
            return
        }
        // Instantiating CBCentralManager triggers the native prompt.
        let delegate = BluetoothPermissionDelegate { auth in
            DispatchQueue.main.async {
                switch auth {
                case .allowedAlways: bluetoothStatus = .granted
                case .denied:        bluetoothStatus = .denied
                case .restricted:    bluetoothStatus = .restricted
                default:             bluetoothStatus = .unknown
                }
            }
        }
        bluetoothDelegate = delegate
        bluetoothCentral = CBCentralManager(delegate: delegate, queue: nil)
    }

    private func openAccessibilityPane() {
        // Accessibility can't be granted programmatically — only path is System Settings.
        // Trigger the system's prompt-and-mark-as-asked flow first, then open Settings.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openSystemSettings("Privacy_Accessibility")
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Step 4 — Ready
    private var readyStep: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: accent.opacity(0.30), radius: 20, y: 6)

            VStack(spacing: 8) {
                Text("You're all set")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("CharBar is now running in your menu bar. Click any icon to interact, or open Settings to configure global shortcuts.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $launchAtLogin.isEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .tint(accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: Navigation
    private func next() {
        if currentStep == totalSteps - 1 {
            finish()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                currentStep += 1
            }
        }
    }

    private func back() {
        guard currentStep > 0 else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            currentStep -= 1
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        onFinish()
    }
}

// MARK: - Bluetooth permission helper
//
// Instantiating CBCentralManager triggers the native Bluetooth prompt the first time;
// we observe the central's state to know when the user has answered.

private final class BluetoothPermissionDelegate: NSObject, CBCentralManagerDelegate {
    let onAuthorizationDecided: (CBManagerAuthorization) -> Void

    init(onAuthorizationDecided: @escaping (CBManagerAuthorization) -> Void) {
        self.onAuthorizationDecided = onAuthorizationDecided
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onAuthorizationDecided(CBManager.authorization)
    }
}
