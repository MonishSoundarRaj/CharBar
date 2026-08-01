//
//  MeetingManager.swift
//  CharBar
//
//  Smart Meeting Manager - Calendar integration with video link detection
//

import Foundation
import EventKit
import SwiftUI
import Combine
import Cocoa

// MARK: - Meeting Link Type
enum MeetingLinkType: String {
    case zoom = "Zoom"
    case googleMeet = "Google Meet"
    case teams = "Microsoft Teams"
    case webex = "Webex"
    case generic = "Video Call"
    
    var icon: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "video.circle.fill"
        case .teams: return "person.2.circle.fill"
        case .webex: return "video.badge.waveform.fill"
        case .generic: return "video.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .zoom: return Color(red: 0.16, green: 0.47, blue: 0.96) // Zoom blue
        case .googleMeet: return Color(red: 0.0, green: 0.53, blue: 0.32) // Google green
        case .teams: return Color(red: 0.38, green: 0.28, blue: 0.68) // Teams purple
        case .webex: return Color(red: 0.0, green: 0.69, blue: 0.31) // Webex green
        case .generic: return .blue
        }
    }
    
    var brandName: String {
        return self.rawValue
    }
}

// MARK: - Smart Meeting Model
struct SmartMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarColor: Color
    let calendarTitle: String
    let location: String?
    let notes: String?
    
    // Reference to original EKEvent for email/calendar actions
    let event: EKEvent?
    
    // Video meeting detection
    var meetingLink: URL?
    var meetingLinkType: MeetingLinkType?
    
    var hasVideoLink: Bool {
        return meetingLink != nil
    }
    
    var videoLink: URL? {
        return meetingLink
    }
    
    var isHappeningNow: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }
    
    var isStartingSoon: Bool {
        let now = Date()
        let fiveMinutesFromNow = now.addingTimeInterval(5 * 60)
        return startDate > now && startDate <= fiveMinutesFromNow
    }
    
    var timeUntilStart: TimeInterval {
        return startDate.timeIntervalSince(Date())
    }
    
    var timeRemainingString: String {
        let now = Date()
        
        // Check if meeting has ended
        if endDate < now {
            return "Ended"
        }
        
        if isHappeningNow {
            let remaining = endDate.timeIntervalSince(now)
            if remaining < 60 {
                return "Ending soon"
            } else if remaining < 3600 {
                return "\(Int(remaining / 60))m left"
            } else {
                return "\(Int(remaining / 3600))h left"
            }
        } else {
            let until = startDate.timeIntervalSince(now)
            if until < 60 {
                return "Starting now"
            } else if until < 3600 {
                return "in \(Int(until / 60))m"
            } else if until < 86400 {
                let hours = Int(until / 3600)
                let mins = Int((until.truncatingRemainder(dividingBy: 3600)) / 60)
                if mins > 0 {
                    return "in \(hours)h \(mins)m"
                }
                return "in \(hours)h"
            } else {
                return formatTime(startDate)
            }
        }
    }
    
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
    
    /// Compact time string for menu bar (e.g., "10m", "3h", no "in" prefix)
    var compactTimeString: String {
        let now = Date()
        
        // Check if meeting has ended
        if endDate < now {
            return "ended"
        }
        
        if isHappeningNow {
            let remaining = endDate.timeIntervalSince(now)
            if remaining < 60 {
                return "<1m"
            } else if remaining < 3600 {
                return "\(Int(remaining / 60))m"
            } else {
                return "\(Int(remaining / 3600))h"
            }
        } else {
            let until = startDate.timeIntervalSince(now)
            if until < 60 {
                return "<1m"
            } else if until < 3600 {
                return "\(Int(until / 60))m"
            } else {
                // Just show hours, no minutes for simplicity
                return "\(Int(until / 3600))h"
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Calendar Access State
enum CalendarAccessState {
    case notDetermined
    case authorized
    case denied
    case restricted
}

// MARK: - Menu Bar State Machine
enum MenuBarMeetingState {
    case idle           // No meetings remaining today - show calendar icon
    case upcoming       // Meeting > 15 minutes away - show time
    case countdown      // Meeting 2-15 minutes away - show countdown
    case action         // Meeting < 2 minutes or active - show Join button
    
    var showsJoinButton: Bool {
        return self == .action
    }
}

// MARK: - Meeting Manager
class MeetingManager: ObservableObject {
    static let shared = MeetingManager()
    
    // MARK: - Published Properties
    @Published var currentMeeting: SmartMeeting? = nil
    @Published var upcomingMeetings: [SmartMeeting] = []
    @Published var accessState: CalendarAccessState = .notDetermined
    @Published var isLoading: Bool = false
    @Published var selectedDate: Date = Date() // For date navigation
    @Published var todaysUpcomingMeetings: [SmartMeeting] = [] // Today's meetings for the "Next Task" section
    
    // MARK: - User Settings
    /// Minutes before meeting to show Join button (default 5 minutes)
    @AppStorage("meeting_joinButtonMinutes") var joinButtonMinutes: Int = 5
    /// Minutes before meeting to start countdown (default 15 minutes)
    @AppStorage("meeting_countdownMinutes") var countdownMinutes: Int = 15
    /// Auto-dismiss notifications after X seconds (0 = manual dismiss)
    @AppStorage("meeting_notificationDismissSeconds") var notificationDismissSeconds: Int = 0
    
    // MARK: - Private
    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private var notificationCheckTimer: Timer?
    private var notifiedMeetingIds: Set<String> = []
    
    // Callback to get the meetings status item for notifications
    var getStatusItem: (() -> NSStatusItem?)? = nil
    
    // MARK: - Computed
    var hasMeeting: Bool {
        return currentMeeting != nil
    }
    
    /// The next upcoming meeting after current (for showing next meeting during current)
    var nextUpcomingMeeting: SmartMeeting? {
        // If we have a current meeting that's happening now, find the next one
        guard let current = currentMeeting, current.isHappeningNow else { return nil }
        
        // Find next meeting that starts after now (not the current one)
        return todaysUpcomingMeetings.first { meeting in
            meeting.id != current.id && meeting.startDate > Date() && !meeting.isHappeningNow
        }
    }
    
    /// Check if next meeting is within warning threshold (countdown or action state)
    var isNextMeetingApproaching: Bool {
        guard let next = nextUpcomingMeeting else { return false }
        let countdownThreshold = Double(countdownMinutes * 60)
        return next.timeUntilStart <= countdownThreshold && next.timeUntilStart > 0
    }
    
    /// The meeting to display in UI (either current or next if next is approaching)
    /// Prioritizes video meetings over non-video events when both are active
    var displayMeeting: SmartMeeting? {
        if let current = currentMeeting, current.isHappeningNow {
            // If current meeting has no video link, check if there's an upcoming video meeting
            // within join threshold that should take priority
            if !current.hasVideoLink {
                if let videoMeeting = todaysUpcomingMeetings.first(where: { meeting in
                    meeting.id != current.id && meeting.hasVideoLink && meeting.timeUntilStart > 0 &&
                    meeting.timeUntilStart <= Double(joinButtonMinutes * 60)
                }) {
                    return videoMeeting
                }
            }
            
            // Check if next meeting (video or not) is within join threshold
            if let next = nextUpcomingMeeting {
                let joinThreshold = Double(joinButtonMinutes * 60)
                if next.timeUntilStart <= joinThreshold && next.timeUntilStart > 0 {
                    return next
                }
            }
        }
        return currentMeeting
    }
    
    var isViewingToday: Bool {
        return Calendar.current.isDateInToday(selectedDate)
    }
    
    var selectedDateText: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else if Calendar.current.isDateInTomorrow(selectedDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: selectedDate)
        }
    }
    
    var formattedFullDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: selectedDate)
    }
    
    // MARK: - Menu Bar State Machine
    
    /// Current state for menu bar display (uses user-configurable thresholds)
    /// Uses displayMeeting which handles the transition between current and next meeting
    var menuBarState: MenuBarMeetingState {
        guard let meeting = displayMeeting else {
            return .idle
        }
        
        // If meeting has ended, return idle (should trigger transition to next meeting)
        if meeting.endDate < Date() {
            return .idle
        }
        
        let timeUntil = meeting.timeUntilStart
        let joinThreshold = Double(joinButtonMinutes * 60)     // User setting (default 5 min)
        let countdownThreshold = Double(countdownMinutes * 60) // User setting (default 15 min)
        
        if meeting.isHappeningNow {
            return .action
        } else if timeUntil > 0 && timeUntil <= joinThreshold {
            return .action  // Show Join button
        } else if timeUntil > 0 && timeUntil <= countdownThreshold {
            return .countdown  // Show countdown text
        } else if timeUntil > 0 {
            return .upcoming
        } else {
            return .idle  // Meeting started but not happening now (ended)
        }
    }
    
    /// Menu bar display text based on state
    /// Uses displayMeeting to handle transitions between current and next meeting
    var menuBarDisplayText: String {
        guard let meeting = displayMeeting else {
            return ""
        }
        
        switch menuBarState {
        case .idle:
            return ""
        case .upcoming:
            // Show meeting time: "3:00 PM"
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: meeting.startDate)
        case .countdown:
            // Show countdown: "14m"
            let mins = Int(meeting.timeUntilStart / 60)
            return "\(mins)m"
        case .action:
            if meeting.isHappeningNow {
                return "●"  // Just red dot for "now" - no text needed
            } else {
                let mins = Int(meeting.timeUntilStart / 60)
                let secs = Int(meeting.timeUntilStart) % 60
                return String(format: "%d:%02d", mins, secs)
            }
        }
    }
    
    /// Short title for menu bar display (truncated if too long)
    var menuBarTitle: String {
        guard let meeting = displayMeeting else {
            return ""
        }
        
        let title = meeting.title
        if title.count > 15 {
            return String(title.prefix(12)) + "..."
        }
        return title
    }
    
    /// Text for countdown state: just "14m" (no title)
    var menuBarCountdownText: String {
        guard let meeting = displayMeeting else { return "" }
        let mins = Int(meeting.timeUntilStart / 60)
        return "\(mins)m"
    }
    
    // MARK: - Icon State
    
    /// SF Symbol name for the calendar icon based on current access + meeting state.
    /// • calendar.badge.checkmark  — authorized, meeting within next hour (or happening now)
    /// • calendar.badge.clock      — authorized, nothing in the next hour
    /// • calendar.badge.exclamationmark — no permission / not determined
    var calendarIconSymbol: String {
        switch accessState {
        case .notDetermined, .denied, .restricted:
            return "calendar.badge.exclamationmark"
        case .authorized:
            let horizon = Date().addingTimeInterval(3600) // next 1 hour
            let hasNearMeeting = todaysUpcomingMeetings.contains {
                $0.isHappeningNow || $0.startDate <= horizon
            }
            return hasNearMeeting ? "calendar.badge.checkmark" : "calendar.badge.clock"
        }
    }
    
    // MARK: - Free Time Context
    
    /// Returns a friendly "free time" message (shown only when truly no remaining meetings today)
    var freeTimeMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 18 {
            return "All done for today"
        } else if hour >= 12 {
            return "No more meetings today"
        } else {
            return "No meetings today"
        }
    }
    
    /// Returns event count summary for a date
    func meetingSummary(for date: Date) -> String {
        let count = upcomingMeetings.count
        if count == 0 {
            return "✓"
        } else if count == 1 {
            return "1 event"
        } else {
            return "\(count) events"
        }
    }
    
    // MARK: - Deep Linking
    
    /// Opens a specific event in Apple Calendar
    func openEventInCalendar(event: EKEvent) {
        // Use AppleScript to open Calendar to the event's date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: event.startDate)
        
        guard let year = components.year, let month = components.month, let day = components.day else {
            openCalendarApp()
            return
        }
        
        let script = """
        tell application "Calendar"
            activate
            view calendar at date "\(month)/\(day)/\(year)"
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
        
        if error != nil {
            openCalendarApp()
        }
    }
    
    /// Opens Apple Calendar to the selected date
    func openCalendarToSelectedDate() {
        // Use AppleScript to open Calendar to a specific date (more reliable than URL scheme)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        
        guard let year = components.year, let month = components.month, let day = components.day else {
            // Fallback: just open Calendar app
            openCalendarApp()
            return
        }
        
        // AppleScript to open Calendar and navigate to date
        let script = """
        tell application "Calendar"
            activate
            view calendar at date "\(month)/\(day)/\(year)"
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error != nil {
                // Fallback: just open Calendar app
                openCalendarApp()
            }
        }
    }
    
    /// Simply opens the Calendar app
    func openCalendarApp() {
        if let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open(calendarURL)
        }
    }
    
    // MARK: - Initialization
    init() {
        checkAccessStatus()
        
        // Listen for settings changes to stop/start notification timer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
        
        // Also listen for UserDefaults changes (backup listener)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func userDefaultsDidChange() {
        // Check if meetings were disabled via UserDefaults directly
        // This is a backup check in case SettingsChanged notification is missed
        if let settingsManager = sharedSettingsManager,
           let config = settingsManager.configurations[.meetings],
           !config.isEnabled {
            // If timer is running but meetings are disabled, stop it
            if notificationCheckTimer != nil {
                notificationCheckTimer?.invalidate()
                notificationCheckTimer = nil
                notifiedMeetingIds.removeAll()
                MeetingNotification.shared.dismiss()
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
        notificationCheckTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func settingsDidChange() {
        // CRITICAL: Must have settings manager
        guard let settingsManager = sharedSettingsManager else {
            return
        }
        
        // Check if meetings config exists
        guard let config = settingsManager.configurations[.meetings] else {
            return
        }
        
        if !config.isEnabled {
            // Stop notification timer if meetings are disabled
            notificationCheckTimer?.invalidate()
            notificationCheckTimer = nil
            notifiedMeetingIds.removeAll()
            
            // CRITICAL: Also dismiss any currently showing notification
            MeetingNotification.shared.dismiss()
        } else if notificationCheckTimer == nil && accessState == .authorized {
            // Restart notification timer if meetings are enabled and we have access
            notificationCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.checkForUpcomingMeetingNotifications()
            }
        }
    }
    
    // MARK: - Access Control
    
    func checkAccessStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .notDetermined:
            accessState = .notDetermined
        case .authorized, .fullAccess:
            accessState = .authorized
            startMonitoring()
        case .denied:
            accessState = .denied
        case .restricted:
            accessState = .restricted
        case .writeOnly:
            accessState = .denied
        @unknown default:
            accessState = .denied
        }
    }
    
    func requestAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self?.accessState = .authorized
                        self?.startMonitoring()
                    } else {
                        self?.accessState = .denied
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self?.accessState = .authorized
                        self?.startMonitoring()
                    } else {
                        self?.accessState = .denied
                    }
                }
            }
        }
    }
    
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Date Navigation
    
    func goToNextDay() {
        if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = nextDay
            fetchMeetings()
        }
    }
    
    func goToPreviousDay() {
        if let prevDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = prevDay
            fetchMeetings()
        }
    }
    
    func goToToday() {
        selectedDate = Date()
        fetchMeetings()
    }
    
    func goToDate(_ date: Date) {
        selectedDate = date
        fetchMeetings()
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        // Initial fetch
        fetchMeetings()
        
        // Refresh every minute
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.fetchMeetings()
        }
        
        // Only start notification timer if meetings are enabled in settings
        // Note: sharedSettingsManager might not be set yet during app launch,
        // so we also check in settingsDidChange() and checkForUpcomingMeetingNotifications()
        let meetingsEnabled = sharedSettingsManager?.configurations[.meetings]?.isEnabled ?? false
        if meetingsEnabled {
            notificationCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.checkForUpcomingMeetingNotifications()
            }
        }
        
        // Listen for calendar changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    // MARK: - Meeting Notifications
    
    private func checkForUpcomingMeetingNotifications() {
        // IMPORTANT: Check if meetings are enabled in settings before showing notifications
        // Check 1: sharedSettingsManager must exist
        guard let settingsManager = sharedSettingsManager else {
            return
        }
        
        // Check 2: meetings config must exist
        guard let meetingConfig = settingsManager.configurations[.meetings] else {
            return
        }
        
        // Check 3: meetings must be enabled
        guard meetingConfig.isEnabled == true else {
            return
        }
        
        // Get notification threshold from user setting (joinButtonMinutes)
        let notificationThreshold = Double(joinButtonMinutes * 60)
        
        // Check current meeting first
        if let meeting = currentMeeting {
            let timeUntil = meeting.timeUntilStart
            
            // Show notification when meeting is within threshold (and we haven't notified yet)
            if timeUntil > 0 && timeUntil <= notificationThreshold && !notifiedMeetingIds.contains(meeting.id) {
                showNotification(for: meeting)
            }
        }
        
        // Also check upcoming meetings (in case current meeting is nil)
        for meeting in upcomingMeetings {
            let timeUntil = meeting.timeUntilStart
            
            // Show notification when meeting is within threshold (and we haven't notified yet)
            if timeUntil > 0 && timeUntil <= notificationThreshold && !notifiedMeetingIds.contains(meeting.id) {
                showNotification(for: meeting)
                break  // Only notify for the next upcoming meeting
            }
        }
        
        // Clean up old notification IDs (meetings that have passed)
        let now = Date()
        notifiedMeetingIds = notifiedMeetingIds.filter { id in
            upcomingMeetings.contains { $0.id == id && $0.endDate > now }
        }
    }
    
    private func showNotification(for meeting: SmartMeeting) {
        // SAFETY CHECK 1: sharedSettingsManager must exist
        guard let settingsManager = sharedSettingsManager else {
            return
        }
        
        // SAFETY CHECK 2: meetings config must exist
        guard let meetingConfig = settingsManager.configurations[.meetings] else {
            return
        }
        
        // SAFETY CHECK 3: meetings must be enabled
        guard meetingConfig.isEnabled == true else {
            return
        }
        
        // SAFETY CHECK 4: user hasn't disabled meeting notifications
        let showMeetingNotifications = UserDefaults.standard.object(forKey: "meeting_showNotification") as? Bool ?? true
        guard showMeetingNotifications else {
            return
        }
        
        notifiedMeetingIds.insert(meeting.id)
        
        DispatchQueue.main.async { [weak self] in
            // Final check before showing - meetings could have been disabled
            guard let sm = sharedSettingsManager,
                  let config = sm.configurations[.meetings],
                  config.isEnabled == true else {
                return
            }
            
            // Check if floating bar is visible
            if FloatingMenuBarController.shared.isVisible {
                MeetingNotification.shared.showAtFloatingBar(
                    meeting: meeting,
                    floatingBarFrame: FloatingMenuBarController.shared.floatingBarFrame
                )
            } else {
                let statusItem = self?.getStatusItem?()
                MeetingNotification.shared.show(meeting: meeting, relativeTo: statusItem)
            }
        }
    }
    
    @objc private func calendarChanged() {
        fetchMeetings()
    }
    
    // MARK: - Fetching
    
    func fetchMeetings() {
        guard accessState == .authorized else { return }
        
        // Don't show loading for quick date changes - only if we have no data yet
        let shouldShowLoading = upcomingMeetings.isEmpty
        if shouldShowLoading {
            isLoading = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let calendar = Calendar.current
            
            // Get start and end of the selected day
            let startOfSelectedDay = calendar.startOfDay(for: self.selectedDate)
            let endOfSelectedDay = calendar.date(byAdding: .day, value: 1, to: startOfSelectedDay) ?? startOfSelectedDay
            
            // Always fetch from start of day to show ALL events for the day
            let predicate = self.eventStore.predicateForEvents(
                withStart: startOfSelectedDay,
                end: endOfSelectedDay,
                calendars: nil
            )
            
            let events = self.eventStore.events(matching: predicate)
            
            // Filter and convert - show ALL events for the day (including past)
            var smartMeetings: [SmartMeeting] = []
            
            for event in events {
                // Skip all-day events
                if event.isAllDay { continue }
                
                // Convert to SmartMeeting
                let meeting = self.convertToSmartMeeting(event)
                smartMeetings.append(meeting)
            }
            
            // Sort by start date
            smartMeetings.sort { $0.startDate < $1.startDate }
            
            // Find the most relevant meeting (only for today)
            let current = calendar.isDateInToday(self.selectedDate) ? self.findMostRelevantMeeting(from: smartMeetings) : smartMeetings.first
            
            // Always fetch today's meetings for the "Next Task" section
            let todaysMeetings = self.fetchTodaysMeetingsForNextTask()
            
            DispatchQueue.main.async {
                // Smooth transition - use withAnimation for smoother date changes
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.upcomingMeetings = smartMeetings
                    self.todaysUpcomingMeetings = todaysMeetings
                    
                    // For menu bar: always use today's meeting
                    if let first = todaysMeetings.first {
                        self.currentMeeting = first
                    } else {
                        self.currentMeeting = nil
                    }
                    
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Fetch today's upcoming meetings (happening now or soon) for the "Next Task Today" section
    private func fetchTodaysMeetingsForNextTask() -> [SmartMeeting] {
        let now = Date()
        let calendar = Calendar.current
        
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        
        // Include meetings that started up to 30 mins ago (still happening)
        let fetchStart = now.addingTimeInterval(-30 * 60)
        
        let predicate = eventStore.predicateForEvents(
            withStart: fetchStart,
            end: endOfToday,
            calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        
        var todayMeetings: [SmartMeeting] = []
        
        for event in events {
            if event.isAllDay { continue }
            if event.endDate < now { continue }
            
            let meeting = convertToSmartMeeting(event)
            todayMeetings.append(meeting)
        }
        
        // Sort by start date
        todayMeetings.sort { $0.startDate < $1.startDate }
        
        // Return ALL remaining meetings for today (not just the next 30 min).
        // The NEXT UP section uses a scroll view so it handles any number of items.
        return todayMeetings
    }
    
    /// Fetch today's meeting specifically for the menu bar (separate from viewed date)
    private func fetchTodaysMeetingForMenuBar() -> SmartMeeting? {
        let now = Date()
        let calendar = Calendar.current
        
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        
        let fetchStart = now.addingTimeInterval(-60 * 60)
        
        let predicate = eventStore.predicateForEvents(
            withStart: fetchStart,
            end: endOfToday,
            calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        
        var todayMeetings: [SmartMeeting] = []
        
        for event in events {
            if event.isAllDay { continue }
            if event.endDate < now { continue }
            
            let meeting = convertToSmartMeeting(event)
            todayMeetings.append(meeting)
        }
        
        todayMeetings.sort { $0.startDate < $1.startDate }
        
        return findMostRelevantMeeting(from: todayMeetings)
    }
    
    private func convertToSmartMeeting(_ event: EKEvent) -> SmartMeeting {
        // Extract calendar color
        let calendarColor: Color
        if let cgColor = event.calendar.cgColor {
            calendarColor = Color(cgColor: cgColor)
        } else {
            calendarColor = .blue
        }
        
        // Detect meeting link
        let (link, linkType) = detectMeetingLink(
            location: event.location,
            url: event.url,
            notes: event.notes
        )
        
        return SmartMeeting(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled Event",
            startDate: event.startDate,
            endDate: event.endDate,
            calendarColor: calendarColor,
            calendarTitle: event.calendar.title,
            location: event.location,
            notes: event.notes,
            event: event, // Store original event for email/calendar actions
            meetingLink: link,
            meetingLinkType: linkType
        )
    }
    
    private func findMostRelevantMeeting(from meetings: [SmartMeeting]) -> SmartMeeting? {
        let now = Date()
        
        // Filter out meetings that have ended
        let activeMeetings = meetings.filter { $0.endDate > now }
        
        // First, look for a meeting happening now
        if let happening = activeMeetings.first(where: { $0.isHappeningNow }) {
            return happening
        }
        
        // Otherwise, return the soonest upcoming meeting that hasn't started yet
        return activeMeetings
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }
    
    // MARK: - Link Detection
    
    private func detectMeetingLink(location: String?, url: URL?, notes: String?) -> (URL?, MeetingLinkType?) {
        // Check URL field first
        if let url = url {
            if let linkType = detectLinkType(from: url.absoluteString) {
                return (url, linkType)
            }
        }
        
        // Check location
        if let location = location {
            if let (extractedURL, linkType) = extractMeetingURL(from: location) {
                return (extractedURL, linkType)
            }
        }
        
        // Check notes
        if let notes = notes {
            if let (extractedURL, linkType) = extractMeetingURL(from: notes) {
                return (extractedURL, linkType)
            }
        }
        
        return (nil, nil)
    }
    
    private func detectLinkType(from urlString: String) -> MeetingLinkType? {
        let lower = urlString.lowercased()
        
        if lower.contains("zoom.us") || lower.contains("zoomgov.com") {
            return .zoom
        }
        if lower.contains("meet.google.com") {
            return .googleMeet
        }
        if lower.contains("teams.microsoft.com") || lower.contains("teams.live.com") {
            return .teams
        }
        if lower.contains("webex.com") {
            return .webex
        }
        
        return nil
    }
    
    private func extractMeetingURL(from text: String) -> (URL, MeetingLinkType)? {
        // Patterns for different meeting providers
        let patterns = [
            ("https?://[^\\s]*zoom\\.us/[^\\s]+", MeetingLinkType.zoom),
            ("https?://[^\\s]*zoomgov\\.com/[^\\s]+", MeetingLinkType.zoom),
            ("https?://meet\\.google\\.com/[^\\s]+", MeetingLinkType.googleMeet),
            ("https?://[^\\s]*teams\\.microsoft\\.com/[^\\s]+", MeetingLinkType.teams),
            ("https?://[^\\s]*teams\\.live\\.com/[^\\s]+", MeetingLinkType.teams),
            ("https?://[^\\s]*webex\\.com/[^\\s]+", MeetingLinkType.webex)
        ]
        
        for (pattern, linkType) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let urlRange = Range(match.range, in: text) {
                        let urlString = String(text[urlRange])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
                        
                        if let url = URL(string: urlString) {
                            return (url, linkType)
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Actions
    
    func joinMeeting(_ meeting: SmartMeeting) {
        guard let link = meeting.meetingLink else { return }
        
        // Smart deep linking - try app URL schemes first
        if let appURL = convertToAppURL(link, type: meeting.meetingLinkType) {
            // Try to open in native app
            let success = NSWorkspace.shared.open(appURL)
            if !success {
                // Fallback to browser if app not installed
                NSWorkspace.shared.open(link)
            }
        } else {
            // Open in browser
            NSWorkspace.shared.open(link)
        }
    }
    
    /// Convert web URLs to native app URL schemes for better UX
    private func convertToAppURL(_ url: URL, type: MeetingLinkType?) -> URL? {
        let urlString = url.absoluteString
        
        switch type {
        case .zoom:
            // Convert zoom.us/j/123456 to zoommtg://zoom.us/join?confno=123456
            if let meetingID = extractZoomMeetingID(from: urlString) {
                var zoomURL = "zoommtg://zoom.us/join?confno=\(meetingID)"
                
                // Extract password if present
                if let password = extractZoomPassword(from: urlString) {
                    zoomURL += "&pwd=\(password)"
                }
                
                return URL(string: zoomURL)
            }
            
        case .googleMeet:
            // Google Meet doesn't have a reliable app URL scheme on macOS
            // Keep using web URL
            return nil
            
        case .teams:
            // Microsoft Teams URL scheme: msteams://
            // Convert to: msteams://l/meetup-join?...
            return nil // Teams links usually work well in browser
            
        default:
            return nil
        }
        
        return nil
    }
    
    /// Extract Zoom meeting ID from various URL formats
    private func extractZoomMeetingID(from urlString: String) -> String? {
        // Match patterns like /j/123456789 or /j/123456789?pwd=...
        let patterns = [
            "/j/(\\d+)",           // Standard format
            "/s/(\\d+)",           // Scheduled meeting
            "confno=(\\d+)"        // Query parameter
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: urlString, options: [], range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        
        return nil
    }
    
    /// Extract Zoom password from URL
    private func extractZoomPassword(from urlString: String) -> String? {
        let patterns = [
            "pwd=([^&\\s]+)",
            "password=([^&\\s]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: urlString, options: [], range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        
        return nil
    }
}

